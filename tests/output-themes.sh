#!/bin/sh
# Verify per-output theme rules for compositor backgrounds, window borders,
# and the panel bar. Requires foot, grim, and ImageMagick convert.
#   sh tests/output-themes.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
for tool in foot grim convert; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping output theme test"
        exit 0
    fi
done

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-output-theme.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

write_config() {
    panel=$1
    cat > "$runtime/config" <<EOF
panel = $panel
xwayland = false
animations = false
shadows = false
corner_radius = 0
gaps = 10
outer_gaps = 10
accent = #ff0000
border_active = #ff0000
border_inactive = #00ff00
bg = #000000
wallpaper_art = false
window-rule = title=ThemeA*; float=true; size=300x200; position=80,140
window-rule = title=ThemeB*; float=true; size=260x180; position=500,140
output-rule = output=HEADLESS-*; accent=#123456; bg=#101112; border-active=#abcdef; border-inactive=#112233; panel-bg=#203040; panel-fg=#f0f4ff; bg-top=#203040; bg-bottom=#101112; bar-height=56; bar-top-margin=8; bar-side-margin=20
EOF
}

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"

start_compositor() {
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
}

stop_compositor() {
    tessa-ctl quit 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    tpid=
    i=0
    while pgrep -x tessa-panel >/dev/null 2>&1; do
        i=$((i + 1))
        if [ "$i" -ge 20 ]; then
            pkill -x tessa-panel 2>/dev/null || true
            break
        fi
        sleep 0.1
    done
    rm -f "$runtime/tessa.sock"
}

wait_state() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        if printf '%s\n' "$state" | grep -q "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not contain: $pattern" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

wait_win() {
    title=$1
    field=$2
    expected=$3
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        got=$(printf '%s\n' "$state" | awk -F '	' -v t="$title" -v f="$field" '
            $1 == "WIN" && $8 == t { print $(f + 0); exit }')
        if [ "$got" = "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "window '$title' field $field did not become '$expected'" >&2
    printf '%s\n' "$state" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

win_field() {
    title=$1
    field=$2
    tessa-ctl state | awk -F '	' -v t="$title" -v f="$field" \
        '$1 == "WIN" && $8 == t { print $(f + 0); exit }'
}

pixel() {
    convert "$1" -crop 1x1+"$2"+"$3" +repage -format '%[pixel:p{0,0}]' info:
}

expect_pixel() {
    image=$1
    x=$2
    y=$3
    expected=$4
    label=$5
    got=$(pixel "$image" "$x" "$y")
    case "$got" in
        *"$expected"*) ;;
        *)
            echo "$label color mismatch: expected $expected, got $got" >&2
            exit 1
            ;;
    esac
}

wait_log() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if grep -q "$pattern" "$runtime/tessa.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not contain: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

write_config false
start_compositor
wait_state "OUT HEADLESS-1 1 1 master"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"

tessa-ctl spawn foot -T ThemeA
tessa-ctl spawn foot -T ThemeB
wait_state "OCC 1 2"
wait_win ThemeA 5 1
wait_win ThemeB 5 1

a_id=$(win_field ThemeA 2)
a_x=$(win_field ThemeA 10)
a_y=$(win_field ThemeA 11)
a_w=$(win_field ThemeA 12)
b_x=$(win_field ThemeB 10)
b_y=$(win_field ThemeB 11)
b_w=$(win_field ThemeB 12)

tessa-ctl dispatch focus "$a_id"
wait_state "FOCUSED $a_id"
sleep 0.3
grim -o HEADLESS-1 "$runtime/theme.png"

expect_pixel "$runtime/theme.png" 20 900 "16,17,18" "per-output background"
expect_pixel "$runtime/theme.png" $((a_x + a_w / 2)) $((a_y + 1)) "171,205,239" "active border"
expect_pixel "$runtime/theme.png" $((b_x + b_w / 2)) $((b_y + 1)) "17,34,51" "inactive border"
echo "compositor output theme: ok"

stop_compositor
write_config true
start_compositor
wait_state "OUT HEADLESS-1 1 1 master"
wait_log "tessa-panel: bar: 56px top=8 side=20"
echo "panel output theme: ok"

stop_compositor
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime"
echo "output theme test passed"
