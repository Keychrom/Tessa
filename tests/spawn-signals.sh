#!/bin/sh
# Verify that children start without the compositor's blocked signal mask and
# without a fabricated X11 environment when XWayland is disabled.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-spawn-signals.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
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

cat > "$runtime/probe.c" <<'EOF'
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    static const int watched[] = {
        SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGPIPE, SIGCHLD, SIGUSR1, SIGUSR2,
    };
    sigset_t set;
    if (sigprocmask(SIG_SETMASK, NULL, &set) != 0) return 1;
    for (int sig = 1; sig < 32; sig++) {
        if (sigismember(&set, sig) == 1) {
            printf("blocked=%d\n", sig);
        }
    }
    for (size_t i = 0; i < sizeof(watched) / sizeof(watched[0]); i++) {
        struct sigaction sa;
        if (sigaction(watched[i], NULL, &sa) == 0 && sa.sa_handler == SIG_IGN) {
            printf("ignored=%d\n", watched[i]);
        }
    }
    const char *display = getenv("DISPLAY");
    const char *xim = getenv("XMODIFIERS");
    printf("DISPLAY=%s\n", display ? display : "");
    printf("XMODIFIERS=%s\n", xim ? xim : "");
    return 0;
}
EOF
cc -O2 -o "$runtime/probe" "$runtime/probe.c"

# IPC spawn goes through /bin/sh, exactly like bindings and the launcher.
"$bin/tessa-ctl" spawn "sh -c 'exec $runtime/probe > $runtime/probe.out'"

i=0
while [ ! -s "$runtime/probe.out" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "spawned process did not write its signal state" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

if grep -q '^blocked=' "$runtime/probe.out"; then
    echo "child inherited a blocked signal mask" >&2
    cat "$runtime/probe.out" >&2
    exit 1
fi
if grep -q '^ignored=' "$runtime/probe.out"; then
    echo "child inherited an ignored signal disposition" >&2
    cat "$runtime/probe.out" >&2
    exit 1
fi
if ! grep -qx 'DISPLAY=' "$runtime/probe.out"; then
    echo "DISPLAY was fabricated without XWayland" >&2
    cat "$runtime/probe.out" >&2
    exit 1
fi
if ! grep -qx 'XMODIFIERS=' "$runtime/probe.out"; then
    echo "XMODIFIERS was set without XWayland" >&2
    cat "$runtime/probe.out" >&2
    exit 1
fi

"$bin/tessa-ctl" quit >/dev/null 2>&1 || true
wait "$tpid" 2>/dev/null || true
tpid=

trap - EXIT INT TERM
rm -rf "$runtime"
echo "spawn signal/environment test passed"
