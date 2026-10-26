#!/bin/sh
# Development session with no GPU/display. Useful over SSH.
# Start this in one shell and use scripts/screenshot.sh in another.
set -eu
cd "$(dirname "$0")/.."

if [ ! -x zig-out/bin/tessa ]; then
    echo "tessa is not built; run scripts/build.sh first" >&2
    exit 1
fi

runtime="${TESSA_RUNTIME_DIR:-/tmp/tessa-headless}"
mkdir -p "$runtime"
chmod 700 "$runtime"

export XDG_RUNTIME_DIR="$runtime"
export WLR_BACKENDS=headless
export WLR_RENDERER=pixman
export WLR_HEADLESS_OUTPUTS="${WLR_HEADLESS_OUTPUTS:-1}"
export PATH="$PWD/zig-out/bin:$PATH"

rm -f "$runtime/tessa.sock"
exec ./zig-out/bin/tessa "$@"
