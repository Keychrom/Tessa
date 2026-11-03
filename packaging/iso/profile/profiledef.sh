#!/usr/bin/env bash
# shellcheck disable=SC2034
iso_name="tessa-linux"
iso_label="TESSA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Tessa Linux <https://keychrom.github.io/>"
iso_application="Tessa Linux live desktop and installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/10-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/usr/local/bin/tessa-installer"]="0:0:755"
  ["/usr/local/bin/tessa-live-home"]="0:0:755"
  ["/usr/local/bin/tessa-live-session"]="0:0:755"
)
