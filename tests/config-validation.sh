#!/bin/sh
# Verify file/line config diagnostics and transactional reload rejection.
# Run from the repository root after building:
#   sh tests/config-validation.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-config.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

write_valid_config() {
    cat > "$runtime/config" <<EOF
panel = false
xwayland = false
gaps = $1
EOF
}

write_valid_config 10

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
sleep 0.2

tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
echo "valid config: ok"

cat > "$runtime/config" <<EOF
panel = false
xwayland = false
gaps = 10
bogus_key = yes
gaps = nope
accent = red
window-rule = unknown=1
include = missing.conf
output-rule = output=HEADLESS-1; gaps=nope
window-rule = match=app ~ "(["
window-rule = title=X; border-active=#zzzzzz
leader = SUPER+
leader_timeout = -1
mode = scratch
mode_timeout = 70000
event-rule = window-open; match=app ~ "["; run=touch /tmp/tessa-bad
event-rule = not-an-event; run=true
event-rule = window-open; app=foot
theme-role = unknown = #ffffff
theme-role = accent = nope
reduce_motion_animations = spin
animation_open_ms = nope
window-rule = title=Bad; opacity=1.5
window-rule = title=Bad; corner-radius=65
window-rule = title=Bad; border-width=17
layer-rule = namespace=x; layer=side
layer-rule = namespace=x; opacity=nope
layer-rule = unknown=1
input-rule = type=joystick
input-rule = tap=maybe
input-rule = accel-speed=2
input-rule = scroll-method=spin
input-rule = tap-button-map=xyz
cursor_size = nope
output-rule = make=*; adaptive-sync=maybe
output-rule = adaptive-sync=on
EOF

tessa-ctl dispatch reload
sleep 0.2
tessa-ctl config >"$runtime/config.out"
grep -q "^gaps 10$" "$runtime/config.out"
grep -q "$runtime/config:4: unknown key 'bogus_key'" "$runtime/config.out"
grep -q "$runtime/config:5: invalid integer for gaps" "$runtime/config.out"
grep -q "$runtime/config:6: invalid color for accent" "$runtime/config.out"
grep -q "$runtime/config:7: invalid window-rule" "$runtime/config.out"
grep -q "$runtime/config:8: included config not found" "$runtime/config.out"
grep -q "$runtime/config:9: invalid output-rule" "$runtime/config.out"
grep -q "$runtime/config:10: invalid window-rule" "$runtime/config.out"
grep -q "$runtime/config:11: invalid window-rule" "$runtime/config.out"
grep -q "$runtime/config:12: invalid leader chord" "$runtime/config.out"
grep -q "$runtime/config:13: leader_timeout out of range" "$runtime/config.out"
grep -q "$runtime/config:15: mode_timeout out of range" "$runtime/config.out"
grep -q "$runtime/config:16: invalid event-rule" "$runtime/config.out"
grep -q "$runtime/config:17: invalid event-rule" "$runtime/config.out"
grep -q "$runtime/config:18: invalid event-rule" "$runtime/config.out"
grep -q "$runtime/config:19: invalid theme-role" "$runtime/config.out"
grep -q "$runtime/config:20: invalid theme-role" "$runtime/config.out"
grep -q "$runtime/config:21: invalid reduce_motion_animations" "$runtime/config.out"
grep -q "$runtime/config:22: invalid integer for animation_open_ms" "$runtime/config.out"
grep -q "$runtime/config:23: invalid window-rule" "$runtime/config.out"
grep -q "$runtime/config:24: invalid window-rule" "$runtime/config.out"
grep -q "$runtime/config:25: invalid window-rule" "$runtime/config.out"
grep -q "$runtime/config:26: invalid layer-rule" "$runtime/config.out"
grep -q "$runtime/config:27: invalid layer-rule" "$runtime/config.out"
grep -q "$runtime/config:28: invalid layer-rule" "$runtime/config.out"
grep -q "$runtime/config:29: invalid input-rule" "$runtime/config.out"
grep -q "$runtime/config:30: invalid input-rule" "$runtime/config.out"
grep -q "$runtime/config:31: invalid input-rule" "$runtime/config.out"
grep -q "$runtime/config:32: invalid input-rule" "$runtime/config.out"
grep -q "$runtime/config:33: invalid input-rule" "$runtime/config.out"
grep -q "$runtime/config:34: invalid integer for cursor_size" "$runtime/config.out"
grep -q "$runtime/config:35: invalid output-rule" "$runtime/config.out"
grep -q "$runtime/config:36: invalid output-rule" "$runtime/config.out"
echo "line diagnostics + rejected reload: ok"

if tessa-ctl config-check >"$runtime/check.out" 2>&1; then
    echo "config-check accepted an invalid configuration" >&2
    cat "$runtime/check.out" >&2
    exit 1
fi
grep -q "diagnostic error" "$runtime/check.out"
echo "config-check failure: ok"

write_valid_config 4
tessa-ctl dispatch reload
sleep 0.2
tessa-ctl config >"$runtime/config.out"
grep -q "^gaps 4$" "$runtime/config.out"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
echo "valid reload after failure: ok"

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
echo "config validation test passed"
