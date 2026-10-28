#!/bin/sh
# Verify wallpaper_image loading and cover/contain/stretch fit modes.
# Run from the repository root after building:
#   sh tests/wallpaper-image.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v grim >/dev/null 2>&1; then
    echo "grim not found; skipping wallpaper image test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-wallpaper.XXXXXX")
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

python3 - "$runtime/wallpaper.png" <<'PY'
import struct
import sys
import zlib

width = height = 64
color = bytes((32, 96, 160))
raw = b"".join(b"\x00" + color * width for _ in range(height))

def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9))
png += chunk(b"IEND", b"")
with open(sys.argv[1], "wb") as fh:
    fh.write(png)
PY

cat > "$runtime/config" <<EOF
panel = true
xwayland = false
animations = false
bg = #102030
bg_top = #102030
bg_bottom = #102030
wallpaper_art = false
wallpaper_image = $runtime/wallpaper.png
wallpaper_fit = stretch
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

wait_log() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if grep -q "$pattern" "$runtime/tessa.log" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "log did not contain: $pattern" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

wait_log "tessa-panel: wallpaper image"
sleep 0.3
grim -o HEADLESS-1 "$runtime/stretch.png"
rgb=$(python3 "$root/tests/png-pixel.py" "$runtime/stretch.png" 960 1000)
awk -v rgb="$rgb" 'BEGIN { split(rgb, c, " "); if (c[1] < 20 || c[1] > 60 || c[2] < 70 || c[2] > 130 || c[3] < 130 || c[3] > 190) exit 1 }' || {
    echo "stretched wallpaper pixel is $rgb, expected 32/96/160" >&2
    cp "$runtime/stretch.png" /tmp/tessa-wallpaper-stretch-failure.png 2>/dev/null || true
    exit 1
}
echo "wallpaper image stretch: ok"

sed 's/wallpaper_fit = stretch/wallpaper_fit = contain/' "$runtime/config" >"$runtime/config.new"
mv "$runtime/config.new" "$runtime/config"
tessa-ctl dispatch reload
sleep 0.8
grim -o HEADLESS-1 "$runtime/contain.png"
center=$(python3 "$root/tests/png-pixel.py" "$runtime/contain.png" 960 540)
edge=$(python3 "$root/tests/png-pixel.py" "$runtime/contain.png" 20 540)
awk -v rgb="$center" 'BEGIN { split(rgb, c, " "); if (c[1] < 20 || c[1] > 60 || c[2] < 70 || c[2] > 130 || c[3] < 130 || c[3] > 190) exit 1 }' || {
    echo "contained wallpaper center pixel is $center, expected image color" >&2
    exit 1
}
awk -v rgb="$edge" 'BEGIN { split(rgb, c, " "); if (c[1] < 10 || c[1] > 30 || c[2] < 20 || c[2] > 60 || c[3] < 30 || c[3] > 80) exit 1 }' || {
    echo "contained wallpaper edge pixel is $edge, expected background #102030" >&2
    cp "$runtime/contain.png" /tmp/tessa-wallpaper-contain-failure.png 2>/dev/null || true
    exit 1
}
echo "wallpaper image contain: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi
pkill -x tessa-panel 2>/dev/null || true

trap - EXIT INT TERM
rm -rf "$runtime"
echo "wallpaper image test passed"
