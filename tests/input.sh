#!/bin/sh
# Verify gesture/input config, tablet-v2 and pointer-gestures globals.
# Touch/tablet hardware events still need a physical device.
#   sh tests/input.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v cc >/dev/null 2>&1; then
    echo "cc not found; skipping input test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-input.XXXXXX")
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
gestures = true
gesture_fingers = 4
gesture_workspace_threshold = 140
gesture_launcher_threshold = 80
touch = true
tablet = true
pointer_constraints = true
xim = false
EOF

cat > "$runtime/registry.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>
static void global(void *d, struct wl_registry *r, uint32_t n, const char *iface, uint32_t v) {
    (void)d; (void)r; (void)n; (void)v;
    printf("%s\n", iface);
    fflush(stdout);
}
static void remove_global(void *d, struct wl_registry *r, uint32_t n) {
    (void)d; (void)r; (void)n;
}
static const struct wl_registry_listener listener = { global, remove_global };
int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    if (wl_display_roundtrip(display) < 0) return 1;
    if (wl_display_roundtrip(display) < 0) return 1;
    wl_display_disconnect(display);
    return 0;
}
EOF

cc -O2 -o "$runtime/registry" "$runtime/registry.c" \
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

tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
tessa-ctl config >"$runtime/config.out"
grep -q "^gestures 1$" "$runtime/config.out"
grep -q "^gesture_fingers 4$" "$runtime/config.out"
grep -q "^gesture_workspace_threshold 140$" "$runtime/config.out"
grep -q "^gesture_launcher_threshold 80$" "$runtime/config.out"
grep -q "^touch 1$" "$runtime/config.out"
grep -q "^tablet 1$" "$runtime/config.out"
grep -q "^pointer_constraints 1$" "$runtime/config.out"
tessa-ctl config --json >"$runtime/config.json"
grep -q '"gestures":true' "$runtime/config.json"
grep -q '"gesture_fingers":4' "$runtime/config.json"
grep -q '"tablet":true' "$runtime/config.json"
echo "input config: ok"

grep -q "gestures: 4-finger swipe" "$runtime/tessa.log"
grep -q "tablet-v2 enabled" "$runtime/tessa.log"
grep -q "pointer-constraints-v1 enabled" "$runtime/tessa.log"
grep -q "pointer-gestures-v1 enabled" "$runtime/tessa.log"
echo "input globals/logs: ok"

"$runtime/registry" >"$runtime/globals.out"
for global in zwp_pointer_gestures_v1 zwp_tablet_manager_v2 zwp_pointer_constraints_v1; do
    if ! grep -qx "$global" "$runtime/globals.out"; then
        echo "missing Wayland global: $global" >&2
        cat "$runtime/globals.out" >&2
        exit 1
    fi
done
echo "wayland input globals: ok"

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
echo "input test passed"
