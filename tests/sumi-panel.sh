#!/bin/sh
# Sumi integration: real Cairo output and pointer/keyboard input on an isolated
# headless session with private fake system/audio services. No global pkill.
# Build first, then: sh tests/sumi-panel.sh
set -eu
cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin
for tool in cc wayland-scanner wtype wlr-randr grim dbus-daemon python3 foot; do
    command -v "$tool" >/dev/null || { echo "missing test dependency: $tool" >&2; exit 1; }
done
python3 -c 'import gi; from gi.repository import Gio'
runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-sumi.XXXXXX")
artifacts=${TESSA_SUMI_ARTIFACT_DIR:-$root/sumi-artifacts}
mkdir -p "$artifacts" "$runtime/build" "$runtime/bin"
pids=
cleanup() {
    cp "$runtime/tessa.log" "$artifacts/tessa.log" 2>/dev/null || true
    cp "$runtime/fake-system.log" "$artifacts/fake-system.log" 2>/dev/null || true
    cp "$runtime/audio.log" "$artifacts/audio.log" 2>/dev/null || true
    for pid in $pids; do kill "$pid" 2>/dev/null || true; done
    for pid in $pids; do wait "$pid" 2>/dev/null || true; done
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
animations = false
bg = #10171c
bg_top = #10171c
bg_bottom = #10171c
wallpaper_art = false
launcher_entry = zzyzxsumi | sh -c 'printf launched > $runtime/launched'
power_lock = true
power_suspend = true
power_reboot = true
power_off = true
EOF
cp config/panel-sumi.conf "$runtime/panel.conf"
printf '\npower_lock = true\npower_suspend = true\npower_reboot = true\npower_off = true\n' >> "$runtime/panel.conf"
export TESSA_CONFIG="$runtime/config" TESSA_PANEL_CONFIG="$runtime/panel.conf"
export TESSA_PANEL_BIN="$bin/tessa-panel" TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf" XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0 WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1
export TESSA_DEBUG=1 TESSA_PANEL_DEBUG=1
export PATH="$runtime/bin:$bin:$PATH"
export TESSA_FAKE_VOLUME_STATE="$runtime/volume" TESSA_FAKE_AUDIO_LOG="$runtime/audio.log"
printf '35 0 60 0 1 3\n' > "$TESSA_FAKE_VOLUME_STATE"
: > "$TESSA_FAKE_AUDIO_LOG"
ln -s "$root/tests/fake-wpctl" "$runtime/bin/wpctl"
chmod +x "$root/tests/fake-wpctl"
addr="unix:path=$runtime/systembus"
dbus-daemon --session --address="$addr" --fork --print-address=1 --print-pid=1 > "$runtime/bus.info"
pids="$(sed -n '2p' "$runtime/bus.info") $pids"
export DBUS_SYSTEM_BUS_ADDRESS="$addr" DBUS_SESSION_BUS_ADDRESS="$addr"
export FAKE_SYSTEM_LOG="$runtime/fake-system.log" FAKE_NM_LOG="$runtime/fake-nm.log" FAKE_BLUEZ_LOG="$runtime/fake-bt.log"
: > "$FAKE_SYSTEM_LOG"
for fake in fake-system fake-networkmanager fake-bluez; do
    python3 "tests/$fake.py" > "$runtime/$fake.out" 2>&1 &
    pids="$! $pids"
done
wayland-scanner client-header tests/protocol/wlr-virtual-pointer-unstable-v1.xml "$runtime/build/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code tests/protocol/wlr-virtual-pointer-unstable-v1.xml "$runtime/build/wlr-virtual-pointer-unstable-v1-protocol.c"
cc -O2 -I"$runtime/build" -o "$runtime/build/automation" tests/automation/main.c "$runtime/build/wlr-virtual-pointer-unstable-v1-protocol.c" $(pkg-config --cflags --libs wayland-client)
"$bin/tessa" > "$runtime/tessa.log" 2>&1 &
pids="$! $pids"
wait_for() {
    file=$1 pattern=$2
    i=0
    until grep -qF "$pattern" "$file" 2>/dev/null; do
        i=$((i + 1)); [ "$i" -lt 120 ] || { echo "missing: $pattern"; tail -50 "$runtime/tessa.log"; exit 1; }
        sleep 0.1
    done
}
wait_for "$runtime/tessa.log" 'tessa-panel: bar surface:'
wait_for "$runtime/tessa.log" 'ppd=balanced'
wlr-randr --output HEADLESS-1 --custom-mode 1920x1080
sleep 0.5
auto() { "$runtime/build/automation" "$@"; }
click() { auto abs "$1" "$2" sleep 200 click 0x110; sleep 0.3; }
capture() { sleep 0.5; grim "$artifacts/$1.png"; }
for title in shell notes build; do
    foot --config=/dev/null -T "$title" sh -c 'printf "\033[38;2;240;141;114mTessa / Sumi\033[0m\n\nA quiet place to make things.\n\n$ "; sleep 180' > "$runtime/foot-$title.log" 2>&1 &
    pids="$! $pids"
done
sleep 1
capture desktop-1920
click 1080 40
tessa-ctl state | grep -q 'ACTIVE 9'
click 840 40
tessa-ctl state | grep -q 'ACTIVE 1'
echo 'workspace clicks 1 and 9: ok'
tessa-ctl panel centered
wait_for "$runtime/tessa.log" 'launcher style: centered'
capture launcher-1920
wtype zzyzxsumi
sleep 0.3
wtype -k Return
sleep 0.5
test -f "$runtime/launched"
echo 'launcher search and Enter: ok'
tessa-ctl panel control
wait_for "$runtime/tessa.log" 'control: open view=home'
capture control-1920
# Track geometry: x=1539..1871; y=290. Padding must not bias endpoints.
click 1539 294
wait_for "$TESSA_FAKE_AUDIO_LOG" 'set-volume @DEFAULT_AUDIO_SINK@ 0%'
click 1871 294
wait_for "$TESSA_FAKE_AUDIO_LOG" 'set-volume @DEFAULT_AUDIO_SINK@ 100%'
click 1778 294
wait_for "$TESSA_FAKE_AUDIO_LOG" 'set-volume @DEFAULT_AUDIO_SINK@ 72%'
echo 'volume endpoints and 72%: ok'
click 1771 354
wait_for "$FAKE_SYSTEM_LOG" 'SetBrightness backlight'
click 1820 450
wait_for "$FAKE_SYSTEM_LOG" 'performance'
echo 'brightness and power profile: ok'
click 1600 401
wait_for "$runtime/tessa.log" 'control: focus=on'
click 1570 215
wait_for "$runtime/tessa.log" 'control: view=wifi'
wtype -k Escape
sleep 0.3
click 1740 800
wait_for "$runtime/tessa.log" 'control: view=theme'
capture theme-1920
wtype -k Escape
sleep 0.3
echo 'focus, Wi-Fi and theme navigation: ok'
wtype -k Escape
wlr-randr --output HEADLESS-1 --custom-mode 1366x768
sleep 0.5
tessa-ctl panel control
sleep 0.5
capture control-1366
# The test pointer's absolute coordinate space is fixed at 1920x1080.
# Convert the small-screen position; scroll over a non-slider portion.
auto abs 1730 930 axis 100
sleep 0.5
capture control-1366-scrolled
# The fixed footer must remain clickable after scrolling (theme at 1190,710).
before=$(grep -cF 'control: view=theme' "$runtime/tessa.log")
click 1673 998
after=$(grep -cF 'control: view=theme' "$runtime/tessa.log")
[ "$after" -gt "$before" ] || { echo 'scrolled footer did not navigate'; exit 1; }
capture theme-1366
wtype -k Escape
wtype -k Escape
tessa-ctl panel centered
capture launcher-1366
wtype -k Escape
tessa-ctl quit
sleep 0.3
if grep -qE 'panic|Assertion|double free' "$runtime/tessa.log"; then
    echo 'panel crashed' >&2; exit 1
fi
echo 'small-screen scrolling, fixed footer and launcher: ok'
echo 'Sumi integration passed'
