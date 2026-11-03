#!/bin/sh
# Conformance test for the stable extension API v1 surface.
#   sh tests/extension-api.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping extension API test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-extension-api.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM
mkdir -p "$runtime"
chmod 700 "$runtime"

cat >"$runtime/probe.py" <<'PY'
import os, socket, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(os.environ["TESSA_IPC"])
s.sendall(("HELLO 1 " + os.environ["TESSA_EXTENSION_TOKEN"] + "\n").encode())
with open(os.environ["TESSA_TEST_TOKEN"], "w") as out:
    out.write(os.environ["TESSA_EXTENSION_TOKEN"])
time.sleep(60)
PY

cat >"$runtime/order.py" <<'PY'
import os, socket, sys, time
with open(os.environ["TESSA_TEST_ORDER"], "a") as out:
    out.write(sys.argv[1] + "\n")
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(os.environ["TESSA_IPC"])
s.sendall(("HELLO 1 " + os.environ["TESSA_EXTENSION_TOKEN"] + "\n").encode())
time.sleep(60)
PY

cat >"$runtime/config" <<EOF
panel = false
xwayland = false
animations = false
extension_ready_timeout = 1000
extension = id=probe; command=python3 $runtime/probe.py; permissions=read,status
extension = id=silent; command=sleep 30; permissions=read
extension = id=first; command=python3 $runtime/order.py first; after=second; permissions=read
extension = id=second; command=python3 $runtime/order.py second; permissions=read
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export TESSA_TEST_TOKEN="$runtime/token"
export TESSA_TEST_ORDER="$runtime/order"
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
    [ "$i" -lt 100 ] || { echo "no socket" >&2; cat "$runtime/tessa.log" >&2; exit 1; }
    sleep 0.1
done

