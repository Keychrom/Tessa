#!/bin/sh
# Verify scrolling layout configuration parsing and diagnostics.
#   sh tests/layout-config.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping layout config test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-layout-config.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM
mkdir -p "$runtime"
chmod 700 "$runtime"

cat >"$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
layout = scrolling
layout_cycle = master,scrolling,monocle,stacking
default_column_width = 42%
column_width_presets = 25%,50%,75%
center_focused_column = always
animation_view_ms = 90
workspace-rule = ws=2; layout=scrolling; default-column-width=640; center-focused-column=never
output-rule = output=HEADLESS-1; default-column-width=33.3%
profile = scrollwide; layout=scrolling; default-column-width=75%; center-focused-column=on-overflow
EOF

"$bin/tessa" --check-config "$runtime/config" >"$runtime/check.log" 2>&1 || {
    echo "valid scrolling config was rejected" >&2
    cat "$runtime/check.log" >&2
    exit 1
}

cat >"$runtime/invalid" <<'EOF'
panel = false
xwayland = false
layout = scrolling
default_column_width = 3%
column_width_presets = 50%,nope
center_focused_column = sometimes
layout_cycle = master,bogus
EOF
if "$bin/tessa" --check-config "$runtime/invalid" >"$runtime/invalid.log" 2>&1; then
    echo "invalid scrolling config was accepted" >&2
    exit 1
fi
for needle in "invalid column width" "invalid column_width_presets" "invalid center_focused_column" "invalid layout_cycle"; do
    if ! grep -q "$needle" "$runtime/invalid.log"; then
        echo "missing diagnostic: $needle" >&2
        cat "$runtime/invalid.log" >&2
        exit 1
    fi
done
echo "layout config validation: ok"

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
    [ "$i" -lt 100 ] || { cat "$runtime/tessa.log" >&2; exit 1; }
    sleep 0.1
done

tessa-ctl config >"$runtime/effective"
grep -q '^layout scrolling$' "$runtime/effective"
grep -q '^layout_cycle master scrolling monocle stacking$' "$runtime/effective"
grep -q '^default_column_width 42.0%$' "$runtime/effective"
grep -q '^column_width_presets 25.0% 50.0% 75.0%$' "$runtime/effective"
grep -q '^center_focused_column always$' "$runtime/effective"
grep -q '^animation_view_ms 90$' "$runtime/effective"

tessa-ctl config --json >"$runtime/config.json"
python3 - "$runtime/config.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
assert cfg["layout"] == "scrolling"
assert cfg["layout_cycle"] == ["master", "scrolling", "monocle", "stacking"]
assert cfg["default_column_width"] == {"kind": "proportion", "value": 0.42}
assert [p["value"] for p in cfg["column_width_presets"]] == [0.25, 0.5, 0.75]
assert cfg["center_focused_column"] == "always"
assert cfg["animation_view_ms"] == 90
PY
echo "layout config JSON: ok"

tessa-ctl layout >/dev/null
tessa-ctl state | grep -q "^OUT HEADLESS-1 1 1 monocle$"
tessa-ctl layout >/dev/null
tessa-ctl state | grep -q "^OUT HEADLESS-1 1 1 stacking$"
echo "configured layout cycle: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime" 2>/dev/null || true
echo "layout config test passed"
