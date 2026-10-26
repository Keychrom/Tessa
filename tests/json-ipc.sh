#!/bin/sh
# Verify versioned JSON state/config output and diagnostics.
# Requires foot and python3. Run from the repository root after building:
#   sh tests/json-ipc.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping JSON IPC test"
    exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping JSON IPC test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-json.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/pyconfig" <<'PY'
import json
import sys

state = json.load(open(sys.argv[1]))
assert state["schema"] == 1
assert state["active_workspace"] == 1
assert len(state["outputs"]) == 1
assert state["outputs"][0]["name"] == "HEADLESS-1"
assert len(state["occupancy"]) == 9
window = next(w for w in state["windows"] if w["title"] == "JsonTest")
assert window["workspace"] == 1
assert window["width"] > 0 and window["height"] > 0
assert window["app_id"] == "foot"

config = json.load(open(sys.argv[2]))
assert config["schema"] == 1
assert config["gaps"] == 12
assert len(config["layouts"]) == 9
assert config["diagnostics"] == []
assert config["errors"] == 0
PY

cat > "$runtime/config" <<EOF
panel = false
xwayland = false
gaps = 12
EOF

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
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

wait_state() {
    pattern=$1
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        if printf '%s\n' "$state" | grep -q "$pattern"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "state did not contain: $pattern" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

wait_state "OUT HEADLESS-1 1 1 master"
tessa-ctl spawn foot -T JsonTest
wait_state "WIN"

tessa-ctl state --json >"$runtime/state.json"
tessa-ctl config --json >"$runtime/config.json"
python3 "$runtime/pyconfig" "$runtime/state.json" "$runtime/config.json"
echo "JSON state/config: ok"

cat > "$runtime/config" <<EOF
panel = false
xwayland = false
gaps = 12
bogus = 1
EOF
tessa-ctl dispatch reload
sleep 0.2
tessa-ctl config --json >"$runtime/config.json"
python3 - "$runtime/config.json" <<'PY'
import json
import sys

config = json.load(open(sys.argv[1]))
assert config["gaps"] == 12
assert config["errors"] == 1
assert len(config["diagnostics"]) == 1
assert "unknown key" in config["diagnostics"][0]["message"]
assert config["diagnostics"][0]["line"] == 4
PY
echo "JSON diagnostics: ok"

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
echo "JSON IPC test passed"
