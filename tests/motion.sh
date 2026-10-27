#!/bin/sh
# Verify Motion v2 config parsing: named curves, per-kind curves, offsets,
# close scale/fade, and rejection of an unknown curve on reload.
#   sh tests/motion.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-motion.XXXXXX")
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
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
xim = false
animations = true
animation_ms = 200
animation_open_ms = 300
animation_workspace_ms = 400
animation_close_ms = 250
animation_curve = ease-out-quint
animation_open_curve = linear
animation_workspace_curve = ease-in-out-cubic
animation_close_curve = snap
animation_open_x = 100
animation_open_y = -50
animation_workspace_offset = 80
animation_close_scale = 0.5
animation_close_fade = false
bezier = snap, 0.1, 0.9, 0.2, 1.0
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
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

tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
tessa-ctl config >"$runtime/config.out"
grep -qx "animation_curve ease-out-quint" "$runtime/config.out"
grep -qx "animation_open_curve linear" "$runtime/config.out"
grep -qx "animation_workspace_curve ease-in-out-cubic" "$runtime/config.out"
grep -qx "animation_close_curve snap" "$runtime/config.out"
grep -qx "animation_open_x 100" "$runtime/config.out"
grep -qx "animation_open_y -50" "$runtime/config.out"
grep -qx "animation_workspace_offset 80" "$runtime/config.out"
grep -qx "animation_close_scale 0.500" "$runtime/config.out"
grep -qx "animation_close_fade 0" "$runtime/config.out"
grep -qx "bezier snap 0.100 0.900 0.200 1.000" "$runtime/config.out"
echo "motion config parsing: ok"

cat >> "$runtime/config" <<'EOF'
animation_close_curve = missing-curve
EOF
tessa-ctl dispatch reload
sleep 0.2
tessa-ctl config >"$runtime/config.out"
grep -qx "animation_close_curve snap" "$runtime/config.out"
grep -q "unknown animation curve 'missing-curve'" "$runtime/config.out"
echo "unknown curve rejection: ok"

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
echo "motion test passed"
