#!/bin/sh
# Verify regex/boolean window-rule expressions and per-rule border colors.
# Requires foot. The rendered border check additionally needs grim and
# ImageMagick convert and is skipped when they are unavailable.
#   sh tests/rule-expressions.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi
if ! command -v foot >/dev/null 2>&1; then
    echo "foot not found; skipping rule expression test"
    exit 0
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-rule-expr.XXXXXX")
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
animations = false
shadows = false
corner_radius = 0
border_active = #ff7755
border_inactive = #202634
window-rule = match=(app ~ "^foot$" && title ~ "^Expr(Rule|Alt)$") && (output ~ "^HEADLESS" || output == "none") && !(title == "Exclude"); float=true; size=420x260; position=60,60; border-active=#12ab34; border-inactive=#abcdef
window-rule = title=OtherRule*; float=true; size=300x200; position=520,60; border-active=#123456; border-inactive=#654321
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

wait_win() {
    title=$1
    field=$2
    expected=$3
    i=0
    while [ "$i" -lt 100 ]; do
        state=$(tessa-ctl state 2>/dev/null || true)
        got=$(printf '%s\n' "$state" | awk -F '	' -v t="$title" -v f="$field" '
            $1 == "WIN" && $8 == t { print $(f + 0); exit }')
        if [ "$got" = "$expected" ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 0.1
    done
    echo "window '$title' field $field did not become '$expected'" >&2
    printf '%s\n' "$state" >&2
    cat "$runtime/tessa.log" >&2
    exit 1
}

win_field() {
    title=$1
    field=$2
    tessa-ctl state | awk -F '	' -v t="$title" -v f="$field" \
        '$1 == "WIN" && $8 == t { print $(f + 0); exit }'
}

tessa-ctl config-check >"$runtime/check.out"
grep -q "config: ok" "$runtime/check.out"
tessa-ctl config >"$runtime/config.out"
grep -q "rule_count 2" "$runtime/config.out"
echo "expression config: ok"

tessa-ctl spawn foot -T ExprRule
tessa-ctl spawn foot -T ExprAlt
tessa-ctl spawn foot -T OtherRule
tessa-ctl spawn foot -T TiledRule
wait_state "OCC 1 4"

wait_win ExprRule 5 1
wait_win ExprRule 12 420
wait_win ExprRule 13 260
wait_win ExprAlt 5 1
wait_win ExprAlt 12 420
wait_win OtherRule 5 1
wait_win OtherRule 12 300
wait_win TiledRule 5 0
echo "boolean/regex expression matching: ok"

if ! command -v grim >/dev/null 2>&1 || ! command -v convert >/dev/null 2>&1; then
    echo "grim or ImageMagick not found; skipping rendered border check"
else
    expr_id=$(win_field ExprRule 2)
    other_id=$(win_field OtherRule 2)
    x=$(win_field ExprRule 10)
    y=$(win_field ExprRule 11)
    w=$(win_field ExprRule 12)
    px=$((x + w / 2))
    py=$((y + 1))

    pixel() {
        convert "$1" -crop 1x1+"$2"+"$3" +repage -format '%[pixel:p{0,0}]' info:
    }

    tessa-ctl dispatch focus "$expr_id"
    wait_state "FOCUSED $expr_id"
    sleep 0.3
    grim -o HEADLESS-1 "$runtime/active.png"
    active=$(pixel "$runtime/active.png" "$px" "$py")
    case "$active" in
        *"18,171,52"*) ;;
        *)
            echo "rule border-active color was not rendered (got $active)" >&2
            exit 1
            ;;
    esac

    tessa-ctl dispatch focus "$other_id"
    wait_state "FOCUSED $other_id"
    sleep 0.3
    grim -o HEADLESS-1 "$runtime/inactive.png"
    inactive=$(pixel "$runtime/inactive.png" "$px" "$py")
    case "$inactive" in
        *"171,205,239"*) ;;
        *)
            echo "rule border-inactive color was not rendered (got $inactive)" >&2
            exit 1
            ;;
    esac
    echo "per-rule active/inactive border colors: ok"
fi

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
echo "rule expression test passed"
