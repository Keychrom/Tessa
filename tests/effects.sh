#!/bin/sh
# Verify scenefx rounded-window rendering. Skips when Tessa was built without
# scenefx or when screenshot tools are unavailable.
# Requires foot, grim, and ImageMagick convert.
#   sh tests/effects.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1 ||
    ! command -v grim >/dev/null 2>&1 ||
    ! command -v convert >/dev/null 2>&1
then
    echo "foot, grim, or ImageMagick not found; skipping effects test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-effects.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
corner_radius = 24
blur = false
border_active = #ff0000
border_inactive = #ff0000
bg = #000000
bg_top = #000000
bg_bottom = #000000
wallpaper_art = false
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export WLR_BACKENDS=headless
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"
export WLR_RENDERER=pixman
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

tessa-ctl config >"$runtime/config.out"
if ! grep -q '^scenefx 1$' "$runtime/config.out"; then
    echo "built without scenefx; skipping effects test"
    tessa-ctl quit 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    tpid=
    trap - EXIT INT TERM
    rm -rf "$runtime"
    exit 0
fi

wait_win() {
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        line=$(printf '%s\n' "$state" | awk -F '	' '$1 == "WIN" { print; exit }')
        if [ -n "$line" ]; then
            printf '%s\n' "$line"
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "no window appeared" >&2
    printf '%s\n' "$state" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

tessa-ctl spawn foot -o colors.background=ffffff -o colors.foreground=000000 -T FXWhite
sleep 0.5
line=$(wait_win)
x=$(printf '%s\n' "$line" | cut -f 10)
y=$(printf '%s\n' "$line" | cut -f 11)
w=$(printf '%s\n' "$line" | cut -f 12)
h=$(printf '%s\n' "$line" | cut -f 13)
mx=$((x + w / 2))
my=$((y + h / 2))
grim -o HEADLESS-1 "$runtime/effects.png"

center=$(convert "$runtime/effects.png" -crop 1x1+"$mx"+"$my" +repage \
    -colorspace Gray -format '%[fx:mean]' info:)
corner=$(convert "$runtime/effects.png" -crop 1x1+"$((x + 2))"+"$((y + 2))" +repage \
    -colorspace Gray -format '%[fx:mean]' info:)
border=$(convert "$runtime/effects.png" -crop 1x1+"$mx"+"$((y + 1))" +repage \
    -format '%[fx:r],%[fx:g]' info:)

if ! awk -v v="$center" 'BEGIN { exit !(v > 0.7) }'; then
    echo "test window content is not white (luminance $center)" >&2
    exit 1
fi
if ! awk -v v="$corner" 'BEGIN { exit !(v < 0.15) }'; then
    echo "window corner is not rounded away (luminance $corner)" >&2
    exit 1
fi
if ! awk -F, -v r="${border%,*}" -v g="${border#*,}" \
    'BEGIN { exit !(r > 0.7 && g < 0.2) }'
then
    echo "active border was not drawn at the frame edge ($border)" >&2
    exit 1
fi
echo "rounded window content and border: ok"

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
echo "effects test passed"
