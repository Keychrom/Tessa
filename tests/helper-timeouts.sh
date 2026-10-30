#!/bin/sh
# Verify the strict helper timeout guarantees: layout helper 100 ms and effect
# helper 200 ms by default. A helper that never replies must be killed and the
# compositor must keep running with rule/layout fallbacks.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v kitty >/dev/null 2>&1; then
    echo "kitty not found; skipping helper timeout test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-helper-timeout.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = false
xwayland = false
animations = false
layout = custom
layout_helper = sleep 30
layout_helper_timeout = 100
effect_helper = sleep 30
effect_helper_timeout = 200
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
        sleep 0.05
    done
    echo "log did not contain: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

start_ms=$(date +%s%3N)
tessa-ctl spawn kitty --class=tessa-timeout -T Timeout >/dev/null
wait_log "layout helper for HEADLESS-1 failed: response timed out"
wait_log "effect helper failed: response timed out"
end_ms=$(date +%s%3N)
elapsed=$((end_ms - start_ms))
if [ "$elapsed" -gt 1500 ]; then
    echo "helper timeout fallback took ${elapsed}ms, expected <= 1500ms" >&2
    exit 1
fi
echo "helper timeouts: ok (${elapsed}ms)"

i=0
while [ "$i" -lt 100 ]; do
    if tessa-ctl state 2>/dev/null | grep -q "tessa-timeout"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "compositor stopped serving state after helper timeouts" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "compositor survived helper timeouts: ok"

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
echo "helper timeout test passed"
