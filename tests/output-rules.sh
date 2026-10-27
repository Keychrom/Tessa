#!/bin/sh
# Verify per-output layout/gap rules and output+workspace precedence.
# Requires foot. Run from the repository root after building:
#   sh tests/output-rules.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping output-rules test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-output-rules.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=2
export PATH="$bin:$PATH"

"$bin/tessa" >"$runtime/tessa.log" 2>&1 &
tpid=$!
i=0
while [ ! -S "$runtime/tessa.sock" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "compositor did not create its socket" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

wait_state() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        if printf '%s\n' "$state" | grep -qF "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not contain: $pattern" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

wait_state "OUT HEADLESS-1"
wait_state "OUT HEADLESS-2"
out1=$(tessa-ctl state | awk '$1 == "OUT" { print $2; exit }')
out2=$(tessa-ctl state | awk -v first="$out1" '$1 == "OUT" && $2 != first { print $2; exit }')
if [ -z "$out1" ] || [ -z "$out2" ]; then
    echo "could not discover two outputs" >&2
    tessa-ctl state >&2
    exit 1
fi

cat > "$runtime/config" <<EOF
panel = false
xwayland = false
animations = false
gaps = 7
outer_gaps = 11
layout = master
output-rule = output=$out2; layout=grid; gaps=40; outer-gaps=60
output-rule = output=$out2; ws=2; layout=master; gaps=25; outer-gaps=35
workspace-rule = ws=2; layout=columns; gaps=5; outer-gaps=10
EOF
tessa-ctl dispatch reload
sleep 0.2
tessa-ctl config >"$runtime/config.out"
grep -qF "output_rule_count 2" "$runtime/config.out"
grep -qF "output_rule output=$out2; layout=grid; gaps=40; outer-gaps=60" "$runtime/config.out"
if command -v python3 >/dev/null 2>&1; then
    tessa-ctl config --json >"$runtime/config.json"
    python3 - "$runtime/config.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    cfg = json.load(f)
assert cfg["output_rule_count"] == 2
assert len(cfg["output_rules"]) == 2
PY
fi
echo "output-rule config: ok"

wait_win_count() {
    ws=$1
    out=$2
    expected=$3
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        count=$(printf '%s\n' "$state" | awk -F '	' -v ws="$ws" -v out="$out" \
            '$1 == "WIN" && $3 == ws && $9 == out { n++ } END { print n + 0 }')
        if [ "$count" -eq "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "expected $expected windows on workspace $ws of $out, got $count" >&2
    printf '%s\n' "$state" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

geom() {
    tessa-ctl state | awk -F '	' -v id="$1" '
        $1 == "WIN" && $2 == id { print $10, $11, $12, $13; exit }'
}

tessa-ctl workspace 1 "$out2"
tessa-ctl spawn foot -T OR1
tessa-ctl spawn foot -T OR2
tessa-ctl spawn foot -T OR3
wait_win_count 1 "$out2" 3
set -- $(geom 1)
x0=$1
y0=$2
w0=$3
h0=$4
set -- $(geom 2)
x1=$1
y1=$2
w1=$3
set -- $(geom 3)
x2=$1
y2=$2
w2=$3

if [ "$w0" -ge 950 ] || [ "$w1" -ne "$w0" ] || [ "$w2" -ne "$w0" ]; then
    echo "output-rule grid widths are wrong: $w0 $w1 $w2" >&2
    exit 1
fi
if [ "$((x1 - x0))" -ne "$((w0 + 40))" ] || [ "$((y2 - y0))" -ne "$((h0 + 40))" ]; then
    echo "output-rule gaps are wrong: x=$x0,$x1 y=$y0,$y2" >&2
    exit 1
fi
if [ "$((x2 - x0))" -ne 460 ]; then
    echo "grid last-row centering is wrong: $x0 vs $x2" >&2
    exit 1
fi
echo "output-level grid/gaps: ok"

tessa-ctl workspace 2 "$out2"
tessa-ctl spawn foot -T OR4
tessa-ctl spawn foot -T OR5
wait_win_count 2 "$out2" 2
set -- $(geom 4)
x4=$1
y4=$2
w4=$3
set -- $(geom 5)
x5=$1
y5=$2
w5=$3

if [ "$((x4 - x0))" -ne -25 ] || [ "$((y4 - y0))" -ne -25 ]; then
    echo "output+workspace outer-gaps are wrong: $x4,$y4 vs $x0,$y0" >&2
    exit 1
fi
if [ "$((x5 - (x4 + w4)))" -ne 25 ] || [ "$y5" -ne "$y4" ]; then
    echo "output+workspace gaps/layout are wrong: $x4,$w4 -> $x5,$y5" >&2
    exit 1
fi
if [ "$w4" -le "$w5" ]; then
    echo "workspace-rule unexpectedly overrode output+workspace layout: $w4,$w5" >&2
    exit 1
fi
echo "output+workspace precedence: ok"

# Restart with the same rules to exercise the initial output seed path.
tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
rm -f "$runtime/tessa.sock"
"$bin/tessa" >>"$runtime/tessa.log" 2>&1 &
tpid=$!
i=0
while [ ! -S "$runtime/tessa.sock" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "compositor did not restart" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
wait_for_layout() {
    ws=$1
    expected=$2
    i=0
    while [ "$i" -lt 100 ]; do
        got=$(tessa-ctl state 2>/dev/null | awk -v out="$out2" -v ws="$ws" \
            '$1 == "OUT" && $2 == out && $3 == ws { print $5; exit }')
        if [ "$got" = "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "workspace $ws on $out2 had layout '$got', expected '$expected'" >&2
    tessa-ctl state >&2
    exit 1
}
wait_for_layout 1 grid
tessa-ctl workspace 2 "$out2"
wait_for_layout 2 master
echo "initial output seed: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi
pkill -x tessa-panel 2>/dev/null || true

trap - EXIT INT TERM
rm -rf "$runtime"
echo "output rules test passed"
