#!/bin/sh
# Verify optional line-protocol HELLO/VERSION negotiation and capability list.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping IPC version test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-ipc-version.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = false
xwayland = false
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

tessa-ctl hello >"$runtime/hello.out"
grep -qF "VERSION	1" "$runtime/hello.out"
grep -qF "CAPABILITIES	state,config,events,subscriptions,config-compare,perf,special,groups" "$runtime/hello.out"
echo "HELLO negotiation: ok"

python3 - "$TESSA_IPC" <<'PY'
import os
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(sys.argv[1])
f = sock.makefile("rb")


def handshake(version):
    sock.sendall(f"HELLO {version}\n".encode())
    first = f.readline().decode().rstrip("\n")
    second = f.readline().decode().rstrip("\n")
    return first, second


first, second = handshake(99)
if first != "VERSION\t1":
    raise SystemExit(f"bad negotiated version: {first!r}")
if not second.startswith("CAPABILITIES\t"):
    raise SystemExit(f"missing capabilities: {second!r}")

sock.sendall(b"CMD state\n")
saw_state = False
while True:
    line = f.readline()
    if not line:
        raise SystemExit("connection closed before state reply")
    text = line.decode().rstrip("\n")
    if text == "STATE":
        saw_state = True
    if text == "END":
        break
if not saw_state:
    raise SystemExit("state reply missing")

sock.sendall(b"HELLO nope\n")
err = f.readline().decode().rstrip("\n")
if err != "ERR\tinvalid-version":
    raise SystemExit(f"bad invalid-version reply: {err!r}")
sock.sendall(b"CMD state\n")
while True:
    line = f.readline()
    if not line:
        raise SystemExit("connection closed after invalid HELLO")
    if line == b"END\n":
        break
print("version negotiation + legacy commands: ok")
PY

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
echo "IPC version test passed"
