#!/bin/sh
# Integration test for external layer-shell clients:
# - Waybar reserves its exclusive zone and exposes workspace/taskbar modules
# - Wofi opens as an exclusive-keyboard layer and receives typed input
# Requires waybar, wofi, foot, wtype.
#   sh tests/external-shell.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

for tool in waybar wofi foot wtype; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping external-shell test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-external.XXXXXX")
tpid=
waybar_pid=
wofi_pid=
foot_pid=
cleanup() {
    [ -n "${wofi_pid:-}" ] && kill "$wofi_pid" 2>/dev/null || true
    [ -n "${waybar_pid:-}" ] && kill "$waybar_pid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    [ -n "${foot_pid:-}" ] && kill "$foot_pid" 2>/dev/null || true
    wait "${wofi_pid:-0}" 2>/dev/null || true
    wait "${waybar_pid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
outer_gaps = 0
EOF
cat > "$runtime/waybar.json" <<'EOF'
{
  "layer": "top",
  "position": "top",
  "height": 34,
  "modules-left": ["ext/workspaces"],
  "modules-center": ["wlr/taskbar"],
  "ext/workspaces": { "format": "{name}" }
}
EOF
cat > "$runtime/waybar.css" <<'EOF'
* { font-family: sans-serif; font-size: 12px; }
window#waybar { background: #202020; color: #ffffff; }
EOF
# Wofi's dmenu reader does not process keyboard input while an upstream pipe
# remains open. Feed it a regular file so EOF arrives before typing.
printf 'alpha\nbeta\n' > "$runtime/items.txt"

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
    if [ "$i" -ge 100 ]; then
        echo "compositor did not create its socket" >&2
        cat "$runtime/tessa.log" >&2
        exit 1
    fi
    sleep 0.1
done

wait_state() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if tessa-ctl state 2>/dev/null | grep -q "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not contain: $pattern" >&2
    tessa-ctl state >&2 2>/dev/null || true
    exit 1
}

waybar -c "$runtime/waybar.json" -s "$runtime/waybar.css" >"$runtime/waybar.log" 2>&1 &
waybar_pid=$!
wait_state "^LAYER	waybar	"
sleep 1
if ! grep -q "Bar configured" "$runtime/waybar.log"; then
    echo "waybar did not configure a bar" >&2
    cat "$runtime/waybar.log" >&2
    exit 1
fi
echo "waybar layer: ok"

tessa-ctl spawn foot -T ExternalShell >/dev/null
sleep 1
state=$(tessa-ctl state)
y=$(printf '%s\n' "$state" | awk -F '\t' '$1 == "WIN" && $7 == "foot" { print $11; exit }')
if [ -z "$y" ] || [ "$y" -lt 34 ]; then
    echo "foot did not start below the Waybar exclusive zone (y=${y:-none})" >&2
    printf '%s\n' "$state" >&2
    exit 1
fi
foot_pid=$(pgrep -n -x foot 2>/dev/null || true)
echo "waybar exclusive zone: ok (foot y=$y)"

wofi --show dmenu --prompt Test < "$runtime/items.txt" >"$runtime/wofi.out" 2>"$runtime/wofi.log" &
wofi_pid=$!
wait_state "^LAYER	wofi	"
wtype -s 300 -d 100 "beta"
wtype -k Return
i=0
while [ "$i" -lt 100 ]; do
    if [ -f "$runtime/wofi.out" ] && [ "$(cat "$runtime/wofi.out")" = "beta" ]; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "wofi did not receive keyboard input or return the selected item" >&2
    cat "$runtime/wofi.out" 2>/dev/null >&2 || true
    tail -80 "$runtime/tessa.log" >&2
    exit 1
fi
echo "wofi keyboard/selection: ok"

# The layer is gone after Wofi exits; focus should return to the foot client.
wait_state "^FOCUSED [1-9]"
echo "focus restore: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime" 2>/dev/null || true
echo "external-shell test passed"
