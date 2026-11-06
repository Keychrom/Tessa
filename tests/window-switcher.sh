#!/bin/sh
# Verify the Phase 2 window switcher: Alt+Tab open/commit, Tab cycling,
# Escape cancel, and the off/icons/snapshot modes.
# Requires wtype. Run from the repository root after building:
#   sh tests/window-switcher.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v wtype >/dev/null 2>&1; then
    echo "wtype not found; skipping window switcher test"
    exit 0
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping window switcher test"
    exit 0
fi

runtime=
tpid=
cleanup() {
    if [ -n "${tpid:-}" ]; then
        kill "$tpid" 2>/dev/null || true
        wait "$tpid" 2>/dev/null || true
    fi
    if [ -n "${runtime:-}" ]; then
        rm -rf "$runtime"
    fi
    return 0
}
trap cleanup EXIT INT TERM

start_session() {
    mode=$1
    outputs=${2:-1}
    runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-switcher.XXXXXX")
    chmod 700 "$runtime"
    cat > "$runtime/config" <<EOF
panel = true
xwayland = false
panel_style = classic
window_switcher = $mode
bar_layout = logo,workspaces,clock
EOF
    export TESSA_CONFIG="$runtime/config"
    export TESSA_IPC="$runtime/tessa.sock"
    export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
    export XDG_RUNTIME_DIR="$runtime"
    export WAYLAND_DISPLAY=wayland-0
    export WLR_BACKENDS=headless
    export WLR_RENDERER=pixman
    export WLR_HEADLESS_OUTPUTS=$outputs
    export PATH="$bin:$PATH"
    export TESSA_DEBUG=1
    export TESSA_PANEL_DEBUG=1

    "$bin/tessa" >"$runtime/tessa.log" 2>&1 &
    tpid=$!
    i=0
    while [ ! -S "$runtime/tessa.sock" ]; do
        i=$((i + 1))
        if [ "$i" -ge 150 ]; then
            echo "compositor did not create its socket" >&2
            cat "$runtime/tessa.log" >&2
            exit 1
        fi
        sleep 0.1
    done
    while [ "$(grep -c 'tessa-panel: bar surface:' "$runtime/tessa.log" 2>/dev/null || true)" -lt "$outputs" ]; do
        i=$((i + 1))
        if [ "$i" -ge 200 ]; then
            echo "panel did not start" >&2
            cat "$runtime/tessa.log" >&2
            exit 1
        fi
        sleep 0.1
    done
}

stop_session() {
    kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    tpid=
    rm -rf "$runtime"
    runtime=
}

focused() {
    "$bin/tessa-ctl" state | sed -n 's/^FOCUSED //p'
}

active_ws() {
    "$bin/tessa-ctl" state | sed -n 's/^ACTIVE //p' | head -n 1
}

output_focused() {
    "$bin/tessa-ctl" state | awk -v out="$1" '$1 == "OUT" && $2 == out { print $4 }'
}

spawn_three() {
    "$bin/tessa-ctl" spawn foot -T ALPHA >/dev/null
    sleep 0.8
    "$bin/tessa-ctl" spawn foot -T BETA >/dev/null
    sleep 0.8
    "$bin/tessa-ctl" spawn foot -T GAMMA >/dev/null
    sleep 0.8
}

fail() {
    echo "FAIL: $*" >&2
    echo "--- log tail ---" >&2
    tail -40 "$runtime/tessa.log" >&2 || true
    exit 1
}

