**English** | [日本語](QUICKSTART.ja.md)

<!-- tessa-site-notice:start -->
> [!NOTE]
> This document has been ported to the website. Read the current version at <https://keychrom.github.io/docs/quickstart/>.
<!-- tessa-site-notice:end -->

# Quickstart

This page takes you from a fresh install to a working Tessa session. For every
option and configuration key, see the [Guide](GUIDE.md).

Tessa is a full Wayland session, not an application you launch inside GNOME or
KDE. Save your work and log out before starting it.

## Before you start

You need:

- Arch Linux, Ubuntu/Debian (via `install.sh`), or another Linux
  distribution with a working Wayland/DRM graphics stack
- Zig 0.17, wlroots 0.20, and scenefx 0.5 for a source build
- A terminal emulator; Tessa's default is `kitty`
- A normal user account with access to the graphical session (do not run Tessa
  as root)

The default build uses scenefx and needs GLES2. If you are in a VM or your GPU
cannot provide GLES2, use the plain `-Dscenefx=false` build described below.

## 1. Install

### Arch Linux (recommended)

Install the build dependencies:

```sh
sudo pacman -Syu --needed base-devel git zig wlroots0.20 scenefx \
  wayland wayland-protocols libxkbcommon libinput pixman libdrm \
  libegl mesa cairo pango glib2
```

Build and install the `tessa-git` package:

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa/packaging/arch
makepkg -si
```

The package installs `tessa`, `tessa-panel`, `tessa-ctl`, the session entry,
an example config, and the screen-sharing portal selector.

#### Recommended packages

Install the terminal, output and screenshot tools, screen-sharing portals, and
session utilities:

```sh
sudo pacman -S --needed foot kitty wlr-randr grim swaylock swayidle wlopm \
  dbus xdg-desktop-portal xdg-desktop-portal-wlr pipewire
```

For X11 applications, install `xwayland-satellite-git` from the AUR:

```sh
git clone https://aur.archlinux.org/xwayland-satellite-git.git
cd xwayland-satellite-git
makepkg -si
```

With an AUR helper, the same set is:

```sh
paru -S foot kitty wlr-randr grim swaylock swayidle wlopm dbus \
  xdg-desktop-portal xdg-desktop-portal-wlr pipewire xwayland-satellite-git
```

### Ubuntu / Debian (recommended)

Use the [Ubuntu / Debian installer](https://keychrom.github.io/docs/install-script/).
It installs the current `0.2.5` tree and builds Zig 0.17, wlroots 0.20,
scenefx 0.5, and any missing Wayland libraries under `/opt/tessa` without
replacing the system libraries.

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa
./install.sh --check
./install.sh
```

The default install includes a terminal, fonts, fcitx5 + Mozc, portals, and
PipeWire. Use `--minimal` to skip those packages, or `--plain` to build
without scenefx effects. The installer is experimental; read its
[testing status](https://keychrom.github.io/docs/install-script/) before
running it.

### NixOS

The repository is a flake with a NixOS module:

```nix
inputs.tessa.url = "github:Keychrom/Tessa";

modules = [
  tessa.nixosModules.default
  {
    programs.tessa.enable = true;
    services.displayManager.sddm.enable = true;
  }
];
```

See the
[NixOS packaging guide](https://github.com/Keychrom/Tessa/blob/main/packaging/nix/README.md)
for a complete VM example, the `tessa-plain` package for pixman-only VMs, and
module options.

### Other distributions

See [Build from source](GUIDE.md#24-build-from-source-development). The default
build needs Zig 0.17, wlroots 0.20, and scenefx 0.5; use `-Dscenefx=false` for
the plain wlroots scene.

## 2. Start Tessa

Log out of your current desktop. At the login screen, choose **Tessa** in GDM,
SDDM, greetd, LightDM, or your display manager.

For a first test from a TTY, log in on the text console and run:

```sh
tessa
```

Tessa starts one panel process per output automatically. Do not start
`tessa-panel` yourself. Quit with `Super+Shift+E`.

## 3. First keys

`Super` is the Windows or Command key.

| Key | Action |
| --- | --- |
| `Super+Return` | Open the terminal (`kitty`) |
| `Super+D` | Open the launcher |
| `Super+Q` | Close the focused window |
| `Super+1` … `Super+9` | Switch workspace |
| `Super+Shift+1` … `9` | Move the window to a workspace |
| `Super+H/J/K/L` | Focus left/down/up/right |
| `Super+Space` | Toggle floating |
| `Super+F` | Toggle fullscreen |
| `Super+R` | Reload the config |
| `Super+Shift+E` | Quit Tessa |

Click a window to focus it, click a bar chip to focus that window, and scroll
over the bar to cycle workspaces. See
[Default bindings](GUIDE.md#7-default-bindings-and-mouse) for the complete list.

## 4. Make it yours

Tessa works without a config file. To start from the example:

```sh
mkdir -p ~/.config/tessa
cp /usr/share/tessa/config.example ~/.config/tessa/config
cp /usr/share/tessa/panel.example ~/.config/tessa/panel.conf
```

For a source checkout, use `config/config.example` and `config/panel.example`.
`config` holds compositor behavior and shared theme tokens; `panel.conf` holds
bar, launcher, popover, wallpaper, and control-center settings. Panel keys left
in `config` still work for compatibility.

Edit either file, then press `Super+R`. Check the result with:

```sh
tessa-ctl config-check
tessa --check-config ~/.config/tessa/config
```

Common first changes are `terminal = foot`, the `font`, the wallpaper colors,
and the `bind =` lines. See [Customization](CUSTOMIZATION.md) for window rules,
layouts, effects, the panel, and the full key reference.

## 5. Optional setup

- **X11 applications:** install `xwayland-satellite` in `PATH` (AUR
  `xwayland-satellite-git`), or set `TESSA_XWAYLAND_BIN` to its absolute path.
- **Japanese input:** install `fcitx5` and `fcitx5-mozc`, then add
  `startup = fcitx5 -d` to your config. For X11 clients, also set
  `xim = true` and `xim_start = fcitx5 -d`.
- **Screen sharing:** install `xdg-desktop-portal`, `xdg-desktop-portal-wlr`,
  and PipeWire. The packaged session installs the portal selector for you.

## If something goes wrong

- **`Super+Return` does nothing:** install `kitty`, or set `terminal` to a
  terminal that is installed.
- **Tessa exits with "Failed to create renderer":** the default scenefx build
  needs GLES2. Build the plain version with `-Dscenefx=false` and start it with
  `WLR_RENDERER=pixman tessa`.
- **X11 applications do not start:** install `xwayland-satellite`.
- **No rounded corners or blur:** check `tessa-ctl config | grep scenefx`.
  `scenefx 0` means the running binary was built with `-Dscenefx=false`.
- **The session feels slow:** set `blur = false`, `shadows = false`, and
  `animations = false` in the config, then press `Super+R`. Blur is the
  heaviest effect; see [Rendering and games](RENDERING.md).
- **The config does not load:** run `tessa --check-config` and check the file
  name and path.
- **Still stuck:** see [Troubleshooting](GUIDE.md#15-troubleshooting) or open an
  issue on [GitHub](https://github.com/Keychrom/Tessa/issues).

## Next steps

- [Setup and customization guide](GUIDE.md)
- [Customization reference](CUSTOMIZATION.md)
- [Rendering and games](RENDERING.md)
- [Build an extension](EXTENDING.md)
- [Extension API v1](EXTENSION-API.md)
