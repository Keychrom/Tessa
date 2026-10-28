#!/bin/sh
# Optional Kitty regression: a late toplevel must stay mapped and receive the
# initial fractional scale. Skips when kitty or wlr-randr is unavailable.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v kitty >/dev/null 2>&1; then
    echo "kitty not found; skipping kitty startup test"
    exit 0
fi
if ! command -v wlr-randr >/dev/null 2>&1; then
    echo "wlr-randr not found; skipping kitty startup test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-kitty.XXXXXX")
tpid=
kpid=
cleanup() {
    [ -n "${kpid:-}" ] && kill "$kpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${kpid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
terminal = kitty
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
unset DISPLAY XMODIFIERS || true

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

name=$(wlr-randr | sed -n '1s/ .*//p')
if [ -z "$name" ]; then
    echo "could not discover the output name" >&2
    wlr-randr >&2
    exit 1
fi
wlr-randr --output "$name" --scale 1.5
i=0
until wlr-randr | grep -q 'Scale: 1.500000'; do
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
        echo "output scale did not change" >&2
        exit 1
    fi
    sleep 0.1
done

"$bin/tessa-ctl" spawn "sh -c 'echo \$\$ > $runtime/kitty.pid; exec env WAYLAND_DEBUG=1 kitty --class=tessa-kitty-test -T KittyStartup'"

i=0
while [ ! -s "$runtime/kitty.pid" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "kitty wrapper did not start" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
kpid=$(cat "$runtime/kitty.pid")

i=0
while ! "$bin/tessa-ctl" state 2>/dev/null | awk -F '\t' '$1 == "WIN" && $7 == "tessa-kitty-test" { found=1 } END { exit found ? 0 : 1 }'; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "kitty did not map" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

sleep 2
if ! kill -0 "$kpid" 2>/dev/null; then
    echo "kitty exited after mapping" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
if ! "$bin/tessa-ctl" state 2>/dev/null | awk -F '\t' '$1 == "WIN" && $7 == "tessa-kitty-test" { found=1 } END { exit found ? 0 : 1 }'; then
    echo "kitty window disappeared" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

if ! grep -Eq 'wp_fractional_scale_v1#[0-9]+\.preferred_scale\(180\)' "$runtime/tessa.log"; then
    echo "kitty did not receive the initial 1.5x preferred scale" >&2
    grep -E 'preferred_scale|fractional' "$runtime/tessa.log" >&2 || true
    exit 1
fi

"$bin/tessa-ctl" quit >/dev/null 2>&1 || true
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
cleanup
echo "kitty startup/fractional test passed"
