#!/bin/sh
# Shell v2: bar module selection/order, per-surface fonts and colors, a PPM
# wallpaper shader source, and layer rules applied to panel layer surfaces.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v grim >/dev/null 2>&1; then
    echo "grim not found; skipping shell v2 test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-shell-v2.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

cat > "$runtime/shader.sh" <<'EOF'
#!/bin/sh
printf 'P6\n64 64\n255\n'
exec python3 -c 'import sys; sys.stdout.buffer.write(bytes((200, 40, 90)) * 64 * 64)'
EOF
chmod +x "$runtime/shader.sh"
mkdir -p "$runtime/theme"
printf 'theme-role = accent = #123456\n' > "$runtime/theme/theme.conf"

cat > "$runtime/config" <<EOF
panel = true
xwayland = false
animations = false
theme = theme
bg = #000000
bg_top = #000000
bg_bottom = #000000
wallpaper_art = false
wallpaper_shader = $runtime/shader.sh
wallpaper_fit = stretch
bar_layout = logo, workspaces, clock, layout, groups, mode, effects, tray, status
bar_font = DejaVu Sans
launcher-font = Noto Sans
popover_font = Terminus
toast-font = JetBrains Mono
bar_fg = #102030
launcher-fg = #203040
popover_fg = #304050
toast-fg = #405060
bar-bg = #0A141E
launcher_bg = #0B1622
popover-bg = #0C1826
toast_bg = #0D1A2A
layer-rule = namespace=tessa-bar; opacity=0.75; corner-radius=21; blur=false
layer-rule = namespace=tessa-overlay; opacity=0.80; corner-radius=23; blur=false
EOF

export TESSA_CONFIG="$runtime/config"

"$bin/tessa-panel" --check >"$runtime/check.log" 2>&1
grep -qF "panel bar-font=DejaVu Sans launcher-font=Noto Sans popover-font=Terminus toast-font=JetBrains Mono" "$runtime/check.log" || {
    echo "per-surface fonts were not resolved" >&2
    cat "$runtime/check.log" >&2
    exit 1
}
grep -qF "panel bar-bg=0.039,0.078,0.118 launcher-bg=0.043,0.086,0.133 popover-bg=0.047,0.094,0.149 toast-bg=0.051,0.102,0.165" "$runtime/check.log" || {
    echo "per-surface backgrounds were not resolved" >&2
    cat "$runtime/check.log" >&2
    exit 1
}
grep -qF "panel bar-fg=0.063,0.125,0.188 launcher-fg=0.125,0.188,0.251 popover-fg=0.188,0.251,0.314 toast-fg=0.251,0.314,0.376" "$runtime/check.log" || {
    echo "per-surface colors were not resolved" >&2
    cat "$runtime/check.log" >&2
    exit 1
}
grep -qF "panel modules=logo,workspaces,clock,layout,groups,mode,effects,tray,status" "$runtime/check.log" || {
    echo "bar module order was not parsed" >&2
    cat "$runtime/check.log" >&2
    exit 1
}
"$bin/tessa-panel" --list-modules --json >"$runtime/modules.json"
python3 - "$runtime/modules.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
bar = {item["id"]: item for item in data["bar"]}
for name in ("layout", "groups", "mode", "effects"):
    item = bar.get(name)
    if not item or not item["context"]:
        raise SystemExit(f"missing context module: {name}")
if not data["surfaces"]:
    raise SystemExit("surface module catalogue is empty")
PY
"$bin/tessa-panel" --theme-json >"$runtime/theme.json" 2>/dev/null
python3 - "$runtime/theme.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
tokens = data["tokens"]
for name in ("accent", "panel.background", "bar.background", "launcher.foreground"):
    if name not in tokens or len(tokens[name]) != 3:
        raise SystemExit(f"missing theme token: {name}")
