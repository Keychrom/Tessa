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

cat > "$runtime/config" <<EOF
panel = true
xwayland = false
animations = false
bg = #000000
bg_top = #000000
bg_bottom = #000000
wallpaper_art = false
wallpaper_shader = $runtime/shader.sh
wallpaper_fit = stretch
bar_layout = logo, workspaces, clock, tray, status
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
grep -qF "panel modules=logo,workspaces,clock,tray,status" "$runtime/check.log" || {
    echo "bar module order was not parsed" >&2
    cat "$runtime/check.log" >&2
    exit 1
}
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
