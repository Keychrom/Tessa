# Packaging Tessa

Tessa requires Zig 0.17 and links the wlroots 0.20 ABI. The default build also
uses scenefx 0.5. Distribution packages must pin these; the source build refers
to `wlroots-0.20` explicitly in `build.zig`.

## NixOS

The repository is a flake with a package and a NixOS module. `nix build` uses
nixpkgs' Zig 0.17, wlroots 0.20, and scenefx 0.5. A `tessa-plain` variant without
scenefx is provided for software rendering (pixman) on VMs.

See [nix/README.md](nix/README.md) for the module options and a complete VM
example.

## Arch Linux

Arch's official repositories provide Zig 0.17 as `zig`, wlroots 0.20 as
`wlroots0.20`, and scenefx 0.5 as `scenefx`, which match this tree. Install the
build dependencies:

```sh
sudo pacman -Syu --needed base-devel git zig wlroots0.20 scenefx \
  wayland wayland-protocols libxkbcommon libinput pixman libdrm \
  libegl mesa cairo pango glib2 gdk-pixbuf2
```

Then build the `tessa-git` package:

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa/packaging/arch
makepkg -si
```

The PKGBUILD declares `depends=('wlroots0.20' ...)` and
`makedepends=('git' 'zig')`; its build step calls `scripts/build.sh`, which
requires Zig 0.17.x.

It installs:

- `/usr/bin/tessa`, `/usr/bin/tessa-panel`, `/usr/bin/tessa-ctl`
- `/usr/bin/tessa-panel-compat` (requires the optional `python` package)
- `/usr/bin/tessa-session`
- `/usr/share/wayland-sessions/tessa.desktop`
- `/usr/share/tessa/config.example` and `/usr/share/tessa/panel.example`
- `/usr/share/xdg-desktop-portal/portals/tessa.portal`
- man pages and documentation under `/usr/share`

The PKGBUILD depends on `scenefx` and enables rounded corners and backdrop blur
by default. For the plain wlroots scene, build a source checkout with
`-Dscenefx=false`. `xwayland-satellite` is optional and is available in
the AUR as `xwayland-satellite-git`; without it, X11 applications do not start.
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

The control center's system features are optional runtime services, listed as
`optdepends`: `networkmanager` for Wi-Fi, `bluez` for Bluetooth,
`power-profiles-daemon` for power profiles, `upower` for battery data, and
`polkit` for authorization. Missing services only mark that control-center
section unavailable; the compositor and the rest of the panel still start.

## Debian / Ubuntu

For a normal install, use the [Ubuntu / Debian installer](https://keychrom.github.io/docs/install-script/).
The rest of this section documents the legacy `.deb` build for downstream
packaging.

The `debian/` directory at the repository root uses debhelper and Zig. Build on
a machine with the development packages in `debian/control`:

```sh
sudo apt install debhelper dpkg-dev fakeroot
ZIG="$HOME/.local/zig-0.17.0/zig" ./scripts/build-deb.sh
sudo apt install ./dist/tessa_<version>_<arch>.deb
```

> **0.2.4 may be the final `.deb` release.** It is the last package planned
> against Zig 0.16 and wlroots 0.19. The current source tree (`0.2.5`) targets
> Zig 0.17, wlroots 0.20, and scenefx 0.5; the Debian definitions are kept for
> downstream packaging but no new binary release is planned.

The Debian build passes `-Dscenefx=false` because Ubuntu 26.04 has no scenefx
0.5 development package. The `.deb` therefore uses the plain wlroots scene
without rounded corners or backdrop blur.

The script runs `dpkg-buildpackage -b -us -uc -d`, collects the `.deb`,
`.buildinfo`, and `.changes` under `dist/`, and prints the package metadata.
`-d` skips the declared build-dependency check because Ubuntu 26.04 packages an
older Zig; the script verifies the supplied Zig is 0.17.x instead.

The package installs the same binaries, session entry, example config, and
portal selector. The wlroots 0.20 development files and the linked
`wlroots-0.20` pkg-config name pin the compositor ABI. NetworkManager, BlueZ,
power-profiles-daemon, UPower, and polkit are listed in `Suggests`; install them
to enable the corresponding control-center sections.

Zig 0.17 is required. If the distribution packages an older Zig, install the
upstream 0.17 toolchain and pass it with `ZIG=...` before building. Run
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
