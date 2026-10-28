#!/bin/sh
# Optional integration: real xwayland-satellite + Kitty. Skips when either is
# unavailable; the fake-satellite test covers DISPLAY readiness in CI.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v kitty >/dev/null 2>&1 || ! command -v xwayland-satellite >/dev/null 2>&1; then
    echo "kitty or xwayland-satellite not found; skipping integration test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-xwayland-kitty.XXXXXX")
tpid=
kpid=
cleanup() {
    [ -n "${kpid:-}" ] && kill "$kpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${kpid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

cat > "$runtime/config" <<'EOF'
panel = false
xwayland = true
xim = true
xim_server = fcitx
animations = false
terminal = kitty
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"
unset DISPLAY XMODIFIERS || true

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

i=0
while ! grep -q 'xwayland: connected on' "$runtime/tessa.log"; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "XWayland did not become ready" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

"$bin/tessa-ctl" spawn "sh -c 'echo \$\$ > $runtime/kitty.pid; exec kitty --class=tessa-kitty-x11 -T KittyX11'"
i=0
while [ ! -s "$runtime/kitty.pid" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "kitty wrapper did not start" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
kpid=$(cat "$runtime/kitty.pid")

i=0
while ! "$bin/tessa-ctl" state 2>/dev/null | awk -F '\t' '$1 == "WIN" && $7 == "tessa-kitty-x11" { found=1 } END { exit found ? 0 : 1 }'; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "kitty did not map" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

sleep 2
if ! kill -0 "$kpid" 2>/dev/null; then
    echo "kitty exited after mapping" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

if ! tr '\0' '\n' < "/proc/$kpid/environ" | grep -q '^DISPLAY=:'; then
    echo "kitty did not inherit a valid DISPLAY" >&2
    tr '\0' '\n' < "/proc/$kpid/environ" | grep '^DISPLAY=' >&2 || true
    exit 1
fi
if ! tr '\0' '\n' < "/proc/$kpid/environ" | grep -qx 'XMODIFIERS=@im=fcitx'; then
    echo "kitty did not inherit XMODIFIERS" >&2
    exit 1
fi
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor logged a failure" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

"$bin/tessa-ctl" quit >/dev/null 2>&1 || true
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
cleanup
echo "real XWayland + Kitty test passed"
