#!/bin/sh
# Verify that wlr-randr changes survive a compositor restart.
# Requires wlr-randr in PATH, or set WLR_RANDR=/path/to/wlr-randr.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if [ -n "${WLR_RANDR:-}" ]; then
    randr=$WLR_RANDR
elif command -v wlr-randr >/dev/null 2>&1; then
    randr=wlr-randr
else
    echo "wlr-randr not found; skipping output persistence test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-output.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/xdg"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = false
xwayland = false
layout = master
layout_2 = columns
EOF

export TESSA_CONFIG="$runtime/config"
export XDG_CONFIG_HOME="$runtime/xdg"
export XDG_RUNTIME_DIR="$runtime"
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"

start_tessa() {
    "$bin/tessa" >"$runtime/$1.log" 2>&1 &
    tpid=$!
    i=0
    while [ ! -S "$runtime/tessa.sock" ]; do
        i=$((i + 1))
        if [ "$i" -ge 100 ]; then
            echo "compositor did not create its socket" >&2
            cat "$runtime/$1.log" >&2
            exit 1
        fi
        sleep 0.1
    done
    sleep 1
}

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
    exit 1
}

stop_tessa() {
    tessa-ctl quit 2>/dev/null || true
    sleep 1
    wait "$tpid" 2>/dev/null || true
    tpid=
    if grep -qE 'Assertion|panic|thread .* panic' "$1"; then
        echo "compositor did not shut down cleanly" >&2
        grep -E 'Assertion|panic|thread .* panic' "$1" >&2
        exit 1
    fi
}

start_tessa first
name=$("$randr" | sed -n '1s/ .*//p')
if [ -z "$name" ]; then
    echo "could not discover the output name" >&2
    "$randr" >&2
    exit 1
fi

"$randr" --output "$name" --scale 2 --pos 40,30 --custom-mode 1280x720@60
sleep 1
info=$("$randr")
printf '%s\n' "$info" | grep -q 'Scale: 2.000000'
printf '%s\n' "$info" | grep -q 'Position: 40,30'
printf '%s\n' "$info" | grep -q '1280x720 px'
config_file="$XDG_CONFIG_HOME/tessa/outputs.conf"
test -f "$config_file"
grep -q "^output $name " "$config_file"

tessa-ctl layout grid
wait_state "OUT $name 1 1 grid"
grep -q "^layout $name 1 grid$" "$config_file"
if grep -q "^layout $name 2 " "$config_file"; then
    echo "config default layout was saved as a runtime override" >&2
    cat "$config_file" >&2
    exit 1
fi
echo "wlr-randr apply + save + layout save: ok"
stop_tessa "$runtime/first.log"

start_tessa second
info=$("$randr")
printf '%s\n' "$info" | grep -q 'Scale: 2.000000'
printf '%s\n' "$info" | grep -q 'Position: 40,30'
printf '%s\n' "$info" | grep -q '1280x720 px'
echo "restart restore: ok"

wait_state "OUT $name 1 1 grid"
tessa-ctl workspace 2
wait_state "OUT $name 2 1 columns"
tessa-ctl workspace 1
wait_state "OUT $name 1 1 grid"
echo "layout restore: ok"
stop_tessa "$runtime/second.log"

trap - EXIT INT TERM
rm -rf "$runtime"
echo "output persistence test passed"
