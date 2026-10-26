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
    pkill -x tessa-panel 2>/dev/null || true
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
