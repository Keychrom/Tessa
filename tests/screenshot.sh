#!/bin/sh
# Verify screencopy capture, full-screen PNG saving, cancellation, and the
# default screenshot binding. Requires wtype and file.
# Run from the repository root after building:
#   sh tests/screenshot.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
for tool in wtype file; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping screenshot test"
        exit 0
    fi
done

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-screenshot.XXXXXX")
tpid=
epid=
cleanup() {
    [ -n "${epid:-}" ] && kill "$epid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
screenshot_dir = $runtime/shots
EOF

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
export TESSA_PANEL_DEBUG=1

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

wait_event() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if grep -q "$pattern" "$runtime/events" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "event stream did not contain: $pattern" >&2
    cat "$runtime/events" >&2
    exit 1
}

wait_log "tessa-panel: state: output=HEADLESS-1"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
tessa-ctl events panel >"$runtime/events" &
epid=$!
sleep 0.3

tessa-ctl panel screenshot
wait_log "screenshot: capture ready 1920x1080"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
wait_event "EVENT.*panel.*arg=screenshot"
sleep 0.3
wtype -k Return
wait_log "screenshot: saved "
sleep 0.3

file_path=$(find "$runtime/shots" -maxdepth 1 -name 'tessa-*.png' | head -n 1)
if [ -z "$file_path" ] || [ ! -f "$file_path" ]; then
    echo "screenshot file was not created" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
if ! file "$file_path" | grep -q "PNG image data, 1920 x 1080"; then
    echo "screenshot is not a 1920x1080 PNG" >&2
    file "$file_path" >&2
    exit 1
fi
if [ "$(wc -c <"$file_path")" -lt 10000 ]; then
    echo "screenshot PNG looks empty" >&2
    ls -l "$file_path" >&2
    exit 1
fi
echo "full screenshot + PNG save: ok"

tessa-ctl panel screenshot
wait_log_count "screenshot: capture ready " 2
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 2
sleep 0.3
wtype -k Escape
wait_log "screenshot: cancelled"
sleep 0.3
count=$(find "$runtime/shots" -maxdepth 1 -name 'tessa-*.png' | wc -l)
if [ "$count" -ne 1 ]; then
    echo "cancelled screenshot created a file" >&2
    find "$runtime/shots" -type f >&2
    exit 1
fi
echo "screenshot cancel: ok"

wtype -M logo -M shift -k s
wait_log_count "screenshot: capture ready " 3
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 3
sleep 0.3
wtype -k Escape
wait_log_count "screenshot: cancelled" 2
sleep 0.3
count=$(find "$runtime/shots" -maxdepth 1 -name 'tessa-*.png' | wc -l)
if [ "$count" -ne 1 ]; then
    echo "Super+Shift+S created a file after cancellation" >&2
    find "$runtime/shots" -type f >&2
    exit 1
fi
echo "Super+Shift+S binding: ok"

kill "$epid" 2>/dev/null || true
wait "$epid" 2>/dev/null || true
epid=

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
echo "screenshot test passed"
