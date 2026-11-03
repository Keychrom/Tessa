#!/usr/bin/env bash
# Runs inside the target rootfs chroot during the ISO build.
set -euo pipefail

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc || true

sed -i 's/^#\s*ja_JP.UTF-8/ja_JP.UTF-8/; s/^#\s*en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen

cat > /etc/locale.conf <<'EOF'
LANG=ja_JP.UTF-8
EOF
cat > /etc/vconsole.conf <<'EOF'
KEYMAP=jp106
EOF
printf 'tessa\n' > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1 localhost
::1 localhost
127.0.1.1 tessa.localdomain tessa
EOF

# Use the official CDN by default; users can run reflector later.
cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF

# Generic initramfs: the ISO is built on a different machine than the target.
sed -i 's/^HOOKS=.*/HOOKS=(base udev modconf block filesystems keyboard fsck)/' \
    /etc/mkinitcpio.conf
sed -i 's/^MODULES=.*/MODULES=()/' /etc/mkinitcpio.conf
mkinitcpio -P

systemctl enable NetworkManager.service
systemctl enable sddm.service
systemctl enable bluetooth.service
systemctl set-default graphical.target

# Calamares owns these at install time.
: > /etc/fstab
truncate -s 0 /etc/machine-id

rm -rf /var/cache/pacman/pkg/* /var/log/* /tmp/*
