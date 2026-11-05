#!/bin/sh
# Verify BlueZ discovery/pairing against a private fake service and Agent1.
# Requires python3-gi, dbus-daemon, gdbus, and wtype.
#   sh tests/bluetooth.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v wtype >/dev/null 2>&1 || ! command -v dbus-daemon >/dev/null 2>&1; then
    echo "wtype or dbus-daemon not found; skipping bluetooth test"
    exit 0
fi
if ! python3 -c "import gi; from gi.repository import Gio" >/dev/null 2>&1; then
    echo "python3-gi not found; skipping bluetooth test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-bt.XXXXXX")
tpid=
fpid=
bpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    [ -n "${fpid:-}" ] && kill "$fpid" 2>/dev/null || true
    [ -n "${bpid:-}" ] && kill "$bpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    wait "$fpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
panel_style = unified
control_features = bluetooth
EOF

addr="unix:path=$runtime/systembus"
dbus-daemon --session --address="$addr" --fork --print-address=1 --print-pid=1 >"$runtime/bus.info"
bpid=$(sed -n '2p' "$runtime/bus.info")
export DBUS_SYSTEM_BUS_ADDRESS="$addr"

export FAKE_BT_LOG="$runtime/fake-bt.log"
: > "$FAKE_BT_LOG"
python3 "$root/tests/fake-bluez.py" >"$runtime/fake.log" 2>&1 &
fpid=$!
i=0
while ! gdbus call --address "$addr" --dest org.bluez --object-path /     --method org.freedesktop.DBus.ObjectManager.GetManagedObjects >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "fake BlueZ did not start" >&2
        cat "$runtime/fake.log" >&2
        exit 1
    fi
    sleep 0.1
done

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
    while [ "$i" -lt 150 ]; do
        if grep -qF "$pattern" "$runtime/tessa.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not contain: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    cat "$runtime/fake-bt.log" >&2
    exit 1
}

wait_fake() {
    pattern=$1
    i=0
    while [ "$i" -lt 150 ]; do
        if grep -qF "$pattern" "$runtime/fake-bt.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "fake BlueZ did not receive: $pattern" >&2
    cat "$runtime/fake-bt.log" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "tessa-panel: system: bt=1"
tessa-ctl panel bluetooth >/dev/null
wait_log "tessa-panel: control: open view=bluetooth"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
wait_fake "RegisterAgent /org/tessa/Agent"

wtype -k Return
wait_fake "Pair"
wait_log "tessa-panel: bluetooth: agent prompt kind=1"
wtype -k Return
wait_fake "agent confirmed"
wait_fake "Connect"
echo "bluetooth pair + agent confirm: ok"

wtype -k Escape
tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE "panic|Assertion|double free" "$runtime/tessa.log"; then
    echo "bluetooth test crashed" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "bluetooth test passed"
