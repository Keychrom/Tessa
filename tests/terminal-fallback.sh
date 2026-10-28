#!/bin/sh
# Verify terminal auto-detection, explicit-terminal handling, and cursor startup.
# Run from the repository root after building:
#   sh tests/terminal-fallback.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-terminal.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime/bin"
chmod 700 "$runtime"
printf '#!/bin/sh\nexit 0\n' > "$runtime/bin/foot"
chmod +x "$runtime/bin/foot"

export TESSA_CONFIG="$runtime/config"
export TESSA_IPC="$runtime/tessa.sock"
export TESSA_OUTPUT_CONFIG="$runtime/outputs.conf"
export XDG_RUNTIME_DIR="$runtime"
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS=1

cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
EOF

PATH="$runtime/bin" "$bin/tessa" >"$runtime/tessa.log" 2>&1 &
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

"$bin/tessa-ctl" config >"$runtime/config.out"
grep -q "^terminal foot$" "$runtime/config.out"
grep -aq "terminal: 'kitty' not found; using 'foot'" "$runtime/tessa.log"
grep -aq "cursor theme: default size 24" "$runtime/tessa.log"
echo "terminal fallback: ok"

"$bin/tessa-ctl" quit
wait "$tpid" 2>/dev/null || true
tpid=

cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
terminal = /no/such/terminal
EOF

"$bin/tessa" >"$runtime/tessa2.log" 2>&1 &
tpid=$!
i=0
while [ ! -S "$runtime/tessa.sock" ]; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
        echo "second compositor did not create its socket" >&2
        cat "$runtime/tessa2.log" >&2
        exit 1
    fi
    sleep 0.1
done

"$bin/tessa-ctl" config >"$runtime/config2.out"
grep -q "^terminal /no/such/terminal$" "$runtime/config2.out"
grep -aq "configured command '/no/such/terminal' was not found" "$runtime/tessa2.log"
echo "explicit terminal: ok"

"$bin/tessa-ctl" quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log" "$runtime/tessa2.log"; then
    echo "compositor did not shut down cleanly" >&2
    exit 1
fi

trap - EXIT INT TERM
rm -rf "$runtime"
echo "terminal fallback test passed"