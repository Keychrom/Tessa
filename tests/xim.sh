#!/bin/sh
# Verify XIM environment and XIM server startup under XWayland.
# Requires xwayland-satellite, fcitx5, xprop, and dbus-run-session.
#   sh tests/xim.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

satellite=$(command -v xwayland-satellite 2>/dev/null || true)
if [ -z "$satellite" ] && [ -x "$HOME/.local/bin/xwayland-satellite" ]; then
    satellite=$HOME/.local/bin/xwayland-satellite
fi
if [ -z "$satellite" ]; then
    echo "xwayland-satellite not found; skipping XIM test"
    exit 0
fi
if ! command -v fcitx5 >/dev/null 2>&1 || ! command -v xprop >/dev/null 2>&1; then
    echo "fcitx5 or xprop not found; skipping XIM test"
    exit 0
fi
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session not found; skipping XIM test"
        exit 0
    fi
    exec dbus-run-session -- sh "$0" "$@"
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-xim.XXXXXX")
tpid=
before_pids=
cleanup() {
    if [ -n "${before_pids:-}" ]; then
        for p in $(pgrep -x fcitx5 2>/dev/null || true); do
            case " $before_pids " in
                *" $p "*) ;;
                *) kill "$p" 2>/dev/null || true ;;
            esac
        done
    fi
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

before_pids=$(pgrep -x fcitx5 2>/dev/null || true)
mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = false
xwayland = true
xim = true
xim_server = fcitx
xim_start = fcitx5 -d
startup = sh -c 'printf %s "\$XMODIFIERS" > $runtime/xim-env'
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export TESSA_XWAYLAND_BIN="$satellite"
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

disp=
i=0
while [ -z "$disp" ]; do
    disp=$(sed -n "s/.*starting XWayland on \(:[0-9][0-9]*\).*/\1/p" "$runtime/tessa.log" | tail -1)
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "XWayland did not start" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

i=0
while [ ! -S "/tmp/.X11-unix/X${disp#:}" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "X socket did not appear for $disp" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

i=0
while [ ! -f "$runtime/xim-env" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "startup command did not run" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
grep -q "@im=fcitx" "$runtime/xim-env"
grep -q "xim: XMODIFIERS=@im=fcitx" "$runtime/tessa.log"
echo "XIM environment: ok"

grep -q "xim: starting 'fcitx5 -d'" "$runtime/tessa.log" || {
    echo "XIM server startup was not triggered" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

i=0
while :; do
    servers=$(DISPLAY=$disp xprop -root XIM_SERVERS 2>/dev/null || true)
    case "$servers" in
        *@server=fcitx*) break ;;
    esac
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "XIM_SERVERS did not list fcitx" >&2
        echo "$servers" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done
echo "XIM server registration: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=

trap - EXIT INT TERM
cleanup
echo "XIM test passed"
