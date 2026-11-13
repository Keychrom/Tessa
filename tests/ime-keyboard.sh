#!/bin/sh
# Regression test for the Fcitx5 keyboard-grab path.
#
# Fcitx5 keeps a keyboard grab while it runs and creates/destroys a virtual
# keyboard as it activates. Re-entering keyboard focus for those virtual
# keyboards made text-input clients disable/enable in a loop; the compositor
# then spent its time re-grabbing the keyboard and clients such as Firefox
# lost input. This test also checks that direct typing reaches a client while
# the input method is deactivated.
#
# Requires foot, wtype, fcitx5, fcitx5-remote and dbus-daemon.
#   sh tests/ime-keyboard.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

for tool in foot wtype fcitx5 fcitx5-remote dbus-daemon; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping IME keyboard test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-ime.XXXXXX")
tpid=
dbus_pid=
fpid=
cleanup() {
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        fcitx5-remote -e >/dev/null 2>&1 || true
    fi
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    [ -n "${dbus_pid:-}" ] && kill "$dbus_pid" 2>/dev/null || true
    [ -n "${fpid:-}" ] && kill "$fpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/xdg/fcitx5"
chmod 700 "$runtime"
cat > "$runtime/xdg/fcitx5/profile" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=mozc

[Groups/0/Items/0]
Name=keyboard-us

[Groups/0/Items/1]
Name=mozc

[GroupOrder]
0=Default
EOF
cat > "$runtime/xdg/fcitx5/config" <<'EOF'
[Behavior]
ActiveByDefault=True
EOF
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
xim = false
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_CONFIG_HOME="$runtime/xdg"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY=wayland-0
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1
export PATH="$bin:$PATH"
export TESSA_DEBUG=1
export XDG_CURRENT_DESKTOP=Tessa
export GTK_IM_MODULE=wayland
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx

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
    tail -80 "$runtime/tessa.log" >&2
    exit 1
}

dbus-daemon --session --fork --print-address=1 --print-pid=1 >"$runtime/dbus.info"
DBUS_SESSION_BUS_ADDRESS=$(sed -n 1p "$runtime/dbus.info")
dbus_pid=$(sed -n 2p "$runtime/dbus.info")
export DBUS_SESSION_BUS_ADDRESS

fcitx5 -d >"$runtime/fcitx.log" 2>&1 || true
wait_log "input method connected"

foot -T IMEKeyboard -e sh -c "read x; printf '%s' \"\$x\" > '$runtime/typed.txt'" \
    >"$runtime/foot.log" 2>&1 &
fpid=$!
sleep 2
wait_log "input method grabbed keyboard"

# Activate the input method so it creates its forwarding virtual keyboard.
# Older builds re-entered keyboard focus for that keyboard, which made the
# client disable and re-enable text input forever.
fcitx5-remote -o >/dev/null 2>&1 || true

# Let the IM settle, then make sure its virtual keyboard is not being
# destroyed and recreated continuously.
sleep 2
vk_count=$(grep -c "virtual keyboard added" "$runtime/tessa.log" || true)
enable_count=$(grep -c "text input enable" "$runtime/tessa.log" || true)
if [ "$vk_count" -gt 20 ] || [ "$enable_count" -gt 20 ]; then
    echo "input method focus loop: virtual keyboards=$vk_count enables=$enable_count" >&2
    tail -100 "$runtime/tessa.log" >&2
    exit 1
fi
echo "input method focus loop: ok ($vk_count virtual keyboards, $enable_count enables)"

fcitx5-remote -c >/dev/null 2>&1 || true
wtype "hello"
wtype -k Return

i=0
while [ "$i" -lt 100 ]; do
    if [ -f "$runtime/typed.txt" ] && [ "$(cat "$runtime/typed.txt")" = "hello" ]; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "typed text did not reach the client" >&2
    cat "$runtime/typed.txt" 2>/dev/null >&2 || true
    tail -100 "$runtime/tessa.log" >&2
    exit 1
fi
echo "direct typing through the IM grab: ok"

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
echo "IME keyboard test passed"
