#!/bin/sh
# Verify the tessa-panel compatibility bridge against fake Hyprland/Niri CLIs.
# Requires Python 3. Run from the repository root:
#   sh tests/panel-compat.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
compat=$root/tools/tessa-panel-compat.py

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping panel compatibility test"
    exit 0
fi
if [ ! -f "$compat" ]; then
    echo "missing $compat" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-compat.XXXXXX")
bpid=
cleanup() {
    if [ -n "${bpid:-}" ]; then
        kill "$bpid" 2>/dev/null || true
        wait "$bpid" 2>/dev/null || true
    fi
    rm -rf "$runtime"
    return 0
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/bin" "$runtime/fixtures"
export FIXTURES="$runtime/fixtures"
export PATH="$runtime/bin:$PATH"

cat >"$runtime/bin/hyprctl" <<'EOF'
#!/bin/sh
case "$*" in
  "-j monitors") cat "$FIXTURES/monitors.json" ;;
  "-j clients") cat "$FIXTURES/clients.json" ;;
  "-j activewindow") cat "$FIXTURES/activewindow.json" ;;
  dispatch\ *) printf '%s\n' "$*" >>"$FIXTURES/dispatch.log" ;;
  *) printf '{}\n' ;;
esac
EOF
chmod +x "$runtime/bin/hyprctl"

cat >"$FIXTURES/monitors.json" <<'EOF'
[{"id":0,"name":"HEADLESS-1","focused":true,"activeWorkspace":{"id":2,"name":"2"},"x":0,"y":0,"width":1920,"height":1080,"make":"Fake","model":"Panel","serial":"001"}]
EOF
cat >"$FIXTURES/clients.json" <<'EOF'
[{"address":"0x1a","mapped":true,"hidden":false,"at":[10,20],"size":[800,600],"workspace":{"id":2,"name":"2"},"floating":false,"fullscreen":0,"class":"foot","title":"Terminal\tOne","monitor":0,"focusHistoryID":0},{"address":"0x1b","mapped":true,"hidden":false,"at":[100,200],"size":[400,300],"workspace":{"id":1,"name":"1"},"floating":true,"fullscreen":0,"class":"kitty","title":"Editor","monitor":0,"focusHistoryID":1}]
EOF
cat >"$FIXTURES/activewindow.json" <<'EOF'
{"address":"0x1a"}
EOF

out=$(python3 "$compat" --compositor hyprland --print-state)
printf '%s\n' "$out" | grep -F "ACTIVE 2" >/dev/null
printf '%s\n' "$out" | grep -F "OUT HEADLESS-1 2 1 hyprland" >/dev/null
printf '%s\n' "$out" | grep -F "FOCUSED 26" >/dev/null
printf '%s\n' "$out" | grep -F "$(printf 'WIN\t26\t2\t1')" >/dev/null
printf '%s\n' "$out" | grep -F 'Terminal\tOne' >/dev/null

cat >"$runtime/bin/niri" <<'EOF'
#!/bin/sh
case "$*" in
  "msg --json outputs") cat "$FIXTURES/niri-outputs.json" ;;
  "msg --json workspaces") cat "$FIXTURES/niri-workspaces.json" ;;
  "msg --json windows") cat "$FIXTURES/niri-windows.json" ;;
  "msg action "*) printf '%s\n' "$*" >>"$FIXTURES/niri-actions.log" ;;
  *) printf '{}\n' ;;
esac
EOF
chmod +x "$runtime/bin/niri"

cat >"$FIXTURES/niri-outputs.json" <<'EOF'
{"eDP-1":{"name":"eDP-1","make":"Fake","model":"Niri","serial":"002","logical":{"x":0,"y":0,"width":1920,"height":1080,"scale":1.0}}}
EOF
cat >"$FIXTURES/niri-workspaces.json" <<'EOF'
[{"id":10,"idx":1,"name":"1","output":"eDP-1","is_active":true,"is_focused":true,"active_window_id":101}]
EOF
cat >"$FIXTURES/niri-windows.json" <<'EOF'
[{"id":101,"title":"Terminal","app_id":"foot","workspace_id":10,"is_focused":true,"is_floating":false,"layout":{"tile_pos_in_workspace_view":[10.0,20.0],"tile_size":[800,600],"window_size":[800,600]},"focus_timestamp":{"secs":100,"nanos":5}}]
EOF

out=$(python3 "$compat" --compositor niri --print-state)
printf '%s\n' "$out" | grep -F "OUT eDP-1 1 1 niri" >/dev/null
printf '%s\n' "$out" | grep -F "FOCUSED 101" >/dev/null
printf '%s\n' "$out" | grep -F "$(printf 'WIN\t101\t1\t1')" >/dev/null

socket_path=$runtime/bridge.sock
python3 "$compat" --compositor hyprland --no-spawn --socket "$socket_path" --poll 0.2 \
    >"$runtime/bridge.out" 2>"$runtime/bridge.err" &
bpid=$!

i=0
while [ ! -S "$socket_path" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "bridge did not create its socket" >&2
        cat "$runtime/bridge.err" >&2
        exit 1
    fi
    sleep 0.05
done

python3 - "$socket_path" "$compat" <<'PY'
import socket
import subprocess
import sys
import time

path, compat = sys.argv[1], sys.argv[2]
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(2)
sock.connect(path)
data = b""
while b"END\n" not in data:
    data += sock.recv(4096)
if b"ACTIVE 2\n" not in data:
    raise SystemExit("missing ACTIVE in bridged state")
sock.sendall(b"CMD focus 27\n")
time.sleep(0.25)
subprocess.run(
    [sys.executable, compat, "--socket", path, "--send", "launcher"],
    check=True,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
event = b""
while b"EVENT\tlauncher" not in event:
    chunk = sock.recv(4096)
    if not chunk:
        break
    event += chunk
if b"EVENT\tlauncher" not in event:
    raise SystemExit(f"missing launcher event: {event!r}")
print("socket state, command, and event passed")
PY

grep -F "focuswindow address:0x1b" "$FIXTURES/dispatch.log" >/dev/null

kill "$bpid"
wait "$bpid" 2>/dev/null || true
bpid=
if [ -e "$socket_path" ]; then
    echo "bridge left its socket behind" >&2
    exit 1
fi

echo "panel compatibility test passed"
