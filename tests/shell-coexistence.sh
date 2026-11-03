#!/bin/sh
# Real external-shell coexistence checks for Quickshell and Noctalia.
# Each shell is optional; the test skips a missing binary.
#
#   sh tests/shell-coexistence.sh
#
# For an uninstalled Noctalia package tree:
#   NOCTALIA_BIN=/path/to/noctalia \
#   NOCTALIA_LIBDIR=/path/to/deps/usr/lib \
#   NOCTALIA_DATA_DIR=/path/to/pkg/usr/share \
#   sh tests/shell-coexistence.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

qs_bin=$(command -v qs 2>/dev/null || true)
noctalia_bin=${NOCTALIA_BIN:-$(command -v noctalia 2>/dev/null || true)}
if [ -z "$qs_bin" ] && [ -z "$noctalia_bin" ]; then
    echo "qs and noctalia not found; skipping shell coexistence test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-shells.XXXXXX")
tpid=
qpid=
npid=
cleanup() {
    [ -n "${qpid:-}" ] && kill "$qpid" 2>/dev/null || true
    [ -n "${npid:-}" ] && kill -- -"$npid" 2>/dev/null || kill "$npid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${qpid:-0}" 2>/dev/null || true
    wait "${npid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM
mkdir -p "$runtime"
chmod 700 "$runtime"

cat >"$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
EOF

cat >"$runtime/shell.qml" <<'QML'
import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    PanelWindow {
        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 30
        color: "#202020"
        Text {
            anchors.centerIn: parent
            text: "Quickshell on Tessa"
            color: "#ffffff"
        }
    }
}
QML

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"

"$bin/tessa" >"$runtime/tessa.log" 2>&1 &
tpid=$!
i=0
while [ ! -S "$runtime/tessa.sock" ]; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || { cat "$runtime/tessa.log" >&2; exit 1; }
    sleep 0.1
done

wait_layer() {
    pattern=$1
    i=0
    while [ "$i" -lt 120 ]; do
        if "$bin/tessa-ctl" state 2>/dev/null | grep -q "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "layer did not appear: $pattern" >&2
    "$bin/tessa-ctl" state >&2 2>/dev/null || true
    cat "$runtime/shell.log" 2>/dev/null >&2 || true
    return 1
}

if [ -n "$qs_bin" ]; then
    "$qs_bin" -p "$runtime/shell.qml" >"$runtime/shell.log" 2>&1 &
    qpid=$!
    wait_layer "^LAYER	quickshell	"
    "$bin/tessa-ctl" shell | grep -qF "EXTERNAL	quickshell	HEADLESS-1	2" || {
        echo "shell status did not report Quickshell" >&2
        "$bin/tessa-ctl" shell >&2
        exit 1
    }
    kill "$qpid" 2>/dev/null || true
    wait "$qpid" 2>/dev/null || true
    qpid=
    echo "quickshell coexistence: ok"
fi

if [ -n "$noctalia_bin" ]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session not found; skipping Noctalia"
    else
        mkdir -p "$runtime/home" "$runtime/xdg-config"
        export HOME="$runtime/home"
        export XDG_CONFIG_HOME="$runtime/xdg-config"
        export XDG_DATA_DIRS="${NOCTALIA_DATA_DIR:-/usr/share}:/usr/share"
        if [ -n "${NOCTALIA_LIBDIR:-}" ]; then
            export LD_LIBRARY_PATH="$NOCTALIA_LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        fi
        export XDG_CURRENT_DESKTOP=Tessa
        setsid dbus-run-session -- "$noctalia_bin" >"$runtime/shell.log" 2>&1 &
        npid=$!
        wait_layer "^LAYER	noctalia-bar"
        "$bin/tessa-ctl" shell | grep -qE "EXTERNAL	noctalia-bar[^	]*	HEADLESS-1	2" || {
            echo "shell status did not report Noctalia" >&2
            "$bin/tessa-ctl" shell >&2
            exit 1
        }
        kill -- -"$npid" 2>/dev/null || kill "$npid" 2>/dev/null || true
        wait "$npid" 2>/dev/null || true
        npid=
        echo "noctalia coexistence: ok"
    fi
fi

"$bin/tessa-ctl" quit >/dev/null 2>&1 || true
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "shell coexistence test passed"