accent = tokens["accent"]
if abs(accent[0] - 0x12 / 255) > 0.01 or abs(accent[1] - 0x34 / 255) > 0.01 or abs(accent[2] - 0x56 / 255) > 0.01:
    raise SystemExit(f"theme include was not applied: {accent}")
if data["fonts"]["bar"] != "DejaVu Sans":
    raise SystemExit(f"theme font export mismatch: {data['fonts']}")
if data["effects"]["animations"] is not False:
    raise SystemExit(f"effect state export mismatch: {data['effects']}")
PY
echo "panel module registry and theme tokens: ok"
"$bin/tessa-panel" --bar-plan 850 200 >"$runtime/bar-plan.log" 2>&1
grep -qF "bar-plan: width=850 available=618 hidden=1 overflow=on" "$runtime/bar-plan.log" || {
    echo "bar overflow plan did not hide a module" >&2
    cat "$runtime/bar-plan.log" >&2
    exit 1
}
grep -qF "hidden: effects priority=30" "$runtime/bar-plan.log" || {
    echo "bar priority did not pick the lowest-priority module" >&2
    cat "$runtime/bar-plan.log" >&2
    exit 1
}
grep -qF "visible: clock priority=100" "$runtime/bar-plan.log" || {
    echo "bar priority hid a high-priority module" >&2
    cat "$runtime/bar-plan.log" >&2
    exit 1
}
echo "bar priority overflow: ok"
grep -qF "wallpaper shader frame 64x64" "$runtime/check.log" || {
    echo "wallpaper shader did not produce a frame" >&2
    cat "$runtime/check.log" >&2
    exit 1
}
echo "panel config: ok"

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

wait_log() {
    pattern=$1
    i=0
    while [ "$i" -lt 150 ]; do
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

wait_log "wallpaper shader frame 64x64"
tessa-ctl config-check | grep -qF "config: ok" || {
    echo "panel-only shell config keys were rejected by the compositor" >&2
    tessa-ctl config-check >&2 || true
    exit 1
}
wait_log "tessa-panel: bar:"
sleep 0.3
"$bin/tessa-ctl" shell | grep -qF "ROLE	bar	tessa-panel" || {
    echo "shell status did not report the integrated bar" >&2
    "$bin/tessa-ctl" shell >&2 || true
    exit 1
}
echo "shell role status: ok"
printf 'theme-role = accent = #654321\n' > "$runtime/theme/theme.conf"
i=0
while [ "$i" -lt 30 ]; do
    if "$bin/tessa-ctl" config 2>/dev/null | grep -qF "accent #654321"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 30 ]; then
    echo "theme file hot reload did not apply" >&2
    "$bin/tessa-ctl" config >&2 || true
    exit 1
fi
echo "theme hot reload: ok"
mkdir -p "$runtime/theme2"
printf 'theme-role = accent = #abcdef\n' > "$runtime/theme2/theme.conf"
sed -i 's/^theme = theme$/theme = theme2/' "$runtime/config"
i=0
while [ "$i" -lt 30 ]; do
    if "$bin/tessa-ctl" config 2>/dev/null | grep -qF "accent #abcdef"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 30 ]; then
    echo "switching to another theme package did not apply" >&2
    "$bin/tessa-ctl" config >&2 || true
    exit 1
fi
printf 'theme-role = accent = #a1b2c3\n' > "$runtime/theme2/theme.conf"
i=0
while [ "$i" -lt 30 ]; do
    if "$bin/tessa-ctl" config 2>/dev/null | grep -qF "accent #a1b2c3"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 30 ]; then
    echo "theme package watcher did not follow the new directory" >&2
    "$bin/tessa-ctl" config >&2 || true
    exit 1
fi
echo "theme package switch: ok"
"$bin/tessa-ctl" status demo-widget "18C" --icon "☀" --priority 90
sleep 0.2
"$bin/tessa-ctl" state --json >"$runtime/widget-state.json"
python3 - "$runtime/widget-state.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for entry in data["statuses"]:
    if entry["id"] == "demo-widget":
        if entry["icon"] != "☀" or entry["priority"] != 90:
            raise SystemExit(f"widget metadata mismatch: {entry}")
        break
