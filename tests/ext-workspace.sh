#!/bin/sh
# Verify ext-workspace-v1: two outputs, groups and nine workspaces per group,
# workspace names/ids, and an activate request switching the active workspace.
#   sh tests/ext-workspace.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

for tool in cc wayland-scanner; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping ext-workspace test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

xml=
for candidate in \
    /usr/share/wayland-protocols/staging/ext-workspace/ext-workspace-v1.xml \
    /usr/share/wayland-protocols/unstable/ext-workspace/ext-workspace-v1.xml
do
    if [ -f "$candidate" ]; then
        xml=$candidate
        break
    fi
done
if [ -z "$xml" ]; then
    echo "ext-workspace-v1 protocol XML not found; skipping"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-ext-workspace.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/build"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
EOF

wayland-scanner client-header "$xml" "$runtime/build/ext-workspace-v1-client-protocol.h"
wayland-scanner private-code "$xml" "$runtime/build/ext-workspace-v1-protocol.c"
cc -O2 -I"$runtime/build" -o "$runtime/build/ext-workspace" \
    "$root/tests/ext-workspace/main.c" \
    "$runtime/build/ext-workspace-v1-protocol.c" \
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

if ! grep -q "ext-workspace-v1 enabled" "$runtime/tessa.log"; then
    echo "ext-workspace-v1 was not enabled" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

"$runtime/build/ext-workspace" >"$runtime/client.out" 2>"$runtime/client.err" || {
    cat "$runtime/client.out" >&2
    cat "$runtime/client.err" >&2
    tail -80 "$runtime/tessa.log" >&2
    exit 1
}
cat "$runtime/client.out"

grep -q '^groups=2 workspaces=18 active2=1 ' "$runtime/client.out"
tessa-ctl state >"$runtime/state.out"
grep -q '^ACTIVE 2$' "$runtime/state.out"
grep -q '^OUT .* 2 ' "$runtime/state.out"
echo "ext-workspace state activation: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime" 2>/dev/null || true
echo "ext-workspace test passed"
