#!/bin/sh
# Verify that mosaic falls back before tiles overlap or shrink below the minimum.
# Requires foot. Run from the repository root after building:
#   sh tests/layout-geometry.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping layout geometry test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-layout.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = false
xwayland = false
layout = master
master_count = 2
grid_columns = 4
workspace-rule = ws=1; gaps=0; outer-gaps=0; master-ratio=0.5
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
tessa-ctl config >"$runtime/config.out"
grep -q "workspace_tuning 1 0 0 0.500" "$runtime/config.out"
echo "workspace tuning config: ok"
n=1
while [ "$n" -le 8 ]; do
    tessa-ctl spawn foot -T "tile-$n"
    n=$((n + 1))
done
wait_state "OCC 1 8"

tessa-ctl layout mosaic
sleep 0.3
state=$(tessa-ctl state)
printf '%s\n' "$state" >"$runtime/state"

awk -F '	' '
$1 == "WIN" {
    n++
    id[n] = $2
    x[n] = $10
    y[n] = $11
    w[n] = $12
    h[n] = $13
}
END {
    if (n != 8) {
        printf "expected 8 tiled windows, got %d\n", n > "/dev/stderr"
        exit 1
    }
    for (i = 1; i <= n; i++) {
        if (w[i] < 160 || h[i] < 160) {
            printf "window %s is smaller than the minimum: %dx%d\n", id[i], w[i], h[i] > "/dev/stderr"
            exit 1
        }
        for (j = i + 1; j <= n; j++) {
            if (x[i] < x[j] + w[j] && x[j] < x[i] + w[i] &&
                y[i] < y[j] + h[j] && y[j] < y[i] + h[i]) {
                printf "windows %s and %s overlap\n", id[i], id[j] > "/dev/stderr"
                exit 1
            }
        }
    }
}' "$runtime/state"

echo "mosaic minimum-size fallback: ok"

tessa-ctl layout grid
sleep 0.3
state=$(tessa-ctl state)
printf '%s\n' "$state" >"$runtime/state"
awk -F '	' '
$1 == "WIN" {
    n++
    x[n] = $10
    y[n] = $11
    w[n] = $12
    h[n] = $13
}
END {
    if (n != 8) {
        printf "expected 8 grid windows, got %d\n", n > "/dev/stderr"
        exit 1
    }
    for (i = 1; i <= n; i++) {
        xs[x[i]] = 1
        ys[y[i]] = 1
        for (j = i + 1; j <= n; j++) {
            if (x[i] < x[j] + w[j] && x[j] < x[i] + w[i] &&
                y[i] < y[j] + h[j] && y[j] < y[i] + h[i]) {
                printf "grid windows %d and %d overlap\n", i, j > "/dev/stderr"
                exit 1
            }
        }
    }
    nx = 0
    ny = 0
    for (k in xs) nx++
    for (k in ys) ny++
    if (nx != 4 || ny != 2) {
        printf "grid_columns=4 produced %d columns and %d rows\n", nx, ny > "/dev/stderr"
        exit 1
    }
    if (x[1] != 0 || y[1] != 0) {
        printf "workspace gaps/outer-gaps were not applied: first tile at %d,%d\n", x[1], y[1] > "/dev/stderr"
        exit 1
    }
}' "$runtime/state"
echo "configured grid columns: ok"

tessa-ctl layout master
sleep 0.3
state=$(tessa-ctl state)
printf '%s\n' "$state" >"$runtime/state"
awk -F '	' '
$1 == "WIN" {
    n++
    x[n] = $10
    y[n] = $11
    w[n] = $12
    h[n] = $13
}
END {
    if (n != 8) {
        printf "expected 8 master windows, got %d\n", n > "/dev/stderr"
        exit 1
    }
    if (!(x[1] == x[2] && w[1] == w[2] && y[1] != y[2] && x[3] > x[1])) {
        printf "master_count=2 did not stack the first two windows in the master column\n" > "/dev/stderr"
        exit 1
    }
    if (!(x[1] == 0 && w[1] == 960 && y[2] == 540 && x[3] == 960)) {
        printf "workspace master-ratio did not produce a 50%% master column\n" > "/dev/stderr"
        exit 1
    }
}' "$runtime/state"
echo "configured master count: ok"

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
echo "layout geometry test passed"
