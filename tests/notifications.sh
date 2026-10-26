#!/bin/sh
# Verify the org.freedesktop.Notifications D-Bus service, toasts, close, and
# expiry. Runs inside a private session bus.
#   sh tests/notifications.sh
set -eu

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session not found; skipping notification test"
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
if ! command -v gdbus >/dev/null 2>&1; then
    echo "gdbus not found; skipping notification test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-notifications.XXXXXX")
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
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
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

notify() {
    app=$1
    replaces=$2
    summary=$3
    body=$4
    timeout_ms=$5
    gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        "$app" "$replaces" "" "$summary" "$body" "[]" "{}" "$timeout_ms"
}

notification_id() {
    sed -n 's/.*uint32 \([0-9][0-9]*\).*/\1/p'
}

wait_log "tessa-panel: notifications: service ready"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
gdbus call --session \
    --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.GetCapabilities \
    >"$runtime/capabilities"
grep -q "body" "$runtime/capabilities"
gdbus call --session \
    --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.GetServerInformation \
    >"$runtime/server"
grep -q "Tessa" "$runtime/server"
echo "notification service + introspection: ok"

out=$(notify "test-app" 0 "Build finished" "Notification body" 10000)
id=$(printf '%s\n' "$out" | notification_id)
if [ -z "$id" ]; then
    echo "Notify did not return an id: $out" >&2
    exit 1
fi
wait_log "notification: added id=$id total=1"
wait_log "layer map: tessa-notifications layer=2 keyboard=0"
echo "notification toast: ok"

gdbus call --session \
    --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null
wait_log "notification: removed id=$id total=0"
echo "CloseNotification: ok"

out=$(notify "test-app" 0 "Expiring" "Should disappear" 1000)
id=$(printf '%s\n' "$out" | notification_id)
wait_log "notification: added id=$id total=1"
wait_log_count "layer map: tessa-notifications layer=2 keyboard=0" 2
wait_log "notification: removed id=$id total=0"
echo "notification expiry + toast recreation: ok"

out=$(notify "test-app" 0 "First" "base" 10000)
id=$(printf '%s\n' "$out" | notification_id)
wait_log "notification: added id=$id total=1"
out=$(notify "test-app" "$id" "Replaced" "new body" 10000)
rid=$(printf '%s\n' "$out" | notification_id)
if [ "$rid" != "$id" ]; then
    echo "replacement changed the notification id ($id -> ${rid:-empty})" >&2
    exit 1
fi
wait_log_count "notification: added id=$id total=1" 2
out=$(notify "test-app" 0 "Second" "stacked toast" 10000)
id2=$(printf '%s\n' "$out" | notification_id)
wait_log "notification: added id=$id2 total=2"
echo "notification replacement + stacking: ok"

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
echo "notification test passed"
