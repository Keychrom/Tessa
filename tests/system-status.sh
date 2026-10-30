#!/bin/sh
# Verify battery and network indicators against deterministic sysfs/proc fixtures.
#   sh tests/system-status.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ] || [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-system-status.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/power/BAT0" "$runtime/net/test0/wireless"
chmod 700 "$runtime"
printf 'Battery\n' >"$runtime/power/BAT0/type"
printf '73\n' >"$runtime/power/BAT0/capacity"
printf 'Charging\n' >"$runtime/power/BAT0/status"
printf 'up\n' >"$runtime/net/test0/operstate"
printf 'Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\n' >"$runtime/route"
printf 'test0\t00000000\t0100000A\t0001\t0\t0\t100\t00000000\t0\t0\t0\n' >>"$runtime/route"
cat >"$runtime/config" <<EOF
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
export TESSA_POWER_SUPPLY_PATH="$runtime/power"
export TESSA_NET_PATH="$runtime/net"
export TESSA_ROUTE_PATH="$runtime/route"

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

wait_log "system: battery 73% charging"
wait_log "system: network Wi-Fi"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
echo "battery + network startup: ok"

printf '42\n' >"$runtime/power/BAT0/capacity"
printf 'Discharging\n' >"$runtime/power/BAT0/status"
wait_log "system: battery 42%"
echo "battery polling: ok"

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
echo "system status test passed"
