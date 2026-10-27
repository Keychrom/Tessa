#!/bin/sh
# Verify window open/close/workspace motion and visual config validation.
# Requires foot. Run after building:
#   sh tests/animations.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping animation test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-animations.XXXXXX")
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
animations = true
reduce_motion = false
animation_ms = 500
shadows = true
bg_top = #162038
bg_bottom = #070a12
wallpaper_art = true
hook = animation-start printf 'open-start %s %s\n' "$TESSA_ARG" "$TESSA_WINDOW_ID" >> "$TESSA_HOOK_LOG"
hook = animation-done printf 'open-done %s %s\n' "$TESSA_ARG" "$TESSA_WINDOW_ID" >> "$TESSA_HOOK_LOG"
hook = close-animation-start printf 'close-start %s\n' "$TESSA_WINDOW_ID" >> "$TESSA_HOOK_LOG"
hook = close-animation-done printf 'close-done %s\n' "$TESSA_WINDOW_ID" >> "$TESSA_HOOK_LOG"
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_HOOK_LOG="$runtime/hooks.log"
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

wait_log() {
    pattern=$1
    i=0
    while [ "$i" -lt 120 ]; do
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

wait_log_count() {
    pattern=$1
    expected=$2
    i=0
    while [ "$i" -lt 120 ]; do
        if [ "$(grep -cF "$pattern" "$runtime/tessa.log" 2>/dev/null || true)" -ge "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not contain $expected occurrences of: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_hook() {
    pattern=$1
    i=0
    while [ "$i" -lt 120 ]; do
        if grep -qF "$pattern" "$runtime/hooks.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "hooks log did not contain: $pattern" >&2
    cat "$runtime/hooks.log" >&2 2>/dev/null || true
    cat "$runtime/tessa.log" >&2
    exit 1
}

tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
echo "animation/visual config: ok"

tessa-ctl spawn foot -T AnimTest
wait_log "animation: start id=1 from=0,18"
wait_log_count "animation: done id=1" 1
wait_hook "open-start open 1"
wait_hook "open-done open 1"
echo "window open animation: ok"

tessa-ctl workspace 2
sleep 0.4
tessa-ctl workspace 1
wait_log "animation: start id=1 from=-54,0"
wait_log_count "animation: done id=1" 2
wait_hook "open-start workspace 1"
wait_hook "open-done workspace 1"
echo "workspace animation: ok"

tessa-ctl dispatch close 1
wait_log "close animation: start id=1"
if command -v grim >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
    grim -o HEADLESS-1 "$runtime/close-mid.png"
    luminance=$(convert "$runtime/close-mid.png" -crop 1x1+960+540 +repage \
        -colorspace Gray -format '%[fx:mean]' info:)
    if ! awk -v v="$luminance" 'BEGIN { exit !(v < 0.3) }'; then
        echo "close snapshot lost its content (center luminance $luminance)" >&2
        exit 1
    fi
    echo "close snapshot content: ok"
fi
wait_log "close animation: done id=1"
wait_hook "close-start 1"
wait_hook "close-done 1"
i=0
while [ "$i" -lt 30 ]; do
    if ! tessa-ctl state 2>/dev/null | grep -q "^WIN	1	"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if tessa-ctl state 2>/dev/null | grep -q "^WIN	1	"; then
    echo "closed window is still present" >&2
    exit 1
fi
echo "window close animation: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi
pkill -x tessa-panel 2>/dev/null || true

trap - EXIT INT TERM
rm -rf "$runtime"
echo "animation test passed"
