#!/bin/sh
# Build a Debian binary package without installing it.
# Usage:
#   ZIG=$HOME/.local/zig-0.16.0/zig ./scripts/build-deb.sh
set -eu

cd "$(dirname "$0")/.."
root=$PWD

for tool in dpkg-buildpackage dpkg-deb dpkg-parsechangelog dh fakeroot; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing packaging tool: $tool" >&2
        echo "install with: sudo apt install debhelper dpkg-dev fakeroot" >&2
        exit 1
    fi
done

if [ -n "${ZIG:-}" ]; then
    zig=$ZIG
elif command -v zig >/dev/null 2>&1; then
    zig=$(command -v zig)
elif [ -x "$HOME/.local/zig-0.16.0/zig" ]; then
    zig=$HOME/.local/zig-0.16.0/zig
else
    echo "Zig 0.16.0 is required; set ZIG=/path/to/zig" >&2
    exit 1
fi

version=$("$zig" version)
case "$version" in
    0.16.*) ;;
    *)
        echo "Zig 0.16.x is required; found $version" >&2
        exit 1
        ;;
esac

zig_dir=$(CDPATH= cd -- "$(dirname -- "$zig")" && pwd)
package_version=$(dpkg-parsechangelog -SVersion)
rm -rf dist
mkdir -p dist

# Ubuntu 26.04 ships Zig 0.14 as 'zig'; skip the declared build dependency and
# use the verified 0.16 toolchain above instead.
PATH="$zig_dir:$PATH" dpkg-buildpackage -b -us -uc -d

for artifact in \
    "$root/../tessa_${package_version}"*.deb \
    "$root/../tessa_${package_version}"*.buildinfo \
    "$root/../tessa_${package_version}"*.changes
do
    [ -e "$artifact" ] || continue
    cp "$artifact" dist/
done

deb=$(find dist -maxdepth 1 -name '*.deb' -print -quit)
if [ -z "$deb" ]; then
    echo "dpkg-buildpackage did not produce a .deb" >&2
    exit 1
fi

dpkg-deb --info "$deb"
echo
echo "package: $deb"
