#!/bin/sh
# Long-lived effect helper: receives window state over a line protocol and
# returns visual overrides (opacity/radius/blur/shadow/border width).
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v kitty >/dev/null 2>&1; then
    echo "kitty not found; skipping effect helper test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-effect-helper.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

cat > "$runtime/effects.py" <<'PY'
import sys

while True:
    lines = []
    while True:
        line = sys.stdin.readline()
        if not line:
            raise SystemExit(0)
        line = line.rstrip("\n")
        if line == "END":
            break
        lines.append(line)
    out = ["VERSION\t1"]
    for line in lines:
        fields = line.split("\t")
        if fields[0] != "WINDOW":
            continue
        # id app_id title output ws focused urgent fullscreen floating visible ...
        if len(fields) > 2 and "tessa-hook" in fields[2]:
            out.append(f"WINDOW\t{fields[1]}\t0.400\t24\toff\toff\t6")
    out.append("END")
    sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()
PY

cat > "$runtime/config" <<EOF
panel = false
xwayland = false
animations = false
effect_helper = python3 $runtime/effects.py
effect_helper_timeout = 800
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

wait_log() {
    pattern=$1
    i=0
    while [ "$i" -lt 150 ]; do
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

wait_log "effect helper started"

tessa-ctl config | grep -qF "effect_helper python3 $runtime/effects.py" || {
    echo "effect_helper was not exposed by the config IPC" >&2
    exit 1
}

tessa-ctl spawn kitty --class=tessa-hook -T HookWindow
i=0
while [ "$i" -lt 150 ]; do
    if tessa-ctl state 2>/dev/null | grep -q "tessa-hook"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 150 ]; then
    echo "kitty window did not map" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi

tessa-ctl state --json >"$runtime/state.json"
i=0
while [ "$i" -lt 150 ]; do
    if python3 - "$runtime/state.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1]))
windows = [w for w in state.get("windows", []) if w.get("app_id") == "tessa-hook"]
if not windows:
    raise SystemExit(1)
w = windows[0]
checks = {
    "opacity": w.get("opacity"),
    "border_width": w.get("border_width"),
    "corner_radius": w.get("corner_radius"),
    "blur": w.get("blur"),
    "shadow": w.get("shadow"),
}
expected = {
    "opacity": 0.4,
    "border_width": 6,
    "corner_radius": 24,
    "blur": False,
    "shadow": False,
}
raise SystemExit(0 if checks == expected else 1)
PY
    then
        break
    fi
    i=$((i + 1))
    sleep 0.1
    tessa-ctl state --json >"$runtime/state.json"
done
if [ "$i" -ge 150 ]; then
    echo "effect helper overrides were not applied" >&2
    cat "$runtime/state.json" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "effect helper overrides: ok"

grep -v "^effect_helper" "$runtime/config" >"$runtime/config.new"
mv "$runtime/config.new" "$runtime/config"
tessa-ctl dispatch reload
i=0
while [ "$i" -lt 100 ]; do
    tessa-ctl state --json >"$runtime/state.json"
    if python3 - "$runtime/state.json" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1]))
windows = [w for w in state.get("windows", []) if w.get("app_id") == "tessa-hook"]
if not windows:
    raise SystemExit(1)
w = windows[0]
raise SystemExit(0 if w.get("opacity") == 1.0 and w.get("border_width") == 2 and w.get("corner_radius") == 10 else 1)
PY
    then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "rule visuals did not return after removing effect_helper" >&2
    cat "$runtime/state.json" >&2
    exit 1
fi
echo "effect helper removal: ok"

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
echo "effect helper test passed"
