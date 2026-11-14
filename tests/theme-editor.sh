#!/bin/sh
# Verify the control-center theme editor writes theme-colors.conf, reloads the
# compositor, and can reset back to the configured palette.
# Requires wayland-scanner, cc, and pkg-config. Run from the repository root:
#   sh tests/theme-editor.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
for tool in wayland-scanner cc pkg-config; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping theme editor test"
        exit 0
    fi
done

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-theme-editor.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime" "$runtime/build"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
panel_style = unified
control_features = all
animations = false
accent = #e2684f
EOF

wayland-scanner client-header "$root/tests/protocol/wlr-virtual-pointer-unstable-v1.xml" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$root/tests/protocol/wlr-virtual-pointer-unstable-v1.xml" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-protocol.c"
cc -O2 -I"$runtime/build" -o "$runtime/build/automation" \
    "$root/tests/automation/main.c" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-protocol.c" \
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

wait_log() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if grep -qF "$pattern" "$runtime/tessa.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not contain: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_accent() {
    expected=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if "$bin/tessa-ctl" config 2>/dev/null | grep -qF "accent $expected"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "compositor accent did not become $expected" >&2
    "$bin/tessa-ctl" config >&2 || true
    exit 1
}

run() { env XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=wayland-0 "$runtime/build/automation" "$@"; }

wait_log "tessa-panel: bar surface"
wait_accent "#e2684f"

"$bin/tessa-ctl" panel theme >/dev/null
wait_log "tessa-panel: control: open view=theme"
sleep 0.5

# Indigo follows Sumi and Vermilion in the third palette card in the 1920x1080 headless layout.
run abs 1610 275
sleep 0.3
run click 0x110
wait_log "tessa-panel: theme: applied indigo"
wait_accent "#7aa2f7"
grep -q '^theme-role = accent = #7aa2f7$' "$runtime/theme-colors.conf"
grep -q '^theme-role = window.border.active = #7aa2f7$' "$runtime/theme-colors.conf"
grep -q '^theme-role = bar.background = #0e1626$' "$runtime/theme-colors.conf"
grep -q '^theme-role = wallpaper.top = #16233f$' "$runtime/theme-colors.conf"
echo "theme preset + compositor reload: ok"

sleep 0.4
# Reset sits at the bottom-right of the theme page.
run abs 1846 548
sleep 0.3
run click 0x110
wait_log "tessa-panel: theme: reset"
wait_accent "#e2684f"
if [ -e "$runtime/theme-colors.conf" ]; then
    echo "theme-colors.conf still exists after reset" >&2
    exit 1
fi
echo "theme reset: ok"

"$bin/tessa-ctl" quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE "panic|Assertion|double free" "$runtime/tessa.log"; then
    echo "theme editor test crashed" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "theme editor test passed"
