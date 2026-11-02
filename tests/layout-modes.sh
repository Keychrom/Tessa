#!/bin/sh
# Verify monocle and deck-style stacking layouts.
# Requires kitty.
#   sh tests/layout-modes.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if ! command -v kitty >/dev/null 2>&1; then
    echo "kitty not found; skipping layout modes test"
    exit 0
fi
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-layout-modes.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat >"$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
outer_gaps = 0
gaps = 0
layout = master
master_ratio = 0.5
master_count = 1
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
    [ "$i" -lt 100 ] || { echo "no socket" >&2; cat "$runtime/tessa.log" >&2; exit 1; }
    sleep 0.1
done

state() { tessa-ctl state; }
wait_state() {
    i=0
    while [ "$i" -lt 100 ]; do
        if state 2>/dev/null | grep -q "$1"; then return 0; fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not contain: $1" >&2
    state >&2
    exit 1
}
win_field() {
    state | awk -F '\t' -v id="$1" -v n="$2" '$1 == "WIN" && $2 == id { print $n; exit }'
}
win_id_by_title() {
    state | awk -F '\t' -v t="$1" '$1 == "WIN" && $8 == t { print $2; exit }'
}

for n in 1 2 3 4; do
    tessa-ctl spawn kitty -T "Mode$n" >/dev/null
    wait_state "Mode$n"
done
sleep 0.3

tessa-ctl layout monocle >/dev/null
wait_state "^OUT .* monocle"
i=0
while [ "$i" -lt 100 ]; do
    count=$(state | awk -F '\t' '$1 == "WIN" && $18 == 1 { n++ } END { print n+0 }')
    [ "$count" = "1" ] && break
    i=$((i + 1)); sleep 0.1
done
if [ "$count" != "1" ]; then
    echo "monocle shows $count windows instead of 1" >&2
    state >&2
    exit 1
fi
id2=$(win_id_by_title Mode2)
tessa-ctl dispatch "focus $id2" >/dev/null
i=0
while [ "$i" -lt 100 ] && [ "$(win_field "$id2" 18)" != "1" ]; do i=$((i + 1)); sleep 0.1; done
if [ "$(win_field "$id2" 18)" != "1" ]; then
    echo "monocle did not reveal the newly focused window" >&2
    exit 1
fi
if [ "$(win_field "$id2" 12)" != "1920" ] || [ "$(win_field "$id2" 13)" != "1080" ]; then
    echo "monocle window is not full usable area: $(win_field "$id2" 12)x$(win_field "$id2" 13)" >&2
    exit 1
fi
echo "monocle: ok"

tessa-ctl layout stacking >/dev/null
wait_state "^OUT .* stacking"
sleep 0.2
id1=$(win_id_by_title Mode1)
if [ "$(win_field "$id1" 12)" != "960" ] || [ "$(win_field "$id1" 13)" != "1080" ]; then
    echo "stacking master is not the left half: $(win_field "$id1" 12)x$(win_field "$id1" 13)" >&2
    exit 1
fi
for n in 2 3 4; do
    id=$(win_id_by_title "Mode$n")
    if [ "$(win_field "$id" 10)" != "960" ] || [ "$(win_field "$id" 12)" != "960" ]; then
        echo "stacking card $n is not in the right stack area" >&2
        exit 1
    fi
    if [ "$(win_field "$id" 18)" != "1" ]; then
        echo "stacking card $n is not marked on_screen" >&2
        exit 1
    fi
done
echo "stacking: ok"

tessa-ctl layout deck >/dev/null
wait_state "^OUT .* stacking"
echo "deck alias: ok"

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
echo "layout modes test passed"
