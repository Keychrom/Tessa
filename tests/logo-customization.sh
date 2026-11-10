#!/bin/sh
# Verify logo_icon/logo_text customization in the bar's Tessa button.
# Run from the repository root after building:
#   sh tests/logo-customization.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v grim >/dev/null 2>&1; then
    echo "grim not found; skipping logo customization test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-logo.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

python3 - "$runtime/icon.png" <<'PY'
import struct
import sys
import zlib

width = height = 64
color = bytes((220, 30, 140))
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
logo_icon = $runtime/icon.png
logo_text = Custom Tessa
EOF

export TESSA_CONFIG="$runtime/config"
summary=$("$bin/tessa-panel" --check 2>&1)
case "$summary" in
    *"logo-text=Custom Tessa"*) ;;
    *)
        echo "logo_text was not parsed" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
case "$summary" in
    *"logo-icon=$runtime/icon.png"*) ;;
    *)
        echo "logo_icon was not parsed" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
case "$summary" in
    *"loaded=yes"*) ;;
    *)
        echo "logo icon was not loaded" >&2
        echo "$summary" >&2
        exit 1
        ;;
esac
echo "logo config parse: ok"

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

wait_log "tessa-panel: logo icon"
sleep 0.3
grim -o HEADLESS-1 "$runtime/bar.png"
# The bar starts at x=16, y=12; the 28 px mark box at x=14..42 has its
# 22 px icon centered, so the middle of the icon is at output (44, 34).
rgb=$(python3 "$root/tests/png-pixel.py" "$runtime/bar.png" 44 34)
awk -v rgb="$rgb" 'BEGIN { split(rgb, c, " "); if (c[1] < 180 || c[1] > 250 || c[2] > 70 || c[3] < 100 || c[3] > 180) exit 1 }' || {
    echo "custom logo pixel is $rgb, expected 220/30/140" >&2
    cp "$runtime/bar.png" /tmp/tessa-logo-failure.png 2>/dev/null || true
    exit 1
}
echo "custom logo icon: ok"

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
echo "logo customization test passed"
