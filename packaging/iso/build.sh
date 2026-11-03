#!/usr/bin/env bash
# Build a Tessa Linux ISO: Arch base + Tessa session + Japanese input,
# installed offline by Calamares from a bundled rootfs.
#
# Run as a normal Arch user on an up-to-date Arch system. The script uses sudo
# for package installation, pacstrap, chroot setup, and mkarchiso.
#
#   ./packaging/iso/build.sh              # full build
#   ./packaging/iso/build.sh --no-calamares  # reuse an existing Calamares package
#   TESSA_ISO_BUILD=/var/tmp/build ./packaging/iso/build.sh
#
# Output: dist/iso/tessa-linux-<date>-x86_64.iso
set -euo pipefail

ISO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$ISO_DIR/../.." && pwd)
BUILD_DIR=${TESSA_ISO_BUILD:-/var/tmp/tessa-iso}
CACHE_DIR=${TESSA_ISO_CACHE:-/var/cache/tessa-iso}
REPO_DIR=$BUILD_DIR/repo
PKG_DIR=$CACHE_DIR/packages
ROOTFS_DIR=$BUILD_DIR/rootfs
PROFILE_DIR=$BUILD_DIR/profile
WORK_DIR=$BUILD_DIR/work
OUT_DIR=${TESSA_ISO_OUT:-$ROOT/dist/iso}
PROFILE_SRC=$ISO_DIR/profile
JOBS=${JOBS:-$(nproc)}
SKIP_CALAMARES=0

for arg in "$@"; do
    case "$arg" in
        --no-calamares) SKIP_CALAMARES=1 ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run as a normal user; the script invokes sudo itself"
command -v pacman >/dev/null || die "this script must run on Arch Linux"
command -v makepkg >/dev/null || die "install base-devel first"
[ -f "$ROOT/src/main.zig" ] || die "run from a Tessa source checkout"

log "package build dependencies"
sudo -v
sudo pacman -S --needed --noconfirm \
    archiso squashfs-tools libisoburn mtools dosfstools syslinux grub efibootmgr \
    base-devel git rsync zstd librsvg imagemagick python

sudo rm -rf "$BUILD_DIR"
sudo install -d -o "$(id -u)" -g "$(id -g)" "$CACHE_DIR" "$PKG_DIR"
mkdir -p "$BUILD_DIR" "$REPO_DIR" "$OUT_DIR"

log "building tessa-iso package"
TESSA_PKG=$BUILD_DIR/pkg-tessa
mkdir -p "$TESSA_PKG"
tar --exclude=.git --exclude=.zig-cache --exclude=zig-out --exclude=dist \
    --exclude='*.iso' --exclude='packaging/iso/build' \
    --transform 's|^\./|tessa/|' \
    -czf "$TESSA_PKG/tessa.tar.gz" -C "$ROOT" .
