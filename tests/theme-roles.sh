#!/bin/sh
# Verify semantic theme roles in the compositor and panel.
# Requires foot, grim, and ImageMagick convert.
#   sh tests/theme-roles.sh
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
        echo "$tool not found; skipping theme role test"
        exit 0
    fi
done

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-theme-roles.XXXXXX")
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
panel = true
xwayland = false
animations = false
shadows = false
corner_radius = 0
wallpaper_art = false
accent = #ff0000
border_active = #ff0000
border_inactive = #00ff00
bg = #000000
panel_bg = #000000
bg_top = #000000
bg_bottom = #000000
theme-role = accent = #00ff00
theme-role = window.border.active = #abcdef
theme-role = window.border.inactive = #112233
theme-role = window.background = #101112
theme-role = panel.background = #ff0000
theme-role = panel.foreground = #f0f4ff
theme-role = wallpaper.top = #101112
theme-role = wallpaper.bottom = #101112
window-rule = title=RoleA*; float=true; size=300x200; position=80,200
window-rule = title=RoleB*; float=true; size=260x180; position=500,200
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
    exit 1
}

win_field() {
    title=$1
    field=$2
    tessa-ctl state | awk -F '	' -v t="$title" -v f="$field" \
        '$1 == "WIN" && $8 == t { print $(f + 0); exit }'
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

wait_log "tessa-panel: bar surface"
tessa-ctl config >"$runtime/config.out"
grep -q "^accent #00ff00$" "$runtime/config.out"
grep -q "^border_active #abcdef$" "$runtime/config.out"
grep -q "^border_inactive #112233$" "$runtime/config.out"
grep -q "^bg #101112$" "$runtime/config.out"
grep -q "^theme_role_count 8$" "$runtime/config.out"
grep -q "^theme_role window.border.active #abcdef$" "$runtime/config.out"
tessa-ctl config --json >"$runtime/config.json"
grep -q '"theme_roles":\[' "$runtime/config.json"
grep -q '"name":"panel.background","color":"#ff0000"' "$runtime/config.json"
echo "theme role config: ok"

tessa-ctl spawn foot -T RoleA
tessa-ctl spawn foot -T RoleB
wait_state "OCC 1 2"
wait_win RoleA 5 1
wait_win RoleB 5 1

a_id=$(win_field RoleA 2)
a_x=$(win_field RoleA 10)
a_y=$(win_field RoleA 11)
a_w=$(win_field RoleA 12)
b_x=$(win_field RoleB 10)
b_y=$(win_field RoleB 11)
b_w=$(win_field RoleB 12)

tessa-ctl dispatch focus "$a_id"
wait_state "FOCUSED $a_id"
sleep 0.4
grim -o HEADLESS-1 "$runtime/roles.png"

wall=$(pixel "$runtime/roles.png" 960 900)
wall_rgb=$(printf '%s\n' "$wall" | sed -n 's/.*srgb(\([0-9]*\),\([0-9]*\),\([0-9]*\)).*/\1 \2 \3/p')
if [ -z "$wall_rgb" ] || ! awk -v v="$wall_rgb" 'BEGIN {
    split(v, a, " ");
    exit !((a[1] >= 10 && a[1] <= 22) && (a[2] >= 11 && a[2] <= 23) && (a[3] >= 12 && a[3] <= 24))
}'; then
    echo "wallpaper role was not rendered (pixel $wall)" >&2
    exit 1
fi
expect_pixel "$runtime/roles.png" $((a_x + a_w / 2)) $((a_y + 1)) "171,205,239" "active border role"
expect_pixel "$runtime/roles.png" $((b_x + b_w / 2)) $((b_y + 1)) "17,34,51" "inactive border role"

bar=$(pixel "$runtime/roles.png" 700 15)
case "$bar" in
    *"255,0"*) ;;
    *)
        red=$(printf '%s\n' "$bar" | sed -n 's/.*srgb(\([0-9]*\),.*/\1/p')
        if [ -z "$red" ] || [ "$red" -lt 150 ]; then
            echo "panel background role was not rendered (pixel $bar)" >&2
            exit 1
        fi
        ;;
esac
echo "panel theme role: ok"

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
echo "theme role test passed"
