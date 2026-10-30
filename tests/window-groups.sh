#!/bin/sh
# Verify tabbed window groups: grouping, tab switching, removal, and adding.
# Run from the repository root after building:
#   sh tests/window-groups.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-window-groups.XXXXXX")
tpid=
apid=
bpid=
cleanup() {
    [ -n "${apid:-}" ] && kill "$apid" 2>/dev/null || true
    [ -n "${bpid:-}" ] && kill "$bpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${apid:-0}" 2>/dev/null || true
    wait "${bpid:-0}" 2>/dev/null || true
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
EOF

cc -O2 -I"$root/protocol" -o "$runtime/window-test" \
    "$root/tests/rule-visuals/window.c" \
    "$root/protocol/xdg-shell-client-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)

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

"$runtime/window-test" tessa-group-a GroupA >"$runtime/a.log" 2>&1 &
apid=$!
sleep 0.2
"$runtime/window-test" tessa-group-b GroupB >"$runtime/b.log" 2>&1 &
bpid=$!

window_fields() {
    app=$1
    tessa-ctl state >"$runtime/state.out"
    awk -F '\t' -v app="$app" '$1 == "WIN" && $7 == app { print $15, $16, $17; exit }' "$runtime/state.out"
}

i=0
a_fields=
b_fields=
while [ "$i" -lt 100 ]; do
    a_fields=$(window_fields tessa-group-a)
    b_fields=$(window_fields tessa-group-b)
    [ -n "$a_fields" ] && [ -n "$b_fields" ] && break
    i=$((i + 1))
    sleep 0.1
done
if [ -z "$a_fields" ] || [ -z "$b_fields" ]; then
    echo "test windows did not appear" >&2
    cat "$runtime/state.out" >&2
    exit 1
fi

tessa-ctl dispatch toggle-group
sleep 0.2
a_fields=$(window_fields tessa-group-a)
b_fields=$(window_fields tessa-group-b)
a_group=$(printf '%s\n' "$a_fields" | cut -d' ' -f2)
b_group=$(printf '%s\n' "$b_fields" | cut -d' ' -f2)
if [ "$a_group" = "0" ] || [ "$a_group" != "$b_group" ]; then
    echo "toggle-group did not create one shared group (a='$a_fields' b='$b_fields')" >&2
    exit 1
fi
a_visible=$(printf '%s\n' "$a_fields" | cut -d' ' -f1)
b_visible=$(printf '%s\n' "$b_fields" | cut -d' ' -f1)
if [ "$a_visible" = "$b_visible" ]; then
    echo "group should show exactly one member (a='$a_fields' b='$b_fields')" >&2
    exit 1
fi
echo "window group create: ok"

tessa-ctl dispatch group-next
sleep 0.2
a_next=$(window_fields tessa-group-a)
b_next=$(window_fields tessa-group-b)
a_visible2=$(printf '%s\n' "$a_next" | cut -d' ' -f1)
b_visible2=$(printf '%s\n' "$b_next" | cut -d' ' -f1)
if [ "$a_visible" = "$a_visible2" ] || [ "$a_visible2" = "$b_visible2" ]; then
    echo "group-next did not switch tabs (before='$a_visible/$b_visible' after='$a_next'/'$b_next')" >&2
    exit 1
fi
echo "window group next: ok"

tessa-ctl dispatch toggle-group
sleep 0.2
a_fields=$(window_fields tessa-group-a)
b_fields=$(window_fields tessa-group-b)
if [ "$(printf '%s\n' "$a_fields" | cut -d' ' -f2)" != "0" ] ||
    [ "$(printf '%s\n' "$b_fields" | cut -d' ' -f2)" != "0" ]; then
    echo "toggle-group did not ungroup both windows (a='$a_fields' b='$b_fields')" >&2
    exit 1
fi
echo "window group ungroup: ok"

tessa-ctl dispatch toggle-group
sleep 0.2
tessa-ctl dispatch group-remove
sleep 0.2
a_fields=$(window_fields tessa-group-a)
b_fields=$(window_fields tessa-group-b)
a_group=$(printf '%s\n' "$a_fields" | cut -d' ' -f2)
b_group=$(printf '%s\n' "$b_fields" | cut -d' ' -f2)
if [ "$a_group" = "$b_group" ]; then
    echo "group-remove did not detach the focused window (a='$a_fields' b='$b_fields')" >&2
    exit 1
fi
tessa-ctl dispatch group-add
sleep 0.2
a_fields=$(window_fields tessa-group-a)
b_fields=$(window_fields tessa-group-b)
a_group=$(printf '%s\n' "$a_fields" | cut -d' ' -f2)
b_group=$(printf '%s\n' "$b_fields" | cut -d' ' -f2)
if [ "$a_group" = "0" ] || [ "$a_group" != "$b_group" ]; then
    echo "group-add did not rejoin the group (a='$a_fields' b='$b_fields')" >&2
    exit 1
fi
echo "window group add/remove: ok"

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
echo "window groups test passed"
