#!/bin/sh
# Verify window/layer rule v3 decoration fields, live title/app-id re-evaluation,
# opacity, and per-layer matching. Screenshot checks are skipped without grim
# and ImageMagick convert.
#   sh tests/rule-visuals.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN:-$root/zig-out/bin}

for tool in cc python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping rule visual test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-rule-visuals.XXXXXX")
tpid=
wpid=
lpid=
cleanup() {
    [ -n "${wpid:-}" ] && kill "$wpid" 2>/dev/null || true
    [ -n "${lpid:-}" ] && kill "$lpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${wpid:-0}" 2>/dev/null || true
    wait "${lpid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
shadows = false
gaps = 10
outer_gaps = 16
border_width = 2
border_active = #e2684f
bg = #000000
bg_top = #000000
bg_bottom = #000000
wallpaper_art = false
corner_radius = 0
blur = false
window-rule = app-id=tessa-rule-test; opacity=0.4; border-width=8; border-active=#000000; corner-radius=0; blur=false; shadow=false
window-rule = title=RuleAfter; opacity=1; border-width=0; corner-radius=3; blur=true; shadow=true
layer-rule = namespace=tessa-layer-test; layer=overlay; opacity=0.2; blur=true
layer-rule = namespace=tessa-layer-test; layer=bottom; opacity=0.5; corner-radius=4; blur=false
EOF

cc -O2 -I"$root/protocol" -o "$runtime/window-test" \
    "$root/tests/rule-visuals/window.c" \
    "$root/protocol/xdg-shell-client-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)
cc -O2 -I"$root/protocol" -o "$runtime/layer-test" \
    "$root/tests/rule-visuals/layer.c" \
    "$root/protocol/layer-shell-protocol.c" \
    "$root/protocol/xdg-shell-client-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)

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

tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
tessa-ctl config --json >"$runtime/config.json"
python3 - "$runtime/config.json" <<'PY'
import json
import sys

config = json.load(open(sys.argv[1]))
assert config["layer_rule_count"] == 2
assert len(config["layer_rules"]) == 2
PY
echo "rule v3 config parsing: ok"

"$runtime/layer-test" >"$runtime/layer.log" 2>&1 &
lpid=$!
"$runtime/window-test" >"$runtime/window.log" 2>&1 &
wpid=$!

wait_log() {
    file=$1
    pattern=$2
    i=0
    while [ "$i" -lt 100 ]; do
        if grep -qF "$pattern" "$file" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not contain: $pattern" >&2
    cat "$file" >&2 2>/dev/null || true
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "$runtime/layer.log" "layer-mapped"
wait_log "$runtime/window.log" "window-mapped"
sleep 0.3

tessa-ctl state --json >"$runtime/state.json"
python3 - "$runtime/state.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1]))
windows = [w for w in state["windows"] if w["app_id"] == "tessa-rule-test"]
assert len(windows) == 1, state["windows"]
w = windows[0]
assert abs(w["opacity"] - 0.4) < 0.01, w
assert w["border_width"] == 8, w
assert w["corner_radius"] == 0, w
assert w["blur"] is False, w
assert w["shadow"] is False, w
layers = [l for l in state["layers"] if l["namespace"] == "tessa-layer-test"]
assert len(layers) == 1, state["layers"]
l = layers[0]
assert l["layer"] == 1, l
assert abs(l["opacity"] - 0.5) < 0.01, l
assert l["corner_radius"] == 4, l
assert l["blur"] is False, l
PY
echo "initial window/layer visuals: ok"

if command -v grim >/dev/null 2>&1; then
    set -- $(tessa-ctl state | awk -F '\t' '$1 == "WIN" { print $10, $11, $12, $13; exit }')
    wx=$1
    wy=$2
    grim -o HEADLESS-1 "$runtime/before.png"
    layer_rgb=$(python3 "$root/tests/png-pixel.py" "$runtime/before.png" 5 5)
    border_rgb=$(python3 "$root/tests/png-pixel.py" "$runtime/before.png" $((wx + 4)) $((wy + 4)))
    content_rgb=$(python3 "$root/tests/png-pixel.py" "$runtime/before.png" $((wx + 20)) $((wy + 20)))
    awk -v rgb="$layer_rgb" 'BEGIN { split(rgb, c, " "); if (c[1] < 80 || c[1] > 190 || c[2] > 30 || c[3] > 30) exit 1 }' || {
        echo "layer opacity pixel is $layer_rgb, expected half red" >&2
        cp "$runtime/before.png" /tmp/tessa-rule-layer-failure.png 2>/dev/null || true
        exit 1
    }
    awk -v rgb="$border_rgb" 'BEGIN { split(rgb, c, " "); if (c[1] > 12 || c[2] > 12 || c[3] > 12) exit 1 }' || {
        echo "window border pixel is $border_rgb, expected the rule's black 8px border" >&2
        cp "$runtime/before.png" /tmp/tessa-rule-border-failure.png 2>/dev/null || true
        exit 1
    }
    awk -v rgb="$content_rgb" 'BEGIN { split(rgb, c, " "); if (c[1] < 50 || c[1] > 170 || c[2] < 50 || c[2] > 170) exit 1 }' || {
        echo "window opacity pixel is $content_rgb, expected dimmed white" >&2
        cp "$runtime/before.png" /tmp/tessa-rule-opacity-failure.png 2>/dev/null || true
        exit 1
    }
    echo "initial opacity/border pixels: ok"
fi

kill -USR1 "$wpid"
wait_log "$runtime/window.log" "window-retitled"
sleep 0.3

tessa-ctl state --json >"$runtime/state.json"
python3 - "$runtime/state.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1]))
windows = [w for w in state["windows"] if w["app_id"] == "tessa-rule-after"]
assert len(windows) == 1, state["windows"]
w = windows[0]
assert w["title"] == "RuleAfter", w
assert abs(w["opacity"] - 1.0) < 0.001, w
assert w["border_width"] == 0, w
assert w["corner_radius"] == 3, w
assert w["blur"] is True, w
assert w["shadow"] is True, w
PY
echo "reactive title/app-id rule re-evaluation: ok"

if command -v grim >/dev/null 2>&1; then
    grim -o HEADLESS-1 "$runtime/after.png"
    border_rgb=$(python3 "$root/tests/png-pixel.py" "$runtime/after.png" $((wx + 4)) $((wy + 4)))
    awk -v rgb="$border_rgb" 'BEGIN { split(rgb, c, " "); if (c[1] < 220 || c[2] < 220 || c[3] < 220) exit 1 }' || {
        echo "retitled content pixel is $border_rgb, expected opaque white without a border" >&2
        cp "$runtime/after.png" /tmp/tessa-rule-retitle-failure.png 2>/dev/null || true
        exit 1
    }
    echo "reactive border/opacity pixels: ok"
fi

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
cleanup
echo "rule visual test passed"
