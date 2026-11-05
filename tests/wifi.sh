#!/bin/sh
# Verify the NetworkManager-backed Wi-Fi flow against a private fake service.
# Requires python3-gi, dbus-daemon, gdbus, and wtype.
#   sh tests/wifi.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v wtype >/dev/null 2>&1 || ! command -v dbus-daemon >/dev/null 2>&1; then
    echo "wtype or dbus-daemon not found; skipping wifi test"
    exit 0
fi
if ! python3 -c "import gi; from gi.repository import Gio" >/dev/null 2>&1; then
    echo "python3-gi not found; skipping wifi test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-wifi.XXXXXX")
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
control_features = wifi
EOF

addr="unix:path=$runtime/systembus"
dbus-daemon --session --address="$addr" --fork --print-address=1 --print-pid=1 >"$runtime/bus.info"
bpid=$(sed -n '2p' "$runtime/bus.info")
export DBUS_SYSTEM_BUS_ADDRESS="$addr"

export FAKE_NM_LOG="$runtime/fake-nm.log"
: > "$FAKE_NM_LOG"
python3 "$root/tests/fake-networkmanager.py" >"$runtime/fake.log" 2>&1 &
fpid=$!
i=0
while ! gdbus introspect --address "$addr" --dest org.freedesktop.NetworkManager \
    --object-path /org/freedesktop/NetworkManager >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "fake NetworkManager did not start" >&2
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
    cat "$runtime/fake-nm.log" >&2
    exit 1
}

wait_fake() {
    pattern=$1
    i=0
    while [ "$i" -lt 150 ]; do
        if grep -qF "$pattern" "$runtime/fake-nm.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "fake NetworkManager did not receive: $pattern" >&2
    cat "$runtime/fake-nm.log" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "tessa-panel: system: wifi aps=2"
tessa-ctl panel wifi >/dev/null
wait_log "tessa-panel: control: open view=wifi"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"

# AP order is strongest-first: TestNet then OpenNet. Connect to OpenNet.
wtype -k Down
wtype -k Return
wait_fake "AddAndActivateConnection ssid=OpenNet psk="
echo "wifi open network: ok"

# Select the secured TestNet and enter a password through the panel modal.
wtype -k Up
wtype -k Return
wait_log "tessa-panel: wifi: password prompt ssid=TestNet"
wtype "secret123"
wtype -k Return
wait_fake "AddAndActivateConnection ssid=TestNet psk=secret123"
if grep -q "secret123" "$runtime/tessa.log"; then
    echo "Wi-Fi password leaked into the panel log" >&2
    exit 1
fi
echo "wifi password modal: ok (password not logged)"

wtype -k Escape
tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE "panic|Assertion" "$runtime/tessa.log"; then
    echo "wifi test crashed" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "wifi test passed"
