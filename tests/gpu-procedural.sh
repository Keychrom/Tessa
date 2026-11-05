#!/bin/sh
# Verify the procedural GPU wallpaper path (no Cairo base texture).
#   sh tests/gpu-procedural.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-panel" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-gpu-procedural.XXXXXX")
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
cat > "$runtime/config" <<'CONF'
panel = true
xwayland = false
panel_modules = background
panel_renderer = gpu
wallpaper_engine = procedural
wallpaper_animation = on
wallpaper_fps = 30
wallpaper_art_opacity = 0.55
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
grep -qF "panel renderer=gpu overlay-renderer=cairo wallpaper-engine=procedural wallpaper-animation=on fps=30 idle-pause=120" "$runtime/check.log" || {
    echo "procedural wallpaper config was not parsed" >&2
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

wait_log "tessa-panel: gpu: OpenGL ES"
if grep -q "shader compile failed\|program link failed" "$runtime/tessa.log"; then
    echo "procedural shader failed to compile" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

if [ -n "${TESSA_CAPTURE_DIR:-}" ] && command -v grim >/dev/null 2>&1; then
    sleep 1.0
    grim "$TESSA_CAPTURE_DIR/procedural-1.png"
    sleep 1.0
    grim "$TESSA_CAPTURE_DIR/procedural-2.png"
    cp "$runtime/tessa.log" "$TESSA_CAPTURE_DIR/tessa-procedural.log"
    size=$(wc -c <"$TESSA_CAPTURE_DIR/procedural-1.png")
    if [ "$size" -lt 60000 ]; then
        echo "procedural screenshot looks empty ($size bytes)" >&2
        exit 1
    fi
    if cmp -s "$TESSA_CAPTURE_DIR/procedural-1.png" "$TESSA_CAPTURE_DIR/procedural-2.png"; then
        echo "procedural animation produced identical frames" >&2
        exit 1
    fi
fi

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "panel crashed during procedural rendering" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
cleanup
echo "gpu procedural test passed"
