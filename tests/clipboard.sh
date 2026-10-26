#!/bin/sh
# Verify clipboard history capture, Super+V, selection, and clipboard restore.
# Requires wl-copy, wl-paste, and wtype.
# Run from the repository root after building:
#   sh tests/clipboard.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
for tool in wl-copy wl-paste wtype; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping clipboard test"
        exit 0
    fi
done

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-clipboard.XXXXXX")
tpid=
epid=
cleanup() {
    [ -n "${epid:-}" ] && kill "$epid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = true
xwayland = false
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
export TESSA_PANEL_DEBUG=1

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

wait_event() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        if grep -q "$pattern" "$runtime/events" 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "event stream did not contain: $pattern" >&2
    cat "$runtime/events" >&2
    exit 1
}

paste_text() {
    timeout 3 wl-paste 2>/dev/null || true
}

wait_log "tessa: wlr-data-control-v1 enabled"
wait_log "tessa-panel: clipboard: data control device ready"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"

printf alpha | wl-copy
wait_log "clipboard: captured 5 bytes (1 entries)"
printf beta | wl-copy
wait_log "clipboard: captured 4 bytes (2 entries)"
echo "clipboard capture: ok"

tessa-ctl events panel >"$runtime/events" &
epid=$!
sleep 0.3

wtype -M logo -k v
wait_log "clipboard open (2 entries)"
wait_event "EVENT.*panel.*arg=clipboard"
wait_log "layer map: tessa-overlay layer=3 keyboard=1"
sleep 0.2

wtype -k Down
wtype -k Return
wait_log "clipboard: selected entry 1"
sleep 0.3
if [ "$(paste_text)" != "alpha" ]; then
    echo "clipboard selection did not restore the older entry" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "Super+V + clipboard restore: ok"

printf gamma | wl-copy
wait_log "clipboard: captured 5 bytes (3 entries)"
tessa-ctl panel clipboard
wait_log "clipboard open (3 entries)"
sleep 0.3
wtype -k Return
wait_log "clipboard: selected entry 0"
sleep 0.3
if [ "$(paste_text)" != "gamma" ]; then
    echo "clipboard did not restore the newest entry" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "new clipboard capture + newest restore: ok"

kill "$epid" 2>/dev/null || true
wait "$epid" 2>/dev/null || true
epid=

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log"; then
    echo "compositor or panel did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic|listener function .* is NULL' "$runtime/tessa.log" >&2
    exit 1
fi
pkill -x tessa-panel 2>/dev/null || true

trap - EXIT INT TERM
rm -rf "$runtime"
echo "clipboard test passed"
