#!/usr/bin/env bash
# Install Tessa from source on Ubuntu or Debian.
#
# Tessa needs Zig 0.17 and wlroots 0.20, which current Ubuntu/Debian releases
# do not all provide. This script installs the build dependencies, downloads a
# matching Zig, builds missing Wayland/wlroots pieces under /opt/tessa, and
# installs Tessa without replacing the distribution's Wayland libraries.
#
# Usage:
#   ./install.sh                 # full install
#   ./install.sh --plain         # no scenefx effects
#   ./install.sh --minimal       # skip kitty/fonts/IME/portal extras
#   ./install.sh --check         # print the plan without changing anything
#
# Run from the Tessa source checkout as a normal user; the script uses sudo.
set -euo pipefail

PREFIX=${TESSA_PREFIX:-/opt/tessa}
WITH_RECOMMENDED=1
SCENEFX=1
CHECK=0
ZIG_VERSION=0.17.1

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --plain) SCENEFX=0 ;;
        --minimal) WITH_RECOMMENDED=0 ;;
        --check) CHECK=1 ;;
        --prefix=*) PREFIX=${1#*=} ;;
        --prefix)
            [ "$#" -ge 2 ] || die "--prefix needs a directory"
            PREFIX=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

case "$PREFIX" in
    /*) ;;
    *) die "prefix must be an absolute path: $PREFIX" ;;
esac
case "$PREFIX" in
    /|/usr|/usr/local|/opt|"$HOME"|*' '*) die "unsafe prefix: $PREFIX" ;;
esac
case "$PREFIX" in
    *[!A-Za-z0-9_./-]*) die "prefix contains unsupported characters: $PREFIX" ;;
esac

if [ ! -f build.zig ] || [ ! -f scripts/build.sh ] || [ ! -f src/main.zig ]; then
    die "run this script from the Tessa source checkout"
fi

if [ ! -r /etc/os-release ]; then
    die "cannot read /etc/os-release; Ubuntu or Debian is required"
fi
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
    ubuntu|debian) ;;
    *)
        case " ${ID_LIKE:-} " in
            *ubuntu*|*debian*) ;;
            *) die "unsupported distribution: ${ID:-unknown} (Ubuntu/Debian required)" ;;
        esac
        ;;
esac

case "$(uname -m)" in
    x86_64|amd64)
        zig_arch=x86_64
        zig_sha=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a
        ;;
    aarch64|arm64)
        zig_arch=aarch64
        zig_sha=a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795
        ;;
    *) die "unsupported architecture: $(uname -m)" ;;
esac
zig_url="https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
else
    die "sudo is required (run as root or install sudo)"
fi

CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/tessa-install
SRC_DIR=$CACHE_DIR/src
BUILD_ROOT=$CACHE_DIR/build
ZIG_ARCHIVE=$CACHE_DIR/zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz
ZIG_DIR=$CACHE_DIR/zig-${zig_arch}-linux-${ZIG_VERSION}
ZIG_BIN=
export GIT_TERMINAL_PROMPT=0

APT_PACKAGES=(
    build-essential pkg-config git curl ca-certificates xz-utils
    meson ninja-build bison flex patchelf
    libwayland-dev wayland-protocols libxkbcommon-dev libpixman-1-dev libdrm-dev
    libinput-dev libevdev-dev libmtdev-dev libwacom-dev libseat-dev libudev-dev
    libegl-dev libgles-dev libgbm-dev libglvnd-dev
    libcairo2-dev libpango1.0-dev libglib2.0-dev libgdk-pixbuf-2.0-dev libfontconfig1-dev
    libdisplay-info-dev libliftoff-dev liblcms2-dev hwdata
    libxcb1-dev libxcb-dri3-dev libxcb-present-dev libxcb-render0-dev
    libxcb-render-util0-dev libxcb-shm0-dev libxcb-xfixes0-dev libxcb-xinput-dev
    libx11-xcb-dev
    libxml2-dev libffi-dev libexpat1-dev libpciaccess-dev glslang-tools
)

RECOMMENDED_PACKAGES=(
    kitty fonts-inter fonts-jetbrains-mono fonts-noto-cjk
    fcitx5 fcitx5-mozc
    xdg-desktop-portal xdg-desktop-portal-wlr pipewire wireplumber dbus-user-session
    wlr-randr grim xwayland
    network-manager bluez power-profiles-daemon upower policykit-1
)

have_pkg() {
    command -v pkg-config >/dev/null 2>&1 || return 1
    pkg-config --exists "$1" 2>/dev/null &&
        pkg-config --atleast-version="$2" "$1" 2>/dev/null
}

pkg_ver() {
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists "$1" 2>/dev/null; then
        pkg-config --modversion "$1" 2>/dev/null
    else
        echo missing
    fi
}

print_dep() {
    local label=$1 pkg=$2 min=$3
    if have_pkg "$pkg" "$min"; then
        printf '  %-22s %s (system)\n' "$label" "$(pkg_ver "$pkg")"
    else
        printf '  %-22s %s (build from source)\n' "$label" "$(pkg_ver "$pkg")"
    fi
}

if [ "$CHECK" -eq 1 ]; then
    printf 'Distribution: %s %s\n' "${ID:-unknown}" "${VERSION_ID:-unknown}"
    printf 'Architecture: %s\n' "$(uname -m)"
    printf 'Install prefix: %s\n' "$PREFIX"
    printf 'scenefx effects: %s\n' "$([ "$SCENEFX" -eq 1 ] && echo enabled || echo disabled)"
    if [ -n "${ZIG:-}" ]; then
        printf 'Zig: %s (from ZIG)\n' "$ZIG"
    elif command -v zig >/dev/null 2>&1; then
        printf 'Zig: %s (system)\n' "$(zig version 2>/dev/null || echo unknown)"
    else
        printf 'Zig: will install %s\n' "$ZIG_VERSION"
    fi
    printf 'Dependencies:\n'
    print_dep 'Wayland' wayland-server 1.24.0
    print_dep 'wayland-protocols' wayland-protocols 1.47
    print_dep 'libdrm' libdrm 2.4.129
    print_dep 'libxkbcommon' xkbcommon 1.8.0
    print_dep 'pixman' pixman-1 0.43.0
    print_dep 'libdisplay-info' libdisplay-info 0.2.0
    print_dep 'libinput' libinput 1.27.0
    print_dep 'wlroots 0.20' wlroots-0.20 0.20.0
    if [ "$SCENEFX" -eq 1 ]; then
        print_dep 'scenefx 0.5' scenefx-0.5 0.5
    fi
    printf '\nWould install apt packages and build any missing pieces under %s.\n' "$PREFIX"
    exit 0
fi

log "installing build dependencies with apt"
"${SUDO[@]}" apt-get update
apt_args=(
    apt-get install -y --no-install-recommends
    -o Dpkg::Options::=--force-confdef
    -o Dpkg::Options::=--force-confold
)
install_list=("${APT_PACKAGES[@]}")
if apt-cache show libwlroots-0.20-dev >/dev/null 2>&1; then
    install_list+=(libwlroots-0.20-dev)
fi
if [ "$SCENEFX" -eq 1 ] && apt-cache show libscenefx-0.5-dev >/dev/null 2>&1; then
    install_list+=(libscenefx-0.5-dev)
fi
if [ "$WITH_RECOMMENDED" -eq 1 ]; then
    install_list+=("${RECOMMENDED_PACKAGES[@]}")
fi
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive "${apt_args[@]}" "${install_list[@]}"

command -v meson >/dev/null 2>&1 || die "meson is missing after apt install"
meson_version=$(meson --version)
dpkg --compare-versions "$meson_version" ge 1.3 ||
    die "meson >= 1.3 is required; found $meson_version (Debian 12 is too old)"

# Keep private builds ahead of the distribution's headers and libraries, but
# do not put them in the global loader path. Installed binaries get an RPATH.
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

select_zig() {
    if [ -n "${ZIG:-}" ]; then
        [ -x "$ZIG" ] || die "ZIG is not executable: $ZIG"
        ZIG_BIN=$ZIG
        return
    fi
    if command -v zig >/dev/null 2>&1; then
        system_zig_version=$(zig version 2>/dev/null || true)
        case "$system_zig_version" in
            0.17.*)
                ZIG_BIN=$(command -v zig)
                log "using system Zig $system_zig_version"
                return
                ;;
            *)
                warn "ignoring system Zig $system_zig_version; using $ZIG_VERSION"
                ;;
        esac
    fi

    if [ ! -x "$ZIG_DIR/zig" ]; then
        mkdir -p "$CACHE_DIR"
        rm -rf "$ZIG_DIR"
        if [ ! -f "$ZIG_ARCHIVE" ]; then
            log "downloading Zig $ZIG_VERSION"
            curl -fL --retry 3 --connect-timeout 15 -o "$ZIG_ARCHIVE.part" "$zig_url"
            mv "$ZIG_ARCHIVE.part" "$ZIG_ARCHIVE"
        fi
        printf '%s  %s\n' "$zig_sha" "$ZIG_ARCHIVE" | sha256sum -c - >/dev/null ||
            die "Zig archive checksum mismatch: $ZIG_ARCHIVE"
        tar -xJf "$ZIG_ARCHIVE" -C "$CACHE_DIR"
    fi
    ZIG_BIN=$ZIG_DIR/zig
}

if [ -z "$ZIG_BIN" ]; then
    select_zig
fi
[ -x "$ZIG_BIN" ] || die "Zig executable not found: $ZIG_BIN"
case "$("$ZIG_BIN" version)" in
    0.17.*) ;;
    *) die "Tessa requires Zig 0.17.x; $ZIG_BIN reports $("$ZIG_BIN" version)" ;;
esac
log "Zig: $("$ZIG_BIN" version)"

mkdir -p "$SRC_DIR" "$BUILD_ROOT"
"${SUDO[@]}" install -d -m 0755 "$PREFIX"

build_meson() {
    local name=$1 repo=$2 tag=$3
    shift 3
    local src=$SRC_DIR/$name
    local build=$BUILD_ROOT/$name

    log "building $name $tag"
    if [ -d "$src/.git" ]; then
        if ! git -C "$src" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
            git -C "$src" fetch --depth=1 origin "refs/tags/$tag:refs/tags/$tag"
        fi
        git -C "$src" checkout -q --force "refs/tags/$tag"
    else
        rm -rf "$src"
        git clone --depth=1 --branch "$tag" "$repo" "$src"
    fi

    if [ -d "$build" ]; then
        meson setup --wipe "$build" "$src" \
            --prefix="$PREFIX" --libdir=lib --buildtype=release \
            --wrap-mode=nodownload "$@"
    else
        meson setup "$build" "$src" \
            --prefix="$PREFIX" --libdir=lib --buildtype=release \
            --wrap-mode=nodownload "$@"
    fi
    ninja -C "$build"
    "${SUDO[@]}" meson install -C "$build"
}

ensure_wayland() {
    have_pkg wayland-server 1.24.0 && return
    build_meson wayland https://gitlab.freedesktop.org/wayland/wayland.git 1.24.0 \
        -Dlibraries=true -Dscanner=true -Dtests=false \
        -Ddocumentation=false -Ddtd_validation=false
}

ensure_wayland_protocols() {
    have_pkg wayland-protocols 1.47 && return
    build_meson wayland-protocols \
        https://gitlab.freedesktop.org/wayland/wayland-protocols.git 1.47 \
        -Dtests=false
}

ensure_libdrm() {
    have_pkg libdrm 2.4.129 && return
    build_meson libdrm https://gitlab.freedesktop.org/mesa/drm.git libdrm-2.4.131 \
        -Dtests=false -Dman-pages=disabled -Dinstall-test-programs=false -Dcairo-tests=disabled
}

ensure_xkbcommon() {
    have_pkg xkbcommon 1.8.0 && return
    build_meson libxkbcommon https://github.com/xkbcommon/libxkbcommon.git \
        xkbcommon-1.13.1 \
        -Denable-x11=false -Denable-wayland=false -Denable-docs=false \
        -Denable-tools=false -Denable-xkbregistry=false
}

ensure_pixman() {
    have_pkg pixman-1 0.43.0 && return
    build_meson pixman https://gitlab.freedesktop.org/pixman/pixman.git pixman-0.46.4 \
        -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled
}

ensure_display_info() {
    have_pkg libdisplay-info 0.2.0 && return
    build_meson libdisplay-info \
        https://gitlab.freedesktop.org/emersion/libdisplay-info.git 0.3.0
}

ensure_libinput() {
    have_pkg libinput 1.27.0 && return
    build_meson libinput https://gitlab.freedesktop.org/libinput/libinput.git 1.29.2 \
        -Dtests=false -Ddocumentation=false -Ddebug-gui=false \
        -Dinstall-tests=false -Dlibwacom=true -Dmtdev=true
}

ensure_wayland
ensure_wayland_protocols
ensure_libdrm
ensure_xkbcommon
ensure_pixman
ensure_display_info
ensure_libinput

if have_pkg wlroots-0.20 0.20.0; then
    log "using wlroots $(pkg_ver wlroots-0.20)"
else
    build_meson wlroots https://gitlab.freedesktop.org/wlroots/wlroots.git 0.20.2 \
        -Dexamples=false -Dxwayland=disabled -Drenderers=gles2 \
        -Dbackends=auto -Dallocators=auto -Dsession=enabled \
        -Dlibliftoff=auto -Dcolor-management=auto -Dxcb-errors=disabled
fi

if [ "$SCENEFX" -eq 1 ]; then
    if have_pkg scenefx-0.5 0.5; then
        log "using scenefx $(pkg_ver scenefx-0.5)"
    else
        build_meson scenefx https://github.com/wlrfx/scenefx.git 0.5 \
            -Dexamples=false
    fi
fi

log "building Tessa"
if [ "$SCENEFX" -eq 1 ]; then
    ZIG="$ZIG_BIN" ./scripts/build.sh -Doptimize=ReleaseSafe -Dscenefx=true
else
    ZIG="$ZIG_BIN" ./scripts/build.sh -Doptimize=ReleaseSafe -Dscenefx=false
fi

for bin in tessa tessa-panel tessa-ctl; do
    [ -x "zig-out/bin/$bin" ] || die "build did not produce zig-out/bin/$bin"
done

log "installing Tessa under $PREFIX"
"${SUDO[@]}" install -d -m 0755 "$PREFIX/bin" "$PREFIX/share/tessa"
for bin in tessa tessa-panel tessa-ctl; do
    "${SUDO[@]}" install -Dm755 "zig-out/bin/$bin" "$PREFIX/bin/$bin"
done
"${SUDO[@]}" install -Dm755 scripts/tessa-session "$PREFIX/bin/tessa-session"
"${SUDO[@]}" install -Dm755 tools/tessa-panel-compat.py "$PREFIX/bin/tessa-panel-compat"
"${SUDO[@]}" install -Dm644 config/config.example "$PREFIX/share/tessa/config.example"
"${SUDO[@]}" install -Dm644 LICENSE "$PREFIX/share/licenses/tessa/LICENSE"

"${SUDO[@]}" install -d -m 0755 /usr/share/tessa/themes/vermilion-ink
"${SUDO[@]}" cp -a examples/themes/vermilion-ink/. /usr/share/tessa/themes/vermilion-ink/
"${SUDO[@]}" chown -R root:root /usr/share/tessa/themes/vermilion-ink
"${SUDO[@]}" install -Dm644 packaging/portal/tessa.portal \
    /usr/share/xdg-desktop-portal/portals/tessa.portal

session_file=$(mktemp)
trap 'rm -f "$session_file"' EXIT
cat >"$session_file" <<EOF
[Desktop Entry]
Name=Tessa
Comment=A quiet tiled Wayland desktop
Exec=/usr/local/bin/tessa-session
TryExec=/usr/local/bin/tessa-session
Type=Application
DesktopNames=Tessa
EOF
"${SUDO[@]}" install -Dm644 "$session_file" /usr/share/wayland-sessions/tessa.desktop

write_wrapper() {
    local name=$1 tmp
    tmp=$(mktemp)
    cat >"$tmp" <<EOF
#!/bin/sh
prefix='$PREFIX'
export PATH="\$prefix/bin:\$PATH"
exec "\$prefix/bin/$name" "\$@"
EOF
    "${SUDO[@]}" install -Dm755 "$tmp" "/usr/local/bin/$name"
    rm -f "$tmp"
}
for name in tessa tessa-panel tessa-ctl tessa-session tessa-panel-compat; do
    write_wrapper "$name"
done

# The private libraries live next to the binaries. Use legacy DT_RPATH (not
# RUNPATH) so an indirect dependency such as wlroots can also find the private
# libwayland/libdrm in the same directory.
log "setting private library paths"
for bin in tessa tessa-panel tessa-ctl; do
    # shellcheck disable=SC2016
    "${SUDO[@]}" patchelf --force-rpath --set-rpath '$ORIGIN/../lib' "$PREFIX/bin/$bin"
done
for lib in "$PREFIX"/lib/*.so*; do
    [ -f "$lib" ] || continue
    [ -L "$lib" ] && continue
    if readelf -h "$lib" >/dev/null 2>&1; then
        # shellcheck disable=SC2016
        "${SUDO[@]}" patchelf --force-rpath --set-rpath '$ORIGIN' "$lib"
    fi
done

cat <<EOF

Tessa is installed.

  compositor: $PREFIX/bin/tessa
  launchers:  /usr/local/bin/tessa, tessa-panel, tessa-ctl, tessa-session, tessa-panel-compat
  panel bridge: $PREFIX/bin/tessa-panel-compat (Hyprland/Niri; requires python3)
  session:    /usr/share/wayland-sessions/tessa.desktop
  config:     ~/.config/tessa/config (copy $PREFIX/share/tessa/config.example)

Log out and choose "Tessa" in your display manager, or run "tessa" from a TTY.
Check the session with:

  tessa-ctl config-check

X11 applications need xwayland-satellite (not packaged by Ubuntu/Debian).
EOF
