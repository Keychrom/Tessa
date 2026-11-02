#!/bin/sh
# Verify the scrolling layout: column widths, viewport focus, presets,
# maximize/center, consume/expel, and state fields.
# Requires kitty and wtype.
#   sh tests/layout-scrolling.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

for tool in kitty wtype; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping scrolling layout test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-scrolling.XXXXXX")
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
layout = scrolling
default_column_width = 50%
column_width_presets = 25%,50%,75%
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

state() { tessa-ctl state; }

wait_state() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if state 2>/dev/null | grep -q "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not contain: $pattern" >&2
    state >&2 2>/dev/null || true
    exit 1
}

view_field() {
    state | awk -v n="$1" '$1 == "VIEW" { print $n; exit }'
}

col_field() {
    idx=$1
    n=$2
    state | awk -v i="$idx" -v n="$n" '$1 == "COL" && $4 == i { print $n; exit }'
}

win_field() {
    id=$1
    n=$2
    state | awk -v id="$id" -v n="$n" '$1 == "WIN" && $2 == id { print $n; exit }'
}

win_id_by_title() {
    state | awk -F '\t' -v title="$1" '$1 == "WIN" && $8 == title { print $2; exit }'
}

wait_col_count() {
    want=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if [ "$(view_field 7)" = "$want" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "column count did not become $want" >&2
    state >&2
    exit 1
}

tessa-ctl spawn kitty -T Scroll1 >/dev/null
wait_state "Scroll1"
wait_col_count 1
if [ "$(col_field 0 6)" != "960" ]; then
    echo "single scrolling column is not the configured 50% width: $(col_field 0 6)" >&2
    exit 1
fi
if [ "$(col_field 0 5)" != "0" ]; then
    echo "single scrolling column did not start at x=0" >&2
    exit 1
fi
echo "single column width: ok"

for n in 2 3 4; do
    tessa-ctl spawn kitty -T "Scroll$n" >/dev/null
    wait_state "Scroll$n"
done
wait_col_count 4
if [ "$(view_field 5)" != "3840" ]; then
    echo "unexpected scrolling content width: $(view_field 5)" >&2
    exit 1
fi

tessa-ctl column-focus last >/dev/null
i=0
while [ "$i" -lt 100 ] && [ "$(view_field 4)" != "1920" ]; do i=$((i + 1)); sleep 0.1; done
if [ "$(view_field 4)" != "1920" ]; then
    echo "focusing the last column did not scroll the view: $(view_field 4)" >&2
    exit 1
fi
id4=$(win_id_by_title Scroll4)
if [ "$(win_field "$id4" 18)" != "1" ]; then
    echo "focused off-screen column is not marked on_screen" >&2
    exit 1
fi
if [ "$(win_field 1 18)" = "1" ]; then
    echo "off-screen column was left marked on_screen" >&2
    exit 1
fi
echo "viewport focus: ok"

tessa-ctl column-focus first >/dev/null
tessa-ctl column-focus right >/dev/null
tessa-ctl column-width center >/dev/null
i=0
while [ "$i" -lt 100 ] && [ "$(view_field 4)" != "480" ]; do i=$((i + 1)); sleep 0.1; done
if [ "$(view_field 4)" != "480" ]; then
    echo "center-column did not center the second column: $(view_field 4)" >&2
    exit 1
fi
echo "center column: ok"

tessa-ctl column-focus first >/dev/null
tessa-ctl column-width cycle >/dev/null
if [ "$(col_field 0 6)" != "480" ]; then
    echo "first preset is not 25%: $(col_field 0 6)" >&2
    exit 1
fi
tessa-ctl column-width cycle >/dev/null
if [ "$(col_field 0 6)" != "960" ]; then
    echo "second preset is not 50%" >&2
    exit 1
fi
tessa-ctl column-width cycle-back >/dev/null
if [ "$(col_field 0 6)" != "480" ]; then
    echo "cycle-back did not restore the 25% preset" >&2
    exit 1
fi
tessa-ctl column-width maximize >/dev/null
if [ "$(col_field 0 6)" != "1920" ] || [ "$(col_field 0 8)" != "1" ]; then
    echo "maximize-column did not fill the viewport" >&2
    exit 1
fi
tessa-ctl column-width maximize >/dev/null
if [ "$(col_field 0 6)" != "480" ] || [ "$(col_field 0 8)" != "0" ]; then
    echo "unmaximize did not restore the column width" >&2
    exit 1
fi
echo "column widths: ok"

tessa-ctl consume >/dev/null
wait_col_count 3
if [ "$(col_field 0 10)" != "2" ]; then
    echo "consume did not merge the right window: $(col_field 0 10)" >&2
    exit 1
fi
if [ "$(col_field 0 9)" = "1" ]; then
    echo "consume unexpectedly produced a tabbed group column" >&2
    exit 1
fi
tessa-ctl expel >/dev/null
wait_col_count 4
if [ "$(col_field 0 10)" != "1" ]; then
    echo "expel did not split the bottom window" >&2
    exit 1
fi
echo "consume/expel: ok"

tessa-ctl dispatch toggle-group >/dev/null
wait_col_count 1
if [ "$(col_field 0 9)" != "1" ] || [ "$(col_field 0 10)" != "1" ]; then
    echo "grouped windows are not a single tabbed column" >&2
    state >&2
    exit 1
fi
tessa-ctl dispatch group-next >/dev/null
sleep 0.2
if [ "$(view_field 7)" != "1" ]; then
    echo "group-next changed the scrolling column count" >&2
    exit 1
fi
tessa-ctl dispatch toggle-group >/dev/null
wait_col_count 4
echo "groups as tabbed columns: ok"

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
echo "scrolling layout test passed"
