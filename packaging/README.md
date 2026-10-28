# Packaging Tessa

Tessa requires Zig 0.16 and links the wlroots 0.19 ABI. Distribution packages
must pin both; the source build refers to `wlroots-0.19` explicitly in
`build.zig`.

## Arch Linux

Arch's official repositories currently provide Zig 0.17 as `zig` and wlroots
0.20 as `wlroots0.20`. Neither is compatible with this tree. Use the AUR
packages:

- `zig0.16-bin` — provides `zig0.16` and installs `/usr/bin/zig-0.16`
- `wlroots0.19` — 0.19.3, provides `libwlroots-0.19.so`

With an AUR helper such as paru:

```sh
sudo pacman -Syu --needed base-devel git
paru -S --needed zig0.16-bin wlroots0.19
```

Without a helper, build the AUR packages manually:

```sh
sudo pacman -S --needed base-devel git meson ninja glslang \
  vulkan-headers wayland-protocols xorg-xwayland minisign
mkdir -p ~/aur && cd ~/aur
for pkg in zig0.16-bin wlroots0.19; do
  git clone "https://aur.archlinux.org/$pkg.git"
  (cd "$pkg" && makepkg -si)
done
```

Then build the `tessa-git` package:

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa/packaging/arch
makepkg -si
```

`makepkg` does not fetch AUR dependencies automatically, so install
`zig0.16-bin` and `wlroots0.19` first. The PKGBUILD declares
`depends=('wlroots0.19' ...)` and `makedepends=('git' 'zig0.16')`; its build
step calls `scripts/build.sh`, which prefers `zig-0.16` when available.

It installs:

- `/usr/bin/tessa`, `/usr/bin/tessa-panel`, `/usr/bin/tessa-ctl`
- `/usr/bin/tessa-session`
- `/usr/share/wayland-sessions/tessa.desktop`
- `/usr/share/tessa/config.example`
- `/usr/share/xdg-desktop-portal/portals/tessa.portal`
- man pages and documentation under `/usr/share`

For rounded corners and blur, install AUR `scenefx0.4` and build from source
with `-Dscenefx=true`; the PKGBUILD uses the default wlroots scene and does not
enable scenefx. `xwayland-satellite` is optional and is available in the AUR as
`xwayland-satellite-git`; without it, X11 applications do not start.
`kitty`/`foot` are user choices. Screen sharing additionally needs
`xdg-desktop-portal`, `xdg-desktop-portal-wlr`, and PipeWire. The installed
`tessa.portal` routes the Screenshot and ScreenCast portals to the wlr backend
when `XDG_CURRENT_DESKTOP=Tessa`. With a single monitor, set up
`~/.config/xdg-desktop-portal-wlr/config`:

```ini
[screencast]
chooser_type=none
output_name=HDMI-A-1
```

## Debian / Ubuntu

The `debian/` directory at the repository root uses debhelper and Zig. Build on
a machine with the development packages in `debian/control`:

```sh
sudo apt install debhelper dpkg-dev fakeroot
ZIG="$HOME/.local/zig-0.16.0/zig" ./scripts/build-deb.sh
sudo apt install ./dist/tessa_0.2.0_amd64.deb
```

The script runs `dpkg-buildpackage -b -us -uc -d`, collects the `.deb`,
`.buildinfo`, and `.changes` under `dist/`, and prints the package metadata.
`-d` skips the declared build-dependency check because Ubuntu 26.04 packages
Zig 0.14; the script verifies the supplied Zig is 0.16.x instead.

The package installs the same binaries, session entry, example config, and
portal selector. The `libwlroots-0.19-dev` build dependency and the linked
`wlroots-0.19` pkg-config name pin the compositor ABI.

Zig 0.16 is required. If the distribution packages an older Zig, install the
upstream 0.16 toolchain and pass it with `ZIG=...` before building. Run
`lintian dist/*.deb` for a first packaging audit.

Do not install the `.deb` on a machine that already has a manual
`/usr/local` install unless you intend to replace it; both copy the same
binaries and session entry to different prefixes.

## Manual install

For development or a user-local install, use:

```sh
./scripts/install-session.sh
```

This installs under `~/.local` by default. `PREFIX=/usr/local` and `sudo` may be
used for a system-wide install.
