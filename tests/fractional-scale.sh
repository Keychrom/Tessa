#!/bin/sh
# Verify fractional-scale-v1 advertisement and runtime scale updates.
# Requires cc, wayland-scanner, and wlr-randr.
#   sh tests/fractional-scale.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v cc >/dev/null 2>&1 || ! command -v wayland-scanner >/dev/null 2>&1; then
    echo "cc or wayland-scanner not found; skipping fractional-scale test"
    exit 0
fi
if ! command -v wlr-randr >/dev/null 2>&1; then
    echo "wlr-randr not found; skipping fractional-scale test"
    exit 0
fi
protocols_dir=$(pkg-config --variable=pkgdatadir wayland-protocols 2>/dev/null || true)
scale_xml=$protocols_dir/staging/fractional-scale/fractional-scale-v1.xml
if [ ! -f "$scale_xml" ]; then
    echo "fractional-scale XML not found; skipping fractional-scale test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-fractional.XXXXXX")
tpid=
cpid=
cpid2=
cleanup() {
    [ -n "${cpid:-}" ] && kill "$cpid" 2>/dev/null || true
    [ -n "${cpid2:-}" ] && kill "$cpid2" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$cpid" 2>/dev/null || true
    wait "$cpid2" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime" "$runtime/build"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
EOF

wayland-scanner client-header "$scale_xml" \
    "$runtime/build/fractional-scale-v1-client-protocol.h"
wayland-scanner private-code "$scale_xml" \
    "$runtime/build/fractional-scale-v1-protocol.c"
cc -O2 -I"$runtime/build" -I"$root/protocol" -o "$runtime/build/fractional-scale" \
    "$root/tests/fractional-scale/main.c" \
    "$runtime/build/fractional-scale-v1-protocol.c" \
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

name=$(wlr-randr | sed -n '1s/ .*//p')
if [ -z "$name" ]; then
    echo "could not discover the output name" >&2
    wlr-randr >&2
    exit 1
fi

"$runtime/build/fractional-scale" >"$runtime/client.log" 2>&1 &
cpid=$!

wait_client() {
    log=$1
    pattern=$2
    i=0
    while [ "$i" -lt 80 ]; do
        if grep -qF "$pattern" "$log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "client did not report: $pattern" >&2
    cat "$log" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_client "$runtime/client.log" "scale 120"
wait_client "$runtime/client.log" "ready"
echo "fractional scale advertised: ok"

wlr-randr --output "$name" --scale 1.5
wait_client "$runtime/client.log" "scale 180"
wlr-randr | grep -q 'Scale: 1.500000'
grep -q "output scale: $name 1.50" "$runtime/tessa.log"
echo "1.5x fractional scale: ok"

# A toplevel created after the output scale last changed must still receive
# the initial preferred scale before its first buffer is configured.
"$runtime/build/fractional-scale" >"$runtime/client-late.log" 2>&1 &
cpid2=$!
wait_client "$runtime/client-late.log" "scale 180"
wait_client "$runtime/client-late.log" "ready"
echo "late toplevel initial scale: ok"

wlr-randr --output "$name" --scale 2
wait_client "$runtime/client.log" "scale 240"
echo "2x integer scale: ok"

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
echo "fractional scale test passed"
