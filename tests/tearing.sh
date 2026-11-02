#!/bin/sh
# Verify wp-tearing-control-v1 advertisement and the async-hint path.
# Headless outputs cannot tear, but the compositor must accept the hint and
# either count a tearing request or fall back cleanly.
# Requires cc and wayland-scanner.
#   sh tests/tearing.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

for tool in cc wayland-scanner; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping tearing test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

xml=
for candidate in \
    /usr/share/wayland-protocols/staging/tearing-control/tearing-control-v1.xml \
    /usr/share/wayland-protocols/unstable/tearing-control/tearing-control-v1.xml
do
    if [ -f "$candidate" ]; then
        xml=$candidate
        break
    fi
done
if [ -z "$xml" ]; then
    echo "tearing-control-v1 protocol XML not found; skipping"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-tearing.XXXXXX")
tpid=
cpid=
cleanup() {
    [ -n "${cpid:-}" ] && kill "$cpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${cpid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/build"
chmod 700 "$runtime"
cat >"$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
outer_gaps = 0
direct_scanout = true
tearing = fullscreen
EOF

wayland-scanner client-header "$xml" "$runtime/build/tearing-control-v1-client-protocol.h"
wayland-scanner private-code "$xml" "$runtime/build/tearing-control-v1-protocol.c"
cc -O2 -I"$runtime/build" -I"$root/protocol" -o "$runtime/build/tearing-test" \
    "$root/tests/tearing/main.c" \
    "$runtime/build/tearing-control-v1-protocol.c" \
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

rendering=$(tessa-ctl rendering)
printf '%s\n' "$rendering" | grep -q '^tearing_protocol 1$' || {
    echo "wp-tearing-control-v1 is not advertised" >&2
    printf '%s\n' "$rendering" >&2
    exit 1
}

"$runtime/build/tearing-test" >"$runtime/client.log" 2>&1 &
cpid=$!
i=0
while [ "$i" -lt 100 ]; do
    if tessa-ctl state 2>/dev/null | grep -q "TearingTest"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "tearing test client did not map" >&2
    cat "$runtime/client.log" >&2
    tail -80 "$runtime/tessa.log" >&2
    exit 1
fi

sleep 1
rendering=$(tessa-ctl rendering)
printf '%s\n' "$rendering" | grep -q '^OUTPUT ' || {
    echo "rendering status has no output line" >&2
    exit 1
}
requests=$(printf '%s\n' "$rendering" | sed -n 's/.*tearing_requests=\([0-9][0-9]*\).*/\1/p' | head -1)
failures=$(printf '%s\n' "$rendering" | sed -n 's/.*tearing_failures=\([0-9][0-9]*\).*/\1/p' | head -1)
if [ "${requests:-0}" -eq 0 ] && [ "${failures:-0}" -eq 0 ]; then
    echo "async hint did not reach the tearing path" >&2
    printf '%s\n' "$rendering" >&2
    grep -E 'tearing|direct scanout' "$runtime/tessa.log" >&2 || true
    exit 1
fi

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
rm -rf "$runtime" 2>/dev/null || true
echo "tearing test passed (requests=${requests:-0} failures=${failures:-0})"