wait_ext() {
    id=$1
    state=$2
    i=0
    while [ "$i" -lt 100 ]; do
        if tessa-ctl state 2>/dev/null | grep -q "^EXT $id $state "; then return 0; fi
        i=$((i + 1)); sleep 0.1
    done
    echo "extension $id did not reach $state" >&2
    tessa-ctl state >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_ext probe ready
wait_ext first ready
wait_ext second ready
i=0
while [ ! -s "$runtime/token" ]; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || { echo "probe did not publish a token" >&2; exit 1; }
    sleep 0.1
done
second_line=$(grep -n "extension 'second' started" "$runtime/tessa.log" | head -1 | cut -d: -f1)
first_line=$(grep -n "extension 'first' started" "$runtime/tessa.log" | head -1 | cut -d: -f1)
if [ -z "$second_line" ] || [ -z "$first_line" ] || [ "$second_line" -ge "$first_line" ]; then
    echo "after= ordering was not honored (second=$second_line first=$first_line)" >&2
    grep "extension '" "$runtime/tessa.log" >&2
    exit 1
fi
echo "handshake and after ordering: ok"

python3 - "$TESSA_IPC" "$runtime/token" <<'PY'
import os, select, socket, sys, time

sock_path, token_path = sys.argv[1], sys.argv[2]
token = open(token_path).read().strip()

def connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(sock_path)
    return s, s.makefile("rwb", buffering=0)

def read_line(f):
    return f.readline().decode(errors="replace")

def handshake(s, f, version, tok):
    f.write((f"HELLO {version} {tok}\n").encode())
    lines = []
    while True:
        line = read_line(f)
        if not line:
            return lines
        lines.append(line.rstrip("\n"))
        if line.startswith("CAPABILITIES") or line.startswith("ERR"):
            if line.startswith("CAPABILITIES"):
                old_timeout = s.gettimeout()
                s.settimeout(0.5)
                try:
                    extra = read_line(f)
                    if extra:
                        lines.append(extra.rstrip("\n"))
                except socket.timeout:
                    pass
                finally:
                    s.settimeout(old_timeout)
            return lines

def expect_forbidden(f, command):
    f.write((command + "\n").encode())
    line = read_line(f)
    if not line.startswith("ERR\tforbidden\t"):
        raise SystemExit(f"{command!r} was not denied: {line!r}")

# Normal handshake and permission matrix.
s, f = connect()
lines = handshake(s, f, "1", token)
if not any(l.startswith("VERSION\t1") for l in lines):
    raise SystemExit(f"missing VERSION: {lines!r}")
if not any(l.startswith("EXTENSION\tprobe\tread,status") for l in lines):
    raise SystemExit(f"missing EXTENSION identity: {lines!r}")
f.write(b"CMD state\n")
line = read_line(f)
if not line.startswith("STATE"):
    raise SystemExit(f"read-scoped state failed: {line!r}")
while read_line(f).strip() != "END":
    pass
expect_forbidden(f, "CMD workspace 2")
expect_forbidden(f, "CMD perf-reset")
f.write(b"CMD nope\n")
if not read_line(f).startswith("ERR\tunknown-command\tnope"):
    raise SystemExit("unknown command did not return ERR unknown-command")

# Malformed HELLO with a token must never fall back to full access.
for bad in ("nope", "0", "1" + token):
    s2, f2 = connect()
    lines = handshake(s2, f2, bad, token)
    if not any(l.startswith("ERR\tinvalid-version") for l in lines):
        raise SystemExit(f"malformed HELLO {bad!r} was accepted: {lines!r}")
    expect_forbidden(f2, "CMD state")
    s2.close()

# Tab-separated HELLO is accepted and authenticated.
s2, f2 = connect()
f2.write(("HELLO\t1\t" + token + "\n").encode())
lines = []
while True:
    line = read_line(f2)
    lines.append(line.rstrip("\n"))
    if line.startswith("ERR"):
        break
    if line.startswith("CAPABILITIES"):
        s2.settimeout(0.5)
        try:
            extra = read_line(f2)
            if extra:
                lines.append(extra.rstrip("\n"))
        except socket.timeout:
            pass
        break
if not any(l.startswith("EXTENSION\tprobe") for l in lines):
    raise SystemExit(f"tab HELLO was not authenticated: {lines!r}")
s2.close()

# Subscriptions made before authentication are cleared by a token HELLO.
s2, f2 = connect()
f2.write(b"CMD subscribe all\n")
if not read_line(f2).startswith("STATE"):
    raise SystemExit("unscoped subscribe did not return a snapshot")
while read_line(f2).strip() != "END":
    pass
lines = handshake(s2, f2, "1", token)
os.system("tessa-ctl workspace 3 >/dev/null 2>&1")
ready, _, _ = select.select([s2], [], [], 0.6)
if ready:
    raise SystemExit("pre-auth subscription leaked after authentication")
f2.write(b"CMD subscribe state\n")
if not read_line(f2).startswith("STATE"):
    raise SystemExit("read-scoped state subscription failed")
while read_line(f2).strip() != "END":
    pass
expect_forbidden(f2, "CMD subscribe events")

# An authenticated connection is revoked when the extension is disabled.
s3, f3 = connect()
handshake(s3, f3, "1", token)
os.system("tessa-ctl extension-enable probe off >/dev/null 2>&1")
deadline = time.time() + 5
while time.time() < deadline:
    state = os.popen("tessa-ctl state 2>/dev/null").read()
    if "\nEXT probe disabled " in state:
        break
    time.sleep(0.1)
else:
    raise SystemExit("probe did not become disabled")
expect_forbidden(f3, "CMD status probe hacked")

# Old tokens are invalid while stopped and after the restarted process rotates
# them.
s4, f4 = connect()
lines = handshake(s4, f4, "1", token)
if not any(l.startswith("ERR\tunauthorized") for l in lines):
    raise SystemExit("old token was accepted while disabled")
s4.close()

os.system("tessa-ctl extension-enable probe on >/dev/null 2>&1")
deadline = time.time() + 5
new_token = token
while time.time() < deadline:
    state = os.popen("tessa-ctl state 2>/dev/null").read()
    current = open(token_path).read().strip()
    if "\nEXT probe ready " in state and current and current != token:
        new_token = current
        break
    time.sleep(0.1)
else:
    raise SystemExit("probe did not restart with a rotated token")
if new_token == token:
    raise SystemExit("token was not rotated on restart")

s5, f5 = connect()
lines = handshake(s5, f5, "1", token)
if not any(l.startswith("ERR\tunauthorized") for l in lines):
    raise SystemExit("old token was accepted after restart")
s5.close()

s6, f6 = connect()
lines = handshake(s6, f6, "1", new_token)
if not any(l.startswith("EXTENSION\tprobe") for l in lines):
    raise SystemExit(f"rotated token was rejected: {lines!r}")
s6.close()

s7, f7 = connect()
f7.write(b"CMD extension-enable probe maybe\n")
if not read_line(f7).startswith("ERR\tbad-argument\textension-enable"):
    raise SystemExit("invalid extension-enable argument was accepted")
s7.close()
print("auth, scopes, revocation, and token rotation: ok")
PY

# A process that starts but never authenticates is killed and reported.
i=0
while [ "$i" -lt 80 ]; do
    if tessa-ctl state 2>/dev/null | grep -q "^EXT silent failed "; then break; fi
    i=$((i + 1)); sleep 0.1
done
[ "$i" -lt 80 ] || { echo "silent extension did not time out" >&2; tessa-ctl state >&2; exit 1; }
tessa-ctl extensions --json >"$runtime/ext.json"
python3 - "$runtime/ext.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
by_id = {e["id"]: e for e in data}
silent = by_id["silent"]
assert silent["state"] == "failed", silent
assert silent["last_error"] == "ready timeout", silent
assert silent["failures"] >= 1, silent
assert silent["next_restart_ms"] >= 0, silent
PY
tessa-ctl extension-enable silent off >/dev/null
echo "ready timeout diagnostics: ok"

# Duplicate dependencies are rejected before the compositor starts.
cat >"$runtime/dup" <<EOF
extension = id=a; command=true; requires=b,b
extension = id=b; command=true
EOF
"$bin/tessa" --check-config "$runtime/dup" >"$runtime/dup.log" 2>&1 && {
    echo "duplicate extension dependency was accepted" >&2
    exit 1
}
grep -q "invalid extension requires" "$runtime/dup.log"
echo "dependency validation: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "extension API test passed"
