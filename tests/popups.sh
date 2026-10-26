#!/bin/sh
# Verify that an xdg-shell client popup is mapped and rendered above its parent.
# Requires cc, wayland-scanner, grim, and ImageMagick's convert.
#   sh tests/popups.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

for tool in cc grim convert; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping popup test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-popup.XXXXXX")
tpid=
cpid=
cleanup() {
    [ -n "${cpid:-}" ] && kill "$cpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${cpid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
printf 'panel = false\nxwayland = false\nanimations = false\n' >"$runtime/config"

cc -O2 -I"$root/protocol" -o "$runtime/popup-test" \
    "$root/tests/popups/main.c" \
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

"$runtime/popup-test" >"$runtime/client.log" 2>&1 &
cpid=$!
i=0
while ! grep -q "popup-mapped" "$runtime/client.log" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "popup did not map" >&2
        cat "$runtime/client.log" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
sleep 0.3
grim -o HEADLESS-1 "$runtime/shot.png"
pixel=$(convert "$runtime/shot.png" -format '%[hex:p{108,88}]' info:)
case "$pixel" in
    FF0000|ff0000) ;;
    *)
        echo "popup pixel is $pixel, expected red at 108,88" >&2
        cp "$runtime/shot.png" /tmp/tessa-popup-failure.png 2>/dev/null || true
        exit 1
        ;;
esac
echo "xdg client popup rendering: ok"

kill "$cpid" 2>/dev/null || true
wait "$cpid" 2>/dev/null || true
cpid=
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
echo "popup test passed"
