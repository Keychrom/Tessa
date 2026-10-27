#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

# Prefer an explicitly selected or version-suffixed toolchain. Arch Linux
# packages Zig 0.17 as `zig` but provides Zig 0.16 as `zig-0.16`.
if [ -n "${ZIG:-}" ]; then
    zig_bin=$ZIG
elif command -v zig-0.16 >/dev/null 2>&1; then
    zig_bin=zig-0.16
else
    zig_bin=zig
fi

if ! command -v "$zig_bin" >/dev/null 2>&1; then
    echo "error: Zig executable not found: $zig_bin" >&2
    echo "Set ZIG=/path/to/zig-0.16 or install Zig 0.16." >&2
    exit 127
fi

version=$("$zig_bin" version)
case "$version" in
    0.16.*) ;;
    *)
        echo "error: Tessa requires Zig 0.16.x; $zig_bin reports $version." >&2
        echo "Set ZIG=/path/to/zig-0.16 or install Zig 0.16." >&2
        exit 1
        ;;
esac

exec "$zig_bin" build "$@"
