#!/bin/sh
# Verify layout-helper v2: per-output processes, version negotiation,
# asynchronous responses, focus/urgent metadata, and custom rectangles.
# Requires cc and python3. Run from the repository root:
#   sh tests/layout-helper-v2.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN:-$root/zig-out/bin}

for tool in cc python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping layout-helper v2 test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-helper-v2.XXXXXX")
tpid=
pids=
cleanup() {
    for pid in ${pids:-}; do kill "$pid" 2>/dev/null || true; done
    for pid in ${pids:-}; do wait "$pid" 2>/dev/null || true; done
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

cat > "$runtime/helper.py" <<'PY'
#!/usr/bin/env python3
import sys
import time

log = open(sys.argv[1], "a", buffering=1)
windows = []
area = (0, 0, 0, 0)
output = "?"

for raw in sys.stdin:
    fields = raw.rstrip("\n").split("\t")
    if not fields:
        continue
    tag = fields[0]
    if tag == "HELLO":
        print("VERSION\t2", flush=True)
    elif tag == "OUTPUT" and len(fields) >= 2:
        output = fields[1]
    elif tag == "AREA" and len(fields) >= 5:
        area = tuple(int(value) for value in fields[1:5])
    elif tag == "WINDOW" and len(fields) >= 2:
        windows.append(fields)
    elif tag == "END":
        log.write(f"REQUEST\t{output}\t{len(windows)}\n")
        for fields in windows:
            focused = fields[4] if len(fields) > 4 else "0"
            urgent = fields[5] if len(fields) > 5 else "0"
            log.write(f"META\t{output}\t{fields[1]}\tfocused={focused}\turgent={urgent}\n")
        time.sleep(0.6)
        ax, ay, aw, ah = area
        for index, fields in enumerate(windows):
            x = ax + 40 + index * 60
            y = ay + 30 + index * 40
            w = min(400, max(40, aw - 80))
            h = min(300, max(40, ah - 60))
            print(f"RECT\t{fields[1]}\t{x}\t{y}\t{w}\t{h}", flush=True)
        print("END", flush=True)
        windows = []
PY

cat > "$runtime/config" <<EOF
panel = false
xwayland = false
xim = false
animations = false
layout = custom
layout_helper = python3 $runtime/helper.py $runtime/helper.log
layout_helper_timeout = 1000
EOF

write_config() {
    pin=$1
    pin_line=
    if [ -n "$pin" ]; then
        pin_line="workspace_pin = $pin 2"
    fi
    cat > "$runtime/config" <<EOF
panel = false
xwayland = false
xim = false
animations = false
layout = custom
layout_helper = python3 $runtime/helper.py $runtime/helper.log
layout_helper_timeout = 1000
$pin_line
EOF
}

cc -O2 -I"$root/protocol" -o "$runtime/window-test" \
    "$root/tests/rule-visuals/window.c" \
    "$root/protocol/xdg-shell-client-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=2
export PATH="$bin:$PATH"
export TESSA_DEBUG=1

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

tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"

"$runtime/window-test" helper-a HelperA >"$runtime/a.log" 2>&1 &
pids="$pids $!"
"$runtime/window-test" helper-b HelperB >"$runtime/b.log" 2>&1 &
pids="$pids $!"
"$runtime/window-test" helper-c HelperC >"$runtime/c.log" 2>&1 &
pids="$pids $!"

wait_win_count() {
    expected=$1
    i=0
    while [ "$i" -lt 150 ]; do
        count=$(tessa-ctl state 2>/dev/null | awk -F '\t' '$1 == "WIN" { n++ } END { print n + 0 }')
        if [ "${count:-0}" -ge "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "expected $expected windows, saw ${count:-0}" >&2
    tessa-ctl state >&2 || true
    cat "$runtime/tessa.log" >&2
    exit 1
}
wait_win_count 3

focused_out=$(tessa-ctl state | awk '$1 == "OUT" && $4 == 1 { print $2; exit }')
other_out=$(tessa-ctl state | awk -v focused="$focused_out" '$1 == "OUT" && $2 != focused { print $2; exit }')
if [ -z "$focused_out" ] || [ -z "$other_out" ]; then
    echo "could not identify both outputs" >&2
    tessa-ctl state >&2
    exit 1
fi
write_config "$other_out"
tessa-ctl dispatch reload
sleep 0.3

focus_id=$(tessa-ctl state | awk -F '\t' '$1 == "WIN" { print $2; exit }')
if [ -z "$focus_id" ]; then
    echo "no window to move" >&2
    tessa-ctl state >&2
    exit 1
fi
tessa-ctl workspace 2 "$other_out"
tessa-ctl dispatch focus "$focus_id"
tessa-ctl dispatch move-workspace 2

i=0
while [ "$i" -lt 150 ]; do
    if tessa-ctl state | awk -v out1="$other_out" -v out2="$focused_out" -F '\t' '
        $1 == "WIN" && $9 == out1 { moved++ }
        $1 == "WIN" && $9 == out2 { first++ }
        END { exit (moved == 1 && first == 2) ? 0 : 1 }'; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 150 ]; then
    echo "window did not move to the second output" >&2
    tessa-ctl state >&2
    exit 1
fi

wait_rects() {
    i=0
    while [ "$i" -lt 150 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        if printf '%s\n' "$state" | awk -v out1="$other_out" -v out2="$focused_out" -F '\t' '
            $1 == "WIN" {
                n++
                if ($12 != 400 || $13 != 300) bad = 1
                if ($9 == out2) first++
                if ($9 == out1) second++
            }
            END { exit (n == 3 && !bad && first == 2 && second == 1) ? 0 : 1 }'; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "helper rectangles were not applied" >&2
    printf '%s\n' "$state" >&2
    cat "$runtime/helper.log" >&2 2>/dev/null || true
    cat "$runtime/tessa.log" >&2
    exit 1
}
wait_rects

i=0
while [ "$i" -lt 150 ]; do
    if grep -q "REQUEST	$focused_out" "$runtime/helper.log" 2>/dev/null &&
        grep -q "REQUEST	$other_out" "$runtime/helper.log" 2>/dev/null; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 150 ]; then
    echo "helper did not receive requests for both outputs" >&2
    cat "$runtime/helper.log" >&2 2>/dev/null || true
    cat "$runtime/tessa.log" >&2
    exit 1
fi
grep -q "layout helper .* negotiated protocol 2" "$runtime/tessa.log" || {
    echo "protocol version negotiation was not logged" >&2
    grep "layout helper" "$runtime/tessa.log" >&2 || true
    exit 1
}
echo "per-output helpers + protocol v2: ok"

if ! grep -q "META	$other_out	.*focused=1" "$runtime/helper.log"; then
    echo "focused metadata was not delivered" >&2
    grep "META" "$runtime/helper.log" >&2 || true
    exit 1
fi

urgent_id=$(tessa-ctl state | awk -F '\t' -v out="$focused_out" '$1 == "WIN" && $9 == out { print $2; exit }')
start_ns=$(date +%s%N)
tessa-ctl dispatch urgent "$urgent_id" on
end_ns=$(date +%s%N)
elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
if [ "$elapsed_ms" -ge 500 ]; then
    echo "layout request blocked the compositor for ${elapsed_ms} ms" >&2
    exit 1
fi
i=0
while [ "$i" -lt 100 ]; do
    if grep -q "META	$focused_out	$urgent_id	.*urgent=1" "$runtime/helper.log" 2>/dev/null; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "urgent metadata was not delivered" >&2
    grep "META" "$runtime/helper.log" >&2 || true
    exit 1
fi
echo "asynchronous layout + focus/urgent metadata: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
cleanup
echo "layout-helper v2 test passed"
