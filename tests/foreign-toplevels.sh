#!/bin/sh
# Verify foreign-toplevel-management and ext-foreign-toplevel-list output.
# These are the compositor-side prerequisites for xdg-desktop-portal-wlr.
# Requires foot, cc, wayland-scanner, and wayland-protocols staging XML.
#   sh tests/foreign-toplevels.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping foreign-toplevel test"
    exit 0
fi
if ! command -v cc >/dev/null 2>&1 || ! command -v wayland-scanner >/dev/null 2>&1; then
    echo "cc or wayland-scanner not found; skipping foreign-toplevel test"
    exit 0
fi
protocols_dir=$(pkg-config --variable=pkgdatadir wayland-protocols 2>/dev/null || true)
ext_xml=$protocols_dir/staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml
if [ ! -f "$ext_xml" ]; then
    echo "ext-foreign-toplevel-list XML not found; skipping foreign-toplevel test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-toplevels.XXXXXX")
tpid=
hpid=
cleanup() {
    [ -n "${hpid:-}" ] && kill "$hpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$hpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime" "$runtime/build"
chmod 700 "$runtime"
printf 'panel = true\nxwayland = false\n' >"$runtime/config"

wayland-scanner client-header "$ext_xml" \
    "$runtime/build/ext-foreign-toplevel-list-v1-client-protocol.h"
wayland-scanner private-code "$ext_xml" \
    "$runtime/build/ext-foreign-toplevel-list-v1-protocol.c"
wayland-scanner client-header \
    "$root/tests/protocol/wlr-foreign-toplevel-management-unstable-v1.xml" \
    "$runtime/build/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"
wayland-scanner private-code \
    "$root/tests/protocol/wlr-foreign-toplevel-management-unstable-v1.xml" \
    "$runtime/build/wlr-foreign-toplevel-management-unstable-v1-protocol.c"
cc -O2 -I"$runtime/build" -o "$runtime/build/foreign-toplevels" \
    "$root/tests/foreign-toplevels/main.c" \
    "$runtime/build/ext-foreign-toplevel-list-v1-protocol.c" \
    "$runtime/build/wlr-foreign-toplevel-management-unstable-v1-protocol.c" \
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
export TESSA_PANEL_DEBUG=1

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

wait_client() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if grep -qF "$pattern" "$runtime/client.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "client did not report: $pattern" >&2
    cat "$runtime/client.log" 2>/dev/null || true
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "foreign-toplevel-management enabled"
wait_log "ext-foreign-toplevel-list enabled"
echo "foreign toplevel globals: ok"

"$runtime/build/foreign-toplevels" >"$runtime/client.log" 2>&1 &
hpid=$!
wait_client "wlr-manager"
wait_client "ext-list"

tessa-ctl spawn foot -T PortalTest
wait_client "ext-title=PortalTest"
wait_client "ext-app-id=foot"
wait_client "wlr-title=PortalTest"
wait_client "wlr-app-id=foot"
wait_client "wlr-state=2"
echo "toplevel metadata and activation: ok"

kill "$hpid" 2>/dev/null || true
wait "$hpid" 2>/dev/null || true
hpid=

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log"; then
    echo "compositor or panel did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime"
echo "foreign toplevel test passed"
