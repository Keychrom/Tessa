#!/bin/sh
# Verify repeated arrange passes reuse window_effects' last-applied cache.
#   sh tests/effect-cache.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN_DIR:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v kitty >/dev/null 2>&1; then
    echo "kitty not found; skipping effect cache test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-effect-cache.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM
mkdir -p "$runtime"
chmod 700 "$runtime"
cat >"$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
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
    [ "$i" -lt 100 ] || { cat "$runtime/tessa.log" >&2; exit 1; }
    sleep 0.1
done

if ! tessa-ctl config 2>/dev/null | grep -q '^scenefx 1$'; then
    echo "built without scenefx; skipping effect cache test"
    tessa-ctl quit 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    tpid=
    trap - EXIT INT TERM
    rm -rf "$runtime"
    exit 0
fi

tessa-ctl spawn kitty -T CacheA >/dev/null
tessa-ctl spawn kitty -T CacheB >/dev/null
i=0
while [ "$i" -lt 100 ]; do
    count=$(tessa-ctl state 2>/dev/null | grep -c '^WIN	' || true)
    [ "$count" -ge 2 ] && break
    i=$((i + 1)); sleep 0.1
done
sleep 0.3

i=0
while [ "$i" -lt 6 ]; do
    tessa-ctl layout master >/dev/null
    i=$((i + 1))
done
sleep 0.3

tessa-ctl perf --json >"$runtime/perf.json"
python3 - "$runtime/perf.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
applies = data["effect_applies"]
skips = data["effect_skips"]
if applies <= 0:
    raise SystemExit(f"no effect applies recorded: {data}")
if skips < 2:
    raise SystemExit(f"effect cache did not reuse work: applies={applies} skips={skips}")
PY
echo "effect cache: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
trap - EXIT INT TERM
rm -rf "$runtime"
echo "effect cache test passed"
