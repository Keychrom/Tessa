#!/bin/sh
# Verify supervised extensions, dependency order, token scopes, and state.
#   sh tests/extensions.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping extensions test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-extensions.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM
mkdir -p "$runtime"
chmod 700 "$runtime"

cat >"$runtime/alpha.py" <<'PY'
import os, socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(os.environ["TESSA_IPC"])
f = s.makefile("rwb", buffering=0)
f.write(("HELLO 1 " + os.environ["TESSA_EXTENSION_TOKEN"] + "\n").encode())
while True:
    line = f.readline().decode(errors="replace")
    if not line:
        raise SystemExit(0)
    if line.startswith("CAPABILITIES"):
        break
f.write(b"CMD status alpha ready\n")
f.write(b"CMD workspace 2\n")
f.write(b"CMD state\n")
lines = []
deadline = time.time() + 2
while time.time() < deadline:
    try:
        line = f.readline().decode(errors="replace")
    except socket.timeout:
        break
    if not line:
        break
    lines.append(line.strip())
    if line == "END\n":
        break
with open(os.path.join(os.path.dirname(os.environ["TESSA_IPC"]), "alpha.out"), "w") as out:
    out.write("\n".join(lines) + "\n")
time.sleep(30)
PY

cat >"$runtime/beta.py" <<'PY'
import os, socket, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(os.environ["TESSA_IPC"])
f = s.makefile("rwb", buffering=0)
f.write(("HELLO 1 " + os.environ["TESSA_EXTENSION_TOKEN"] + "\n").encode())
while True:
    line = f.readline().decode(errors="replace")
    if not line or line.startswith("CAPABILITIES"):
        break
f.write(b"CMD status beta ready\n")
time.sleep(30)
PY

cat >"$runtime/config" <<EOF
panel = false
xwayland = false
animations = false
extension = id=alpha; command=python3 $runtime/alpha.py; permissions=read,status
extension = id=beta; command=python3 $runtime/beta.py; requires=alpha; permissions=read,status
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
    i=0
    while [ "$i" -lt 100 ]; do
        if tessa-ctl state 2>/dev/null | grep -q "^EXT $1 $2 "; then return 0; fi
        i=$((i + 1)); sleep 0.1
    done
    echo "extension $1 did not reach $2" >&2
    tessa-ctl state >&2
    exit 1
}
wait_ext alpha ready
wait_ext beta ready

tessa-ctl state | grep -q '^STATUS	alpha	ready'
tessa-ctl state | grep -q '^STATUS	beta	ready'
tessa-ctl state | grep -q '^EXT alpha ready'
tessa-ctl state | grep -q '^EXT beta ready'
echo "extension lifecycle: ok"

if ! grep -q 'ERR	forbidden	workspace' "$runtime/alpha.out"; then
    echo "extension without workspace scope was not denied" >&2
    cat "$runtime/alpha.out" >&2
    exit 1
fi
if ! grep -q 'ACTIVE 1' "$runtime/alpha.out"; then
    echo "forbidden workspace command still changed state" >&2
    cat "$runtime/alpha.out" >&2
    exit 1
fi
echo "token scopes: ok"

tessa-ctl extensions --json >"$runtime/ext.json"
python3 - "$runtime/ext.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
by_id = {e["id"]: e for e in data}
assert by_id["alpha"]["state"] == "ready", by_id
assert by_id["beta"]["state"] == "ready", by_id
assert by_id["alpha"]["permissions"] == "read,status", by_id["alpha"]
assert by_id["alpha"]["api"] == 1
PY
echo "extension JSON: ok"

tessa-ctl extension-enable alpha off >/dev/null
wait_ext alpha disabled
tessa-ctl state | grep -q '^EXT alpha disabled'
tessa-ctl extension-enable alpha on >/dev/null
wait_ext alpha ready
echo "extension enable/disable: ok"

python3 - "$TESSA_IPC" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
s.connect(sys.argv[1])
f = s.makefile("rwb", buffering=0)
f.write(b"HELLO 1 deadbeef\n")
line = f.readline().decode()
if not line.startswith("ERR\tunauthorized"):
    raise SystemExit(f"bad-token reply: {line!r}")
f.write(b"CMD state\n")
line = f.readline().decode()
if not line.startswith("ERR\tforbidden"):
    raise SystemExit(f"bad-token command was not denied: {line!r}")
PY
echo "bad token: ok"

cat >"$runtime/bad-api" <<EOF
extension = id=x; command=true; api=9
EOF
"$bin/tessa" --check-config "$runtime/bad-api" >"$runtime/bad-api.log" 2>&1 && {
    echo "unsupported extension api was accepted" >&2
    exit 1
}
grep -q "unsupported api" "$runtime/bad-api.log"

cat >"$runtime/bad-dep" <<EOF
extension = id=x; command=true; requires=missing
EOF
"$bin/tessa" --check-config "$runtime/bad-dep" >"$runtime/bad-dep.log" 2>&1 && {
    echo "unknown extension dependency was accepted" >&2
    exit 1
}
grep -q "requires unknown" "$runtime/bad-dep.log"

cat >"$runtime/cycle" <<EOF
extension = id=a; command=true; requires=b
extension = id=b; command=true; requires=a
EOF
"$bin/tessa" --check-config "$runtime/cycle" >"$runtime/cycle.log" 2>&1 && {
    echo "extension dependency cycle was accepted" >&2
    exit 1
}
grep -q "dependency cycle" "$runtime/cycle.log"
echo "extension validation: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "extensions test passed"
