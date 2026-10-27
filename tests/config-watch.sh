#!/bin/sh
# Verify automatic config reload after an atomic save and transactional
# rejection of an invalid edit. Run from the repository root:
#   sh tests/config-watch.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-watch.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

write_config() {
    cat > "$runtime/config.new" <<EOF
panel = false
xwayland = false
xim = false
gaps = $1
EOF
    mv "$runtime/config.new" "$runtime/config"
}

wait_gaps() {
    expected=$1
    i=0
    while [ "$i" -lt 50 ]; do
        if tessa-ctl config 2>/dev/null | grep -qx "gaps $expected"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "config did not become gaps=$expected" >&2
    tessa-ctl config 2>/dev/null | head -20 >&2 || true
    return 1
}

write_config 5

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
wait_gaps 5
grep -q "config watch: watching" "$runtime/tessa.log"
echo "initial watch: ok"

write_config 31
wait_gaps 31
grep -q "config watch: reloading after file change" "$runtime/tessa.log"
echo "atomic save reload: ok"

cat > "$runtime/config.new" <<EOF
panel = false
xwayland = false
xim = false
gaps = nope
EOF
mv "$runtime/config.new" "$runtime/config"
sleep 0.5
wait_gaps 31
grep -q "config reload rejected" "$runtime/tessa.log"
echo "invalid edit kept previous config: ok"

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
echo "config watch test passed"
