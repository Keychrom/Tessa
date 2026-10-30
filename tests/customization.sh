#!/bin/sh
# Exercise declarative window rules, live rule reloads, and config introspection.
# Requires foot. Run from the repository root after building:
#   sh tests/customization.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping customization test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-rules.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

write_config() {
    work_action=$1
    cat > "$runtime/config" <<EOF
panel = false
xwayland = false
layout = master
master_count = 2
mosaic_ratio = 0.700
mosaic_min_size = 180
grid_columns = 4
border_active = #ff7755
border_inactive = #202634
window-rule = title=FloatRule*; float=true; size=500x400; position=30,40
window-rule = $work_action
window-rule = app-id=foot; title=FullRule*; fullscreen=true
EOF
}

write_config "title=WorkRule*; workspace=2"

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
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
    echo "state did not contain: $pattern" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

wait_win() {
    title=$1
    field=$2
    expected=$3
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        got=$(printf '%s\n' "$state" | awk -F '	' -v t="$title" -v f="$field" '
            $1 == "WIN" && index($8, t) > 0 { print $(f + 0); exit }')
        if [ "$got" = "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "window '$title' field $field did not become '$expected'" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

wait_state "OUT HEADLESS-1 1 1 master"
tessa-ctl config >"$runtime/config.out"
grep -q "master_count 2" "$runtime/config.out"
grep -q "mosaic_ratio 0.700" "$runtime/config.out"
grep -q "mosaic_min_size 180" "$runtime/config.out"
grep -q "grid_columns 4" "$runtime/config.out"
grep -q "border_active #ff7755" "$runtime/config.out"
grep -q "rule_count 3" "$runtime/config.out"
grep -q "rule title=FloatRule\*; float=true; size=500x400; position=30,40" "$runtime/config.out"
echo "effective config introspection: ok"

tessa-ctl spawn foot -T FloatRule
tessa-ctl spawn foot -T WorkRule
tessa-ctl spawn foot -T FullRule
wait_state "OCC 1 2"
wait_state "OCC 2 1"

wait_win FloatRule 5 1
wait_win FloatRule 12 500
wait_win FloatRule 13 400
wait_win FloatRule 10 30
wait_win FloatRule 11 40
wait_win WorkRule 3 2
wait_win WorkRule 5 0
wait_win FullRule 6 1
wait_win FullRule 12 1920
wait_win FullRule 13 1080
echo "window rules on map: ok"

write_config "title=WorkRule*; workspace=3; float=true; size=600x300"
tessa-ctl dispatch reload
wait_win WorkRule 3 3
wait_win WorkRule 5 1
tessa-ctl config >"$runtime/config.out"
grep -q "border_active #ff7755" "$runtime/config.out"
tessa-ctl workspace 3
wait_state "OUT HEADLESS-1 3 1 master"
wait_win WorkRule 12 600
wait_win WorkRule 13 300
echo "window rule reload: ok"

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
echo "customization test passed"