else:
    raise SystemExit("external widget was not present in state")
PY
echo "declarative widget: ok"
grim -o HEADLESS-1 "$runtime/shader.png"
rgb=$(python3 "$root/tests/png-pixel.py" "$runtime/shader.png" 960 540)
awk -v rgb="$rgb" 'BEGIN { split(rgb, c, " "); if (c[1] < 190 || c[1] > 210 || c[2] < 30 || c[2] > 50 || c[3] < 80 || c[3] > 100) exit 1 }' || {
    echo "wallpaper shader pixel is $rgb, expected 200/40/90" >&2
    exit 1
}
echo "wallpaper shader: ok"

i=0
while [ "$i" -lt 100 ]; do
    if tessa-ctl state 2>/dev/null | grep -qF "LAYER	tessa-bar"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
tessa-ctl state >"$runtime/state.txt"
awk -F '\t' '
    $1 == "LAYER" && $2 == "tessa-bar" {
        if ($5 == "0.750" && $6 == "21") found = 1
    }
    END { exit(found ? 0 : 1) }
' "$runtime/state.txt" || {
    echo "tessa-bar layer rule was not applied" >&2
    grep -E '^LAYER' "$runtime/state.txt" >&2 || true
    exit 1
}
echo "bar layer rule: ok"

cat > "$runtime/demo.popover" <<'EOF'
title = Demo widget
body = Declarative content from the module
action = Open calendar | tessa-ctl panel calendar
action = Clear widget | tessa-ctl status demo-widget --clear
EOF
"$bin/tessa-panel" --popover-check "$runtime/demo.popover" >"$runtime/popover.log" 2>&1
grep -qF "popover: title=Demo widget actions=2" "$runtime/popover.log" || {
    echo "popover file was not parsed" >&2
    cat "$runtime/popover.log" >&2
    exit 1
}
grep -qF "action: Open calendar -> tessa-ctl panel calendar" "$runtime/popover.log" || {
    echo "popover actions were not parsed" >&2
    cat "$runtime/popover.log" >&2
    exit 1
}
"$bin/tessa-ctl" status demo-widget "18C" --icon "☀" --priority 90 --popover "$runtime/demo.popover"
sleep 0.3
"$bin/tessa-ctl" state --json >"$runtime/widget-popover.json"
python3 - "$runtime/widget-popover.json" "$runtime/demo.popover" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for entry in data["statuses"]:
    if entry["id"] == "demo-widget":
        if entry["popover"] != sys.argv[2]:
            raise SystemExit(f"widget popover path mismatch: {entry}")
        break
else:
    raise SystemExit("external widget was not present in state")
PY
"$bin/tessa-ctl" panel module demo-widget
i=0
while [ "$i" -lt 100 ]; do
    if tessa-ctl state 2>/dev/null | grep -qF "LAYER	tessa-overlay"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "external module popover did not open" >&2
    tessa-ctl state | grep -E '^LAYER' >&2 || true
    exit 1
fi
echo "external module popover: ok"
"$bin/tessa-ctl" panel module demo-widget
i=0
while [ "$i" -lt 100 ]; do
    if ! tessa-ctl state 2>/dev/null | grep -qF "LAYER	tessa-overlay"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "external module popover did not close" >&2
    exit 1
fi

tessa-ctl panel calendar
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
i=0
while [ "$i" -lt 100 ]; do
    if tessa-ctl state 2>/dev/null | awk -F '\t' '
        $1 == "LAYER" && $2 == "tessa-overlay" && $5 == "0.800" && $6 == "23" { found = 1 }
        END { exit(found ? 0 : 1) }
    '; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "tessa-overlay layer rule was not applied" >&2
    tessa-ctl state | grep -E '^LAYER' >&2 || true
    exit 1
fi
echo "popover layer rule: ok"

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
echo "shell v2 test passed"
