#!/bin/sh
# Verify MPRIS artwork decoding and the unified media card.
#   sh tests/media-art.sh
set -eu

if [ -z "${TESSA_MEDIA_ART_PRIVATE:-}" ]; then
    if ! command -v dbus-run-session >/dev/null 2>&1; then
        echo "dbus-run-session not found; skipping media artwork test"
        exit 0
    fi
    exec dbus-run-session -- env TESSA_MEDIA_ART_PRIVATE=1 sh "$0" "$@"
fi

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! python3 -c 'import gi; gi.require_version("Gio", "2.0")' >/dev/null 2>&1; then
    echo "PyGObject not found; skipping media artwork test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-media-art.XXXXXX")
tpid=
ppid=
cleanup() {
    [ -n "${ppid:-}" ] && kill "$ppid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
python3 - "$runtime/art.png" <<'PY'
import struct, sys, zlib
size = 8
raw = b"".join(b"\x00" + bytes((220, 70, 50)) * size for _ in range(size))
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw))
png += chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY

cat > "$runtime/config" <<EOF
panel = true
xwayland = false
panel_style = unified
control_features = media
EOF

export FAKE_ART_URL="file://$runtime/art.png"
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
export TESSA_PANEL_DEBUG=1

python3 "$root/tests/fake-mpris.py" "$runtime/commands" "$runtime/ready" >"$runtime/player.log" 2>&1 &
ppid=$!
i=0
while [ ! -f "$runtime/ready" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "fake MPRIS player did not start" >&2
        cat "$runtime/player.log" >&2
        exit 1
    fi
    sleep 0.1
done

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
    while [ "$i" -lt 150 ]; do
        if grep -qF "$pattern" "$runtime/tessa.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not contain: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "media: service ready"
tessa-ctl panel control >/dev/null
wait_log "tessa-panel: control: open view=home"
wait_log "media: artwork 128x128"
echo "media artwork: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE "panic|Assertion|double free" "$runtime/tessa.log"; then
    echo "media artwork test crashed" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "media artwork test passed"
