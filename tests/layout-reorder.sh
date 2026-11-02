#!/bin/sh
# Verify dynamic tile reordering (IPC and mouse) and Mod+wheel scrolling.
# Requires kitty, wtype, cc, and wayland-scanner.
#   sh tests/layout-reorder.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

for tool in kitty wtype cc wayland-scanner; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping reorder test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-reorder.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime" "$runtime/build"
chmod 700 "$runtime"
cat >"$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
outer_gaps = 0
gaps = 0
layout = master
master_count = 1
master_ratio = 0.5
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

"$bin/tessa" >"$runtime/tessa.log" 2>&1 &
tpid=$!
i=0
while [ ! -S "$runtime/tessa.sock" ]; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || { echo "no socket" >&2; cat "$runtime/tessa.log" >&2; exit 1; }
    sleep 0.1
done

state() { tessa-ctl state; }
wait_state() {
    i=0
    while [ "$i" -lt 100 ]; do
        if state 2>/dev/null | grep -q "$1"; then return 0; fi
        i=$((i + 1)); sleep 0.1
    done
    echo "state did not contain: $1" >&2
    state >&2
    exit 1
}
win_field() {
    id=$1
    n=$2
    state | awk -F '\t' -v id="$id" -v n="$n" '$1 == "WIN" && $2 == id { print $n; exit }'
}
win_id_by_title() {
    state | awk -F '\t' -v t="$1" '$1 == "WIN" && $8 == t { print $2; exit }'
}
view_field() {
    state | awk -v n="$1" '$1 == "VIEW" { print $n; exit }'
}
automation() { "$runtime/build/automation" "$@"; }

for n in 1 2 3 4; do
    tessa-ctl spawn kitty -T "Reorder$n" >/dev/null
    wait_state "Reorder$n"
done
sleep 0.3

id1=$(win_id_by_title Reorder1)
id4=$(win_id_by_title Reorder4)
tessa-ctl reorder "$id4" before "$id1" >/dev/null
wait_state "Reorder"
sleep 0.2
if [ "$(win_field "$id4" 10)" != "0" ] || [ "$(win_field "$id4" 12)" != "960" ]; then
    echo "IPC reorder did not move Reorder4 to master" >&2
    state >&2
    exit 1
fi
echo "IPC reorder: ok"

id2=$(win_id_by_title Reorder2)
tessa-ctl swap "$id1" "$id2" >/dev/null
sleep 0.2
if [ "$(win_field "$id1" 11)" != "360" ] || [ "$(win_field "$id2" 11)" != "0" ]; then
    echo "swap did not exchange the two stack slots" >&2
    state >&2
    exit 1
fi
echo "swap: ok"

# Drag the master window into the stack area.
wtype -M logo -s 2000 -k F24 >/dev/null 2>&1 &
sleep 0.3
automation abs 480 540 press 0x110 move 900 300 sleep 100 release 0x110 sleep 100 >/dev/null
sleep 0.5
if [ "$(win_field "$id4" 10)" = "0" ]; then
    echo "tiled mouse drag did not move the master window" >&2
    state >&2
    exit 1
fi
echo "tiled mouse drag: ok"

tessa-ctl layout scrolling >/dev/null
wait_state "^OUT .* scrolling"
tessa-ctl column-focus last >/dev/null
sleep 0.2
before=$(view_field 4)
wtype -M logo -s 1000 -k F24 >/dev/null 2>&1 &
sleep 0.2
automation abs 960 540 axis -5 sleep 100 >/dev/null
sleep 0.4
after=$(view_field 4)
if [ -z "$before" ] || [ "$before" = "$after" ]; then
    echo "Mod+wheel did not change the scrolling view ($before -> $after)" >&2
    state >&2
    exit 1
fi
echo "Mod+wheel scrolling: ok ($before -> $after)"

tessa-ctl layout master >/dev/null
wait_state "^OUT .* master"
echo "scrolling flatten on mode switch: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime" 2>/dev/null || true
echo "reorder test passed"
