#!/bin/sh
# A theme may provide only "arrow" (or only "left_ptr"), without "default".
# Tessa must select a cursor that actually exists rather than leaving a NULL
# cursor image.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

source_arrow=
for candidate in \
    /usr/share/icons/Adwaita/cursors/arrow \
    /usr/share/icons/whiteglass/cursors/arrow \
    /usr/share/icons/handhelds/cursors/arrow \
    /usr/share/icons/default/cursors/arrow
do
    if [ -e "$candidate" ]; then
        source_arrow=$candidate
        break
    fi
done
if [ -z "$source_arrow" ]; then
    echo "no arrow cursor available to synthesize a theme; skipping"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-cursor-theme.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/icons/OnlyArrow/cursors"
chmod 700 "$runtime"
cp -L "$source_arrow" "$runtime/icons/OnlyArrow/cursors/arrow"

cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
cursor_theme = OnlyArrow
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
export XCURSOR_PATH="$runtime/icons"

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
grep -q 'cursor theme: OnlyArrow size 24' "$runtime/tessa.log"
grep -q "cursor: theme has no 'default' cursor; using 'arrow'" "$runtime/tessa.log"
grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log" && {
    echo "compositor panicked while loading the cursor theme" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

"$bin/tessa-ctl" quit >/dev/null 2>&1 || true
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
cleanup
echo "cursor theme fallback test passed"
