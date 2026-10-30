#!/bin/sh
# Verify workspace-to-output pins redirect switches and cross-output moves.
# Requires foot. Run from the repository root after building:
#   sh tests/workspace-pinning.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping workspace-pinning test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-pinning.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
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

wait_win() {
    id=$1
    ws=$2
    out=$3
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        got=$(printf '%s\n' "$state" | awk -F '	' -v id="$id" '
            $1 == "WIN" && $2 == id { print $3 "	" $9; exit }')
        if [ "$got" = "$ws	$out" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "window $id was not on workspace $ws of $out" >&2
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
workspace_pin = $out2 3
EOF
tessa-ctl dispatch reload
sleep 0.2
tessa-ctl config >"$runtime/config.out"
grep -qF "workspace_pin $out2 3" "$runtime/config.out"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
if command -v python3 >/dev/null 2>&1; then
    tessa-ctl config --json >"$runtime/config.json"
    python3 - "$runtime/config.json" "$out2" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    cfg = json.load(f)
assert any(p["output"] == sys.argv[2] and p["workspace"] == 3 for p in cfg["workspace_pins"])
PY
fi
echo "workspace pin config: ok"

tessa-ctl spawn foot -T PinTest
wait_win 1 1 "$out1"
echo "window starts on focused output: ok"

tessa-ctl workspace 3
wait_state "OUT $out2 3 1"
wait_state "OUT $out1 1 0"
wait_state "ACTIVE 3"
echo "pinned workspace switch: ok"

tessa-ctl dispatch focus 1
wait_state "FOCUSED 1"
wait_state "OUT $out1 1 1"
tessa-ctl dispatch move-workspace 3
wait_win 1 3 "$out2"
wait_state "OUT $out2 3 1"
wait_state "OUT $out1 1 0"
echo "cross-output workspace move: ok"

tessa-ctl workspace 2 "$out1"
wait_state "OUT $out1 2 1"
tessa-ctl workspace 3 "$out1"
wait_state "OUT $out2 3 1"
wait_state "OUT $out1 2 0"
echo "explicit pin redirect: ok"

tessa-ctl workspace 4 "$out1"
wait_state "OUT $out1 4 1"
echo "unpinned workspace remains on requested output: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime"
echo "workspace pinning test passed"
