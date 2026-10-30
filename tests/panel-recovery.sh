#!/bin/sh
# Verify that the built-in panel is supervised and restarted after a crash.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-panel-recovery.XXXXXX")
tpid=
panel_pid=
cleanup() {
    [ -n "${panel_pid:-}" ] && kill "$panel_pid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
animations = false
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
    count=${2:-1}
    i=0
    while [ "$i" -lt 150 ]; do
        if [ "$(grep -cF "$pattern" "$runtime/tessa.log" 2>/dev/null || true)" -ge "$count" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not contain $count occurrence(s) of: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_panel_pid() {
    i=0
    while [ "$i" -lt 100 ]; do
        pid=$(pgrep -P "$tpid" -x tessa-panel 2>/dev/null | head -n 1 || true)
        if [ -n "$pid" ]; then
            printf '%s\n' "$pid"
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "no panel child found" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_bar() {
    i=0
    while [ "$i" -lt 150 ]; do
        if tessa-ctl state 2>/dev/null | grep -qF "LAYER	tessa-bar"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "tessa-bar layer did not appear" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "panel started for HEADLESS-1" 1
wait_bar
pid=$(wait_panel_pid)
panel_pid=$pid
echo "initial panel pid: $pid"
tessa-ctl state | awk -F '\t' '
    $1 == "PANEL" && $2 == "HEADLESS-1" && $4 == "1" { found = 1 }
    END { exit(found ? 0 : 1) }
' || {
    echo "PANEL state line is missing or not supervised" >&2
    tessa-ctl state >&2
    exit 1
}

kill -KILL "$pid"
wait_log "panel process $pid for HEADLESS-1 exited unexpectedly" 1
wait_log "panel started for HEADLESS-1" 2
new_pid=$(wait_panel_pid)
panel_pid=$new_pid
if [ "$new_pid" = "$pid" ]; then
    echo "panel pid did not change after crash" >&2
    exit 1
fi
wait_bar
echo "first restart: ok (pid $new_pid)"

kill -KILL "$new_pid"
wait_log "panel process $new_pid for HEADLESS-1 exited unexpectedly" 1
wait_log "panel started for HEADLESS-1" 3
third_pid=$(wait_panel_pid)
panel_pid=$third_pid
if [ "$third_pid" = "$new_pid" ]; then
    echo "panel pid did not change after second crash" >&2
    exit 1
fi
wait_bar
echo "second restart: ok (pid $third_pid)"

sed 's/^panel = true$/panel = false/' "$runtime/config" >"$runtime/config.new"
mv "$runtime/config.new" "$runtime/config"
tessa-ctl dispatch reload
wait_log "panel stopped for HEADLESS-1" 1
i=0
while [ "$i" -lt 50 ] && kill -0 "$third_pid" 2>/dev/null; do
    i=$((i + 1))
    sleep 0.1
done
if kill -0 "$third_pid" 2>/dev/null; then
    echo "panel $third_pid did not stop after panel=false reload" >&2
    exit 1
fi
echo "panel disable reload: ok"

sed 's/^panel = false$/panel = true/' "$runtime/config" >"$runtime/config.new"
mv "$runtime/config.new" "$runtime/config"
tessa-ctl dispatch reload
wait_log "panel started for HEADLESS-1" 4
fourth_pid=$(wait_panel_pid)
panel_pid=$fourth_pid
wait_bar
echo "panel enable reload: ok (pid $fourth_pid)"

third_pid=$fourth_pid

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
i=0
while [ "$i" -lt 50 ] && kill -0 "$third_pid" 2>/dev/null; do
    i=$((i + 1))
    sleep 0.1
done
if kill -0 "$third_pid" 2>/dev/null; then
    echo "panel $third_pid survived compositor shutdown" >&2
    exit 1
fi
panel_pid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime"
echo "panel recovery test passed"
