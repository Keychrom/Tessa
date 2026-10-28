#!/bin/sh
# Verify named workspaces in config, IPC, state, and deferred bind resolution.
# Run from the repository root after building:
#   sh tests/workspace-names.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-workspace-names.XXXXXX")
tpid=
wpid=
cleanup() {
    [ -n "${wpid:-}" ] && kill "$wpid" 2>/dev/null || true
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${wpid:-0}" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
animations = false
bind = SUPER+F1 workspace Code
window-rule = app-id=tessa-name-test; workspace=Chat
workspace-name = 2 Code
workspace-name = 3 Chat
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

if ! tessa-ctl config-check >"$runtime/check.out"; then
    cat "$runtime/check.out" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
grep -q "config: ok" "$runtime/check.out"
tessa-ctl config >"$runtime/config.out"
grep -q "^workspace_name 2 Code$" "$runtime/config.out"
grep -q "^workspace_name 3 Chat$" "$runtime/config.out"
echo "workspace names config: ok"

tessa-ctl state >"$runtime/state.out"
grep -q "^WORKSPACE 2 Code$" "$runtime/state.out"
grep -q "^WORKSPACE 3 Chat$" "$runtime/state.out"
echo "workspace names state: ok"

tessa-ctl config --json >"$runtime/config.json"
python3 - "$runtime/config.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
names = data["workspace_names"]
assert len(names) == 9, names
assert names[1] == "Code", names
assert names[2] == "Chat", names
assert names[0] == "" and names[3] == "", names
PY
echo "workspace names json: ok"

"$runtime/window-test" tessa-name-test NameTest >"$runtime/window.log" 2>&1 &
wpid=$!
win_ws=
i=0
while [ "$i" -lt 100 ]; do
    tessa-ctl state >"$runtime/state.out"
    win_line=$(awk -F '\t' '$1 == "WIN" && $7 == "tessa-name-test" { print; exit }' "$runtime/state.out")
    if [ -n "$win_line" ]; then
        win_ws=$(printf '%s\n' "$win_line" | cut -f3)
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$win_ws" != "3" ]; then
    echo "window rule did not resolve workspace Chat (got '$win_ws')" >&2
    cat "$runtime/state.out" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
tessa-ctl workspace Chat
i=0
focused=0
while [ "$i" -lt 100 ]; do
    tessa-ctl state >"$runtime/state.out"
    focused=$(awk '$1 == "FOCUSED" { print $2 }' "$runtime/state.out")
    [ "$focused" != "0" ] && break
    i=$((i + 1))
    sleep 0.1
done
if [ "$focused" = "0" ] || [ -z "$focused" ]; then
    echo "window on Chat was not focused after switching workspace" >&2
    cat "$runtime/state.out" >&2
    exit 1
fi
tessa-ctl dispatch move-workspace Code
i=0
while [ "$i" -lt 100 ]; do
    tessa-ctl state >"$runtime/state.out"
    win_ws=$(awk -F '\t' '$1 == "WIN" && $7 == "tessa-name-test" { print $3; exit }' "$runtime/state.out")
    [ "$win_ws" = "2" ] && break
    i=$((i + 1))
    sleep 0.1
done
if [ "$win_ws" != "2" ]; then
    echo "move-workspace Code did not move the window (got '$win_ws')" >&2
    cat "$runtime/state.out" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
fi
echo "workspace names window rule: ok"

tessa-ctl workspace Code
tessa-ctl state >"$runtime/state.out"
grep -q "^ACTIVE 2$" "$runtime/state.out"
grep -q "^OUT [^ ]* 2 1 " "$runtime/state.out"
tessa-ctl state --json >"$runtime/state.json"
python3 - "$runtime/state.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
assert data["active_workspace"] == 2, data
assert data["active_workspace_name"] == "Code", data
assert data["workspace_names"][1] == "Code", data
PY
tessa-ctl workspace Chat
tessa-ctl state >"$runtime/state.out"
grep -q "^ACTIVE 3$" "$runtime/state.out"
echo "workspace names command: ok"

cat > "$runtime/config.invalid" <<'EOF'
panel = false
xwayland = false
workspace-name = 2 Code
workspace-name = 3 Chat
window-rule = app-id=no-such-app; workspace=Missing
EOF
cp "$runtime/config.invalid" "$runtime/config"
tessa-ctl dispatch reload
sleep 0.2
if tessa-ctl config-check >"$runtime/check.invalid" 2>&1; then
    echo "config-check accepted an unknown workspace name" >&2
    cat "$runtime/check.invalid" >&2
    exit 1
fi
tessa-ctl config >"$runtime/config.out"
grep -q "^workspace_name 2 Code$" "$runtime/config.out"
grep -q "^workspace_name 3 Chat$" "$runtime/config.out"
echo "workspace names validation: ok"

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
echo "workspace names test passed"
