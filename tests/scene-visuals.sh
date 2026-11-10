#!/bin/sh
# Verify per-scene theme colors and wallpaper switching, and that saving while
# a scene is active captures its visual tokens.
# Requires cc, pkg-config, grim, and ImageMagick convert.
#   sh tests/scene-visuals.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
for tool in cc pkg-config grim convert; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping scene visual test"
        exit 0
    fi
done

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-scene-visual.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/scenes"
chmod 700 "$runtime" "$runtime/scenes"
convert -size 1920x1080 xc:'#0000ff' "$runtime/blue.png"
convert -size 1920x1080 xc:'#ff0000' "$runtime/red.png"

cat > "$runtime/config" <<EOF
panel = true
xwayland = false
animations = false
wallpaper_image = $runtime/blue.png
wallpaper_art = false
panel_bg = #101010
bg = #000000
accent = #00ff00
EOF

cat > "$runtime/scenes/themed.scene" <<EOF
name = themed
workspace = 1
layout = master
gaps = 10
outer_gaps = 16
master_ratio = 0.58
master_count = 1
mosaic_ratio = 0.62
mosaic_min_size = 160
grid_columns = 0
column_width = 50%
center_focused_column = never

[theme]
accent = #ff00ff
bg = #001122
border_active = #ff0000
border_inactive = #0000ff
panel_bg = #220011
panel_fg = #ffffff
bg_top = #330000
bg_bottom = #000033

[wallpaper]
image = $runtime/red.png
fit = stretch
art = false
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_SCENE_DIR="$runtime/scenes"
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
    while [ "$i" -lt 120 ]; do
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

pixel() {
    convert "$1" -crop 1x1+960+700 +repage -format '%[pixel:p{0,0}]' info:
}

expect_pixel() {
    image=$1
    expected=$2
    label=$3
    got=$(pixel "$image")
    case "$got" in
        *"$expected"*) ;;
        *)
            echo "$label pixel mismatch: expected $expected, got $got" >&2
            exit 1
            ;;
    esac
}

wait_log "tessa-panel: bar surface"
sleep 0.6
grim -o HEADLESS-1 "$runtime/base.png"
expect_pixel "$runtime/base.png" "0,0,255" "base wallpaper"

"$bin/tessa-ctl" scene activate themed >/dev/null
wait_log "tessa-panel: scene visual themed"
sleep 1.0
grim -o HEADLESS-1 "$runtime/scene.png"
expect_pixel "$runtime/scene.png" "255,0,0" "scene wallpaper"
"$bin/tessa-ctl" state | grep -q '^SCENE_STYLE	HEADLESS-1	themed	#ff00ff	#001122	#330000	#000033	#220011	#ffffff	#ff0000	#0000ff	'
echo "scene wallpaper + style state: ok"

"$bin/tessa-ctl" workspace 2 >/dev/null
wait_log "tessa-panel: scene visual cleared"
sleep 1.0
grim -o HEADLESS-1 "$runtime/clear.png"
expect_pixel "$runtime/clear.png" "0,0,255" "restored base wallpaper"
echo "scene visual clear: ok"

# Saving while the scene is active captures its colors and wallpaper.
"$bin/tessa-ctl" workspace 1 >/dev/null
sleep 0.2
"$bin/tessa-ctl" scene save themed-copy >/dev/null
wait_log "scene: saved 'themed-copy'"
grep -q '^\[theme\]$' "$runtime/scenes/themed-copy.scene"
grep -q '^accent = #ff00ff$' "$runtime/scenes/themed-copy.scene"
grep -q '^panel_bg = #220011$' "$runtime/scenes/themed-copy.scene"
grep -q '^\[wallpaper\]$' "$runtime/scenes/themed-copy.scene"
grep -q "^image = $runtime/red.png$" "$runtime/scenes/themed-copy.scene"
grep -q '^fit = stretch$' "$runtime/scenes/themed-copy.scene"
echo "scene visual capture: ok"

"$bin/tessa-ctl" quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE "panic|Assertion|double free" "$runtime/tessa.log"; then
    echo "scene visual test crashed" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "scene visual test passed"
