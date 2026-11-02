#!/bin/sh
# Verify direct-scanout mode and per-output rendering statistics.
# Headless pixman cannot scan out, but the compositor must still enter/leave
# scanout mode and keep the counters coherent. Real zero-copy is hardware-only.
# Requires kitty and wtype.
#   sh tests/rendering.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

for tool in kitty wtype; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found; skipping rendering test"
        exit 0
    fi
done
if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-rendering.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    [ -n "${TESSA_KEEP:-}" ] || rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat >"$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
outer_gaps = 0
direct_scanout = true
tearing = off
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

wait_win_field() {
    field=$1
    want=$2
    i=0
    while [ "$i" -lt 100 ]; do
        value=$(tessa-ctl state 2>/dev/null | awk -F '\t' '$1 == "WIN" && $7 == "kitty" { print $'"$field"'; exit }')
        if [ "$value" = "$want" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "kitty field $field did not become $want" >&2
    tessa-ctl state >&2 2>/dev/null || true
    exit 1
}

tessa-ctl spawn kitty -T RenderScanout >/dev/null
wait_state "RenderScanout"
sleep 0.5

rendering=$(tessa-ctl rendering)
printf '%s\n' "$rendering" | grep -q '^tearing_protocol 1$' || {
    echo "tearing-control protocol is not advertised" >&2
    printf '%s\n' "$rendering" >&2
    exit 1
}
printf '%s\n' "$rendering" | grep -q '^OUTPUT ' || {
    echo "rendering status has no per-output data" >&2
    exit 1
}

wtype -M logo -k f
wait_win_field 6 1
sleep 0.5
rendering=$(tessa-ctl rendering)
printf '%s\n' "$rendering" | grep -q 'scanout_active=1' || {
    echo "fullscreen window did not enter scanout mode" >&2
    printf '%s\n' "$rendering" >&2
    tail -80 "$runtime/tessa.log" >&2
    exit 1
}
grep -q 'direct scanout:.*kitty' "$runtime/tessa.log" || {
    echo "scanout transition was not logged" >&2
    tail -80 "$runtime/tessa.log" >&2
    exit 1
}

perf=$(tessa-ctl perf --json)
printf '%s\n' "$perf" | grep -q '"outputs":\[' || {
    echo "perf json has no outputs array" >&2
    printf '%s\n' "$perf" >&2
    exit 1
}
printf '%s\n' "$perf" | grep -q '"scanout_frames":' || {
    echo "perf json has no scanout counter" >&2
    exit 1
}

tessa-ctl perf --reset >/dev/null
perf=$(tessa-ctl perf --json)
printf '%s\n' "$perf" | grep -q '"frames":0' || {
    echo "perf reset did not clear the global sample window" >&2
    printf '%s\n' "$perf" >&2
    exit 1
}

rendering_json=$(tessa-ctl rendering --json)
printf '%s\n' "$rendering_json" | grep -q '"direct_scanout":1' || {
    echo "rendering json has no direct_scanout field" >&2
    printf '%s\n' "$rendering_json" >&2
    exit 1
}
printf '%s\n' "$rendering_json" | grep -q '"color_management":0' || {
    echo "rendering json has no color_management field" >&2
    exit 1
}

wtype -M logo -k f
wait_win_field 6 0
sleep 0.5
rendering=$(tessa-ctl rendering)
printf '%s\n' "$rendering" | grep -q 'scanout_active=0' || {
    echo "fullscreen exit did not restore the scene" >&2
    printf '%s\n' "$rendering" >&2
    exit 1
}
grep -q 'direct scanout:.*ended' "$runtime/tessa.log" || {
    echo "scanout exit was not logged" >&2
    exit 1
}

# Disabling the feature must leave fullscreen composition untouched.
sed -i 's/^direct_scanout = true$/direct_scanout = false/' "$runtime/config"
sleep 1
wtype -M logo -k f
wait_win_field 6 1
sleep 0.5
rendering=$(tessa-ctl rendering)
printf '%s\n' "$rendering" | grep -q 'scanout_active=0' || {
    echo "direct_scanout=false did not disable scanout mode" >&2
    printf '%s\n' "$rendering" >&2
    exit 1
}
wtype -M logo -k f
wait_win_field 6 0

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
echo "rendering test passed"
