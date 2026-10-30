#!/bin/sh
# Verify MPRIS media discovery, bar chip/popover, and play/next/previous.
# Requires python3 with PyGObject, gdbus/wtype, and dbus-run-session.
#   sh tests/media.sh
set -eu

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session not found; skipping media test"
        exit 0
    fi
    exec dbus-run-session -- sh "$0" "$@"
fi

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v wtype >/dev/null 2>&1; then
    echo "wtype not found; skipping media test"
    exit 0
fi
if ! python3 -c 'import gi; gi.require_version("Gio", "2.0")' >/dev/null 2>&1; then
    echo "PyGObject not found; skipping media test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-media.XXXXXX")
tpid=
ppid=
cleanup() {
    [ -n "${ppid:-}" ] && kill "$ppid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
printf 'panel = true\nxwayland = false\n' >"$runtime/config"

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

python3 "$root/tests/fake-mpris.py" "$runtime/commands" "$runtime/ready" >"$runtime/player.log" 2>&1 &
ppid=$!
i=0
while [ ! -f "$runtime/ready" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "fake MPRIS player did not start" >&2
        cat "$runtime/player.log" >&2
        exit 1
    fi
    sleep 0.1
done

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

wait_command() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if grep -qx "$pattern" "$runtime/commands" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "MPRIS command was not called: $pattern" >&2
    cat "$runtime/commands" 2>/dev/null || true
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "media: service ready"
wait_log "media: state=1 title=Test Song"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
echo "MPRIS discovery: ok"

tessa-ctl panel media
wait_log "media: controls open"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
sleep 0.3
wtype -k space
wait_command PlayPause
wait_log "media: state=2 title=Test Song"
echo "media play/pause: ok"

wtype -k Right
wait_command Next
wait_log "media: state=2 title=Track 2"
echo "media next: ok"

wtype -k Left
wait_command Previous
wait_log_count "media: state=2 title=Test Song" 2
wtype -k Escape
wait_log_count "tessa-panel: overlay close" 1
sleep 0.3

wtype -M logo -k m
wait_log_count "media: controls open" 2
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 2
sleep 0.2
wtype -k Escape
wait_log_count "tessa-panel: overlay close" 2
echo "Super+M binding: ok"

kill "$ppid" 2>/dev/null || true
wait "$ppid" 2>/dev/null || true
ppid=

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log"; then
    echo "compositor or panel did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime"
echo "media test passed"
