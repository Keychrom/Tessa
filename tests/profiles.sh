#!/bin/sh
# Verify named layout profiles referenced by output and workspace rules.
# Requires foot. Run from the repository root after building:
#   sh tests/profiles.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping profile test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-profiles.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<'EOF'
panel = false
xwayland = false
layout = master
gaps = 10
outer_gaps = 10
master_count = 1
master_ratio = 0.58
profile = compact; gaps=0; outer-gaps=0; master-ratio=0.5; master-count=2
profile = grid3; layout=grid; grid-columns=3; gaps=6; outer-gaps=2
output-rule = output=HEADLESS-*; profile=compact; gaps=4
workspace-rule = ws=2; profile=grid3
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

wait_occ() {
    ws=$1
    expected=$2
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        if printf '%s\n' "$state" | grep -qE "^OCC[[:space:]]+$ws[[:space:]]+$expected$"; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "workspace $ws occupancy did not become $expected" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

wait_state "OUT HEADLESS-1 1 1 master"
tessa-ctl config >"$runtime/config.out"
grep -q "^profile_count 2$" "$runtime/config.out"
grep -q "^workspace_rule_count 1$" "$runtime/config.out"
grep -q "^profile compact master 0 0 0.500 2" "$runtime/config.out"
grep -q "^profile grid3 grid 6 2" "$runtime/config.out"
grep -q "^layout_ws 2 grid$" "$runtime/config.out"
grep -q "^workspace_tuning 2 6 2 0.580$" "$runtime/config.out"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
tessa-ctl config --json >"$runtime/config.json"
grep -q '"profile_count":2' "$runtime/config.json"
grep -q '"profiles":\[' "$runtime/config.json"
grep -q '"name":"grid3","layout":"grid"' "$runtime/config.json"
echo "profile config: ok"

n=1
while [ "$n" -le 4 ]; do
    tessa-ctl spawn foot -T "out-$n"
    n=$((n + 1))
done
wait_occ 1 4
sleep 0.3
tessa-ctl state >"$runtime/state1"
awk -F '	' '
$1 == "WIN" {
    n++
    w[n] = $12
    h[n] = $13
    x[$10] = 1
    y[$11] = 1
}
END {
    if (n != 4) {
        printf "expected 4 output-profile windows, got %d\n", n > "/dev/stderr"
        exit 1
    }
    for (i = 1; i <= n; i++) {
        if (w[i] != 958 || h[i] != 538) {
            printf "output profile geometry wrong: %dx%d\n", w[i], h[i] > "/dev/stderr"
            exit 1
        }
    }
    nx = 0
    ny = 0
    for (k in x) nx++
    for (k in y) ny++
    if (nx != 2 || ny != 2 || !(0 in x) || !(962 in x) || !(0 in y) || !(542 in y)) {
        printf "output profile gaps/ratio/count were not applied\n" > "/dev/stderr"
        exit 1
    }
}' "$runtime/state1"
echo "output profile: ok"

tessa-ctl workspace 2
wait_state "OUT HEADLESS-1 2 1 grid"
n=1
while [ "$n" -le 4 ]; do
    tessa-ctl spawn foot -T "ws2-$n"
    n=$((n + 1))
done
wait_occ 2 4
sleep 0.3
tessa-ctl state >"$runtime/state2"
awk -F '	' '
$1 == "WIN" && $3 == 2 {
    n++
    w[n] = $12
    h[n] = $13
    x[$10] = 1
    y[$11] = 1
}
END {
    if (n != 4) {
        printf "expected 4 workspace-profile windows, got %d\n", n > "/dev/stderr"
        exit 1
    }
    for (i = 1; i <= n; i++) {
        if (w[i] != 634 || h[i] != 535) {
            printf "workspace profile geometry wrong: %dx%d\n", w[i], h[i] > "/dev/stderr"
            exit 1
        }
    }
    if (!(2 in x) || !(642 in x) || !(1282 in x) || !(643 in x)) {
        printf "workspace profile grid columns were not applied\n" > "/dev/stderr"
        exit 1
    }
    if (!(2 in y) || !(543 in y)) {
        printf "workspace profile gaps were not applied\n" > "/dev/stderr"
        exit 1
    }
}' "$runtime/state2"
echo "workspace profile: ok"

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
echo "profile test passed"
