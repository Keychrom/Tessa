#!/bin/sh
# Verify that notification toasts follow the focused output in a dual-output
# headless session. Runs inside a private session bus.
#   sh tests/notification-routing.sh
set -eu

if [ -z "${TESSA_PRIVATE_BUS:-}" ]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session not found; skipping notification routing test"
        exit 0
    fi
    exec dbus-run-session -- env TESSA_PRIVATE_BUS=1 sh "$0" "$@"
fi

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v gdbus >/dev/null 2>&1; then
    echo "gdbus not found; skipping notification routing test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-notify-route.XXXXXX")
tpid=
cleanup() {
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
export WLR_HEADLESS_OUTPUTS=2
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
    while [ "$i" -lt 120 ]; do
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

wait_state() {
    pattern=$1
    i=0
    while [ "$i" -lt 120 ]; do
        if tessa-ctl state 2>/dev/null | grep -qF "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not contain: $pattern" >&2
    exit 1
}

notify() {
    summary=$1
    gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        rich-app 0 "" "$summary" "route test" "[]" "{}" 10000
}

wait_log "tessa-panel: notifications: service ready"
wait_state "HEADLESS-2"

i=0
while [ "$(tessa-ctl state 2>/dev/null | grep -c '^OUT ')" -lt 2 ]; do
    i=$((i + 1))
    if [ "$i" -ge 120 ]; then
        echo "second output did not appear" >&2
        exit 1
    fi
    sleep 0.1
done
focused=$(tessa-ctl state | awk '$1 == "OUT" && $4 == "1" { print $2; exit }')
other=$(tessa-ctl state | awk '$1 == "OUT" && $4 != "1" { print $2; exit }')
if [ -z "$focused" ] || [ -z "$other" ]; then
    echo "could not determine focused/other output" >&2
    tessa-ctl state >&2
    exit 1
fi

out=$(notify "On focused output one")
id=$(printf '%s\n' "$out" | sed -n 's/.*uint32 \([0-9][0-9]*\).*/\1/p')
[ -n "$id" ] || { echo "Notify did not return an id" >&2; exit 1; }
wait_log "notifications: toast surface 380x82 output=$focused"
echo "notification on focused output $focused: ok"

tessa-ctl workspace 1 "$other"
wait_log "notifications: toast surface 380x82 output=$other"
echo "existing toast moved to focused output $other: ok"

out=$(notify "On focused output two")
id2=$(printf '%s\n' "$out" | sed -n 's/.*uint32 \([0-9][0-9]*\).*/\1/p')
[ -n "$id2" ] || { echo "second Notify did not return an id" >&2; exit 1; }
wait_log "notification: added id=$id2 total=2"
echo "new notification uses focused output $other: ok"

gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null
gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$id2" >/dev/null

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
echo "notification routing test passed"
