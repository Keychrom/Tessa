#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

# Require Zig 0.17, which is the `zig` package in current Arch Linux.
if [ -n "${ZIG:-}" ]; then
    zig_bin=$ZIG
else
    zig_bin=zig
fi

if ! command -v "$zig_bin" >/dev/null 2>&1; then
    echo "error: Zig executable not found: $zig_bin" >&2
    echo "Set ZIG=/path/to/zig-0.17 or install Zig 0.17." >&2
    exit 127
fi

version=$("$zig_bin" version)
case "$version" in
    0.17.*) ;;
    *)
        echo "error: Tessa requires Zig 0.17.x; $zig_bin reports $version." >&2
        echo "Set ZIG=/path/to/zig-0.17 or install Zig 0.17." >&2
        exit 1
        ;;
esac

exec "$zig_bin" build "$@"
