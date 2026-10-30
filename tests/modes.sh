#!/bin/sh
# Verify named input modes, mode-specific key bindings, and mode state.
# Requires foot and wtype. Run from the repository root after building:
#   sh tests/modes.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping modes test"
    exit 0
fi
if ! command -v wtype >/dev/null 2>&1; then
    echo "wtype not found; skipping modes test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-modes.XXXXXX")
tpid=
epid=
cleanup() {
    [ -n "${epid:-}" ] && kill "$epid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = false
xwayland = false

leader = SUPER+SPACE
leader_timeout = 300

mode = leader
bind = f spawn touch $runtime/leader-fired
bind = Escape enter-mode default

mode = resize
mode_timeout = 250
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default

mode = default
bind = SUPER+SHIFT+r enter-mode resize
EOF

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

wait_width() {
    expected=$1
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        got_width=$(printf '%s\n' "$state" | awk -F '	' '$1 == "WIN" { print $12; exit }')
        if [ "$got_width" = "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "window width did not become $expected (got ${got_width:-empty})" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

tessa-ctl events mode-change >"$runtime/events" &
epid=$!
sleep 0.2

wait_state "MODE default"
tessa-ctl config >"$runtime/config.out"
grep -q "mode resize" "$runtime/config.out"
grep -q "active_mode default" "$runtime/config.out"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
tessa-ctl config --json >"$runtime/config.json"
grep -q '"modes":\["default","leader","resize"\]' "$runtime/config.json"
echo "mode config: ok"

tessa-ctl spawn foot -T ModeTest
wait_state "WIN"
wid=$(tessa-ctl state | awk -F '	' '$1 == "WIN" { print $2; exit }')
tessa-ctl dispatch float "$wid"
wait_state "WIN"
sleep 0.2
width=$(tessa-ctl state | awk -F '	' '$1 == "WIN" { print $12; exit }')
if [ -z "$width" ] || [ "$width" -le 0 ]; then
    echo "floating window has no width" >&2
    tessa-ctl state >&2
    exit 1
fi

tessa-ctl mode resize
wait_state "MODE resize"
tessa-ctl state --json | grep -q '"mode":"resize"'
wtype -k l
wait_width $((width + 30))
i=0
while ! grep -q "EVENT.*mode-change.*arg=resize" "$runtime/events" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
        echo "mode-change event was not emitted" >&2
        cat "$runtime/events" >&2
        exit 1
    fi
    sleep 0.1
done
echo "mode-specific key binding + event: ok"

width2=$((width + 30))
wtype -k Escape
wait_state "MODE default"
wtype -k l
sleep 0.2
width3=$(tessa-ctl state | awk -F '	' '$1 == "WIN" { print $12; exit }')
if [ "$width3" != "$width2" ]; then
    echo "normal key was intercepted after leaving the mode" >&2
    tessa-ctl state >&2
    exit 1
fi
echo "mode exit: ok"

rm -f "$runtime/leader-fired"
wtype -M logo -k space
wait_state "MODE leader"
wait_state "MODE default"
echo "leader timeout: ok"

wtype -M logo -k space
wait_state "MODE leader"
wtype -k f
i=0
while [ ! -e "$runtime/leader-fired" ]; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
        echo "leader binding did not run" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
wait_state "MODE default"
echo "leader chord binding: ok"

tessa-ctl mode resize
wait_state "MODE resize"
wait_state "MODE default"
echo "mode timeout: ok"

kill "$epid" 2>/dev/null || true
wait "$epid" 2>/dev/null || true
epid=

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
echo "modes test passed"
