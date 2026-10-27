#!/bin/sh
# Verify JSON-RPC request ids, capability negotiation, and JSON event streams.
# Requires python3. Run from the repository root after building:
#   sh tests/json-rpc.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping JSON-RPC test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-json-rpc.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
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

tessa-ctl rpc '{"jsonrpc":"2.0","id":1,"method":"hello"}' >"$runtime/hello.out"
grep -q '"id":1' "$runtime/hello.out"
grep -q '"protocol":"tessa-jsonrpc","version":1' "$runtime/hello.out"
grep -q '"capabilities":\["state","config","events","subscriptions","request-ids"\]' "$runtime/hello.out"
echo "capability negotiation: ok"

tessa-ctl rpc '{"jsonrpc":"2.0","id":7,"method":"state"}' >"$runtime/state.out"
grep -q '"id":7' "$runtime/state.out"
grep -q '"result":{"schema":1' "$runtime/state.out"
tessa-ctl rpc '{"jsonrpc":"2.0","id":"cfg","method":"config"}' >"$runtime/config.out"
grep -q '"id":"cfg"' "$runtime/config.out"
grep -q '"result":{"schema":1' "$runtime/config.out"
echo "request ids and read methods: ok"

tessa-ctl rpc '{"jsonrpc":"2.0","id":3,"method":"missing"}' >"$runtime/error.out"
grep -q '"id":3' "$runtime/error.out"
grep -q '"code":-32601' "$runtime/error.out"
tessa-ctl rpc '{"jsonrpc":"2.0","id":4,"method":' >"$runtime/parse.out"
grep -q '"id":null' "$runtime/parse.out"
grep -q '"code":-32700' "$runtime/parse.out"
echo "JSON-RPC errors: ok"

cat > "$runtime/subscribe.py" <<'PY'
import json
import os
import socket
import sys

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(os.environ["TESSA_IPC"])
s.sendall(b'{"jsonrpc":"2.0","id":"sub-1","method":"subscribe"}\n')
f = s.makefile("rb")
ack = json.loads(f.readline())
if ack.get("id") != "sub-1" or not ack.get("result", {}).get("subscribed"):
    print("bad subscribe ack", ack, file=sys.stderr)
    sys.exit(1)
line = f.readline()
if not line:
    print("no event received", file=sys.stderr)
    sys.exit(1)
event = json.loads(line)
params = event.get("params", {})
if event.get("method") != "event":
    print("bad event envelope", event, file=sys.stderr)
    sys.exit(1)
if params.get("name") != "workspace-change" or params.get("ws") != 2:
    print("bad event payload", event, file=sys.stderr)
    sys.exit(1)
if params.get("subscription") != "sub-1":
    print("event missing subscription id", event, file=sys.stderr)
    sys.exit(1)
print("json event subscription: ok")
PY

python3 "$runtime/subscribe.py" >"$runtime/subscribe.out" 2>"$runtime/subscribe.err" &
py_pid=$!
sleep 0.3
tessa-ctl workspace 2
i=0
while kill -0 "$py_pid" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
        echo "JSON event subscriber did not finish" >&2
        kill "$py_pid" 2>/dev/null || true
        cat "$runtime/subscribe.err" >&2
        exit 1
    fi
    sleep 0.1
done
wait "$py_pid"
cat "$runtime/subscribe.out"
echo "JSON event stream: ok"

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
echo "JSON-RPC test passed"
