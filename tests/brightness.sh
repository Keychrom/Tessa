#!/bin/sh
# Verify brightness and power-profile controls against fake logind/PPD.
# Requires python3-gi, dbus-daemon, wayland-scanner, and cc.
#   sh tests/brightness.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v dbus-daemon >/dev/null 2>&1 || ! command -v wayland-scanner >/dev/null 2>&1; then
    echo "dbus-daemon or wayland-scanner not found; skipping brightness test"
    exit 0
fi
if ! python3 -c "import gi; from gi.repository import Gio" >/dev/null 2>&1; then
    echo "python3-gi not found; skipping brightness test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-bright.XXXXXX")
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

mkdir -p "$runtime" "$runtime/build"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
panel_style = unified
control_features = brightness,power_profile
EOF

wayland-scanner client-header "$root/tests/protocol/wlr-virtual-pointer-unstable-v1.xml" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$root/tests/protocol/wlr-virtual-pointer-unstable-v1.xml" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-protocol.c"
cc -O2 -I"$runtime/build" -o "$runtime/build/automation" \
    "$root/tests/automation/main.c" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)

addr="unix:path=$runtime/systembus"
dbus-daemon --session --address="$addr" --fork --print-address=1 --print-pid=1 >"$runtime/bus.info"
bpid=$(sed -n '2p' "$runtime/bus.info")
export DBUS_SYSTEM_BUS_ADDRESS="$addr"

export FAKE_SYSTEM_LOG="$runtime/fake-system.log"
: > "$FAKE_SYSTEM_LOG"
python3 "$root/tests/fake-system.py" >"$runtime/fake.log" 2>&1 &
fpid=$!
i=0
while ! gdbus call --address "$addr" --dest org.freedesktop.UPower.PowerProfiles \
    --object-path /org/freedesktop/UPower/PowerProfiles \
    --method org.freedesktop.DBus.Properties.GetAll \
    org.freedesktop.UPower.PowerProfiles >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "fake system service did not start" >&2
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
    exit 1
}

wait_fake() {
    pattern=$1
    i=0
    while [ "$i" -lt 150 ]; do
        if grep -qF "$pattern" "$runtime/fake-system.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "fake system did not receive: $pattern" >&2
    cat "$runtime/fake-system.log" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "ppd=balanced"
tessa-ctl panel control >/dev/null
wait_log "tessa-panel: control: open view=home"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"

run() { env XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=wayland-0 "$runtime/build/automation" "$@"; }
# Brightness slider at 70%.
run abs 1771 190
sleep 0.3
run click 0x110
sleep 0.5
wait_fake "SetBrightness backlight"
echo "brightness slider: ok"

# Power profile: performance (third button).
run abs 1820 228
sleep 0.3
run click 0x110
sleep 0.5
wait_fake "performance"
echo "power profile: ok"

wtype -k Escape 2>/dev/null || true
tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE "panic|Assertion|double free" "$runtime/tessa.log"; then
    echo "brightness test crashed" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "brightness test passed"
