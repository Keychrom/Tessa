#!/bin/sh
# Verify config-defined event-to-action rules, expression filtering, and
# coexistence with unconditional hooks. Requires foot.
#   sh tests/event-rules.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping event rules test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-event-rules.XXXXXX")
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
window-rule = title=WsTwo*; workspace=2
event-rule = window-open; match=app ~ "^foot$" && ws == "2"; run=printf '%s:%s:%s\n' "\$TESSA_EVENT" "\$TESSA_TITLE" "\$TESSA_WORKSPACE" >> $runtime/matches
event-rule = window-open; match=title == "IdRule" && id ~ "^[0-9]+\$"; run=touch $runtime/id-rule
event-rule = workspace-change; match=event == "workspace-change" && ws == "3"; run=touch $runtime/ws-rule
event-rule = window-open; match=title == "NeverMatch"; run=touch $runtime/never
hook = window-open touch $runtime/hook-fired
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

wait_file() {
    path=$1
    i=0
    while [ ! -e "$path" ]; do
        i=$((i + 1))
        if [ "$i" -ge 50 ]; then
            echo "event rule did not run: $path" >&2
            cat "$runtime/tessa.log" >&2
            exit 1
        fi
        sleep 0.1
    done
}

tessa-ctl config >"$runtime/config.out"
grep -q "event_rule_count 4" "$runtime/config.out"
grep -q "event_rule window-open" "$runtime/config.out"
tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
tessa-ctl config --json >"$runtime/config.json"
grep -q '"event_rule_count":4' "$runtime/config.json"
grep -q '"event_rules":\[' "$runtime/config.json"
echo "event rule config: ok"

wait_state "MODE default"
tessa-ctl spawn foot -T WsTwo
wait_state "OCC 2 1"
wait_file "$runtime/matches"
wait_file "$runtime/hook-fired"
match=$(cat "$runtime/matches")
if [ "$match" != "window-open:WsTwo:2" ]; then
    echo "event rule received unexpected context: $match" >&2
    exit 1
fi
echo "window-open expression match: ok"

tessa-ctl spawn foot -T IdRule
wait_state "OCC 1 1"
wait_file "$runtime/id-rule"
echo "window id expression: ok"

tessa-ctl spawn foot -T WsOne
wait_state "OCC 1 2"
sleep 0.3
count=$(wc -l <"$runtime/matches")
if [ "$count" -ne 1 ]; then
    echo "event rule matched a window on the wrong workspace" >&2
    cat "$runtime/matches" >&2
    exit 1
fi
if [ -e "$runtime/never" ]; then
    echo "event rule with a false expression ran" >&2
    exit 1
fi
echo "expression filtering: ok"

tessa-ctl workspace 3
wait_state "OUT HEADLESS-1 3 1 master"
wait_file "$runtime/ws-rule"
echo "workspace-change rule: ok"

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
echo "event rules test passed"
