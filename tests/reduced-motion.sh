#!/bin/sh
# Verify reduced-motion fade mode and per-kind animation durations.
# Requires foot. Run from the repository root after building:
#   sh tests/reduced-motion.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping reduced-motion test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-reduced-motion.XXXXXX")
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
panel = false
xwayland = false
animations = true
animation_ms = 500
animation_open_ms = 400
animation_workspace_ms = 300
animation_close_ms = 500
reduce_motion = true
reduce_motion_animations = fade
reduce_motion_fade_ms = 120
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
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

wait_log() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
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

tessa-ctl config >"$runtime/config.out"
grep -q "^animation_ms 500$" "$runtime/config.out"
grep -q "^animation_open_ms 400$" "$runtime/config.out"
grep -q "^animation_workspace_ms 300$" "$runtime/config.out"
grep -q "^animation_close_ms 500$" "$runtime/config.out"
grep -q "^reduce_motion 1$" "$runtime/config.out"
grep -q "^reduce_motion_animations fade$" "$runtime/config.out"
grep -q "^reduce_motion_fade_ms 120$" "$runtime/config.out"
echo "reduced-motion config: ok"

tessa-ctl spawn foot -T ReducedOpen
wait_state "WIN"
sleep 0.4
if grep -q "animation: start id=" "$runtime/tessa.log"; then
    echo "movement animation ran with reduce_motion enabled" >&2
    grep "animation: start" "$runtime/tessa.log" >&2
    exit 1
fi
echo "reduced-motion open: ok"

wid=$(tessa-ctl state | awk -F '	' '$1 == "WIN" { print $2; exit }')
tessa-ctl dispatch close "$wid"
wait_log "close animation: start id=$wid"
wait_log "close animation: done id=$wid"
i=0
while tessa-ctl state 2>/dev/null | grep -q "^WIN	"; do
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
        echo "closed window did not disappear" >&2
        exit 1
    fi
    sleep 0.1
done
echo "reduced-motion close fade: ok"

cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = true
animation_ms = 500
reduce_motion = true
reduce_motion_animations = none
EOF
tessa-ctl dispatch reload
tessa-ctl spawn foot -T AbsoluteReduced
wait_state "WIN"
wid=$(tessa-ctl state | awk -F '	' '$1 == "WIN" { print $2; exit }')
tessa-ctl dispatch close "$wid"
sleep 0.3
if grep -q "close animation: start id=$wid" "$runtime/tessa.log"; then
    echo "close animation ran with reduced-motion animations disabled" >&2
    exit 1
fi
echo "reduced-motion none: ok"

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
echo "reduced-motion test passed"
