#!/bin/sh
# Verify per-window GPU shader effects. Headless pixman compositors use the
# shared-memory upload path; a working surfaceless EGL/llvmpipe stack applies
# the shader and the window content becomes monochrome.
#   sh tests/window-shader.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

for tool in foot grim convert; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping window shader test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-shader.XXXXXX")
tpid=
fpid=
cleanup() {
    [ -n "${fpid:-}" ] && kill "$fpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

chmod 700 "$runtime"
if [ -n "${TESSA_CAPTURE_DIR:-}" ]; then
    mkdir -p "$TESSA_CAPTURE_DIR"
fi

cat > "$runtime/red.sh" <<'SH'
#!/bin/sh
printf '\033[41m                                                            \033[0m\n'
i=0
while [ $i -lt 12 ]; do
    echo "window shader test line $i"
    i=$((i + 1))
done
sleep 120
SH
chmod +x "$runtime/red.sh"

write_config() {
    {
        echo "panel = false"
        echo "xwayland = false"
        echo "animations = false"
        echo "bg = #808080"
        if [ "$1" = "on" ]; then
            echo "window-rule = app-id=foot; shader=mono; shader-strength=1.0"
        fi
    } > "$runtime/config"
}

write_config on

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

env WAYLAND_DISPLAY=wayland-0 foot "$runtime/red.sh" >"$runtime/foot.log" 2>&1 &
fpid=$!

geometry() {
    i=0
    while [ "$i" -lt 100 ]; do
        line=$(tessa-ctl state 2>/dev/null | awk '$1 == "WIN" && $7 == "foot" { print $10, $11, $12, $13 }')
        if [ -n "$line" ]; then
            echo "$line"
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "foot window did not map" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

read x y w h <<EOF2
$(geometry)
EOF2
# Stay inside the compositor-drawn border, which keeps its accent colour.
inset=8
w=$((w - inset * 2))
h=$((h - inset * 2))
x=$((x + inset))
y=$((y + inset))

sleep 1.5
if ! grep -qF "window shader:" "$runtime/tessa.log"; then
    echo "shader backend did not initialize" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
if grep -qF "effect unavailable" "$runtime/tessa.log"; then
    echo "shader effect was not applied" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

grim -o HEADLESS-1 "$runtime/on.png"
if [ -n "${TESSA_CAPTURE_DIR:-}" ]; then
    cp "$runtime/on.png" "$TESSA_CAPTURE_DIR/window-shader-on.png"
fi
on_sat=$(convert "$runtime/on.png" -crop "${w}x${h}+${x}+${y}" +repage \
    -colorspace HSL -channel G -separate +channel \
    -format '%[fx:maxima]' info:)

# Removing the rule through the config watcher must restore the normal content.
write_config off
sleep 1.5
grim -o HEADLESS-1 "$runtime/off.png"
if [ -n "${TESSA_CAPTURE_DIR:-}" ]; then
    cp "$runtime/off.png" "$TESSA_CAPTURE_DIR/window-shader-off.png"
fi
off_sat=$(convert "$runtime/off.png" -crop "${w}x${h}+${x}+${y}" +repage \
    -colorspace HSL -channel G -separate +channel \
    -format '%[fx:maxima]' info:)

if ! awk -v s="$on_sat" 'BEGIN { exit !(s < 0.05) }'; then
    echo "mono shader did not produce grayscale output: max saturation $on_sat" >&2
    exit 1
fi
if ! awk -v s="$off_sat" 'BEGIN { exit !(s > 0.30) }'; then
    echo "removing the shader rule did not restore colored content: max saturation $off_sat" >&2
    exit 1
fi

if [ -n "${TESSA_CAPTURE_DIR:-}" ]; then
    echo "captures: $TESSA_CAPTURE_DIR"
fi
echo "window shader test passed"
