#!/bin/sh
# Verify volume detection and controls through the wpctl command bridge.
# Requires wtype and a session for the headless compositor.
#   sh tests/audio.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v wtype >/dev/null 2>&1; then
    echo "wtype not found; skipping audio test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-audio.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime" "$runtime/bin"
chmod 700 "$runtime"
printf 'panel = true\nxwayland = false\n' >"$runtime/config"
printf '40 0\n' >"$runtime/volume"
cp "$root/tests/fake-wpctl" "$runtime/bin/wpctl"
chmod +x "$runtime/bin/wpctl"

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export PATH="$runtime/bin:$bin:$PATH"
export TESSA_DEBUG=1
export TESSA_PANEL_DEBUG=1
export TESSA_FAKE_VOLUME_STATE="$runtime/volume"
export TESSA_FAKE_AUDIO_LOG="$runtime/commands"

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

wait_log_count() {
    pattern=$1
    expected=$2
    i=0
    while [ "$i" -lt 100 ]; do
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

wait_log "audio: service ready"
wait_log "audio: source=wpctl volume=40 muted=0"
echo "audio detection: ok"

tessa-ctl panel audio
wait_log "audio: controls open"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
sleep 0.3
wtype -k Up
wait_log "audio: source=wpctl volume=45 muted=0"
echo "volume up: ok"

wtype -k m
wait_log "audio: source=wpctl volume=45 muted=1"
echo "mute: ok"

wtype -k m
wait_log_count "audio: source=wpctl volume=45 muted=0" 2
wtype -k Down
wait_log_count "audio: source=wpctl volume=40 muted=0" 2
echo "unmute and volume down: ok"

wtype -k Escape
wait_log_count "tessa-panel: overlay close" 1
sleep 0.3

wtype -M logo -M shift -k a
wait_log_count "audio: controls open" 2
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 2
sleep 0.2
wtype -k Escape
wait_log_count "tessa-panel: overlay close" 2
echo "Super+Shift+A binding: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log"; then
    echo "compositor or panel did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log" >&2
    exit 1
fi
pkill -x tessa-panel 2>/dev/null || true

trap - EXIT INT TERM
rm -rf "$runtime"
echo "audio test passed"
