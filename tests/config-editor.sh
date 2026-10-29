#!/bin/sh
# Config check/diff preview and the interactive editor write-back path.
set -eu

cd "$(dirname "$0")/.."
root=$PWD
bin=$root/zig-out/bin

if [ ! -x "$bin/tessa" ] || [ ! -x "$bin/tessa-ctl" ]; then
    echo "build first: ./scripts/build.sh" >&2
    exit 1
fi

runtime=$(mktemp -d "${TMPDIR:-/tmp}/tessa-config-editor.XXXXXX")
tpid=
cleanup() {
    [ -n "${tpid:-}" ] && kill "$tpid" 2>/dev/null || true
    wait "${tpid:-0}" 2>/dev/null || true
    pkill -x tessa-panel 2>/dev/null || true
    rm -rf "$runtime"
}
trap cleanup EXIT INT TERM

mkdir -p "$runtime"
chmod 700 "$runtime"
cat > "$runtime/config" <<EOF
panel = false
xwayland = false
gaps = 12
border_width = 2
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

cat > "$runtime/candidate" <<EOF
panel = false
xwayland = false
gaps = 20
border_width = 3
EOF

tessa-ctl config-check "$runtime/candidate" >"$runtime/check.out"
grep -qF "config: ok" "$runtime/check.out"
echo "candidate check: ok"

cat > "$runtime/invalid" <<EOF
panel = false
not_a_real_key = 1
EOF

if tessa-ctl config-check "$runtime/invalid" >"$runtime/invalid.out" 2>&1; then
    echo "invalid config was accepted" >&2
    cat "$runtime/invalid.out" >&2
    exit 1
fi
grep -qF "diagnostic error" "$runtime/invalid.out"
grep -qF "unknown key 'not_a_real_key'" "$runtime/invalid.out"
echo "invalid candidate rejected: ok"

tessa-ctl config-diff "$runtime/candidate" >"$runtime/diff.out"
grep -qF -- "-gaps 12" "$runtime/diff.out"
grep -qF -- "+gaps 20" "$runtime/diff.out"
grep -qF -- "-border_width 2" "$runtime/diff.out"
grep -qF -- "+border_width 3" "$runtime/diff.out"
echo "diff preview: ok"

tessa-ctl config | grep -qF "gaps 12"
cat > "$runtime/editor.sh" <<'EOF'
#!/bin/sh
printf 'gaps = 32\n' >> "$1"
EOF
chmod +x "$runtime/editor.sh"

printf 'y\n' | EDITOR="$runtime/editor.sh" tessa-ctl config-edit >"$runtime/edit.out" 2>"$runtime/edit.err"
grep -qF "applied $runtime/config" "$runtime/edit.out"
grep -qF "gaps = 32" "$runtime/config"
i=0
while [ "$i" -lt 100 ]; do
    if tessa-ctl config 2>/dev/null | grep -qF "gaps 32"; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done
if [ "$i" -ge 100 ]; then
    echo "edited config was not reloaded" >&2
    cat "$runtime/edit.out" >&2
    cat "$runtime/edit.err" >&2
    exit 1
fi
echo "interactive edit + apply: ok"

cat > "$runtime/editor.sh" <<'EOF'
#!/bin/sh
printf 'bar_font = DejaVu Sans\n' >> "$1"
EOF
printf 'y\n' | EDITOR="$runtime/editor.sh" tessa-ctl config-edit >"$runtime/panel-edit.out" 2>"$runtime/panel-edit.err"
grep -qF "applied $runtime/config" "$runtime/panel-edit.out"
grep -qF "panel-only or comment changes" "$runtime/panel-edit.err"
grep -qF "bar_font = DejaVu Sans" "$runtime/config"
echo "panel-only edit: ok"

cat > "$runtime/editor.sh" <<'EOF'
#!/bin/sh
printf 'gaps = 48\n' >> "$1"
EOF
printf 'n\n' | EDITOR="$runtime/editor.sh" tessa-ctl config-edit >"$runtime/discard.out" 2>"$runtime/discard.err"
grep -qF "discarded" "$runtime/discard.out"
if grep -qF "gaps = 48" "$runtime/config"; then
    echo "discarded edit was written to the config" >&2
    exit 1
fi
echo "interactive edit discard: ok"

tessa-ctl quit
wait "$tpid" 2>/dev/null || true
tpid=
if grep -qE 'Assertion|panic|thread .* panic' "$runtime/tessa.log"; then
    echo "compositor did not shut down cleanly" >&2
    grep -E 'Assertion|panic|thread .* panic' "$runtime/tessa.log" >&2
    exit 1
fi
pkill -x tessa-panel 2>/dev/null || true

trap - EXIT INT TERM
rm -rf "$runtime"
echo "config editor test passed"
