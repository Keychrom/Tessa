#!/bin/sh
# Verify the v1-compatible external layout-helper protocol, timeout/fallback
# path, and restart. Requires cc and python3. Run from the repository root:
#   sh tests/layout-helper.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=${TESSA_BIN:-$root/zig-out/bin}

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v cc >/dev/null 2>&1; then
    echo "cc not found; skipping layout helper test"
    exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found; skipping layout helper test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-helper.XXXXXX")
tpid=
pids=
cleanup() {
    for pid in ${pids:-}; do kill "$pid" 2>/dev/null || true; done
    for pid in ${pids:-}; do wait "$pid" 2>/dev/null || true; done
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "$tpid" 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"

cat > "$runtime/helper.py" <<'PY'
#!/usr/bin/env python3
import sys

windows = []
for raw in sys.stdin:
    fields = raw.rstrip("\n").split("\t")
    if not fields:
        continue
    if fields[0] == "WINDOW" and len(fields) >= 2:
        windows.append(fields[1])
    elif fields[0] == "END":
        for index, window_id in enumerate(windows):
            print(f"RECT\t{window_id}\t{40 + index * 60}\t{30 + index * 40}\t400\t300", flush=True)
        print("END", flush=True)
        windows = []
PY

write_config() {
    helper=$1
    cat > "$runtime/config" <<EOF
panel = false
xwayland = false
layout = custom
layout_helper = $helper
layout_helper_timeout = 500
EOF
}

write_config "python3 $runtime/helper.py"

cc -O2 -I"$root/protocol" -o "$runtime/window-test" \
    "$root/tests/rule-visuals/window.c" \
    "$root/protocol/xdg-shell-client-protocol.c" \
    $(pkg-config --cflags --libs wayland-client)

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

wait_custom_rects() {
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        if printf '%s\n' "$state" | awk -F '	' '
            $1 == "WIN" {
                n++
                if ($12 != 400 || $13 != 300) bad = 1
                xs[$10] = 1
                ys[$11] = 1
            }
            END {
                nx = 0
                ny = 0
                for (x in xs) nx++
                for (y in ys) ny++
                if (n != 3 || bad || nx != 3 || ny != 3 ||
                    !("40" in xs) || !("100" in xs) || !("160" in xs) ||
                    !("30" in ys) || !("70" in ys) || !("110" in ys)) exit 1
            }' 2>/dev/null; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "helper rectangles were not applied" >&2
    printf '%s\n' "$state" >&2
    exit 1
}

wait_state "OUT HEADLESS-1 1 1 custom"
tessa-ctl config >"$runtime/config.out"
grep -q "layout custom" "$runtime/config.out"
grep -q "layout_helper python3 $runtime/helper.py" "$runtime/config.out"
grep -q "layout_helper_timeout 500" "$runtime/config.out"
echo "helper config: ok"

"$runtime/window-test" helper-a HelperA >"$runtime/a.log" 2>&1 &
pids="$pids $!"
"$runtime/window-test" helper-b HelperB >"$runtime/b.log" 2>&1 &
pids="$pids $!"
"$runtime/window-test" helper-c HelperC >"$runtime/c.log" 2>&1 &
pids="$pids $!"
wait_state "OCC 1 3"
wait_custom_rects
echo "custom layout protocol: ok"

write_config "/bin/false"
tessa-ctl dispatch reload
sleep 0.3
state=$(tessa-ctl state)
wait_state "OUT HEADLESS-1 1 1 custom"
if printf '%s\n' "$state" | awk -F '	' '
    $1 == "WIN" && $12 == 400 && $13 == 300 { found = 1 }
    END { exit found ? 0 : 1 }'; then
    echo "broken helper did not fall back to the built-in layout" >&2
    printf '%s\n' "$state" >&2
    exit 1
fi
echo "helper failure fallback: ok"

write_config "python3 $runtime/helper.py"
tessa-ctl dispatch reload
wait_custom_rects
echo "helper restart after reload: ok"

ids=$(tessa-ctl state | awk -F '	' '
    $1 == "WIN" && ($8 == "HelperB" || $8 == "HelperC") { print $2 }')
for id in $ids; do
    tessa-ctl dispatch close "$id"
done
wait_state "OCC 1 1"
state=$(tessa-ctl state)
printf '%s\n' "$state" | awk -F '	' '
    $1 == "WIN" {
        n++
        if ($10 != 40 || $11 != 30 || $12 != 400 || $13 != 300) bad = 1
    }
    END {
        if (n != 1 || bad) exit 1
    }' || {
    echo "single-window custom layout was not applied" >&2
    printf '%s\n' "$state" >&2
    exit 1
}
echo "single-window custom layout: ok"

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
echo "layout helper test passed"
