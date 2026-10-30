#!/bin/sh
# Boundary/fuzz pass for the config parser (offline) and the line/IPC parser
# (live headless compositor). Set TESSA_FUZZ_ITERS for a longer run and
# TESSA_FUZZ_BIN to test a sanitizer/Debug build.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_FUZZ_BIN:-${TESSA_BIN_DIR:-$root/zig-out/bin}}
iters=${TESSA_FUZZ_ITERS:-200}
seed=${TESSA_FUZZ_SEED:-1}

if [ "${TESSA_FUZZ_ASAN:-0}" = 1 ]; then
    libasan=$(ldconfig -p 2>/dev/null | awk '$1 == "libasan.so.8" || $1 == "libasan.so" { print $NF; exit }')
    if [ -z "$libasan" ]; then
        echo "TESSA_FUZZ_ASAN=1 but libasan was not found" >&2
        exit 1
    fi
    export LD_PRELOAD="$libasan${LD_PRELOAD:+:$LD_PRELOAD}"
    export ASAN_OPTIONS="verify_asan_link_order=0:detect_leaks=0:abort_on_error=1${ASAN_OPTIONS:+:$ASAN_OPTIONS}"
    echo "ASan runtime enabled (allocator/interceptor pass)"
fi

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping parser fuzz test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-fuzz.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/corpus"
chmod 700 "$runtime"

python3 - "$root/config/config.example" "$runtime/corpus" "$iters" "$seed" <<'PY'
import os
import random
import sys

seed_path, outdir, count, seed = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
base = open(seed_path, "rb").read()
rng = random.Random(seed)
fragments = [
    b"window-rule = app-id=x; opacity=2; size=999x-1\n",
    b"bind = SUPER+; special\n",
    b"include = /does/not/exist\n",
    b"theme-role = accent = #zzzzzz\n",
    b"layer-rule = namespace=\xff; blur=maybe\n",
    b"\\\t\r\n\x00",
    b"workspace-rule = ws=999; master-ratio=9\n",
    b"output-rule = output=*; adaptive-sync=maybe\n",
    b"input = type=touchpad; tap=maybe\n",
    b"effect_helper = " + b"A" * 600 + b"\n",
]

for i in range(count):
    if i == 0:
        data = b""
    elif i == 1:
        data = base
    else:
        if rng.random() < 0.75:
            data = bytearray(base)
        else:
            data = bytearray(rng.randbytes(rng.randrange(0, 2048)))
        for _ in range(rng.randrange(1, 24)):
            op = rng.randrange(4)
            if op == 0 and data:
                pos = rng.randrange(len(data))
                data[pos] ^= 1 << rng.randrange(8)
            elif op == 1 and len(data) < 12000:
                pos = rng.randrange(len(data) + 1)
                data[pos:pos] = bytes((rng.randrange(256),))
            elif op == 2 and data:
                start = rng.randrange(len(data))
                end = min(len(data), start + rng.randrange(1, 40))
                del data[start:end]
            else:
                pos = rng.randrange(len(data) + 1)
                data[pos:pos] = rng.choice(fragments)
        data = bytes(data[:16000])
    with open(os.path.join(outdir, f"case-{i:04d}.conf"), "wb") as fh:
        fh.write(data)
PY

crashes=0
timeouts=0
for f in "$runtime"/corpus/case-*.conf; do
    set +e
    timeout 3 "$bin/tessa" --check-config "$f" >"$runtime/check.out" 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 124 ]; then
        timeouts=$((timeouts + 1))
        echo "config fuzz timeout: $f" >&2
    elif [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
        crashes=$((crashes + 1))
        echo "config fuzz crash (rc=$rc): $f" >&2
        tail -20 "$runtime/check.out" >&2
    fi
    if grep -qE 'panic:|Segmentation fault|Aborted|thread .* panic' "$runtime/check.out" 2>/dev/null; then
        crashes=$((crashes + 1))
        echo "config parser panic: $f" >&2
        tail -20 "$runtime/check.out" >&2
    fi
done
if [ "$crashes" -ne 0 ] || [ "$timeouts" -ne 0 ]; then
    echo "config fuzz failed: crashes=$crashes timeouts=$timeouts" >&2
    exit 1
fi
echo "config fuzz: ok ($iters cases)"

cat > "$runtime/config" <<EOF
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

python3 - "$TESSA_IPC" "$iters" "$seed" <<'PY'
import json
import os
import random
import socket
import sys

path, count, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rng = random.Random(seed ^ 0x5A5A)

def connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(path)
    return s

def line(f):
    value = f.readline()
    if not value:
        raise ConnectionError("closed")
    return value

def handshake_and_state(s, f):
    s.sendall(b"HELLO 1\n")
    if not line(f).startswith(b"VERSION\t1"):
        raise RuntimeError("bad VERSION")
    if not line(f).startswith(b"CAPABILITIES\t"):
        raise RuntimeError("bad CAPABILITIES")
    s.sendall(b"CMD state\n")
    saw_state = False
    while True:
        value = line(f)
        if value == b"STATE\n":
            saw_state = True
        if value == b"END\n":
            break
    if not saw_state:
        raise RuntimeError("missing STATE")

def safe(payload):
    return b"quit" not in payload and b"spawn" not in payload

s = connect()
f = s.makefile("rb")
handshake_and_state(s, f)

sent = 0
for i in range(count):
    kind = rng.randrange(5)
    if kind == 0:
        payload = b"CMD fuzz-" + rng.randbytes(rng.randrange(0, 64)).replace(b"\n", b"x")
    elif kind == 1:
        payload = rng.randbytes(rng.randrange(0, 512)).replace(b"\n", b"x")
    elif kind == 2:
        payload = b"CMD " + bytes(rng.choice(b"abcXYZ0123 \t=;:#-") for _ in range(rng.randrange(0, 128)))
    elif kind == 3:
        payload = b'{"jsonrpc":"2.0","id":' + rng.randbytes(rng.randrange(0, 32)).replace(b"\n", b"x") + b',"method":"' + rng.randbytes(rng.randrange(0, 32)).replace(b"\n", b"x") + b'"}'
    else:
        payload = b"HELLO " + rng.randbytes(rng.randrange(0, 16)).replace(b"\n", b"x")
    if not safe(payload):
        continue
    try:
        s.sendall(payload + b"\n")
        sent += 1
    except OSError:
        s.close()
        s = connect()
        f = s.makefile("rb")
    if (i + 1) % 40 == 0:
        s.close()
        s = connect()
        f = s.makefile("rb")
        handshake_and_state(s, f)

# An overlong line must not take down the compositor; it may close this client.
try:
    s.sendall(b"CMD " + b"A" * 20000 + b"\n")
except OSError:
    pass
s.close()

s = connect()
f = s.makefile("rb")
handshake_and_state(s, f)
s.close()
print(f"ipc fuzz: ok ({sent} payloads, long-line recovery)")
PY

tessa-ctl state >"$runtime/state.out"
grep -qF "STATE" "$runtime/state.out"
if ! kill -0 "$tpid" 2>/dev/null; then
    echo "compositor died during IPC fuzzing" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
if grep -qE 'Assertion|panic|thread .* panic|Segmentation fault' "$runtime/tessa.log"; then
    echo "compositor reported a crash during IPC fuzzing" >&2
    grep -E 'Assertion|panic|thread .* panic|Segmentation fault' "$runtime/tessa.log" >&2
    exit 1
fi

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "parser fuzz test passed"
