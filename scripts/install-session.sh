#!/bin/sh
# Build and install Tessa, its panel, and a Wayland session file.
# Default prefix is ~/.local. For a system-wide install:
#   sudo PREFIX=/usr/local ./scripts/install-session.sh
set -eu
cd "$(dirname "$0")/.."
prefix="${PREFIX:-$HOME/.local}"

zig build -Doptimize=ReleaseSafe --prefix "$prefix"
install -Dm755 scripts/tessa-session "$prefix/bin/tessa-session"
desktop="$prefix/share/wayland-sessions/tessa.desktop"
install -Dm644 session/tessa.desktop "$desktop"
sed -i "s|^Exec=.*|Exec=$prefix/bin/tessa-session|" "$desktop"

echo "installed under $prefix"
echo "log out and choose 'Tessa' in your display manager"
