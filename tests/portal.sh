#!/bin/sh
# End-to-end ScreenCast through xdg-desktop-portal, xdg-desktop-portal-wlr,
# and PipeWire. Set TESSA_PORTAL_ROOT to a prefix such as an extracted Debian
# package root when the portal services are not installed system-wide.
# Requires dbus-run-session, python3 with PyGObject, and the portal binaries.
#   sh tests/portal.sh
set -eu

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session not found; skipping portal test"
        exit 0
    fi
    exec dbus-run-session -- sh "$0" "$@"
fi

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin
portal_root=${TESSA_PORTAL_ROOT:-}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping portal test"
    exit 0
fi
if ! python3 -c 'import gi; gi.require_version("Gio", "2.0")' >/dev/null 2>&1; then
    echo "PyGObject not found; skipping portal test"
    exit 0
fi

find_program() {
    name=$1
    if [ -n "$portal_root" ]; then
        for path in "$portal_root/usr/bin/$name" "$portal_root/usr/libexec/$name"; do
            [ -x "$path" ] && { printf '%s\n' "$path"; return 0; }
        done
        return 1
    fi
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    for path in "/usr/libexec/$name" "/usr/lib/$name"; do
        [ -x "$path" ] && { printf '%s\n' "$path"; return 0; }
    done
    return 1
}

portal_bin=$(find_program xdg-desktop-portal) || {
    echo "xdg-desktop-portal not found; skipping portal test"
    exit 0
}
wlr_bin=$(find_program xdg-desktop-portal-wlr) || {
    echo "xdg-desktop-portal-wlr not found; skipping portal test"
    exit 0
}
pipewire_bin=$(find_program pipewire) || {
    echo "pipewire not found; skipping portal test"
    exit 0
}

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-portal.XXXXXX")
tpid=
ppid=
dpid=
wpid=
cleanup() {
    [ -n "${wpid:-}" ] && kill "$wpid" 2>/dev/null || true
    [ -n "${dpid:-}" ] && kill "$dpid" 2>/dev/null || true
    [ -n "${ppid:-}" ] && kill "$ppid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$wpid" 2>/dev/null || true
    wait "$dpid" 2>/dev/null || true
    wait "$ppid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/share/xdg-desktop-portal/portals" \
    "$runtime/xdgconfig/xdg-desktop-portal-wlr"
chmod 700 "$runtime"
printf 'panel = false\nxwayland = false\n' >"$runtime/config"
cat >"$runtime/share/xdg-desktop-portal/portals/tessa.portal" <<'EOF'
[portal]
DBusName=org.freedesktop.impl.portal.desktop.wlr
Interfaces=org.freedesktop.impl.portal.Screenshot;org.freedesktop.impl.portal.ScreenCast;
UseIn=Tessa;
EOF
cat >"$runtime/xdgconfig/xdg-desktop-portal-wlr/config" <<'EOF'
[screencast]
chooser_type=none
output_name=HEADLESS-1
max_fps=30
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Tessa
export XDG_CONFIG_HOME="$runtime/xdgconfig"
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"
export TESSA_DEBUG=1
export TESSA_PANEL_DEBUG=1

if [ -n "$portal_root" ]; then
    export XDG_DATA_DIRS="$runtime/share:$portal_root/usr/share:/usr/local/share:/usr/share"
    export PIPEWIRE_MODULE_DIR="$portal_root/usr/lib/x86_64-linux-gnu/pipewire-0.3"
    export PIPEWIRE_CONFIG_DIR="$portal_root/usr/share/pipewire"
else
    export XDG_DATA_DIRS="$runtime/share:/usr/local/share:/usr/share"
fi
export PIPEWIRE_RUNTIME_DIR="$runtime"

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

"$pipewire_bin" >"$runtime/pipewire.log" 2>&1 &
ppid=$!
i=0
while [ ! -S "$runtime/pipewire-0" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "PipeWire did not create its socket" >&2
        cat "$runtime/pipewire.log" >&2
        exit 1
    fi
    sleep 0.1
done

"$portal_bin" >"$runtime/portal.log" 2>&1 &
dpid=$!
"$wlr_bin" -l DEBUG >"$runtime/xdpw.log" 2>&1 &
wpid=$!

i=0
while :; do
    names=$(gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.ListNames 2>/dev/null || true)
    case "$names" in
    *org.freedesktop.portal.Desktop*org.freedesktop.impl.portal.desktop.wlr*) break ;;
    esac
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "portal services did not appear" >&2
        cat "$runtime/portal.log" >&2
        cat "$runtime/xdpw.log" >&2
        exit 1
    fi
    sleep 0.1
done

if grep -q "failed to initialize screencast" "$runtime/xdpw.log"; then
    echo "xdg-desktop-portal-wlr failed to initialize" >&2
    cat "$runtime/xdpw.log" >&2
    exit 1
fi

if ! timeout 30 python3 "$root/tests/portal-client.py" >"$runtime/client.log" 2>&1; then
    echo "ScreenCast client failed" >&2
    cat "$runtime/client.log" >&2
    cat "$runtime/xdpw.log" >&2
    cat "$runtime/portal.log" >&2
    exit 1
fi
if ! grep -q "portal screencast ok" "$runtime/client.log"; then
    echo "ScreenCast did not complete" >&2
    cat "$runtime/client.log" >&2
    exit 1
fi
grep -q "remote fd" "$runtime/client.log"
echo "ScreenCast portal and PipeWire remote: ok"

kill "$wpid" "$dpid" "$ppid" 2>/dev/null || true
wait "$wpid" 2>/dev/null || true
wait "$dpid" 2>/dev/null || true
wait "$ppid" 2>/dev/null || true
wpid=
dpid=
ppid=

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log"; then
    echo "compositor or panel did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log" >&2
    exit 1
fi
pkill -x tessa-panel 2>/dev/null || true

trap - EXIT INT TERM
rm -rf "$runtime"
echo "portal test passed"
