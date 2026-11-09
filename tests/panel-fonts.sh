#!/bin/sh
# Verify that the panel selects the locale-appropriate CJK font fallback.
#   sh tests/panel-fonts.sh
set -eu

cd "$(dirname "$0")/.."
bin=${TESSA_BIN_DIR:-$PWD/zig-out/bin}

if [ ! -x "$bin/tessa-panel" ]; then
    echo "build first: ./scripts/build.sh panel" >&2
    exit 1
fi

check() {
    lang=$1
    expected=$2
    out=$(env -u LC_ALL -u LC_CTYPE LANG="$lang" TESSA_DEBUG=1 "$bin/tessa-panel" --check 2>&1) || {
        echo "$out" >&2
        exit 1
    }
    if ! printf '%s\n' "$out" | grep -q "font fallback=.*$expected"; then
        echo "missing '$expected' fallback for LANG=$lang" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
}

check ja_JP.UTF-8 "Noto Sans CJK JP"
check ko_KR.UTF-8 "Noto Sans CJK KR"
check zh_CN.UTF-8 "Noto Sans CJK SC"
check zh_TW.UTF-8 "Noto Sans CJK TC"

echo "panel font fallback: ok"
