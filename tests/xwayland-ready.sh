#!/bin/sh
# DISPLAY must appear only after the X socket is accepting connections.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

display_num=57
socket=/tmp/.X11-unix/X$display_num
lock=/tmp/.X$display_num-lock
if [ -e "$socket" ] || [ -e "$lock" ]; then
    echo "X display :$display_num is already in use; skipping" >&2
    exit 0
fi
if [ ! -d /tmp/.X11-unix ] || [ ! -w /tmp/.X11-unix ]; then
    echo "/tmp/.X11-unix is not writable; skipping" >&2
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-xwayland.XXXXXX")
tpid=
spid=
cleanup() {
    if [ -z "${spid:-}" ] && [ -s "$runtime/satellite.pid" ]; then
        spid=$(cat "$runtime/satellite.pid")
    fi
    [ -n "${spid:-}" ] && kill "$spid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${spid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -f "$socket" "$lock"
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

cat > "$runtime/fake-xwayland-satellite" <<EOF
#!/bin/sh
echo \$\$ > "$runtime/satellite.pid"
sleep 1
: > "$socket"
while :; do sleep 1; done
EOF
chmod 755 "$runtime/fake-xwayland-satellite"

cat > "$runtime/config" <<EOF
panel = false
xwayland = true
xwayland_display = :$display_num
xim = true
xim_server = fcitx
animations = false
startup = sh -c 'printf "%s|%s\n" "\$DISPLAY" "\$XMODIFIERS" > $runtime/startup.env'
EOF

cat > "$runtime/probe.c" <<'EOF'
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    sigset_t set;
    if (sigprocmask(SIG_SETMASK, NULL, &set) != 0) return 1;
    for (int sig = 1; sig < 32; sig++) {
        if (sigismember(&set, sig) == 1) printf("blocked=%d\n", sig);
    }
    const char *display = getenv("DISPLAY");
    const char *xim = getenv("XMODIFIERS");
    printf("DISPLAY=%s\n", display ? display : "");
    printf("XMODIFIERS=%s\n", xim ? xim : "");
    return 0;
}
EOF
cc -O2 -o "$runtime/probe" "$runtime/probe.c"

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export TESSA_XWAYLAND_BIN="$runtime/fake-xwayland-satellite"
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

# The fake X server waits one second, so a child started now must not see a
# DISPLAY pointing at a socket that does not exist yet.
"$bin/tessa-ctl" spawn "sh -c 'exec $runtime/probe > $runtime/early.out'"
i=0
while [ ! -s "$runtime/early.out" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "early probe did not run" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.05
done
if ! grep -qx 'DISPLAY=' "$runtime/early.out"; then
    echo "DISPLAY was published before the X socket existed" >&2
    cat "$runtime/early.out" >&2
    exit 1
fi
if [ -e "$runtime/startup.env" ]; then
    echo "startup hooks ran before the X socket existed" >&2
    cat "$runtime/startup.env" >&2
    exit 1
fi

i=0
while ! grep -q 'xwayland: connected on :57' "$runtime/tessa.log"; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "XWayland never became ready" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

"$bin/tessa-ctl" spawn "sh -c 'exec $runtime/probe > $runtime/ready.out'"
i=0
while [ ! -s "$runtime/ready.out" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "ready probe did not run" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.05
done
if grep -q '^blocked=' "$runtime/ready.out"; then
    echo "child inherited a blocked signal mask" >&2
    cat "$runtime/ready.out" >&2
    exit 1
fi
if ! grep -qx 'DISPLAY=:57' "$runtime/ready.out"; then
    echo "DISPLAY was not published after the socket appeared" >&2
    cat "$runtime/ready.out" >&2
    exit 1
fi
if ! grep -qx 'XMODIFIERS=@im=fcitx' "$runtime/ready.out"; then
    echo "XMODIFIERS was not published with a ready X display" >&2
    cat "$runtime/ready.out" >&2
    exit 1
fi
i=0
while [ ! -s "$runtime/startup.env" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "startup hooks did not run after XWayland became ready" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.05
done
if ! grep -qx ':57|@im=fcitx' "$runtime/startup.env"; then
    echo "startup command did not receive the X environment" >&2
    cat "$runtime/startup.env" >&2
    exit 1
fi

"$bin/tessa-ctl" quit >/dev/null 2>&1 || true
wait "$tpid" 2>/dev/null || true
tpid=

trap - EXIT INT TERM
cleanup
echo "XWayland readiness test passed"
