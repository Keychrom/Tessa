#!/bin/sh
# Named special workspaces: rule assignment, explicit toggle, and move action.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v kitty >/dev/null 2>&1; then
    echo "kitty not found; skipping special workspace test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-special.XXXXXX")
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
special-workspace = notes
special-workspace = tools
window-rule = app-id=tessa-special; special=notes; size=420x280
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

"$bin/tessa-ctl" spawn kitty --class=tessa-special -T SpecialNotes
i=0
while :; do
    "$bin/tessa-ctl" state >"$runtime/state.out" 2>/dev/null || true
    if awk -F '\t' '$1 == "WIN" && $7 == "tessa-special" && $15 == "0" { found=1 } END { exit found ? 0 : 1 }' "$runtime/state.out"; then
        break
    fi
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "special window was not hidden initially" >&2
        cat "$runtime/state.out" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

"$bin/tessa-ctl" special notes
i=0
while :; do
    "$bin/tessa-ctl" state >"$runtime/state.out" 2>/dev/null || true
    if grep -q '^SPECIAL .* notes$' "$runtime/state.out" &&
        awk -F '\t' '$1 == "WIN" && $7 == "tessa-special" && $15 == "1" { found=1 } END { exit found ? 0 : 1 }' "$runtime/state.out"; then
        break
    fi
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "special workspace did not become visible" >&2
        cat "$runtime/state.out" >&2
        exit 1
    fi
    sleep 0.1
done

"$bin/tessa-ctl" special notes
i=0
while :; do
    "$bin/tessa-ctl" state >"$runtime/state.out" 2>/dev/null || true
    if ! grep -q '^SPECIAL ' "$runtime/state.out" &&
        awk -F '\t' '$1 == "WIN" && $7 == "tessa-special" && $15 == "0" { found=1 } END { exit found ? 0 : 1 }' "$runtime/state.out"; then
        break
    fi
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "special workspace did not hide" >&2
        cat "$runtime/state.out" >&2
        exit 1
    fi
    sleep 0.1
done

"$bin/tessa-ctl" spawn kitty --class=tessa-move -T MoveSpecial
i=0
while :; do
    "$bin/tessa-ctl" state >"$runtime/state.out" 2>/dev/null || true
    if awk -F '\t' '$1 == "WIN" && $7 == "tessa-move" && $3 == "1" { found=1 } END { exit found ? 0 : 1 }' "$runtime/state.out"; then
        break
    fi
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "move test window did not map" >&2
        cat "$runtime/state.out" >&2
        exit 1
    fi
    sleep 0.1
done
"$bin/tessa-ctl" move-to-special tools
i=0
while :; do
    "$bin/tessa-ctl" state >"$runtime/state.out" 2>/dev/null || true
    if grep -q '^SPECIAL .* tools$' "$runtime/state.out" &&
        awk -F '\t' '$1 == "WIN" && $7 == "tessa-move" && $15 == "1" { found=1 } END { exit found ? 0 : 1 }' "$runtime/state.out"; then
        break
    fi
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "move-to-special did not expose the window" >&2
        cat "$runtime/state.out" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

"$bin/tessa-ctl" quit >/dev/null 2>&1 || true
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "special workspace test passed"
