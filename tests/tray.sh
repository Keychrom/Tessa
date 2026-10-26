#!/bin/sh
# Verify the StatusNotifier watcher/host, item icons, tray popover, and activate.
# Requires python3 with PyGObject, gdbus/wtype, and dbus-run-session.
#   sh tests/tray.sh
set -eu

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session not found; skipping tray test"
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
    echo "wtype not found; skipping tray test"
    exit 0
fi
if ! python3 -c 'import gi; gi.require_version("Gio", "2.0")' >/dev/null 2>&1; then
    echo "PyGObject not found; skipping tray test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-tray.XXXXXX")
tpid=
ppid=
cleanup() {
    [ -n "${ppid:-}" ] && kill "$ppid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
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
    cat "$runtime/item.log" 2>/dev/null || true
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
    echo "tray command was not called: $pattern" >&2
    cat "$runtime/commands" 2>/dev/null || true
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "tray: service ready"

host_state=$(gdbus call --session \
    --dest org.kde.StatusNotifierWatcher \
    --object-path /StatusNotifierWatcher \
    --method org.freedesktop.DBus.Properties.Get \
    org.kde.StatusNotifierWatcher IsStatusNotifierHostRegistered)
case "$host_state" in
    *true*) ;;
    *) echo "tray host is not registered: $host_state" >&2; exit 1 ;;
esac
protocol=$(gdbus call --session \
    --dest org.kde.StatusNotifierWatcher \
    --object-path /StatusNotifierWatcher \
    --method org.freedesktop.DBus.Properties.Get \
    org.kde.StatusNotifierWatcher ProtocolVersion)
case "$protocol" in
    *0*) ;;
    *) echo "unexpected tray protocol version: $protocol" >&2; exit 1 ;;
esac
echo "StatusNotifier watcher: ok"

python3 "$root/tests/fake-tray.py" "$runtime/commands" "$runtime/ready" >"$runtime/item.log" 2>&1 &
ppid=$!
i=0
while [ ! -f "$runtime/ready" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "fake StatusNotifierItem did not register" >&2
        cat "$runtime/item.log" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

wait_log "tray: 1 item(s) first=Test Tray"
wait_log "tray: icon 22x22"
echo "tray item registration and icon: ok"

tessa-ctl panel tray
wait_log "tray: popover open"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
sleep 0.3
wtype -k Return
wait_command Activate
echo "tray popover activate: ok"

wtype -k Escape
wait_log_count "tessa-panel: overlay close" 1
sleep 0.3

wtype -M logo -M shift -k t
wait_log_count "tray: popover open" 2
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 2
sleep 0.2
wtype -k Escape
wait_log_count "tessa-panel: overlay close" 2
echo "Super+Shift+T binding: ok"

kill "$ppid" 2>/dev/null || true
wait "$ppid" 2>/dev/null || true
ppid=
wait_log "tray: no items"

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
echo "tray test passed"
