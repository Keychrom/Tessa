#!/bin/sh
# Verify scene save/restore, non-destructive activation, layout application,
# persistence across restart, the scene deck, and Super+Shift+Tab.
# Requires cc, pkg-config, wayland-scanner, grim, and wtype.
#   sh tests/scenes.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
for tool in cc pkg-config grim wtype; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping scene test"
        exit 0
    fi
done

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-scenes.XXXXXX")
tpid=
cleanup() {
    pkill -f "$runtime/window-test" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/scenes"
chmod 700 "$runtime" "$runtime/scenes"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
animations = false
panel_style = unified
EOF

cc -O2 -I"$root/protocol" -o "$runtime/window-test" \
    "$root/tests/rule-visuals/window.c" \
    "$root/protocol/xdg-shell-client-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)

export TESSA_CONFIG="$runtime/config"
export TESSA_SCENE_DIR="$runtime/scenes"
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

start_compositor() {
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
}

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

wait_occ() {
    ws=$1
    count=$2
    i=0
    while [ "$i" -lt 120 ]; do
        if "$bin/tessa-ctl" state 2>/dev/null | grep -q "^OCC $ws $count$"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "workspace $ws did not reach $count windows" >&2
    "$bin/tessa-ctl" state >&2 || true
    exit 1
}

wait_scene_active() {
    name=$1
    i=0
    while [ "$i" -lt 120 ]; do
        active=$("$bin/tessa-ctl" state 2>/dev/null | awk -F '\t' -v n="$name" '$1 == "SCENE" && $2 == n { print $7; exit }')
        if [ "$active" = "1" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "scene $name did not become active" >&2
    "$bin/tessa-ctl" state >&2 || true
    exit 1
}

start_compositor
wait_log "tessa-panel: bar surface"

"$runtime/window-test" code Code >"$runtime/w1.log" 2>&1 &
"$runtime/window-test" chat Chat >"$runtime/w2.log" 2>&1 &
wait_occ 1 2

"$bin/tessa-ctl" scene save coding >/dev/null
wait_log "scene: saved 'coding'"
grep -q '^name = coding$' "$runtime/scenes/coding.scene"
grep -q '^workspace = 1$' "$runtime/scenes/coding.scene"
grep -q '^layout = master$' "$runtime/scenes/coding.scene"
grep -q '^app_id = code$' "$runtime/scenes/coding.scene"
grep -q "^command = $runtime/window-test code Code$" "$runtime/scenes/coding.scene"
grep -q '^\[theme\]$' "$runtime/scenes/coding.scene"
grep -q '^\[wallpaper\]$' "$runtime/scenes/coding.scene"
grep -q '^fit = cover$' "$runtime/scenes/coding.scene"
"$bin/tessa-ctl" scene list | grep -q "^coding	1	master	2$"
"$bin/tessa-ctl" state | grep -q '^SCENE	coding	master	2	2	1	0	'
echo "scene save: ok"

pkill -f "$runtime/window-test" 2>/dev/null || true
wait_occ 1 0
"$bin/tessa-ctl" scene activate coding >/dev/null
wait_occ 1 2
wait_scene_active coding
apps=$("$bin/tessa-ctl" state | awk -F '\t' '$1 == "WIN" && $2 > 0 { print $7 }' | sort | tr '\n' ' ')
case "$apps" in
    *code*chat*|*chat*code*) ;;
    *)
        echo "restored apps were not code/chat: $apps" >&2
        exit 1
        ;;
esac
echo "scene restore: ok"

# Applying a scene is non-destructive: an extra window stays.
"$runtime/window-test" extra Extra >"$runtime/w3.log" 2>&1 &
wait_occ 1 3
"$bin/tessa-ctl" scene activate coding >/dev/null
sleep 0.5
wait_occ 1 3
echo "non-destructive apply: ok"

# Layout is part of the scene.
"$bin/tessa-ctl" workspace 2 >/dev/null
"$runtime/window-test" grid Grid >"$runtime/w4.log" 2>&1 &
wait_occ 2 1
"$bin/tessa-ctl" layout grid >/dev/null
"$bin/tessa-ctl" scene save grid-scene >/dev/null
wait_log "scene: saved 'grid-scene'"
grep -q '^layout = grid$' "$runtime/scenes/grid-scene.scene"
"$bin/tessa-ctl" layout master >/dev/null
"$bin/tessa-ctl" scene activate grid-scene >/dev/null
wait_log "scene: apply 'grid-scene'"
i=0
layout=
while [ "$i" -lt 120 ]; do
    layout=$("$bin/tessa-ctl" state | awk '$1 == "OUT" && $2 == "HEADLESS-1" { print $5; exit }')
    [ "$layout" = "grid" ] && break
    i=$((i + 1))
    sleep 0.1
done
if [ "$layout" != "grid" ]; then
    echo "scene layout did not apply: $layout" >&2
    exit 1
fi
echo "scene layout: ok"

# Scene deck: IPC, live previews, Enter to apply, Escape to close.
"$bin/tessa-ctl" workspace 1 >/dev/null
"$bin/tessa-ctl" panel scenes >/dev/null
wait_log "scene deck: open"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
sleep 0.8
wtype -k Return
wait_log "scene deck: activate coding"
wait_log "overlay close"
echo "scene deck: ok"

# Default binding opens the deck.
wtype -M logo -M shift -k Tab
wait_log "scene deck: open"
sleep 0.5
wtype -k Escape
wait_log "overlay close"
echo "scene binding: ok"

# Scenes survive a compositor restart; the save-time command still resolves.
"$bin/tessa-ctl" quit
wait "$tpid" 2>/dev/null || true
tpid=
start_compositor
wait_log "scene: loaded 2 scene(s)"
"$bin/tessa-ctl" scene list | grep -q "^coding	1	master	2$"
"$bin/tessa-ctl" scene list | grep -q "^grid-scene	2	grid	1$"
echo "scene restart persistence: ok"

"$bin/tessa-ctl" scene delete coding >/dev/null
wait_log "scene: deleted 'coding'"
if "$bin/tessa-ctl" scene list | grep -q '^coding	'; then
    echo "deleted scene still listed" >&2
    exit 1
fi
echo "scene delete: ok"

"$bin/tessa-ctl" quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE "panic|Assertion|double free" "$runtime/tessa.log"; then
    echo "scene test crashed" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "scene test passed"