cp "$ISO_DIR/package/PKGBUILD" "$TESSA_PKG/PKGBUILD"
(
    cd "$TESSA_PKG"
    makepkg -f --noconfirm -s
)
cp "$TESSA_PKG"/*.pkg.tar.zst "$PKG_DIR/"

if [ "$SKIP_CALAMARES" -eq 0 ]; then
    log "building calamares from the AUR"
    CALAMARES_SRC=$BUILD_DIR/aur-calamares
    git clone --depth=1 https://aur.archlinux.org/calamares.git "$CALAMARES_SRC"
    (
        cd "$CALAMARES_SRC"
        makepkg -f --noconfirm -s
    )
    cp "$CALAMARES_SRC"/*.pkg.tar.zst "$PKG_DIR/"
else
    log "reusing calamares package from $PKG_DIR"
    compgen -G "$PKG_DIR/calamares-*.pkg.tar.zst" >/dev/null ||
        die "--no-calamares given but no calamares package is in $PKG_DIR"
fi

log "local package repository"
cp "$PKG_DIR"/*.pkg.tar.zst "$REPO_DIR/"
repo-add "$REPO_DIR/tessa-iso.db.tar.gz" "$REPO_DIR"/*.pkg.tar.zst

write_pacman_conf() {
    local dest=$1
    cat > "$dest" <<EOF
[options]
HoldPkg = pacman glibc
Architecture = auto
SigLevel = Never

[core]
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch

[extra]
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch

[multilib]
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch

[tessa-iso]
Server = file://$REPO_DIR
EOF
}
write_pacman_conf "$BUILD_DIR/pacman-build.conf"
write_pacman_conf "$BUILD_DIR/pacman-profile.conf"

log "installing the target root filesystem"
sudo mkdir -p "$ROOTFS_DIR"
# shellcheck disable=SC2046
sudo pacstrap -C "$BUILD_DIR/pacman-build.conf" -c -K "$ROOTFS_DIR" \
    $(grep -vE '^\s*(#|$)' "$ISO_DIR/rootfs/packages.x86_64")

log "configuring the target root filesystem"
sudo install -d -m 0755 "$ROOTFS_DIR/usr/share/tessa/themes/vermilion-ink"
sudo cp -a "$ROOT/examples/themes/vermilion-ink/." \
    "$ROOTFS_DIR/usr/share/tessa/themes/vermilion-ink/"
if [ -d "$ISO_DIR/rootfs/overlay" ]; then
    sudo cp -a "$ISO_DIR/rootfs/overlay/." "$ROOTFS_DIR/"
fi
sudo cp -a "$ISO_DIR/profile/airootfs/etc/skel/." "$ROOTFS_DIR/etc/skel/"
sudo install -Dm644 "$ISO_DIR/profile/airootfs/etc/environment" \
    "$ROOTFS_DIR/etc/environment"
sudo install -Dm644 "$ISO_DIR/profile/airootfs/etc/profile.d/tessa-ime.sh" \
    "$ROOTFS_DIR/etc/profile.d/tessa-ime.sh"
sudo install -Dm644 "$ISO_DIR/profile/airootfs/etc/xdg/autostart/fcitx5-tessa.desktop" \
    "$ROOTFS_DIR/etc/xdg/autostart/fcitx5-tessa.desktop"
sudo install -m 0755 "$ISO_DIR/rootfs/setup.sh" "$ROOTFS_DIR/rootfs-setup.sh"
sudo arch-chroot "$ROOTFS_DIR" /rootfs-setup.sh
sudo rm -f "$ROOTFS_DIR/rootfs-setup.sh"
sudo rm -rf "$ROOTFS_DIR/var/cache/pacman/pkg"/* "$ROOTFS_DIR/var/log"/* \
    "$ROOTFS_DIR/tmp"/*

log "building the installer rootfs image"
ROOTFS_IMAGE=$BUILD_DIR/rootfs.squashfs
sudo mksquashfs "$ROOTFS_DIR" "$ROOTFS_IMAGE" \
    -comp zstd -Xcompression-level 19 -b 1M -noappend -quiet

log "preparing the live ISO profile"
rm -rf "$PROFILE_DIR"
cp -a "$PROFILE_SRC" "$PROFILE_DIR"
cp "$BUILD_DIR/pacman-profile.conf" "$PROFILE_DIR/pacman.conf"
install -d "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager.service \
    "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
ln -sf /etc/systemd/system/tessa-live-home.service \
    "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants/tessa-live-home.service"
ln -sf /usr/lib/systemd/system/sddm.service \
    "$PROFILE_DIR/airootfs/etc/systemd/system/display-manager.service"
ln -sf /usr/lib/systemd/system/graphical.target \
    "$PROFILE_DIR/airootfs/etc/systemd/system/default.target"
ln -sf /usr/share/zoneinfo/Asia/Tokyo \
    "$PROFILE_DIR/airootfs/etc/localtime"
ln -sf /dev/null \
    "$PROFILE_DIR/airootfs/etc/systemd/system/systemd-firstboot.service"

# Calamares' Python job modules import libcalamares from /usr/lib/calamares.
# The AUR package does not add that directory to the embedded interpreter's
# search path, so expose it explicitly for the live session.
pyver=$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
pyroot="$PROFILE_DIR/airootfs/usr/lib/python${pyver}"
install -d "$pyroot/site-packages"
printf '/usr/lib/calamares\n' > "$pyroot/site-packages/calamares.pth"
ln -sfn /usr/lib/libcalamares.so "$pyroot/libcalamares.so"
convert "$ROOT/docs/images/mosaic.png" -resize 640x480^ -gravity center \
    -extent 640x480 -fill '#0a0f1a' -colorize 35% "$PROFILE_DIR/syslinux/splash.png"
install -d "$PROFILE_DIR/airootfs/usr/share/tessa-installer"
cp "$ROOTFS_IMAGE" "$PROFILE_DIR/airootfs/usr/share/tessa-installer/rootfs.squashfs"
cp "$ISO_DIR/branding/logo.svg" "$PROFILE_DIR/airootfs/etc/calamares/branding/tessa/logo.svg"
rsvg-convert -w 160 -h 160 "$ISO_DIR/branding/logo.svg" \
    -o "$PROFILE_DIR/airootfs/etc/calamares/branding/tessa/logo.png"
for image in mosaic launcher ime; do
    convert "$ROOT/docs/images/$image.png" -resize 1280x720^ \
        -gravity center -extent 1280x720 \
        "$PROFILE_DIR/airootfs/etc/calamares/branding/tessa/$image.png"
done

log "building the ISO"
sudo mkarchiso -v -r -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

iso=$(find "$OUT_DIR" -maxdepth 1 -name 'tessa-linux-*.iso' -printf '%T@ %p\n' |
    sort -n | tail -1 | cut -d' ' -f2-)
[ -n "$iso" ] || die "mkarchiso did not produce an ISO"
log "done: $iso"
