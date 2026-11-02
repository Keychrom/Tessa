#!/bin/sh
# Verify effect-helper protocol v2: partial fields, tint, animation overrides.
#   sh tests/effect-v2.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v kitty >/dev/null 2>&1; then
    echo "kitty not found; skipping effect v2 test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-effect-v2.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM
mkdir -p "$runtime"
chmod 700 "$runtime"

cat >"$runtime/effects.py" <<'PY'
import sys

while True:
    lines = []
    while True:
        line = sys.stdin.readline()
        if not line:
            raise SystemExit(0)
        line = line.rstrip("\n")
        if line == "END":
            break
        lines.append(line.split("\t"))
    out = ["VERSION\t2"]
    for fields in lines:
        if fields[0] != "WINDOW":
            continue
        title = fields[3] if len(fields) > 3 else ""
        if title == "EffFull":
            out.append(f"WINDOW\t{fields[1]}\topacity=0.900\tradius=16\ttint=#ff000080\topen-ms=240\topen-curve=spring-soft")
        elif title == "EffPartial":
            out.append(f"WINDOW\t{fields[1]}\ttint=#00ff0080")
    out.append("END")
    sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()
PY

cat >"$runtime/config" <<EOF
panel = false
xwayland = false
animations = true
corner_radius = 0
border_width = 0
bg = #000000
bg_top = #000000
bg_bottom = #000000
wallpaper_art = false
effect_helper = python3 $runtime/effects.py
effect_helper_timeout = 800
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export WLR_BACKENDS=headless
export WLR_RENDERER=gles2
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"
export TESSA_DEBUG=1

"$bin/tessa" >"$runtime/tessa.log" 2>&1 &
tpid=$!
i=0
while [ ! -S "$runtime/tessa.sock" ]; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || { cat "$runtime/tessa.log" >&2; exit 1; }
    sleep 0.1
done

wait_title() {
    i=0
    while [ "$i" -lt 100 ]; do
        if tessa-ctl state --json 2>/dev/null | grep -q "\"$1\""; then return 0; fi
        i=$((i + 1)); sleep 0.1
    done
    echo "window $1 did not appear" >&2
    tessa-ctl state --json >&2
    exit 1
}

tessa-ctl spawn kitty -T EffFull >/dev/null
wait_title EffFull
tessa-ctl spawn kitty -T EffPartial >/dev/null
wait_title EffPartial
sleep 1

tessa-ctl state --json >"$runtime/state.json"
python3 - "$runtime/state.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
windows = {w["title"]: w for w in data["windows"]}
full = windows["EffFull"]
partial = windows["EffPartial"]
assert full["tint"] == [1.0, 0.0, 0.0, 0.502], full["tint"]
assert full["opacity"] == 0.9, full["opacity"]
assert full["corner_radius"] == 16, full["corner_radius"]
assert full["animation"]["open_ms"] == 240, full["animation"]
assert full["animation"]["open_curve"] == "spring-soft", full["animation"]
assert partial["tint"] == [0.0, 1.0, 0.0, 0.502], partial["tint"]
assert partial["opacity"] == 1.0, partial["opacity"]
PY
echo "effect v2 state: ok"

if command -v grim >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
    grim "$runtime/shot.png"
    geom=$(python3 - "$runtime/state.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
w = [x for x in data["windows"] if x["title"] == "EffFull"][0]
print(w["x"] + w["width"] // 2, w["y"] + w["height"] // 2)
PY
)
    set -- $geom
    pixel=$(convert "$runtime/shot.png" -format "%[pixel:p{$1,$2}]" info:)
    red=$(printf '%s\n' "$pixel" | sed -n 's/.*(\([0-9][0-9]*\),.*/\1/p')
    if [ -z "$red" ] || [ "$red" -lt 64 ]; then
        echo "tint pixel was not visible: $pixel" >&2
        exit 1
    fi
    echo "effect v2 tint pixel: ok"
else
    echo "grim/ImageMagick not found; skipping tint pixel check"
fi

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "effect v2 test passed"
