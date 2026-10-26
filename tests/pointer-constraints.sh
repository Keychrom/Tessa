#!/bin/sh
# Verify pointer-constraints-v1 activation and deactivation on focus changes.
# Requires cc and wayland-scanner.
#   sh tests/pointer-constraints.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v cc >/dev/null 2>&1 || ! command -v wayland-scanner >/dev/null 2>&1; then
    echo "cc or wayland-scanner not found; skipping pointer-constraints test"
    exit 0
fi
protocols_dir=$(pkg-config --variable=pkgdatadir wayland-protocols 2>/dev/null || true)
constraints_xml=$protocols_dir/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml
if [ ! -f "$constraints_xml" ]; then
    echo "pointer-constraints XML not found; skipping pointer-constraints test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-constraints.XXXXXX")
tpid=
cpid=
cleanup() {
    [ -n "${cpid:-}" ] && kill "$cpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$cpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime" "$runtime/build"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
pointer_constraints = true
EOF

wayland-scanner client-header "$constraints_xml" \
    "$runtime/build/pointer-constraints-unstable-v1-client-protocol.h"
wayland-scanner private-code "$constraints_xml" \
    "$runtime/build/pointer-constraints-unstable-v1-protocol.c"
cc -O2 -I"$runtime/build" -I"$root/protocol" -o "$runtime/build/pointer-constraints" \
    "$root/tests/pointer-constraints/main.c" \
    "$runtime/build/pointer-constraints-unstable-v1-protocol.c" \
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

"$runtime/build/pointer-constraints" >"$runtime/client.log" 2>&1 &
cpid=$!

wait_client() {
    pattern=$1
    expected=${2:-1}
    i=0
    while [ "$i" -lt 150 ]; do
        count=$(grep -cF "$pattern" "$runtime/client.log" 2>/dev/null || true)
        if [ "$count" -ge "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "client did not report $expected occurrence(s) of: $pattern" >&2
    cat "$runtime/client.log" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_client "constraint-created"
wait_client "activated"
echo "pointer constraint activation: ok"

tessa-ctl workspace 2
wait_client "deactivated"
echo "pointer constraint deactivation: ok"

tessa-ctl workspace 1
wait_client "activated" 2
echo "pointer constraint reactivation: ok"

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
rm -rf "$runtime"
echo "pointer constraints test passed"