# --- snapshot: open, cycle, commit ---------------------------------------
start_session snapshot
spawn_three
[ "$(focused)" = 3 ] || fail "expected window 3 focused, got $(focused)"
mark=$(wc -l <"$runtime/tessa.log")
# Hold Alt for 2s so the overlay maps and owns the keyboard.
wtype -M alt -k Tab -s 2000 -m alt &
wpid=$!
sleep 0.7
grep -q "switcher: open windows=3 selected=1 previews=true live=true" "$runtime/tessa.log" || fail "snapshot switcher did not open with live previews"
wtype -k Tab
sleep 0.2
wtype -k Return
wait "$wpid" || true
sleep 0.4
[ "$(focused)" = 1 ] || fail "Tab+Return should focus window 1, got $(focused)"
grep -q "switcher: activate id=1" "$runtime/tessa.log" || fail "commit was not logged"
grep -q "switcher: thumbnail id=" "$runtime/tessa.log" || fail "live preview frames did not arrive"
stop_session

# --- Escape cancels without changing focus --------------------------------
start_session snapshot
spawn_three
mark=$(wc -l <"$runtime/tessa.log")
wtype -M alt -k Tab -s 1200 -m alt &
wpid=$!
sleep 0.6
wtype -k Escape
wait "$wpid" || true
sleep 0.4
[ "$(focused)" = 3 ] || fail "Escape changed focus to $(focused)"
if tail -n +$((mark + 1)) "$runtime/tessa.log" | grep -q "switcher: focus id="; then
    fail "Escape still committed a window"
fi
stop_session

# --- icons mode -----------------------------------------------------------
start_session icons
spawn_three
mark=$(wc -l <"$runtime/tessa.log")
wtype -M alt -k Tab -s 1600 -m alt &
wpid=$!
sleep 0.6
grep -q "switcher: open windows=3 selected=1 previews=false live=false" "$runtime/tessa.log" || fail "icons switcher did not open"
wtype -k Return
wait "$wpid" || true
sleep 0.4
[ "$(focused)" = 2 ] || fail "icons mode should focus window 2, got $(focused)"
stop_session

# --- off mode -------------------------------------------------------------
start_session off
spawn_three
mark=$(wc -l <"$runtime/tessa.log")
wtype -M alt -k Tab
sleep 0.4
if tail -n +$((mark + 1)) "$runtime/tessa.log" | grep -q "switcher: open"; then
    fail "switcher opened while window_switcher=off"
fi
[ "$(focused)" = 3 ] || fail "off mode changed focus to $(focused)"
stop_session

# --- other workspaces are listed and activation switches back ------------
start_session snapshot
"$bin/tessa-ctl" spawn foot -T WORKSPACE-A >/dev/null
sleep 0.8
"$bin/tessa-ctl" workspace 2 >/dev/null
sleep 0.4
"$bin/tessa-ctl" spawn foot -T WORKSPACE-B >/dev/null
sleep 0.8
"$bin/tessa-ctl" spawn foot -T WORKSPACE-C >/dev/null
sleep 0.8
"$bin/tessa-ctl" panel switcher
sleep 1
wtype -k End
sleep 0.2
wtype -k Return
sleep 0.8
[ "$(active_ws)" = 1 ] || fail "workspace activation did not switch to workspace 1 (got $(active_ws))"
[ "$(focused)" = 1 ] || fail "workspace activation focused $(focused), expected 1"
grep -q "switcher: activate id=1" "$runtime/tessa.log" || fail "cross-workspace activation was not logged"
stop_session

# --- another output is listed and activation focuses that output ---------
start_session snapshot 2
"$bin/tessa-ctl" workspace 1 HEADLESS-1 >/dev/null
sleep 0.4
"$bin/tessa-ctl" spawn foot -T OUTPUT-A >/dev/null
sleep 0.8
"$bin/tessa-ctl" workspace 1 HEADLESS-2 >/dev/null
sleep 0.4
"$bin/tessa-ctl" spawn foot -T OUTPUT-B >/dev/null
sleep 0.8
"$bin/tessa-ctl" panel switcher
sleep 1
wtype -k Return
sleep 0.8
[ "$(focused)" = 1 ] || fail "cross-output activation focused $(focused), expected 1"
[ "$(output_focused HEADLESS-1)" = 1 ] || fail "HEADLESS-1 did not become the focused output"
stop_session

echo "window switcher test passed"
