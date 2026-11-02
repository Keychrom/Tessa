#!/bin/sh
# Verify panel_modules ownership and the supervisor restart on mask changes.
#   sh tests/panel-modules.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-panel-modules.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM
mkdir -p "$runtime"
chmod 700 "$runtime"

cat >"$runtime/config" <<EOF
panel = true
panel_modules = launcher,notifications
xwayland = false
animations = false
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export TESSA_PANEL_BIN="$bin/tessa-panel"
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
    [ "$i" -lt 100 ] || { cat "$runtime/tessa.log" >&2; exit 1; }
    sleep 0.1
done
wait_panel() {
    i=0
    while [ "$i" -lt 100 ]; do
        line=$(tessa-ctl state 2>/dev/null | awk -F '	' '$1 == "PANEL" { print; exit }')
        pid=$(printf '%s\n' "$line" | awk -F '	' '{ print $3 }')
        if [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null; then return 0; fi
        i=$((i + 1)); sleep 0.1
    done
    echo "panel did not start" >&2
    tessa-ctl state >&2
    exit 1
}

wait_panel
sleep 0.5
if tessa-ctl state | grep -q '^LAYER	tessa-bar'; then
    echo "bar was created while panel_modules excluded it" >&2
    exit 1
fi
if tessa-ctl state | grep -q '^LAYER	tessa-background'; then
    echo "background was created while panel_modules excluded it" >&2
    exit 1
fi
tessa-ctl state | grep -q '^PANEL	HEADLESS-1	[0-9]*	1	1$'
echo "launcher+notifications ownership: ok"

tessa-ctl panel calendar >/dev/null
sleep 0.4
if tessa-ctl state | grep -q '^LAYER	tessa-overlay'; then
    echo "popover opened while popovers were disabled" >&2
    exit 1
fi
tessa-ctl launcher >/dev/null
i=0
while [ "$i" -lt 100 ]; do
    tessa-ctl state | grep -q '^LAYER	tessa-overlay' && break
    i=$((i + 1)); sleep 0.1
done
tessa-ctl state | grep -q '^LAYER	tessa-overlay'
echo "launcher-only overlay: ok"

cat >"$runtime/config" <<EOF
panel = true
panel_modules = bar
xwayland = false
animations = false
EOF
tessa-ctl dispatch reload >/dev/null
sleep 1
tessa-ctl state | grep -q '^LAYER	tessa-bar'
if tessa-ctl state | grep -q '^LAYER	tessa-background'; then
    echo "background survived a bar-only module reload" >&2
    exit 1
fi
tessa-ctl state | grep -q '^PANEL	HEADLESS-1	[0-9]*	1	0$'
tessa-ctl panel calendar >/dev/null
sleep 0.3
if tessa-ctl state | grep -q '^LAYER	tessa-overlay'; then
    echo "popover opened after bar-only reload" >&2
    exit 1
fi
echo "module mask reload: ok"

cat >"$runtime/config" <<EOF
panel = true
panel_modules = popovers
xwayland = false
animations = false
EOF
tessa-ctl dispatch reload >/dev/null
sleep 1
tessa-ctl panel extensions >/dev/null
i=0
while [ "$i" -lt 100 ]; do
    tessa-ctl state | grep -q '^LAYER	tessa-overlay' && break
    i=$((i + 1)); sleep 0.1
done
tessa-ctl state | grep -q '^LAYER	tessa-overlay'
echo "extensions popover: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "panel modules test passed"
