# Packaging Tessa

Tessa is built with Zig and links wlroots 0.19. Distribution packages should pin
the `wlroots-0.19` library; the source build refers to it explicitly in
`build.zig`.

## Arch Linux

The PKGBUILD builds a `tessa-git` package from GitHub:

```sh
cd packaging/arch
makepkg -si
```

It installs:

- `/usr/bin/tessa`, `/usr/bin/tessa-panel`, `/usr/bin/tessa-ctl`
- `/usr/bin/tessa-session`
- `/usr/share/wayland-sessions/tessa.desktop`
- `/usr/share/tessa/config.example`
- `/usr/share/xdg-desktop-portal/portals/tessa.portal`

Runtime dependencies are checked by `makepkg`. `xwayland-satellite` is optional;
without it, X11 applications do not start. `kitty`/`foot` are user choices.
Screen sharing additionally needs `xdg-desktop-portal`,
`xdg-desktop-portal-wlr`, and PipeWire. The installed `tessa.portal` routes the
Screenshot and ScreenCast portals to the wlr backend when
`XDG_CURRENT_DESKTOP=Tessa`. With a single monitor, set up
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
dpkg-buildpackage -b -us -uc
sudo apt install ../tessa_0.1.0_amd64.deb
```

The package installs the same binaries, session entry, example config, and
portal selector. The `libwlroots-0.19-dev` build dependency and the linked
`wlroots-0.19` pkg-config name pin the compositor ABI.

Zig 0.16 is required. If the distribution packages an older Zig, install the
upstream 0.16 toolchain and make it the first `zig` in `PATH` before building.

## Manual install

For development or a user-local install, use:

```sh
./scripts/install-session.sh
```

This installs under `~/.local` by default. `PREFIX=/usr/local` and `sudo` may be
used for a system-wide install.
