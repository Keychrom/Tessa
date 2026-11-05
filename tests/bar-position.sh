#!/bin/sh
# Verify bar_position=top|bottom|left|right recreates the layer surface with
# the expected orientation and keeps the default top placement.
#   sh tests/bar-position.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-bar-position.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

write_config() {
    pos=$1
    cat > "$runtime/config" <<EOF
panel = true
xwayland = false
bar_position = $pos
bar_height = 44
bar_top_margin = 12
bar_side_margin = 16
EOF
}

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

check_surface() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        line=$(grep -F "tessa-panel: bar surface:" "$runtime/tessa.log" 2>/dev/null | tail -n 1)
        if echo "$line" | grep -q "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "last bar surface does not match '$pattern': $line" >&2
    exit 1
}

write_config top
export TESSA_CONFIG="$runtime/config"
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

wait_log "tessa-panel: bar: position=top 44px edge=12 inset=16"
check_surface 'x44$'
echo "bar position top: ok"

for pos in bottom left right; do
    write_config "$pos"
    tessa-ctl dispatch reload
    wait_log "tessa-panel: bar: position=$pos 44px edge=12 inset=16"
    if [ "$pos" = "left" ] || [ "$pos" = "right" ]; then
        check_surface 'bar surface: 44x'
    else
        check_surface 'x44$'
    fi
    if ! pgrep -x tessa-panel >/dev/null 2>&1; then
        echo "panel died after switching to $pos" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    echo "bar position $pos: ok"
done

write_config top
tessa-ctl dispatch reload
wait_log "tessa-panel: bar: position=top 44px edge=12 inset=16"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime"
echo "bar position test passed"
