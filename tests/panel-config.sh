#!/bin/sh
# Verify panel.conf precedence and that the compositor reads shared panel
# visuals (panel colors and wallpaper) for Scene saves.
#   sh tests/panel-config.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-panel-config.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/scenes"
chmod 700 "$runtime" "$runtime/scenes"

cat > "$runtime/config" <<EOF
panel = false
xwayland = false
animations = false
bg = #102030
panel_bg = #111111
wallpaper_image = /tmp/base.png
wallpaper_fit = cover
font = LegacyFont
logo_text = Legacy
EOF

cat > "$runtime/panel.conf" <<EOF
font = PanelFont
logo_text = PanelText
bar_height = 50
bar_priority = clock=100, status=80
bar_overflow = true
panel_bg = #123456
wallpaper_image = /tmp/panel.png
wallpaper_fit = contain
EOF

if ! "$bin/tessa" --check-config "$runtime/config" >"$runtime/check.log" 2>&1; then
    echo "compositor rejected panel.conf" >&2
    cat "$runtime/check.log" >&2
    exit 1
fi
if ! grep -q '^config: ok$' "$runtime/check.log"; then
    echo "compositor config validation did not pass" >&2
    cat "$runtime/check.log" >&2
    exit 1
fi

summary=$(TESSA_CONFIG="$runtime/config" TESSA_PANEL_CONFIG= "$bin/tessa-panel" --check 2>&1)
case "$summary" in
    *"panel config= base-config=$runtime/config"*) ;;
    *)
        echo "empty TESSA_PANEL_CONFIG did not disable panel.conf" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
case "$summary" in
    *"font=LegacyFont"*) ;;
    *)
        echo "base config font was not used without panel.conf" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
case "$summary" in
    *"logo-text=Legacy"*) ;;
    *)
        echo "base config logo_text was not used without panel.conf" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac

summary=$(TESSA_CONFIG="$runtime/config" "$bin/tessa-panel" --check 2>&1)
case "$summary" in
    *"panel config=$runtime/panel.conf"*) ;;
    *)
        echo "panel.conf was not loaded from the config directory" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
case "$summary" in
    *"panel font=PanelFont"*) ;;
    *)
        echo "panel.conf did not override font" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
case "$summary" in
    *"logo-text=PanelText"*) ;;
    *)
        echo "panel.conf did not override logo_text" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
case "$summary" in
    *"bar-height=50"*) ;;
    *)
        echo "panel.conf did not override bar_height" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac

cat > "$runtime/extra.conf" <<EOF
logo_text = Extra
EOF
summary=$(TESSA_CONFIG="$runtime/config" TESSA_PANEL_CONFIG="$runtime/extra.conf" "$bin/tessa-panel" --check 2>&1)
case "$summary" in
    *"panel config=$runtime/extra.conf"*) ;;
    *)
        echo "TESSA_PANEL_CONFIG override path was not used" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
case "$summary" in
    *"logo-text=Extra"*) ;;
    *)
        echo "TESSA_PANEL_CONFIG override did not apply" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
echo "panel config precedence: ok"

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
unset TESSA_PANEL_CONFIG

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
sleep 0.3

if ! grep -q "config: loaded panel settings from $runtime/panel.conf" "$runtime/tessa.log"; then
    echo "compositor did not load panel.conf" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

"$bin/tessa-ctl" scene save split >/dev/null
scene="$runtime/scenes/split.scene"
for expected in \
    '^panel_bg = #123456$' \
    '^image = /tmp/panel.png$' \
    '^fit = contain$'
do
    if ! grep -q "$expected" "$scene"; then
        echo "scene save did not capture panel.conf visual: $expected" >&2
        cat "$scene" >&2
        exit 1
    fi
done
echo "compositor panel visuals: ok"

sed -i 's/#123456/#654321/' "$runtime/panel.conf"
i=0
while [ "$i" -lt 50 ]; do
    if grep -q "config watch: reloading after file change" "$runtime/tessa.log"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 50 ]; then
    echo "panel.conf change did not trigger a config reload" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
"$bin/tessa-ctl" scene save reloaded >/dev/null
if ! grep -q '^panel_bg = #654321$' "$runtime/scenes/reloaded.scene"; then
    echo "panel.conf reload did not reach the compositor" >&2
    cat "$runtime/scenes/reloaded.scene" >&2
    exit 1
fi
echo "panel config reload: ok"

"$bin/tessa-ctl" quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime"
echo "panel config test passed"
