#!/bin/sh
# Headless smoke test for the compositor, extension hooks, and tessa-ctl.
# Run from the repository root after building:
#   sh tests/smoke.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-smoke.XXXXXX")
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

cat > "$runtime/hook.sh" <<'HOOK'
#!/bin/sh
printf '%s|%s|%s|%s|%s\n' \
    "$TESSA_EVENT" "$TESSA_WORKSPACE" "$TESSA_PREVIOUS_WORKSPACE" \
    "$TESSA_OUTPUT" "$TESSA_WINDOW_ID" >> "$TESSA_EVENT_LOG"
HOOK
chmod +x "$runtime/hook.sh"

cat > "$runtime/extra.conf" <<EOF
hook = workspace-change $runtime/hook.sh
EOF

cat > "$runtime/config" <<EOF
panel = false
xwayland = false
hook = startup $runtime/hook.sh
hook = config-reload $runtime/hook.sh
hook = window-open $runtime/hook.sh
hook = window-focus $runtime/hook.sh
hook = window-close $runtime/hook.sh
launcher_entry = Smoke Test | sh -c 'true'
include = $runtime/extra.conf
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_EVENT_LOG="$runtime/events.log"
export TESSA_IPC="$runtime/tessa.sock"
export XDG_RUNTIME_DIR="$runtime"
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"

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

state=
wait_state() {
    pattern=$1
    i=0
    while [ "$i" -lt 30 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        if printf '%s\n' "$state" | grep -q "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not contain: $pattern" >&2
    printf '%s\n' "$state" >&2
    return 1
}

wait_log() {
    pattern=$1
    i=0
    while [ "$i" -lt 30 ]; do
        if grep -q "$pattern" "$runtime/events.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "hook log did not contain: $pattern" >&2
    cat "$runtime/events.log" 2>/dev/null >&2 || true
    return 1
}

wait_state "OUT HEADLESS-1"
wait_log "startup|"
echo "state: ok"

tessa-ctl events >"$runtime/events.stream" 2>"$runtime/events.err" &
epid=$!
sleep 0.3

tessa-ctl workspace 3
wait_state "OUT HEADLESS-1 3 1"
echo "workspace + IPC half-close: ok"

tessa-ctl status smoke "Tessa extension status" --exec "sh -c 'true'"
wait_state "STATUS.*smoke"
wait_state "sh -c"
echo "status API: ok"

tessa-ctl status smoke --clear
wait_state "OUT HEADLESS-1 3 1"
if printf '%s\n' "$state" | grep -q "STATUS"; then
    echo "status clear failed" >&2
    exit 1
fi
echo "status clear: ok"

tessa-ctl dispatch reload
wait_state "OUT HEADLESS-1 3 1"
wait_log "config-reload|"
echo "config reload + include hook: ok"

wait_log "workspace-change|3|1|HEADLESS-1|"
echo "workspace hook: ok"

i=0
while ! grep -q "EVENT.*workspace-change" "$runtime/events.stream" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
        echo "event stream did not receive workspace-change" >&2
        cat "$runtime/events.stream" >&2
        exit 1
    fi
    sleep 0.1
done
echo "event subscription: ok"

if command -v foot >/dev/null 2>&1; then
    tessa-ctl spawn foot -T SmokeWindow
    wait_state "WIN"
    wid=$(printf '%s
' "$state" | awk -F '	' '$1 == "WIN" { print $2; exit }')
    if [ -z "$wid" ]; then
        echo "could not find spawned window id" >&2
        exit 1
    fi
    wait_log "window-open|"
    wait_log "window-focus|"
    tessa-ctl dispatch close "$wid"
    wait_log "window-close|"
    wait_state "OUT HEADLESS-1 3 1"
    if ! grep -q "EVENT.*window-open" "$runtime/events.stream" ||
        ! grep -q "EVENT.*window-close" "$runtime/events.stream"; then
        echo "event stream missed window lifecycle" >&2
        cat "$runtime/events.stream" >&2
        exit 1
    fi
    echo "window lifecycle events: ok"
else
    echo "foot not found; skipping window lifecycle"
fi

kill "$epid" 2>/dev/null || true
wait "$epid" 2>/dev/null || true
epid=

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "smoke test passed"
