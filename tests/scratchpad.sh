#!/bin/sh
# Verify scratchpad window-rule assignment and toggle/move commands.
# Run from the repository root after building:
#   sh tests/scratchpad.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-scratchpad.XXXXXX")
tpid=
wpid=
cleanup() {
    [ -n "${wpid:-}" ] && kill "$wpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${wpid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
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
window-rule = app-id=tessa-scratch-test; scratchpad=true
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

"$runtime/window-test" tessa-scratch-test ScratchTest >"$runtime/window.log" 2>&1 &
wpid=$!

win_fields() {
    tessa-ctl state >"$runtime/state.out"
    awk -F '\t' '$1 == "WIN" && $7 == "tessa-scratch-test" { print $14, $15; exit }' "$runtime/state.out"
}

i=0
fields=
while [ "$i" -lt 100 ]; do
    fields=$(win_fields)
    [ -n "$fields" ] && break
    i=$((i + 1))
    sleep 0.1
done
if [ "$fields" != "1 0" ]; then
    echo "scratchpad rule did not hide the window (got '$fields')" >&2
    cat "$runtime/state.out" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "scratchpad rule: ok"

tessa-ctl dispatch toggle-scratchpad
sleep 0.2
fields=$(win_fields)
if [ "$fields" != "1 1" ]; then
    echo "toggle-scratchpad did not show the window (got '$fields')" >&2
    cat "$runtime/state.out" >&2
    exit 1
fi
focused=$(awk '$1 == "FOCUSED" { print $2 }' "$runtime/state.out")
if [ "$focused" = "0" ] || [ -z "$focused" ]; then
    echo "visible scratchpad window was not focused" >&2
    cat "$runtime/state.out" >&2
    exit 1
fi
echo "scratchpad toggle on: ok"

tessa-ctl dispatch toggle-scratchpad
sleep 0.2
fields=$(win_fields)
focused=$(awk '$1 == "FOCUSED" { print $2 }' "$runtime/state.out")
if [ "$fields" != "1 0" ] || [ "$focused" != "0" ]; then
    echo "toggle-scratchpad did not hide the window or clear focus (got '$fields', focus '$focused')" >&2
    cat "$runtime/state.out" >&2
    exit 1
fi
echo "scratchpad toggle off: ok"

tessa-ctl dispatch toggle-scratchpad
sleep 0.2
tessa-ctl dispatch move-to-scratchpad
sleep 0.2
fields=$(win_fields)
if [ "$fields" != "0 1" ]; then
    echo "move-to-scratchpad did not return the window to normal tiling (got '$fields')" >&2
    cat "$runtime/state.out" >&2
    exit 1
fi
tessa-ctl dispatch move-to-scratchpad
sleep 0.2
fields=$(win_fields)
if [ "$fields" != "1 1" ]; then
    echo "move-to-scratchpad did not assign the focused window (got '$fields')" >&2
    cat "$runtime/state.out" >&2
    exit 1
fi
echo "scratchpad move: ok"

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
echo "scratchpad test passed"
