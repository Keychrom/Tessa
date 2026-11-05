#!/bin/sh
# Verify the opt-in GPU background renderer, including its Cairo fallback when
# the headless pixman compositor cannot provide EGL/dmabuf.
#   sh tests/gpu-background.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-gpu-fallback.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
if [ -n "${TESSA_CAPTURE_DIR:-}" ]; then
    mkdir -p "$TESSA_CAPTURE_DIR"
fi
cat > "$runtime/config" <<CONF
panel = true
xwayland = false
panel_renderer = gpu
overlay_renderer = gpu
wallpaper_animation = true
wallpaper_fps = 30
CONF

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

"$bin/tessa-panel" --check >"$runtime/check.log" 2>&1
grep -qF "panel renderer=gpu overlay-renderer=gpu wallpaper-engine=cairo wallpaper-animation=on fps=30 idle-pause=120" "$runtime/check.log" || {
    echo "panel renderer config was not parsed" >&2
    cat "$runtime/check.log" >&2
    exit 1
}

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

wait_log "tessa-panel: bar surface:"

# The GPU path logs either a successful EGL init or a fallback reason. Under
# pixman the EGL window surface normally fails and the panel continues with
# Cairo.
i=0
while [ "$i" -lt 100 ]; do
    if grep -qE 'tessa-panel: gpu: (EGL|.*using Cairo|.*failed)' "$runtime/tessa.log"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if ! grep -qE 'tessa-panel: gpu: (EGL|.*using Cairo|.*failed)' "$runtime/tessa.log"; then
    echo "GPU backend did not report its state" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
if grep -qE 'shader compile failed|program link failed|eglSwapBuffers failed' "$runtime/tessa.log"; then
    echo "GPU backend reported a rendering failure" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
if [ -n "${TESSA_CAPTURE_DIR:-}" ] && command -v grim >/dev/null 2>&1; then
    mkdir -p "$TESSA_CAPTURE_DIR"
    sleep 1.0
    grim "$TESSA_CAPTURE_DIR/gpu-background-1.png"
    sleep 1.0
    grim "$TESSA_CAPTURE_DIR/gpu-background-2.png"
    cp "$runtime/tessa.log" "$TESSA_CAPTURE_DIR/tessa-gpu.log"
    size=$(wc -c <"$TESSA_CAPTURE_DIR/gpu-background-1.png")
    if [ "$size" -lt 60000 ]; then
        echo "background screenshot looks empty ($size bytes)" >&2
        exit 1
    fi
    if grep -q "tessa-panel: gpu: EGL" "$runtime/tessa.log"; then
        if cmp -s "$TESSA_CAPTURE_DIR/gpu-background-1.png" "$TESSA_CAPTURE_DIR/gpu-background-2.png"; then
            echo "GPU wallpaper animation produced identical frames" >&2
            exit 1
        fi
    fi
fi

tessa-ctl launcher
wait_log "tessa-panel: launcher style:"
sleep 0.5
if grep -qE 'overlay program link failed|overlay draw failed' "$runtime/tessa.log"; then
    echo "GPU overlay failed" >&2
    grep -E 'overlay program link failed|overlay draw failed' "$runtime/tessa.log" >&2
    exit 1
fi
tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "panel crashed during GPU fallback" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

grep "tessa-panel: gpu:" "$runtime/tessa.log" || true

trap - EXIT INT TERM
cleanup
echo "gpu background test passed"
