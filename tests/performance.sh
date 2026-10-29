#!/bin/sh
# Headless frame-time budget: animation-only and full-effects workloads.
# The default budget is deliberately generous for the software pixman
# headless renderer; run with TESSA_PERF_BUDGET_MS=16 on target hardware.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}
budget=${TESSA_PERF_BUDGET_MS:-100}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v kitty >/dev/null 2>&1; then
    echo "kitty not found; skipping performance test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-perf.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

write_config() {
    effects=$1
    cat > "$runtime/config" <<EOF
panel = false
xwayland = false
animations = true
animation_ms = 250
animation_workspace_ms = 250
frame_time_budget = $budget
$effects
EOF
}

write_config ""

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

wait_window() {
    i=0
    while [ "$i" -lt 150 ]; do
        if tessa-ctl state 2>/dev/null | grep -q "tessa-perf"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "performance test window did not map" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

workload() {
    n=0
    while [ "$n" -lt 8 ]; do
        tessa-ctl workspace 2 >/dev/null
        tessa-ctl workspace 1 >/dev/null
        n=$((n + 1))
    done
    sleep 0.5
}

check_perf() {
    label=$1
    tessa-ctl perf --json >"$runtime/perf.json"
    python3 - "$runtime/perf.json" "$budget" "$label" <<'PY'
import json
import sys

perf = json.load(open(sys.argv[1]))
budget = int(sys.argv[2])
label = sys.argv[3]
print(
    f"{label}: frames={perf['frames']} avg={perf['avg_us']}us "
    f"p50={perf['p50_us']}us p95={perf['p95_us']}us max={perf['max_us']}us "
    f"over_budget={perf['over_budget']} scenefx={perf['scenefx']}"
)
if perf["frames"] < 10:
    print(f"{label}: not enough rendered frames", file=sys.stderr)
    raise SystemExit(1)
if perf["p95_us"] > budget * 1000:
    print(f"{label}: p95 {perf['p95_us']}us exceeds budget {budget}ms", file=sys.stderr)
    raise SystemExit(1)
PY
}

tessa-ctl spawn kitty --class=tessa-perf -T Performance >/dev/null
wait_window
sleep 0.5

tessa-ctl perf --reset
workload
check_perf "animations"

write_config "corner_radius = 20
shadows = true
blur = true
blur_radius = 8
blur_passes = 2"
tessa-ctl dispatch reload
sleep 0.5

tessa-ctl perf --reset
workload
check_perf "effects"

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
echo "performance test passed"
