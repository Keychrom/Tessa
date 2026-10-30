#!/bin/sh
# Automate pointer and keyboard interactions that do not need physical input:
# bar workspace clicks, window-chip close, click-to-focus, floating drag/resize,
# fullscreen, and launcher typing.
# Requires foot, wtype, cc, and wayland-scanner.
#   sh tests/interaction.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

for tool in foot wtype cc wayland-scanner; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping interaction test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-interaction.XXXXXX")
tpid=
cleanup() {
    [ -n "${wpid:-}" ] && kill "$wpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${wpid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    pkill -x foot 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime" "$runtime/build"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
animations = false
launcher_entry = zzyzxauto | sh -c 'printf launched > $runtime/launched'
EOF

wayland-scanner client-header "$root/tests/protocol/wlr-virtual-pointer-unstable-v1.xml" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$root/tests/protocol/wlr-virtual-pointer-unstable-v1.xml" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-protocol.c"
cc -O2 -I"$runtime/build" -o "$runtime/build/automation" \
    "$root/tests/automation/main.c" \
    "$runtime/build/wlr-virtual-pointer-unstable-v1-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)

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
    tail -80 "$runtime/tessa.log" >&2
    exit 1
}

wait_state() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        if printf '%s\n' "$state" | grep -q "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not match: $pattern" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

win_field() {
    id=$1
    field=$2
    printf '%s\n' "$state" | awk -F '\t' -v id="$id" -v f="$field" \
        '$1 == "WIN" && $2 == id { print $f; exit }'
}

wait_win() {
    id=$1
    field=$2
    expected=$3
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        value=$(win_field "$id" "$field")
        if [ "$value" = "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "window $id field $field did not become $expected (got ${value:-none})" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

automation() {
    "$runtime/build/automation" "$@"
}

wait_log "tessa-panel: state: output=HEADLESS-1"
wait_log "tessa-panel: bar surface:"
bar_w=$(sed -n 's/.*bar surface: \([0-9]*\)x\([0-9]*\).*/\1/p' "$runtime/tessa.log" | tail -1)
bar_h=$(sed -n 's/.*bar surface: \([0-9]*\)x\([0-9]*\).*/\2/p' "$runtime/tessa.log" | tail -1)
if [ -z "$bar_w" ] || [ -z "$bar_h" ]; then
    echo "could not parse bar size" >&2
    exit 1
fi
sleep 0.3
ws_y=$((12 + bar_h / 2))
ws1_x=$((16 + bar_w / 2 - 115 + 11))
ws2_x=$((ws1_x + 26))
automation abs "$ws2_x" "$ws_y" click 0x110
wait_state "ACTIVE 2"
automation abs "$ws1_x" "$ws_y" click 0x110
wait_state "ACTIVE 1"
echo "bar workspace clicks: ok"

tessa-ctl spawn foot -T InteractionA
wait_state "WIN"
state=$(tessa-ctl state)
wid=$(printf '%s\n' "$state" | awk -F '\t' '$1 == "WIN" { print $2; exit }')
if [ -z "$wid" ]; then
    echo "could not find InteractionA window" >&2
    exit 1
fi

tessa-ctl dispatch float "$wid"
wait_win "$wid" 5 1
state=$(tessa-ctl state)
x=$(win_field "$wid" 10)
y=$(win_field "$wid" 11)
w=$(win_field "$wid" 12)
h=$(win_field "$wid" 13)
if [ "$w" -lt 200 ] || [ "$h" -lt 200 ]; then
    echo "floating window has no geometry" >&2
    printf '%s\n' "$state" >&2
    exit 1
fi

wtype -M logo -s 1500 -k F24 >/dev/null 2>&1 &
wpid=$!
sleep 0.3
cx=$((x + w / 2))
cy=$((y + h / 2))
automation abs "$cx" "$cy" press 0x110 move 120 80 release 0x110 sleep 100
wait "$wpid" 2>/dev/null || true
wpid=
wait_win "$wid" 10 "$((x + 120))"
wait_win "$wid" 11 "$((y + 80))"
echo "floating drag: ok"

state=$(tessa-ctl state)
x=$(win_field "$wid" 10)
y=$(win_field "$wid" 11)
w=$(win_field "$wid" 12)
h=$(win_field "$wid" 13)

wtype -M logo -s 1500 -k F24 >/dev/null 2>&1 &
wpid=$!
sleep 0.3
automation abs "$((x + w - 20))" "$((y + h - 20))" press 0x111 move 100 60 release 0x111 sleep 100
wait "$wpid" 2>/dev/null || true
wpid=
i=0
while :; do
    state=$(tessa-ctl state 2>/dev/null || true)
    new_w=$(win_field "$wid" 12)
    new_h=$(win_field "$wid" 13)
    if [ "${new_w:-0}" -ge "$((w + 60))" ] && [ "${new_h:-0}" -ge "$((h + 30))" ]; then
        break
    fi
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
        echo "floating resize did not grow the window: ${w}x${h} -> ${new_w:-?}x${new_h:-?}" >&2
        printf '%s\n' "$state" >&2
        exit 1
    fi
    sleep 0.1
done
echo "floating resize: ok"

wtype -M logo -k f
wait_win "$wid" 6 1
wtype -M logo -k f
wait_win "$wid" 6 0
echo "fullscreen toggle: ok"

tessa-ctl spawn foot -T InteractionB
wait_state "WIN.*InteractionB"
state=$(tessa-ctl state)
wid_b=$(printf '%s\n' "$state" | awk -F '\t' '$1 == "WIN" && $8 == "InteractionB" { print $2; exit }')
if [ -z "$wid_b" ]; then
    echo "could not find InteractionB window" >&2
    exit 1
fi
wait_state "FOCUSED $wid_b"
state=$(tessa-ctl state)
bx=$(win_field "$wid_b" 10)
by=$(win_field "$wid_b" 11)
bw=$(win_field "$wid_b" 12)
bh=$(win_field "$wid_b" 13)
automation abs "$((bx + 20))" "$((by + 20))" click 0x110
wait_state "FOCUSED $wid_b"
state=$(tessa-ctl state)
ax=$(win_field "$wid" 10)
ay=$(win_field "$wid" 11)
aw=$(win_field "$wid" 12)
ah=$(win_field "$wid" 13)
automation abs "$((ax + aw / 2))" "$((ay + ah / 2))" click 0x110
wait_state "FOCUSED $wid"
echo "click-to-focus: ok"

# The first window chip starts near x=156 on the 1888px bar.
automation abs "$((16 + 184))" "$ws_y" click 0x111
i=0
while [ "$i" -lt 100 ]; do
    state=$(tessa-ctl state 2>/dev/null || true)
    if ! printf '%s\n' "$state" | grep -q "^WIN	$wid	"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if printf '%s\n' "$state" | grep -q "^WIN	$wid	"; then
    echo "right-clicking the window chip did not close it" >&2
    printf '%s\n' "$state" >&2
    exit 1
fi
echo "window-chip right-click close: ok"

wtype -M logo -k d
wait_log "layer map: tessa-overlay"
sleep 0.3
wtype "zzyzxauto"
sleep 0.3
wtype -k Return
i=0
while [ ! -f "$runtime/launched" ]; do
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
        echo "launcher did not run the typed entry" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
echo "launcher typing: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
cleanup
echo "interaction test passed"
