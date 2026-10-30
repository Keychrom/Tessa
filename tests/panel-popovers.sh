#!/bin/sh
# Verify the clock/calendar and power popovers, their IPC events, keyboard
# navigation, and configurable power commands. Requires wtype.
# Run from the repository root after building:
#   sh tests/panel-popovers.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v wtype >/dev/null 2>&1; then
    echo "wtype not found; skipping panel popovers test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-popovers.XXXXXX")
tpid=
epid=
cleanup() {
    [ -n "${epid:-}" ] && kill "$epid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
power_lock = touch $runtime/lock-fired
power_suspend = touch $runtime/suspend-fired
power_reboot = touch $runtime/reboot-fired
power_off = touch $runtime/off-fired
layer-rule = namespace=tessa-overlay; opacity=0.80; corner-radius=23; blur=false
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

tessa-ctl panel calendar
wait_log "tessa-panel: calendar open"
wait_event "EVENT.*panel.*arg=calendar"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
tessa-ctl state | awk -F '\t' '
    $1 == "LAYER" && $2 == "tessa-overlay" {
        if ($5 == "0.800" && $6 == "23") found = 1
    }
    END { exit(found ? 0 : 1) }
' || {
    echo "popover layer rule was not applied" >&2
    tessa-ctl state | grep -E '^LAYER' >&2 || true
    exit 1
}
sleep 0.2

wtype -k Right
wait_log "tessa-panel: calendar month "
wtype -k Escape
wait_log "tessa-panel: overlay close"
sleep 0.3
echo "calendar popover + event: ok"

tessa-ctl panel power
wait_log "tessa-panel: power menu open"
wait_event "EVENT.*panel.*arg=power"
# The previous overlay may still be closing; wait for this one's keyboard focus.
i=0
while [ "$(grep -cF 'layer map: tessa-overlay layer=3 keyboard=1' "$runtime/tessa.log")" -lt 2 ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "power overlay did not map" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
sleep 0.2
wtype -k Down
wtype -k Return
wait_log "tessa-panel: power action: Suspend"

i=0
while [ ! -f "$runtime/suspend-fired" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "power_suspend command did not run" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
if [ -f "$runtime/lock-fired" ] || [ -f "$runtime/reboot-fired" ] || [ -f "$runtime/off-fired" ]; then
    echo "the wrong power action ran" >&2
    ls -l "$runtime"/*-fired >&2
    exit 1
fi
echo "power menu + configured command: ok"

kill "$epid" 2>/dev/null || true
wait "$epid" 2>/dev/null || true
epid=

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
echo "panel popovers test passed"
