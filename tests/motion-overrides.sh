#!/bin/sh
# Verify per-window animation overrides and spring curves using real xdg
# clients and the debug animation log.
#   sh tests/motion-overrides.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN:-$root/zig-out/bin}

if ! command -v cc >/dev/null 2>&1; then
    echo "cc not found; skipping motion override test"
    exit 0
fi
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-motion-overrides.XXXXXX")
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
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
xim = false
animations = true
animation_ms = 200
animation_open_ms = 200
animation_workspace_ms = 200
animation_close_ms = 200
spring = bounce, 0.35, 1.4
window-rule = app-id=tessa-noanim; animation=false
window-rule = app-id=tessa-slow; animation-ms=600
window-rule = app-id=tessa-spring; animation-open-ms=450; animation-curve=bounce; animation-close-ms=350; animation-close-curve=bounce
EOF

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
export WLR_HEADLESS_OUTPUTS=1
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

if ! tessa-ctl config-check >"$runtime/check.out"; then
    cat "$runtime/check.out" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
if ! grep -q "config: ok" "$runtime/check.out"; then
    cat "$runtime/check.out" >&2
    exit 1
fi

"$runtime/window-test" tessa-noanim NoAnim >"$runtime/noanim.log" 2>&1 &
pids="$pids $!"
"$runtime/window-test" tessa-slow Slow >"$runtime/slow.log" 2>&1 &
pids="$pids $!"
"$runtime/window-test" tessa-spring Spring >"$runtime/spring.log" 2>&1 &
pids="$pids $!"

i=0
while [ "$i" -lt 100 ]; do
    count=$(tessa-ctl state 2>/dev/null | awk -F '\t' '$1 == "WIN" { n++ } END { print n + 0 }')
    if [ "${count:-0}" -ge 3 ]; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "${count:-0}" -lt 3 ]; then
    echo "windows did not map" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

get_id() {
    tessa-ctl state | awk -F '\t' -v app="$1" '$1 == "WIN" && $7 == app { print $2; exit }'
}
noanim_id=$(get_id tessa-noanim)
slow_id=$(get_id tessa-slow)
spring_id=$(get_id tessa-spring)
for id in "$noanim_id" "$slow_id" "$spring_id"; do
    if [ -z "$id" ]; then
        echo "window id lookup failed" >&2
        tessa-ctl state >&2
        exit 1
    fi
done

sleep 0.5
if grep -q "animation: start id=$noanim_id " "$runtime/tessa.log"; then
    echo "noanim window unexpectedly animated" >&2
    grep "animation: start id=$noanim_id " "$runtime/tessa.log" >&2
    exit 1
fi
if ! grep -q "animation: start id=$slow_id from=0,18 ms=600 curve=bezier" "$runtime/tessa.log"; then
    echo "slow window did not use its 600 ms override" >&2
    grep "animation: start id=$slow_id " "$runtime/tessa.log" >&2 || true
    exit 1
fi
if ! grep -q "animation: start id=$spring_id from=0,18 ms=450 curve=spring" "$runtime/tessa.log"; then
    echo "spring window did not use its spring curve/450 ms override" >&2
    grep "animation: start id=$spring_id " "$runtime/tessa.log" >&2 || true
    exit 1
fi
echo "per-window open animation overrides: ok"

tessa-ctl workspace 2
sleep 0.2
tessa-ctl workspace 1
sleep 0.2
if grep -q "animation: start id=$noanim_id " "$runtime/tessa.log"; then
    echo "noanim window unexpectedly animated on workspace switch" >&2
    grep "animation: start id=$noanim_id " "$runtime/tessa.log" >&2
    exit 1
fi
if ! grep -q "animation: start id=$slow_id from=-54,0 ms=600 curve=bezier" "$runtime/tessa.log"; then
    echo "slow window did not use its 600 ms workspace override" >&2
    grep "animation: start id=$slow_id " "$runtime/tessa.log" >&2 || true
    exit 1
fi
if ! grep -q "animation: start id=$spring_id from=-54,0 ms=200 curve=spring" "$runtime/tessa.log"; then
    echo "spring window did not use its spring workspace curve" >&2
    grep "animation: start id=$spring_id " "$runtime/tessa.log" >&2 || true
    exit 1
fi
echo "per-window workspace animation overrides: ok"

tessa-ctl dispatch close "$noanim_id"
tessa-ctl dispatch close "$slow_id"
tessa-ctl dispatch close "$spring_id"
sleep 0.5

if grep -q "close animation: start id=$noanim_id " "$runtime/tessa.log"; then
    echo "noanim window unexpectedly produced a close effect" >&2
    grep "close animation: start id=$noanim_id " "$runtime/tessa.log" >&2
    exit 1
fi
if ! grep -q "close animation: start id=$slow_id .*ms=600 curve=bezier" "$runtime/tessa.log"; then
    echo "slow window did not use its 600 ms close override" >&2
    grep "close animation: start id=$slow_id " "$runtime/tessa.log" >&2 || true
    exit 1
fi
if ! grep -q "close animation: start id=$spring_id .*ms=350 curve=spring" "$runtime/tessa.log"; then
    echo "spring window did not use its 350 ms spring close override" >&2
    grep "close animation: start id=$spring_id " "$runtime/tessa.log" >&2 || true
    exit 1
fi
echo "per-window close animation overrides: ok"

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
echo "motion override test passed"
