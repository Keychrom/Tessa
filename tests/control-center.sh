#!/bin/sh
# Verify the unified control-center mode, IPC entry points, and feature gating.
# Requires wtype. Run from the repository root after building:
#   sh tests/control-center.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v wtype >/dev/null 2>&1; then
    echo "wtype not found; skipping control center test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-control.XXXXXX")
tpid=
cleanup() {
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
panel_style = unified
control_features = all
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

wait_log "tessa-panel: state: output=HEADLESS-1"

wait_log_count() {
    pattern=$1
    count=$2
    i=0
    while [ "$i" -lt 100 ]; do
        n=$(grep -cF "$pattern" "$runtime/tessa.log" 2>/dev/null || true)
        if [ "${n:-0}" -ge "$count" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not reach $count occurrences of: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

"$bin/tessa-panel" --check >"$runtime/check.out" 2>&1
grep -q "panel style=unified" "$runtime/check.out"
grep -q "control-features=wifi,bluetooth,focus,notifications,media,volume,brightness,power_profile,battery,quick_actions,tray,calendar,power" "$runtime/check.out"

cat > "$runtime/classic.conf" <<EOF
panel = true
panel_style = classic
control_features = wifi
EOF
TESSA_CONFIG="$runtime/classic.conf" "$bin/tessa-panel" --check >"$runtime/classic.out" 2>&1
grep -q "panel style=classic" "$runtime/classic.out"
grep -q "control-features=wifi$" "$runtime/classic.out"

cat > "$runtime/none.conf" <<EOF
panel = true
control_features = none
EOF
TESSA_CONFIG="$runtime/none.conf" "$bin/tessa-panel" --check >"$runtime/none.out" 2>&1
grep -q "control-features=$" "$runtime/none.out"

tessa-ctl panel control >/dev/null
wait_log "tessa-panel: control: open view=home"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
wtype -k Escape
wait_log "tessa-panel: overlay close"
echo "control center home + close: ok"

tessa-ctl panel wifi >/dev/null
wait_log "tessa-panel: control: open view=wifi"
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 2
wtype -k Escape
wait_log "tessa-panel: control: view=home"
wtype -k Escape
wait_log "tessa-panel: overlay close"
echo "wifi view + back: ok"

tessa-ctl panel bluetooth >/dev/null
wait_log "tessa-panel: control: open view=bluetooth"
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 3
wtype -k Escape
wait_log "tessa-panel: control: view=home"
wtype -k Escape
wait_log "tessa-panel: overlay close"
echo "bluetooth view + back: ok"

tessa-ctl panel notifications >/dev/null
wait_log "tessa-panel: control: open view=notifications"
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 4
wtype -k Escape
wait_log "tessa-panel: control: view=home"
wtype -k Escape
wait_log "tessa-panel: overlay close"
echo "notifications view + back: ok"

tessa-ctl panel audio >/dev/null
wait_log "tessa-panel: control: open view=audio"
wait_log_count "layer map: tessa-overlay layer=3 keyboard=1" 5
wtype -k Tab
wait_log "audio: tab input"
wtype -k Escape
wait_log "tessa-panel: control: view=home"
wtype -k Escape
wait_log "tessa-panel: overlay close"
echo "audio view + tabs: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE "panic|Assertion" "$runtime/tessa.log"; then
    echo "control center test crashed" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "control center test passed"
