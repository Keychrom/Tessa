**English** | [日本語](GUIDE.ja.md)

<!-- tessa-site-notice:start -->
> [!NOTE]
> This document has been ported to the website. Read the current version at <https://keychrom.github.io/docs/guide/>.
<!-- tessa-site-notice:end -->

# Tessa Setup & Customization Guide

> **New to Tessa?** Start with the [Quickstart](QUICKSTART.md) for installation,
> first launch, and the essential keys.

This guide collects the setup and customization surface of the current Tessa
tree. It covers the implementation through the 0.7 roadmap, including special
workspaces, shell v2, the effect helper, performance instrumentation, and the
interactive config editor.

Tessa is three programs:

- **`tessa`** — the wlroots compositor/window manager.
- **`tessa-panel`** — the wallpaper, floating taskbar, launcher, and shell UI.
- **`tessa-ctl`** — the state/event/automation client.

There is no Waybar, Rofi, or wofi dependency. Configuration is a flat
`key = value` file. `Super+R` reloads it, `tessa-ctl config-check` diagnoses it,
and `tessa-ctl config` prints the effective values and parsed rules.

---

## 1. Requirements

### Required

For a normal install on Ubuntu or Debian, use the `install.sh` installer in
section 2.1. On Arch Linux, use the PKGBUILD in section 2.2. The Zig/wlroots
development requirements below apply only to source and package builds.

- Linux (development is tested on Ubuntu 26.04)
- Zig **0.17.0**
- wlroots **0.20** development files
- Wayland, wayland-protocols >= 1.47, xkbcommon, pixman, libdrm, libinput,
  seat/udev, EGL/GLES
- Cairo, Pango, GLib/GIO, and gdk-pixbuf for the panel, notifications, and
  MPRIS artwork
- Fonts: Inter, JetBrains Mono, Noto Sans CJK JP (or equivalent)
- A terminal; the default command is `kitty` (`terminal = foot` is fine)

Ubuntu 26.04 example (install Zig 0.17 from upstream if the distribution
package is older):

```sh
sudo apt install build-essential pkg-config git \
  libwayland-dev wayland-protocols \
  libxkbcommon-dev libpixman-1-dev libdrm-dev libinput-dev \
  libseat-dev libudev-dev libegl-dev libgles2-mesa-dev \
  libcairo2-dev libpango1.0-dev libglib2.0-dev libfontconfig1-dev \
  fonts-inter fonts-jetbrains-mono fonts-noto-cjk \
  xwayland xauth xterm fcitx5 fcitx5-mozc
```

Ubuntu 26.04 packages wlroots 0.19, not 0.20. The installer in 2.1 builds
wlroots 0.20 and scenefx 0.5 under `/opt/tessa`; use it for a complete
toolchain.

On Arch Linux, the official `zig` (0.17) and `wlroots0.20` match this tree.
Install them as shown in section 2.2.

If wlroots is installed under `/usr/local`, verify that pkg-config and the
shared library are visible:

```sh
pkg-config --modversion wlroots-0.20
ldconfig -p | grep wlroots
```

### Optional

- `xwayland-satellite` for X11 applications (`xwayland = true` auto-start)
- `wlr-randr` for runtime output mode/position/scale/transform changes
- `grim` for screenshots and tests
- `wtype` for keyboard injection in headless tests
- `swaylock` for the default `Super+Escape` lock action
- `swayidle` and `wlopm` for idle/locking and output power
- `wpctl` (PipeWire), `pactl` (PulseAudio), or `amixer` (ALSA) for volume
- `xdg-desktop-portal`, `xdg-desktop-portal-wlr`, and PipeWire for screen sharing
- Fcitx5 + Mozc for Wayland IME and XIM
- scenefx **0.5** for the default rounded corners and backdrop blur
  (`-Dscenefx=false` omits it)

---

## 2. Install or Build

### 2.1 Ubuntu / Debian installer

Use the [Ubuntu / Debian installer](https://keychrom.github.io/docs/install-script/)
for a normal install. It installs the current `0.2.5` tree, builds Zig 0.17,
wlroots 0.20, scenefx 0.5, and any missing Wayland libraries under
`/opt/tessa`, and leaves the distribution's Wayland libraries untouched.

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa
./install.sh --check
./install.sh
```

The installer places:

- `/opt/tessa/bin/tessa`, `tessa-panel`, and `tessa-ctl`
- `/opt/tessa/bin/tessa-session`
- `/usr/local/bin` wrappers for the four commands
- `/usr/share/wayland-sessions/tessa.desktop`
- `/usr/share/xdg-desktop-portal/portals/tessa.portal`
- an example config and the Vermilion Ink theme

The default install also adds a terminal, fonts, fcitx5 + Mozc, portals, and
PipeWire. Use `--minimal` to skip those packages or `--plain` to build without
scenefx effects. The installer is experimental; read its
[testing status](https://keychrom.github.io/docs/install-script/) before using
it.

Log out and select **Tessa** in GDM, SDDM, greetd, or another display manager.
The session entry starts the installed compositor and panel directly; the
source session installer in section 3.2 is only for development.

Verify the installation:

```sh
tessa-ctl config-check
command -v tessa tessa-panel tessa-ctl
```

If Tessa was previously installed manually under `/usr/local`, keep only one
installation. The installer replaces the `/usr/local/bin` wrappers and session
entry used by an older manual install.

### 2.2 NixOS

The repository is a flake with a package and a NixOS module. The module installs
the compositor, its session entry, the portal, and the optional XWayland
satellite:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.tessa.url = "github:Keychrom/Tessa";

  outputs = { self, nixpkgs, tessa, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        tessa.nixosModules.default
        {
          programs.tessa.enable = true;
          services.displayManager.sddm.enable = true;
          programs.tessa.extraPackages = with pkgs; [ foot grim ];
        }
      ];
    };
  };
}
```

`nix build github:Keychrom/Tessa` builds the default scenefx package. On a VM
without 3D acceleration use `tessa.packages.x86_64-linux.tessa-plain` and set
`environment.sessionVariables.WLR_RENDERER = "pixman";`. See
`packaging/nix/README.md` in the repository for module options, autologin, and
a complete VM configuration.

### 2.3 Arch Linux

Arch's official repositories provide `zig` 0.17, `wlroots0.20`, and `scenefx`
0.5, which match this tree. Install the build dependencies:

```sh
sudo pacman -Syu --needed base-devel git zig wlroots0.20 scenefx \
  wayland wayland-protocols libxkbcommon libinput pixman libdrm \
  libegl mesa cairo pango glib2
```

Then build and install Tessa:

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa/packaging/arch
makepkg -si
```

The resulting `tessa-git` package installs the binaries, session entry, config
example, portal selector, man pages, and documentation under `/usr`.

Verify:

```sh
tessa-ctl config-check
command -v tessa tessa-panel tessa-ctl
```

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

The PKGBUILD depends on `scenefx` and enables rounded corners and blur by
default; pass `-Dscenefx=false` to a source build for the plain wlroots scene.
The 0.2.4 Arch package was built and exercised with the 0.16/0.19 AUR
toolchain. The 0.2.5 PKGBUILD has been built and installed on Arch Linux with
the official `zig` and `wlroots0.20`, and the full headless suite passes in
plain and scenefx builds. If `makepkg` reports an ABI or dependency problem,
confirm `zig version` is 0.17.x and
`pkg-config --modversion wlroots-0.20` is 0.20.x.

### 2.4 Build from source (development)

From the repository root:

```sh
chmod +x scripts/*.sh scripts/tessa-session
./scripts/build.sh
```

Release build:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe
```

`scripts/build.sh` requires Zig 0.17.x; set `ZIG=/path/to/zig` to choose an
explicit toolchain. On Arch, the official `zig` package is the supported
compiler.

Artifacts:

- `zig-out/bin/tessa`
- `zig-out/bin/tessa-panel`
- `zig-out/bin/tessa-ctl`

Run tests with:

```sh
sh tests/smoke.sh
sh tests/animations.sh
sh tests/output-rules.sh
sh tests/config-watch.sh
```

The full set is `sh tests/*.sh`. Tests skip optional dependencies that are not
installed (`foot`, `grim`, `wlr-randr`, PipeWire, D-Bus, etc.).
`tests/effects.sh` runs only in a scenefx build.

### scenefx effects build

The default build uses scenefx 0.5 for rounded corners and backdrop blur and
requires its GLES2 renderer. Install scenefx 0.5 and build normally:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe
```

For the plain wlroots scene, which supports both GL and pixman, disable scenefx:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe -Dscenefx=false
```

If scenefx is installed under a non-system prefix, set its pkg-config and
library paths for both build and run:

```sh
export PKG_CONFIG_PATH=$HOME/.local/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=$HOME/.local/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
./scripts/build.sh -Dscenefx=true
```

The `corner_radius` and `blur` keys are accepted in a `-Dscenefx=false` build
but have no visual effect.

### Panel build

The default build includes `tessa-panel`, the shell panel. To build and install
only the compositor and `tessa-ctl`, disable the panel:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe -Dpanel=false
```

This also drops the panel's Cairo, Pango, GdkPixbuf, and GIO build dependencies.
Run an external layer-shell bar or launcher instead. The built-in panel,
launcher, notifications, tray, and wallpaper are unavailable, and `panel = true`
in the config is ignored. The default remains `-Dpanel=true`.

To build just one side, use the named steps:

```sh
./scripts/build.sh panel       # tessa-panel only
./scripts/build.sh compositor  # tessa only
```

The panel still expects Tessa's IPC socket at runtime. To run it under another
compositor, use the compatibility bridge below.

### Running Tessa Panel under Hyprland or Niri

`tools/tessa-panel-compat.py` is a stdlib-only Python 3 bridge. It translates
Hyprland or Niri's state into the panel's `WIN`/`OUT`/`FOCUSED` IPC lines,
starts one `tessa-panel` per output, and translates the panel's `spawn`,
`workspace`, `focus`, and `close` commands back to the host compositor.

Build the panel and start the bridge inside the Hyprland/Niri session:

```sh
./scripts/build.sh panel
python3 tools/tessa-panel-compat.py
```

Packaged installs provide `tessa-panel-compat` in `PATH`; use that instead of
the `tools/` path. The bridge auto-detects the compositor from
`HYPRLAND_INSTANCE_SIGNATURE` or `NIRI_SOCKET`. Force one with
`--compositor hyprland` or `--compositor niri`.

It listens on `$XDG_RUNTIME_DIR/tessa.sock` (override with `--socket` or
`TESSA_IPC`), starts panels with `TESSA_PANEL_OUTPUT` and the output
make/model/serial, and restarts a panel that exits. Only the first output gets
the notification and system-service owner flags.

Open the launcher and switcher from compositor key bindings:

```ini
# Hyprland
bind = SUPER, Space, exec, tessa-panel-compat --send launcher
bind = ALT, Tab, exec, tessa-panel-compat --send switcher
bind = ALT SHIFT, Tab, exec, tessa-panel-compat --send switcher-prev
```

For Niri, spawn `tessa-panel-compat --send launcher` or
`tessa-panel-compat --send switcher` from `binds`. Other panel views are
available as `--send control`, `--send wifi`, `--send bluetooth`,
`--send notifications`, and `--send calendar`.

The panel reads the normal Tessa config (`panel_modules`, `bar_layout`, theme,
fonts, and so on). To use a specific file, set `TESSA_CONFIG` before starting
the bridge. If `tessa-panel` is not in `PATH`, pass `--panel /path/to/tessa-panel`.

Current limitations:

- The bar only represents workspaces 1–9. Hyprland special/named workspaces and
  dynamic Niri workspaces outside that range are not translated.
- Tessa extensions, status entries, and `tessa-ctl` automation are unavailable;
  the bridge has no extension host. Actions that invoke `tessa-ctl` (such as the
  config editor) will not work; edit the config file directly.
- The window switcher falls back to wlr-screencopy crops or monograms. Live
  per-window capture requires the host compositor's ext capture protocols.
- Blur and rounded corners are compositor-side. Hyprland/Niri do not apply
  Tessa's scenefx effects to panel surfaces.
- The panel's power-menu Quit action is ignored by the bridge; log out through
  the host compositor instead.
- Alt+Tab is press-to-open, not hold-to-cycle. Use Tab/arrow keys and Enter to
  commit, or Escape to cancel.
- Stop other notification daemons (mako, dunst) and tray implementations before
  starting the bridge, or they will compete for the same D-Bus names.

Debug the translated state without starting panels:

```sh
python3 tools/tessa-panel-compat.py --print-state
python3 tools/tessa-panel-compat.py --no-spawn --verbose
```

`--print-state` prints the exact state the panel would receive, which is the
fastest way to check output names, workspaces, and window IDs after a mapping
change.

---

## 3. Run and Install

### 3.1 Directly from a TTY

Run from the active physical console or a TTY, not over SSH. For a package
install:

```sh
tessa
```

For a source build:

```sh
cd /path/to/Tessa
PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

wlroots autodetects DRM and libinput. Tessa starts one `tessa-panel` per output
from `PATH`. The DRM backend needs an active logind/seat session and access to
input devices; run it as your normal user from a logged-in TTY, not as root.
An SSH session cannot use DRM, so use headless or nested Wayland there.

Quit with `Super+Shift+E` or `tessa-ctl quit`.

### 3.2 Display-manager session

The Ubuntu/Debian installer and Arch `tessa-git` package already install the
session entry. Use this only for a source build:

```sh
# Per-user install
./scripts/install-session.sh

# System-wide install
sudo PREFIX=/usr/local ./scripts/install-session.sh
```

Add `-Dscenefx=false` to either command for a plain build without scenefx,
for example when the GPU cannot provide GLES2:

```sh
./scripts/install-session.sh -Dscenefx=false
```

The installer places:

- `tessa`, `tessa-panel`, and `tessa-ctl`
- `tessa-session`
- `wayland-sessions/tessa.desktop`
- `xdg-desktop-portal/portals/tessa.portal`

Log out and choose **Tessa** in GDM, SDDM, greetd, or another display manager.
`tessa-session` prepends its directory to `PATH`, sets
`XDG_CURRENT_DESKTOP=Tessa`, and starts `tessa`.

Distribution packaging definitions live in `packaging/arch/PKGBUILD` and
`debian/`. See [`packaging/README.md`](../packaging/README.md) for installed
files and dependencies.

### 3.3 Headless development

```sh
./scripts/run-headless.sh
```

In another shell:

```sh
./scripts/screenshot.sh /tmp/tessa.png
```

The script sets:

- `XDG_RUNTIME_DIR=/tmp/tessa-headless` (override with `TESSA_RUNTIME_DIR`)
- `WLR_BACKENDS=headless`
- `WLR_RENDERER=pixman`
- `WLR_HEADLESS_OUTPUTS=1` (override in the environment)
- `PATH` containing `zig-out/bin`

For two headless outputs:

```sh
WLR_HEADLESS_OUTPUTS=2 ./scripts/run-headless.sh
```

### 3.4 Nested Wayland

To run Tessa as a window on another Wayland compositor:

```sh
WLR_BACKENDS=wayland WLR_RENDERER=gles2 \
  PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

### 3.5 XWayland / X11

Tessa uses the external
[`xwayland-satellite`](https://github.com/Supreeeme/xwayland-satellite), not
wlroots' built-in XWayland. Put it in `PATH` or set `TESSA_XWAYLAND_BIN`.

```ini
xwayland = true
xwayland_display = auto
```

`auto` scans `/tmp/.X11-unix/X<n>` and `/tmp/.X<n>-lock` for the first free
display. Use `:1` etc. to force one. `TESSA_NO_XWAYLAND=1` disables XWayland.

XIM:

```ini
xim = true
xim_server = fcitx
# Optional: start after the X display appears
xim_start = fcitx5 -d
```

`XMODIFIERS=@im=fcitx` is exported to X11 clients. Leave `xim_start` empty if
Fcitx5 is already started by the session.

### 3.6 Screen-sharing portal

`install-session.sh` installs `tessa.portal`. For a manual install, copy
`packaging/portal/tessa.portal` into
`/usr/share/xdg-desktop-portal/portals/`.

Required: `xdg-desktop-portal`, `xdg-desktop-portal-wlr`, and PipeWire.

Example xdpw setup for one output:

```ini
# ~/.config/xdg-desktop-portal-wlr/config
[screencast]
chooser_type=none
output_name=HEADLESS-1
```

Portal services are D-Bus activated from the systemd user manager and do not
inherit the variables the compositor sets for its own children. `tessa-session`
publishes them once the Wayland socket exists:

```sh
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP \
  XDG_SESSION_TYPE XDG_SESSION_DESKTOP
systemctl --user try-restart xdg-desktop-portal
```

Without that import the portal never starts `xdg-desktop-portal-wlr` and
applications such as Discord, Chromium-based browsers, or OBS report that no
screen sources are available. Starting `tessa` directly from a TTY needs the
same commands. With no `chooser_type` configured, xdpw runs the first chooser
it finds (`slurp`, `wmenu`, `wofi`, `rofi`, `bemenu`, `mew`, or `fuzzel`) and
otherwise falls back to an arbitrary output.

---

## 4. Environment Variables

| Variable | Meaning |
| --- | --- |
| `TESSA_CONFIG` | Config path; defaults to `$XDG_CONFIG_HOME/tessa/config` or `~/.config/tessa/config` |
| `TESSA_PANEL_CONFIG` | Panel file loaded after `config`; defaults to `panel.conf` next to `config`. Empty disables the overlay |
| `TESSA_SCENE_DIR` | Scene directory; defaults to `<config-dir>/scenes` |
| `TESSA_IPC` | IPC socket path; defaults to `$XDG_RUNTIME_DIR/tessa.sock` |
| `TESSA_OUTPUT_CONFIG` | Output/layout state file; defaults to `$XDG_CONFIG_HOME/tessa/outputs.conf` |
| `TESSA_DEBUG` | Verbose Tessa/wlroots logging |
| `TESSA_PANEL_DEBUG` | Verbose panel logging |
| `TESSA_CTL_DEBUG` | Verbose `tessa-ctl` logging |
| `TESSA_NO_PANEL` | Disable automatic panel start |
| `TESSA_PANEL_BIN` | Override the panel executable |
| `TESSA_PANEL_OUTPUT` | Output name for a manually started panel |
| `TESSA_NO_XWAYLAND` | Disable XWayland start |
| `TESSA_ALLOW_LINUX_DMABUF` | Re-enable linux-dmabuf on a vmwgfx session where it is auto-disabled |
| `TESSA_GPU_DISABLE` | `1` forces the Cairo panel/wallpaper path |
| `TESSA_SHADER_DISABLE` | `1` disables per-window shader effects |
| `TESSA_XWAYLAND_BIN` | Path to `xwayland-satellite` |
| `TESSA_SOCKET_NAME` | Explicit Wayland socket name |
| `TESSA_STARTUP` | Extra startup command (prefer the `startup` config key) |
| `WLR_BACKENDS` | `drm`, `headless`, `wayland`, etc. |
| `WLR_RENDERER` | `gles2` or `pixman` (scenefx builds use GLES2) |
| `WLR_HEADLESS_OUTPUTS` | Number of headless outputs |
| `TESSA_RUNTIME_DIR` | Runtime directory used by the headless/screenshot scripts |

---

## 5. Configuration Basics

Copy the examples:

```sh
mkdir -p ~/.config/tessa
cp config/config.example ~/.config/tessa/config
cp config/panel.example ~/.config/tessa/panel.conf
```

Tessa uses two settings files:

| File | Owns |
| --- | --- |
| `config` | key bindings, rules, outputs, layouts, rendering, animations, startup/hooks, and shared theme tokens |
| `panel.conf` | bar, launcher, popovers, wallpaper, panel fonts/colors, logo, control center, and panel commands |

The panel reads `config` first, then `panel.conf`, then `theme-colors.conf`.
The compositor reads `config` and then `panel.conf`, because Scene saves need the
panel wallpaper and panel colors. Panel keys left in `config` still work for
compatibility, so existing setups need no migration. `TESSA_PANEL_CONFIG`
overrides the panel file; an empty value disables it. The config directory is
watched for `.conf` changes, so saving `panel.conf` reloads the session too.
`theme` packages and `theme-role` stay shared by both. Because the compositor
loads `panel.conf` for shared visuals, a `theme`/`include` or compositor key
placed there also takes effect; keep compositor-only settings in `config`.
When upgrading an existing single-file setup, do not copy `panel.example` over
an existing `panel.conf`: it contains active defaults. Move the panel keys from
`config` instead.

Format rules:

- `key = value`
- Lines beginning with `#` are comments
- `include = path` loads another file; relative paths are resolved next to the
  including file
- Include depth is limited to 8
- Flat values are taken verbatim; whitespace is preserved after trimming, and quote characters are not stripped
- Rule/extension clauses support quoted values; a `;` cannot be used inside a flat value

Reload and inspect:

```sh
tessa --check-config [file]      # offline validation; non-zero on errors
tessa-panel --check              # effective panel settings (config + panel.conf)
tessa-ctl config                 # effective settings and parsed rules
tessa-ctl config --json          # schema-1 JSON
tessa-ctl config-check           # non-zero on errors
tessa-ctl dispatch reload        # same as Super+R
```

`tessa --check-config` loads the config into a temporary parser state without
starting the compositor. It prints the same file/line diagnostics and is safe
to use from editors, CI, or a pre-login TTY. A reload with errors is rejected
and the previous configuration remains active.
Diagnostics include the file name and line number.

Tessa also watches the config directory. Atomic saves of the main config and
`.conf` includes in that directory reload automatically after a short debounce;
manual `Super+R` / `tessa-ctl dispatch reload` is still available. Invalid
edits are rejected and keep the previous configuration.

---

## 6. Configuration Keys

### 6.1 Core and layout

| Key | Default | Meaning |
| --- | --- | --- |
| `terminal` | `kitty` | Command for `Super+Return` and `Terminal=true` apps |
| `gaps` | `10` | Gap between tiles |
| `outer_gaps` | `16` | Gap around the tiling area |
| `border_width` | `2` | Window border thickness (0–16) |
| `master_ratio` | `0.58` | Master width ratio (0.15–0.9) |
| `master_count` | `1` | Windows stacked in the master column (1–8) |
| `mosaic_ratio` | `0.62` | Mosaic slice ratio (0.25–0.85) |
| `mosaic_min_size` | `160` | Minimum tile before mosaic falls back to grid (80–600) |
| `grid_columns` | `0` | Fixed grid columns; `0` is automatic (max 8) |
| `layout` | `master` | Default: `master`, `mosaic`, `grid`, `columns`, `scrolling`, `monocle`, `stacking`, or `custom` |
| `layout_cycle` | `master,mosaic,grid,columns` | Comma-separated layouts cycled by `Super+T` |
| `default_column_width` | `50%` | Scrolling column width (`50%`, `0.5`, or fixed `640`) |
| `column_width_presets` | `33.333%,50%,66.667%` | Presets cycled by `column-width-cycle` |
| `center_focused_column` | `never` | Scrolling focus policy: `never`, `always`, `on-overflow` |
| `animation_view_ms` | `180` | Scrolling viewport animation duration |
| `animation_view_curve` | `ease-out-cubic` | Curve for the scrolling viewport |
| `layout_1` … `layout_9` | inherited | Initial layout for a workspace without a saved/runtime override |
| `layout_helper` | empty | One asynchronous custom layout helper per output |
| `layout_helper_timeout` | `100` | Helper timeout in ms (10–1000) |
| `effect_helper` | empty | Long-lived per-window visual effect helper |
| `effect_helper_timeout` | `200` | Effect-helper timeout in ms (20–2000) |
| `extension_ready_timeout` | `10000` | Time to wait for a supervised extension's token handshake in ms (`0` disables; 1000–60000) |
| `frame_time_budget` | `16` | Render-commit budget in ms; frames above it are counted by `tessa-ctl perf` |
| `direct_scanout` | `true` | Hide compositor nodes for an opaque fullscreen client so wlroots can scan it out directly |
| `tearing` | `off` | `off`, `fullscreen`, or `force`; always requires the client's async hint |
| `explicit_sync` | `true` | Advertise `linux-drm-syncobj-v1` when renderer/backend timelines and a DRM fd are available; restart to change |
| `output_config` | `~/.config/tessa/outputs.conf` | Output and layout persistence file |
| `workspace_pin` | — | `OUTPUT WORKSPACE` pin; repeatable |
| `workspace-name` | — | `WORKSPACE NAME` display/command alias; repeatable |
| `special-workspace` | — | Declare a named special (hidden overlay) workspace; repeatable |
| `workspace-rule` | — | Per-workspace layout/spacing rule |
| `output-rule` | — | Per-output layout, spacing, theme, and VRR rule matched by connector or EDID |
| `input` / `input-rule` | — | Per-device libinput policy; repeatable |
| `profile` | — | Named layout/tuning profile referenced by output/workspace rules |
| `window-rule` | — | Declarative window rule |
| `layer-rule` | — | Declarative layer-shell rule |
| `theme-role` | — | Semantic color role (`accent`, borders, wallpaper, panel) |
| `mode` | `default` | Start a named input-mode section for following `bind` lines |
| `bind` | — | Add or override a key binding |
| `include` | — | Include another config file |

### 6.2 Appearance and animation

| Key | Default | Meaning |
| --- | --- | --- |
| `accent` | `#e2684f` | Accent for borders, bar, launcher |
| `bg` | `#0a0f1a` | Base wallpaper color |
| `bg_top` | unset | Top wallpaper gradient color; derived from `bg` if omitted |
| `bg_bottom` | unset | Bottom wallpaper gradient color |
| `wallpaper_art` | `true` | Draw ink/sun/water decorative art |
| `wallpaper_art_opacity` | `0.55` | Art opacity from `0.0` (off) to `1.0`; keeps the artwork behind translucent surfaces |
| `wallpaper_image` | empty | PNG wallpaper path (absolute or `~/...`); replaces gradient/art |
| `wallpaper_shader` | empty | Command that prints a binary PPM (P6) frame; takes precedence over the image |
| `wallpaper_fit` | `cover` | Image fit: `cover`, `contain`, or `stretch` |
| `border_active` | empty | Focused border; empty uses `accent` |
| `border_inactive` | `#293347` | Unfocused border |
| `font` | `Inter` | Panel UI font |
| `animations` | `true` | Window open/close and workspace motion |
| `reduce_motion` | `false` | Disable movement animations |
| `reduce_motion_animations` | `none` | `none`, or `fade` for a closing-window fade |
| `reduce_motion_fade_ms` | `120` | Fade duration when reduced motion is `fade` |
| `animation_ms` | `160` | Default animation duration (0–1000 ms) |
| `animation_open_ms` | inherited | Open-animation duration (`-1` inherits) |
| `animation_workspace_ms` | inherited | Workspace-animation duration (`-1` inherits) |
| `animation_close_ms` | inherited | Close-effect duration (`-1` inherits) |
| `animation_curve` | `ease-out-cubic` | Global timing curve for open/workspace |
| `animation_open_curve` | inherited | Open timing curve |
| `animation_workspace_curve` | inherited | Workspace timing curve |
| `animation_close_curve` | `smoothstep` | Close timing curve |
| `bezier` | — | Named cubic-bezier: `name, x1, y1, x2, y2` |
| `spring` | — | Named spring: `name, damping, frequency` |
| `animation_open_x` / `_y` | `0` / `18` | Open-animation start offset in px |
| `animation_workspace_offset` | `54` | Workspace-slide start offset in px |
| `animation_close_scale` | `0.92` | Close snapshot final scale (0–1) |
| `animation_close_fade` | `true` | Fade the close snapshot |
| `shadows` | `true` | Layered window shadows |
| `corner_radius` | `10` | Rounded window radius (0–64; scenefx build) |
| `blur` | `true` | Backdrop blur for translucent surfaces (scenefx build) |
| `blur_radius` | `6` | Blur radius (1–32) |
| `blur_passes` | `3` | Blur quality passes (1–5) |

`animations = false`, `reduce_motion = true`, or `animation_ms = 0` disables
motion. The panel launcher fades and scales in, reveals result rows in a short
stagger, and slides its selection marker between results.

### 6.3 Panel and shell

`panel`/`autostart_panel` and `panel_modules` are compositor startup settings
and stay in `config`. The remaining keys normally live in `panel.conf`; they
still work in `config` for compatibility.

| Key | Default | Meaning |
| --- | --- | --- |
| `panel` / `autostart_panel` | `true` | Auto-start `tessa-panel` per output |
| `panel_modules` | all | Enabled panel parts: `background`, `bar`, `launcher`, `popovers`, `notifications`, `toasts`, `tray`, `media`, `audio`; also `all`/`none` |
| `bar_height` | `44` | Bar thickness/height (32–96) |
| `bar_position` | `top` | Bar edge: `top`, `bottom`, `left`, or `right` |
| `panel_style` | `classic` | `classic` keeps separate popovers; `unified` adds the control center |
| `control_features` | `all` | Control-center features (CSV, `all`, `none`) |
| `window_switcher` | `snapshot` | Alt+Tab switcher: live `snapshot` previews, `icons`, or `off` |
| `control_action` | - | Custom quick action `Label \| command` (repeatable) |
| `bar_top_margin` | `12` | Distance from the chosen edge (0–64) |
| `bar_side_margin` | `16` | Inset along the bar; left/right for top/bottom, top/bottom for left/right (0–128) |
| `logo_text` | `TESSA` | Brand label on horizontal bars; empty shows the mark alone |
| `logo_icon` | empty | PNG drawn in place of the five-petal mark (absolute or `~/...`); invalid files fall back to the mark |
| `panel_bg` | `#0e131d` | Base panel background used by `panel.background` and per-surface defaults |
| `panel_fg` | `#edf2fa` | Base panel foreground used by `panel.foreground` and per-surface defaults |
| `bar_layout` | logo, workspaces, chips, clock, battery, network, volume, stats, media, tray, status | Comma/space-separated module list; selects and orders the right cluster. `layout`, `groups`, `mode`, and `effects` are opt-in context modules |
| `bar-font`, `launcher-font`, `popover-font`, `toast-font` | `font` | Per-surface fonts |
| `bar-fg`, `launcher-fg`, `popover-fg`, `toast-fg` | `panel_fg` | Per-surface foreground colors |
| `bar-bg`, `launcher-bg`, `popover-bg`, `toast-bg` | `panel_bg` | Per-surface background colors |
| `launcher_entry` | — | Extra launcher item `Name \| command`; repeatable |
| `launcher_style` | `centered` | Launcher layout: `centered` (Wofi-style) or `start` (Windows-style menu anchored to the bar edge) |
| `panel_renderer` | `cairo` | Background renderer: `cairo` or `gpu` (EGL/GLES2; falls back to Cairo) |
| `overlay_renderer` | `cairo` | Launcher/popover presentation: `cairo` or `gpu` (cached Cairo texture, GPU scale/fade) |
| `wallpaper_engine` | `cairo` | With `panel_renderer = gpu`: `cairo` texture or `procedural` GPU-generated Vermilion Ink |
| `wallpaper_animation` | `off` | GPU wallpaper motion: `off`, `on`, or `auto` (pause on battery and after `wallpaper_idle_pause`) |
| `wallpaper_idle_pause` | `120` | Seconds without input before `auto` pauses; `0` disables the idle pause |
| `wallpaper_fps` | `30` | GPU wallpaper frame rate (1–120) |
| `power_lock` | `loginctl lock-session` | Power-menu Lock |
| `power_suspend` | `systemctl suspend` | Suspend |
| `power_reboot` | `systemctl reboot` | Reboot |
| `power_off` | `systemctl poweroff` | Power Off |
| `screenshot_dir` | `~/Pictures/Screenshots` | PNG output directory |
| `volume_status` | empty | Volume status command; auto-detects `wpctl`/`pactl`/`amixer` |
| `volume_up` | empty | Volume-up command |
| `volume_down` | empty | Volume-down command |
| `volume_mute` | empty | Mute-toggle command |

`control_features` accepts `wifi`, `bluetooth`, `focus`, `notifications`,
`media`, `volume`, `brightness`, `power_profile`, `battery`, `quick_actions`,
`tray`, `calendar`, and `power`, separated by commas, spaces, or `|`.
`control_action` is repeatable up to four times.

`window_switcher = snapshot` (default) renders live per-window previews for
all outputs and workspaces. `icons` shows app monograms; `off` disables the
switcher. See [Window switcher](#window-switcher).

Changing bar geometry or `bar_position` recreates the bar layer surface and
updates its exclusive zone. On `left`/`right` the bar becomes a vertical strip:
workspaces and window chips stack from the top, and status modules stack upward
from the bottom. The launcher and popovers anchor to the chosen edge.

`panel_renderer = gpu` with the default `wallpaper_engine = cairo` keeps Cairo as
the source of truth for the wallpaper: the panel renders it once, uploads it as
a texture, and an EGL/GLES2 shader adds the optional water/ink motion.
`wallpaper_engine = procedural` instead generates the gradient, ink, sun, and
water directly in the shader and only uploads the small corner mark; palette
changes cross-fade over 300 ms. `wallpaper_image` and `wallpaper_shader` keep
the texture path. `wallpaper_animation = auto` pauses on
battery power, after `wallpaper_idle_pause` seconds without input, and whenever
a fullscreen window is visible; `on` ignores the battery and idle checks but
still pauses for fullscreen and overlays. It needs a usable client-side EGL/GLES
stack that can present to the compositor; Mesa's llvmpipe can work even in a
headless pixman session. Systems without EGL/GLES, with a broken driver, or
with a compositor that cannot import the resulting buffers log the reason and
fall back to Cairo automatically. Set `TESSA_GPU_DISABLE=1` to force Cairo.
Builds made with `-Dgpu=false` omit the EGL/GLES dependency entirely.

### 6.4 Input and gestures

| Key | Default | Meaning |
| --- | --- | --- |
| `kb_layout` | environment | XKB layout (e.g. `us,de`) |
| `kb_variant` | empty | XKB variant |
| `kb_options` | empty | XKB options (e.g. `grp:alt_shift_toggle`) |
| `kb_model` | empty | XKB model |
| `kb_rules` | empty | XKB rules |
| `repeat_rate` | `25` | Repeat rate |
| `repeat_delay` | `600` | Delay before repeat (ms) |
| `leader` | unset | Leader chord such as `SUPER+SPACE` |
| `leader_timeout` | `1000` | Leader-mode timeout in ms; `0` keeps it active |
| `mode_timeout` | `0` | Timeout for the current named mode in ms |
| `gestures` | `true` | Touchpad gestures |
| `gesture_fingers` | `3` | Fingers for workspace/launcher swipes (2–5) |
| `gesture_workspace_threshold` | `400` | Horizontal swipe threshold (20–1000) |
| `gesture_launcher_threshold` | `300` | Upward swipe threshold (20–1000) |
| `touch` | `true` | Accept touch devices |
| `tablet` | `true` | tablet-v2 tools and pads |
| `pointer_constraints` | `true` | `pointer-constraints-v1` |
| `cursor_theme` | system default | Xcursor theme name; empty uses the system default |
| `cursor_size` | `24` | Cursor size in logical pixels (16–96) |
| `input` / `input-rule` | — | Per-device libinput rule; repeatable |

`input` rules are described in section 11. Cursor theme and size reload live;
an unknown theme leaves the previous cursor active.

`Super+R` also rebuilds keymaps.

### 6.5 X11 and IME

| Key | Default | Meaning |
| --- | --- | --- |
| `xwayland` | `true` | Start `xwayland-satellite` and export `DISPLAY` |
| `xwayland_display` | `auto` | `auto` or an explicit `:0` etc. |
| `xim` | `true` | Export `XMODIFIERS` for X11 clients |
| `xim_server` | `fcitx` | XIM server name |
| `xim_start` | empty | Command started after the X display appears |
| `linux_dmabuf` | `true` | Advertise `zwp_linux_dmabuf_v1`; auto-disabled on vmwgfx |

### 6.6 Startup, hooks, and automation

| Key | Meaning |
| --- | --- |
| `startup` | Command run once at startup |
| `hook` | `<event> <command>` lifecycle hook; repeatable |
| `event-rule` | Conditional event command; see section 8.8 |
| `include` | Split configuration across files |

See the event table in section 13.

---

## 7. Default Bindings and Mouse

### Keyboard

| Binding | Action |
| --- | --- |
| `Super+Return` | Terminal |
| `Super+D` | Launcher |
| `Super+V` | Clipboard history |
| `Super+Shift+S` | Screenshot UI |
| `Super+M` | MPRIS media controls |
| `Super+Shift+T` | StatusNotifier tray |
| `Super+Shift+A` | Volume popover |
| `Super+T` | Cycle through `layout_cycle` (four original layouts by default) |
| `Super+Q` | Close focused window |
| `Super+Shift+E` | Quit Tessa |
| `Super+R` | Reload config |
| `Super+1` … `Super+9` | Switch workspace |
| `Super+Shift+1` … `9` | Move window to workspace |
| `Super+H/J/K/L` | Focus left/down/up/right |
| `Super`+left-drag | Reorder a tiled window; inserts a column in scrolling |
| `Super`+wheel | Scroll the viewport in a scrolling layout |
| `Super+Shift+H/J/K/L` | Swap/move in that direction, or to an adjacent output |
| `Super+Space` | Toggle floating |
| `Super+F` | Toggle fullscreen |
| `Super+grave` | Toggle the scratchpad |
| `Super+Shift+grave` | Move the focused window to/from the scratchpad |
| `Super+Shift+G` | Group/ungroup tiled windows on the workspace |
| `Super+Escape` | Spawn `swaylock` |
| `Super+Tab` / `Super+Page_Up` | Cycle windows; cycles tabs when a group is focused |
| `Super+Shift+Tab` | Open the Scene deck |
| `Alt+Tab` / `Alt+Shift+Tab` | MRU window switcher; hold Alt, release to commit |
| `Super+Ctrl+H/L` | Shrink/grow master ratio |
| `Super+Alt+H/L` | Shrink/grow floating width |
| `Super+Alt+J/K` | Grow/shrink floating height |

Use XKB keysym names. `Super`, `Logo`, and `Win` are equivalent modifiers.

```ini
bind = SUPER+Return terminal
bind = SUPER+d launcher
bind = SUPER+1 workspace 1
bind = SUPER+SHIFT+1 move-to-workspace 1
bind = SUPER+h focus left
bind = SUPER+SHIFT+h move left
bind = SUPER+ctrl+h ratio -0.03
bind = SUPER+SHIFT+r enter-mode resize
```

Actions: `terminal`, `spawn`, `close`, `quit`, `workspace`,
`move-to-workspace`, `focus`, `move`, `toggle-float`, `toggle-fullscreen`,
`toggle-scratchpad`, `move-to-scratchpad`, `special`/`toggle-special`,
`move-to-special`, `toggle-group`, `group-next`,
`group-prev`, `group-add`, `group-remove`,
`focus-next`, `focus-prev`, `launcher`, `clipboard`, `screenshot`, `media`,
`tray`, `audio`, `window-switcher`, `scene-switcher`, `reload`, `ratio`, `toggle-layout`, `set-layout`,
`resize-width`, `resize-height`, `focus-column-*`, `move-column-*`,
`move-window-up/down`, `consume-window`, `expel-window`,
`column-width-cycle`, `column-width-cycle-back`, `column-width-set`,
`column-width-maximize`, `center-column`, and `enter-mode`.

### Mouse

- Click a window to focus; click a bar chip to focus it
- Right-click a bar chip to close the window
- Scroll over the bar to cycle workspaces
- `Super+left-drag` moves a floating window; on a tiled window it reorders tiles
- `Super+right-drag` resizes a floating window
- In scrolling mode, `Super+wheel` scrolls the viewport
- Client-side titlebar drags work for floating windows
- Click `TESSA` for the launcher, right-click for the power menu
- Click the clock for the calendar

---

## 8. Layouts and Rules

### 8.1 Built-in layouts

- **master**: master area plus a vertical stack; `master_ratio`, `master_count`
- **mosaic** (`spiral`): recursive spiral for up to eight windows; falls back
  to **grid** when the configured minimum tile cannot be maintained, and to
  **master** above eight windows
- **grid**: `ceil(sqrt(n))` columns; the last row is centered; `grid_columns`
  can fix the column count
- **columns** (`column`): equal-width full-height columns
- **scrolling** (`scroll`, `scroller`): Niri-style horizontal column strip
- **monocle**: the focused tiled window fills the workspace
- **stacking** (`deck`): master area plus overlapping stack cards
- **custom** (`helper`): external layout helper

`Super+T` cycles the built-in layouts. The default cycle is the original four;
add new modes explicitly with `layout_cycle`. `custom` is not in the default
cycle; select it explicitly with `set-layout custom`. `layout_N` only seeds
workspaces with no saved/runtime choice. Runtime choices are persisted in
`outputs.conf`.

### 8.1.1 Scrolling, monocle, and stacking

- **scrolling**: Niri-style horizontal columns. New windows become a column
  next to the focused column. Each column has a proportion or fixed width; a
  column can contain multiple windows via `consume`.
- **monocle**: the focused tiled window fills the usable area; other tiled
  windows are hidden until focused.
- **stacking** (alias `deck`): the first `master_count` windows use the master
  area, and the remaining windows overlap in the right stack area. The focused
  card is raised.

Scrolling keys:

```ini
layout = scrolling
default_column_width = 50%       # 50%, 0.5, or a fixed 640
column_width_presets = 33.333%,50%,66.667%
center_focused_column = never    # never, always, on-overflow
animation_view_ms = 180
layout_cycle = master,scrolling,monocle,stacking
```

In scrolling mode, `focus left/right` and `move left/right` operate on columns;
`focus up/down` and `move up/down` operate within a column. The explicit
actions are `focus-column-*`, `move-column-*`, `move-window-up/down`,
`consume-window`, `expel-window`, `column-width-cycle`,
`column-width-cycle-back`, `column-width-set`, `column-width-maximize`, and
`center-column`.

`consume-window` appends the active window of the right column to the focused
column. `expel-window` moves the bottom window of the focused column into a new
column on the right. Grouped windows behave as a single tabbed column;
consume/expel is refused while a group is involved.

`swap` and `reorder` work on the flat tiled order and are refused while the
workspace is scrolling; use `column-move`, `move-window-*`, or a tile drag
there.

Column state (order, width, viewport) is session state. Switching away from
scrolling flattens the column order into the normal tiled order so the next
layout preserves it, but multi-window columns and per-column widths are not
restored when scrolling is selected again. The layout mode itself is persisted
normally.

`layout_cycle` accepts a comma-separated list of layout names. The default is
`master,mosaic,grid,columns`; add `scrolling`, `monocle`, or `stacking` to make
them reachable with `Super+T`.

### 8.2 `workspace-rule`

```ini
workspace-rule = ws=2; layout=grid; gaps=4; outer-gaps=8; master-ratio=0.65
```

Keys: required `ws=1..9`, plus `layout`, `gaps`, `outer-gaps`,
`master-ratio=0.15..0.9`, `master-count=1..8`, `mosaic-ratio=0.25..0.85`,
`mosaic-min-size=80..600`, `grid-columns=0..8`,
`default-column-width=50%|0.5|640`, `center-focused-column=never|always|on-overflow`,
and `profile=NAME`.

### 8.3 `output-rule`

```ini
output-rule = output=HDMI-A-1; layout=grid; gaps=8; outer-gaps=12
output-rule = output=HDMI-A-1; ws=2; layout=master; master-ratio=0.62
output-rule = output=HDMI-A-1; profile=compact; gaps=4
output-rule = output=HEADLESS-*; accent=#8fd3ff; bg=#0c1118
output-rule = output=HEADLESS-*; border-active=#8fd3ff; border-inactive=#243040
output-rule = output=HEADLESS-*; panel-bg=#111827; panel-fg=#eef2f8
output-rule = output=HEADLESS-*; bg-top=#162038; bg-bottom=#070a12
output-rule = output=HEADLESS-*; bar-height=52; bar-top-margin=8; bar-side-margin=20
output-rule = make=Dell Inc.; model=DELL*; adaptive-sync=on
output-rule = serial=ABC123; adaptive-sync=off
```

Match clauses:

- `output=` / `monitor=`: connector name, for example `HDMI-A-1`
- `make=` / `vendor=`: EDID manufacturer string
- `model=`: EDID model string
- `serial=` / `edid-serial=`: EDID serial number
- Any combination of the above; at least one is required. Every field that is
  present must match. `*` and `?` wildcards are supported.

Layout/tuning keys (optionally narrowed with `ws=`):

- `ws=1..9`: optional; omitted means all workspaces
- `layout=...`
- `gaps=N`, `outer-gaps=N`
- `master-ratio=0.15..0.9`, `master-count=1..8`
- `mosaic-ratio=0.25..0.85`, `mosaic-min-size=80..600`
- `grid-columns=0..8`
- `default-column-width=50%|0.5|640`
- `center-focused-column=never|always|on-overflow`
- `profile=NAME`: apply a named profile before this rule's explicit keys

Theme keys (all workspaces only):

- `accent=#RRGGBB`, `bg=#RRGGBB`
- `border-active=#RRGGBB`, `border-inactive=#RRGGBB`
- `panel-bg=#RRGGBB`, `panel-fg=#RRGGBB`
- `bg-top=#RRGGBB`, `bg-bottom=#RRGGBB`
- `bar-height=0..200`, `bar-top-margin=0..128`, `bar-side-margin=0..256`;
  the panel clamps them to 32–96, 0–64, and 0–128 at runtime

Output policy keys (all workspaces only):

- `adaptive-sync=on|off` / `vrr=on|off`: request VRR on the matched output.
  Tessa commits the change immediately and logs whether it succeeded. Outputs
  that do not advertise adaptive-sync support ignore the request. Removing the
  rule restores the output's state from before Tessa applied a policy; startup
  defaults are normally off.

The compositor applies the output background and border colors. The panel
re-reads the same rule for its own output, so bar height, margins, wallpaper,
and panel colors stay in sync. Theme and adaptive-sync fields are ignored when
`ws=` is present.

#### Named profiles

```ini
profile = compact; gaps=0; outer-gaps=0; master-ratio=0.5; master-count=2
profile = grid3; layout=grid; grid-columns=3; gaps=6; outer-gaps=2
output-rule = output=DP-1; profile=compact; gaps=4
workspace-rule = ws=2; profile=grid3
```

Profiles can be declared before or after the rules that use them. Explicit
keys in the rule override the profile. Profiles cover layout and spacing;
theme keys remain on `output-rule`. An unknown profile is a config error and
the reload is rejected. Workspace profiles can set `layout`, `gaps`,
`outer-gaps`, `master-ratio`, `master-count`, `mosaic-ratio`,
`mosaic-min-size`, and `grid-columns`.

Precedence:

```text
global defaults
  < output rule (all workspaces)
  < workspace-rule
  < output rule with ws=
  < runtime layout choice
```

`Super+Ctrl+H/L` changes the active output/workspace ratio for the current
session. Config reload restores configured values.

### 8.4 `window-rule`

```ini
window-rule = app-id=pavucontrol; float=true
window-rule = title=*Picture-in-Picture*; float=true; position=40,40
window-rule = app-id=firefox; workspace=2
window-rule = app-id=org.example.*; fullscreen=true
window-rule = match=app ~ "^firefox$" && title !~ "Private|Incognito"; workspace=2
window-rule = match=(class == "foot" || class == "Alacritty") && output ~ "^DP-"; float=true
window-rule = title=Chat*; border-active=#4cc9f0; border-inactive=#1b2a41
window-rule = app-id=mpv; opacity=0.9; corner-radius=0; border-width=0
window-rule = title=Picture-in-Picture; opacity=0.85; corner-radius=14; blur=true
```

Match keys:

| Key | Meaning |
| --- | --- |
| `app-id`, `app_id`, `class` | xdg app-id |
| `title` | Window title |
| `output`, `monitor` | Output name |
| `match`, `expr` | Boolean expression with POSIX ERE regexes |

Expression fields are `app` / `app-id` / `class`, `title`, and `output` /
`monitor`. Operators are `==`, `!=`, `~` (regex match), `!~` (regex
non-match), `&&` / `and`, `||` / `or`, `!` / `not`, and parentheses. Quoted
values may contain spaces. Regexes use POSIX extended syntax and are
case-sensitive.

Actions:

| Key | Meaning |
| --- | --- |
| `float=true/false` | Floating or tiled |
| `tile=true/false` | Inverse of `float` |
| `fullscreen=true/false` | Fullscreen |
| `workspace=1..9\|name` | Assign workspace |
| `workspace=special` | Assign to the scratchpad (alias for `scratchpad=true`) |
| `workspace=special:NAME` | Assign to a declared special workspace |
| `special=NAME` | Assign to a declared special workspace (shorthand) |
| `scratchpad=true/false` | Hidden floating scratchpad assignment |
| `size=WxH` | Floating size |
| `width=N`, `height=N` | One floating axis |
| `position=X,Y` | Floating position |
| `border-active=#RRGGBB` | Per-window focused border |
| `border-inactive=#RRGGBB` | Per-window unfocused border |
| `opacity=0.0..1.0` | Window and decoration opacity |
| `corner-radius=0..64` | Per-window rounding (`rounding` is an alias) |
| `blur=true/false` | Per-window backdrop blur |
| `shadow=true/false` | Per-window layered shadow |
| `tearing=true/false` | Allow async tearing for this client when `tearing` is `fullscreen` or `force` (or opt in while the global mode is `off`) |
| `border-width=0..16` | Per-window border thickness; `0` hides it |
| `tint=#RRGGBBAA` | Translucent colour overlay above the content; `none` clears it |
| `shader=NAME` | Offscreen GPU effect: `mono`, `crt`, `vignette`, `pixelate`, or `wave`; `none` clears it |
| `shader-strength=0.0..1.0` | Effect intensity (default `1.0`) |
| `shader-param=N` | Effect parameter; currently the pixelate block size in pixels (default `8`) |
| `animation=true/false` | Enable or disable motion for this window |
| `animation-ms=N` | Base animation duration override (0–1000) |
| `animation-open-ms`, `animation-workspace-ms`, `animation-close-ms` | Per-kind duration override |
| `animation-curve=NAME` | Open/workspace curve override |
| `animation-open-curve`, `animation-workspace-curve`, `animation-close-curve` | Per-kind curve override |

Patterns use `*` and `?`. Simple keys and `match` are combined with AND. Rules
run in file order and later matches win, including border colors and visual
effects. Invalid expressions or regexes are reported with file/line diagnostics
and reject the reload. Structural actions (`float`, `workspace`, `size`,
`position`, `fullscreen`) run at map time and on config reload. Decorative
actions (`border-*`, `opacity`, `corner-radius`, `blur`, `shadow`,
`tearing`, `border-width`) also re-evaluate immediately when the title or
app-id changes.
Motion rule keys (`animation*`) use the same pass and apply to the next
transition. Per-rule colors, border width, opacity, rounding, and shadow state
are carried into the close snapshot effect. `corner-radius` and `blur` require a
scenefx build (the default; disabled with `-Dscenefx=false`); opacity, shadows,
and border width work in every build.

Window shaders run in a private surfaceless EGL/GLES2 context and replace the
window content with an offscreen effect texture. The compositor-drawn border,
shadow, and animations stay on the normal path. Shader rules are opt-in and
apply on the next content commit. `TESSA_SHADER_DISABLE=1` and a
`-Dshaders=false` build disable them without changing the config. Close
animations use the unfiltered snapshot, and effects need an importable DMA-BUF
or shared-memory buffer; unsupported formats fall back to normal content for
that window. See [Rendering](RENDERING.md) for the pipeline and limits.

### 8.5 `layer-rule`

Layer-shell surfaces (bars, notifications, wallpaper providers, and other
`zwlr_layer_shell_v1` clients) use a separate rule list:

```ini
layer-rule = namespace=tessa-bar; opacity=0.94; corner-radius=12; blur=true
layer-rule = namespace=tessa-notifications; layer=top; opacity=1; blur=false
layer-rule = namespace=my-wallpaper; layer=background; opacity=1; blur=false
```

Match keys:

| Key | Meaning |
| --- | --- |
| `namespace`, `ns` | Layer namespace with `*`/`?` patterns |
| `output`, `monitor` | Output name with `*`/`?` patterns |
| `layer` | `background`, `bottom`, `top`, `overlay`, or `0..3` |

Actions:

| Key | Meaning |
| --- | --- |
| `opacity=0.0..1.0` | Layer surface opacity |
| `corner-radius=0..64` | Layer surface rounding (`rounding` is an alias) |
| `blur=true/false` | Backdrop blur override |

Layer rules are evaluated in file order and later matches win. With no rule,
layer opacity is `1` and blur follows the global `blur` setting for the top and
overlay layers (background and bottom layers stay unblurred); rounded corners
default to `0`. The panel's surfaces use the namespaces `tessa-bar`,
`tessa-overlay` (launcher, calendar, power, clipboard, media, tray, audio,
screenshot, and extensions popovers), and `tessa-notifications` (toasts). A layer rule with
`layer=top` styles bar and toasts; popovers are on the overlay layer. Rules
re-apply on `Super+R` / config reload. `corner-radius` and `blur` require a
scenefx build (the default; disabled with `-Dscenefx=false`). `tessa-ctl state`
and `tessa-ctl state --json` expose
the effective layer values, and `tessa-ctl config` / `config --json` list the
parsed rules.

### 8.6 External layout helper

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

Tessa starts one helper per output and sends requests asynchronously; the
compositor never blocks waiting for a reply. It advertises `HELLO 2` and sends
tab-separated `LAYOUT\t2`, `OUTPUT`, `AREA`, `OUTER_GAP`, `GAP`, `BORDER`,
`SCALE`, `TRANSFORM`, `COUNT`, and `WINDOW` lines ending in `END`. A protocol-2
helper announces `VERSION 2`; after that each `WINDOW` carries `id`, app-id,
title, focused, and urgent fields. The first request uses the three-field
protocol-1 form. Replies contain an optional `VERSION 2`, tab-separated
`RECT\tid\tx\ty\tw\th` lines, and `END`. Coordinates are absolute logical
coordinates; rectangles include the border. A helper that ignores the `HELLO`
and version lines remains compatible.

The previous rectangles stay visible while a reply is pending; the first reply
falls back to the built-in layout until it arrives. Timeout, crash, malformed
reply, ID mismatch, or missing rectangles fall back to master for that output.
Helpers are retried lazily on the next request after one second (there is no
dedicated retry timer). `stdout` is reserved for the protocol;
diagnostics go to `stderr`. `tessa-ctl dispatch urgent <id> on|off` updates the
urgent flag sent to helpers. See
[CUSTOMIZATION.md](CUSTOMIZATION.md#external-layout-helper).

### 8.7 Workspace pins

```ini
workspace_pin = eDP-1 1
workspace_pin = HDMI-A-1 3
```

Keyboard, gesture, IPC, bar, and foreign-activation switches redirect to the
pinned output. `Super+Shift+<n>` and `CMD move-workspace <n>` move a window to
that output. A missing output ignores the pin. A later pin for the same
workspace wins.

#### Named workspaces

Workspaces 1–9 can have global names:

```ini
workspace-name = 2 Code
workspace-name = 3 Chat
bind = SUPER+2 workspace Code
bind = SUPER+SHIFT+2 move-to-workspace Code
window-rule = app-id=org.mozilla.firefox; workspace=Chat
```

Names are single tokens (no spaces), cannot be numeric, and must be unique.
They are resolved after the whole config is parsed, so a `workspace-name` line
may appear after the bindings and rules that use it. The bar uses the name as
the workspace pill label (very long names are shortened); `tessa-ctl workspace
Code`, `CMD move-workspace Code`, and window-rule `workspace=` all accept the
name. Numeric indices continue to work. Names are presentation and command
aliases: windows remain assigned to the numeric workspace internally, and
names apply to that number on every output.

#### Scratchpad

A scratchpad is a hidden floating overlay per output:

```ini
window-rule = app-id=org.example.notes; scratchpad=true
bind = SUPER+grave toggle-scratchpad
bind = SUPER+SHIFT+grave move-to-scratchpad
```

`Super+grave` shows or hides the focused output's scratchpad windows; when
shown, the first one is focused. `Super+Shift+grave` moves the focused window
into the scratchpad, or returns a scratchpad window to normal tiling. A window
rule can use `scratchpad=true` or `workspace=special`. Changing workspaces hides
the scratchpad. Scratchpad windows are floating, do not count as workspace
occupancy, and remain hidden from the bar while closed. IPC equivalents are
`CMD toggle-scratchpad` and `CMD move-to-scratchpad`.

#### Special workspaces

Named special workspaces are declared once and act as hidden overlays on each
output. They are separate from the scratchpad and can hold tiled or floating
windows:

```ini
special-workspace = notes
special-workspace = tools
window-rule = app-id=org.example.notes; special=notes; size=520x360
bind = SUPER+ALT+n special notes
bind = SUPER+ALT+SHIFT+n move-to-special notes
```

`workspace=special:tools` is accepted as an equivalent rule form. Toggle with
`tessa-ctl special tools`; move the focused window with `tessa-ctl
move-to-special tools`. While a special workspace is visible, normal workspace
windows on that output are hidden. Toggling it off restores the normal workspace
view and focuses the first visible normal window. Special clients do not count
toward workspace occupancy.

#### Window groups

`Super+Shift+G` groups the tiled windows on the active workspace into one
tabbed tile and shows the focused member. `Super+Tab` and `Super+Page_Up`
cycle the group's tabs while a group member is focused; the bar lists only the
visible member. Pressing `Super+Shift+G` again on a grouped window ungroups the
whole group.

```ini
bind = SUPER+ALT+g group-add
bind = SUPER+ALT+SHIFT+g group-remove
```

`group-add` adds the focused tiled window to an existing group on the same
workspace. `group-remove` detaches it and restores normal tiling. Moving a
member to another workspace or scratchpad removes it from the group. Groups are
runtime state and are not persisted across restart. IPC commands are
`toggle-group`, `group-next`, `group-prev`, `group-add`, and `group-remove`.

### 8.8 Event rules

Event rules run a command when a lifecycle event matches an expression:

```ini
event-rule = window-open; match=app ~ "^firefox$" && ws == "2"; run=notify-send "Firefox" "Opened on workspace 2"
event-rule = window-open; match=title == "Mail" && id ~ "^[0-9]+$"; run=touch ~/.local/state/mail-opened
event-rule = workspace-change; match=ws == "3"; run=~/bin/on-workspace-3
```

The event name is the first clause or `event=<name>`. `match` / `expr` is
optional; without it every event of that name runs the command. `run` /
`command` is required. Event rules use the same boolean/regex syntax as window
rules and additionally expose `event`, `ws`, and `id`; numeric values are
compared as strings (`ws == "3"`).

Commands receive the normal hook environment (`TESSA_EVENT`, `TESSA_WINDOW_ID`,
`TESSA_WORKSPACE`, `TESSA_TITLE`, `TESSA_OUTPUT`, `TESSA_ARG`, and so on).
Matching rules run in config order before unconditional `hook` entries. Like
hooks, commands run through `/bin/sh -c` with the compositor's privileges.

### 8.9 Long-lived effect helper

```ini
effect_helper = python3 ~/.config/tessa/effects.py
effect_helper_timeout = 200
```

The effect helper is one long-lived process for all outputs. Tessa sends a
coalesced request whenever window metadata or focus changes. The current
protocol is v2; helpers that reply `VERSION 1` keep using the v1 positional
format.

```text
HELLO\t2
EFFECT\t2
WINDOW\t<id>\t<app-id>\t<title>\t<output>\t<ws>\t<focused>\t<urgent>\t<fullscreen>\t<floating>\t<visible>\t<opacity>\t<radius>\t<blur>\t<shadow>\t<border-width>\t<x>\t<y>\t<w>\t<h>\t[<tint>]
END
```

Every field is tab-separated. `tint` is appended only after the
helper has negotiated v2. Reply:

```text
VERSION\t2
WINDOW\t<id>\topacity=0.9\tradius=16\tblur=on\tshadow=off\tborder-width=2\ttint=#ff8844aa\topen-ms=240\topen-curve=spring-soft
END
```

Every v2 field is optional; omitted fields keep the rule value. `tint` is
`#RRGGBBAA` or `none`; animation fields accept `-1`–`1000` ms and any curve
registered by `bezier`/`spring` or the built-ins. Omitting a window removes its
override. Tessa validates IDs, ranges, and curve names; a timeout, crash,
malformed reply, unknown curve, or bad value drops all overrides and returns to
rule visuals. The helper is retried on the next refresh after one second.
`stdout` is reserved for the protocol. See
[EXTENDING.md](EXTENDING.md#effect-helper-process-protocol). The
protocol never injects code into the compositor.

---

## 9. Monitors and Outputs

### Basics

- Each output has its own wallpaper, bar, and nine workspaces
- One panel process per output
- `Super+1` … `9` applies to the focused output unless pinned
- `Super+Shift+H/J/K/L` can move a window to an adjacent output

### `wlr-randr`

```sh
wlr-randr
wlr-randr --output HDMI-A-1 --mode 2560x1440@144
wlr-randr --output HDMI-A-1 --pos 1920,0
wlr-randr --output eDP-1 --scale 1.5
wlr-randr --output eDP-1 --transform 90
```

To place a left monitor and a center monitor explicitly, use logical layout
coordinates (take the connector names from `wlr-randr`):

```sh
wlr-randr --output DP-1 --pos 0,0
wlr-randr --output HDMI-A-1 --pos 2560,0
```

Settings are saved to `outputs.conf` and restored on the next start. Override
the path with `output_config` or `TESSA_OUTPUT_CONFIG`. The file is mode 0600.
Disabled-output state is not persisted.

### Scaling

- Integer scales render the panel with integer buffers
- Fractional-scale-aware clients receive the exact scale, including runtime
  changes
- Unsupported clients fall back to the ceiling
- The panel uses an integer Cairo buffer scale, so fractional scales are
  downsampled
- XWayland scaling depends on `xwayland-satellite`
- Fractional X11 behavior has not been validated on hardware

### External bars and launchers

Tessa Panel stays the default (`panel = true`). For a layer-shell bar or launcher
from another desktop, disable the integrated panel and start the program from
`startup`:

```ini
panel = false
startup = waybar
```

`panel = false` also turns off Tessa's background, notifications, and built-in
launcher. To keep selected parts of Tessa Panel, leave `panel = true` and
choose the pieces instead:

```ini
# Keep Tessa's launcher and notifications; let Waybar own the bar.
panel = true
panel_modules = launcher,notifications,toasts
startup = waybar
```

`panel_modules` accepts `background` (`wallpaper`), `bar`, `launcher`,
`popovers` (`popover`), `notifications` (`notification`), `toasts` (`toast`),
`tray`, `media`, and `audio` (`volume`); `all`/`none` are aliases. The key also
accepts `panel-modules`. The supervisor restarts the panel when the mask changes. If both
Tessa's bar and an external bar reserve the same edge, both exclusive zones are
honored and the desktop becomes shorter; disable one of them. Run
`tessa-ctl shell` to see which roles Tessa Panel owns and which external
layer-shell clients are present. `tests/external-shell.sh` covers Waybar and
Wofi; `tests/shell-coexistence.sh` covers Quickshell and Noctalia when their
binaries are installed.

Waybar 0.15 uses layer-shell directly and can use the standard workspace and
toplevel protocols:

```jsonc
{
  "layer": "top",
  "position": "top",
  "height": 34,
  "modules-left": ["ext/workspaces"],
  "modules-center": ["wlr/taskbar"]
}
```

Tessa exposes one `ext-workspace-v1` group per output with nine workspaces.
Names come from `workspace-name` (or `1`…`9`); active and urgent state are
updated live, and activating a workspace switches that output. Only the
workspace `activate` capability is advertised because Tessa's workspace set is
fixed. `wlr-foreign-toplevel-management` also follows windows when they move
between outputs.

Wofi and other layer-shell launchers need no compositor-specific setup. To
replace the built-in launcher binding:

```ini
bind = SUPER+D spawn wofi --show drun
```

Use `layer=overlay` for Wofi if fullscreen windows should not cover it. A
Quickshell `PanelWindow` uses layer-shell; `Quickshell.WindowManager` consumes
the ext-workspace groups, and `ToplevelManager` consumes foreign-toplevel.
`focusable: true` panels request `ON_DEMAND` keyboard focus and are focused on
click.

If Tessa Panel and an external bar use the same edge, both reserve space; disable
one. Their trays also compete for the single `org.kde.StatusNotifierWatcher`, so
only one tray is populated. Waybar minimize/maximize requests are no-ops because
Tessa has no such window state.

### Output loss

Clients move to the first remaining output. Removing the last output terminates
the compositor.

---

## 10. Appearance

### Colors and wallpaper

```ini
accent = #e2684f
bg = #0a0f1a
bg_top = #162038
bg_bottom = #070a12
wallpaper_art = true
```

`bg_top` and `bg_bottom` derive from `bg` when omitted. `wallpaper_art = false`
removes the ink/sun artwork.

A PNG can replace the generated wallpaper:

```ini
wallpaper_image = ~/Pictures/wallpaper.png
wallpaper_fit = cover
```

`wallpaper_image` accepts an absolute path or a leading `~/`. The panel loads
the PNG through Cairo and reloads it when the config reloads. `wallpaper_fit`
is `cover` (fill and crop, the default), `contain` (letterbox using `bg`), or
`stretch`. Without an image, the gradient and art above are used. Image load
errors are logged and fall back to the gradient.

A command can render a procedural wallpaper instead:

```ini
wallpaper_shader = ~/.config/tessa/sunset.sh
wallpaper_fit = stretch
```

The command must print a binary PPM header (`P6`, width, height, maxval `255`)
followed by exactly one whitespace byte and `width * height * 3` RGB bytes. It
runs on config load/reload; the frame is cached until the next reload. The
shader takes precedence over `wallpaper_image`. Because the command is invoked
synchronously, keep render time short.

### Bar and fonts

```ini
bar_height = 44
bar_top_margin = 12
bar_side_margin = 16
logo_text = TESSA
logo_icon = ~/Pictures/tessa-mark.png
panel_bg = #0e1320
panel_fg = #eef2f8
font = Inter
bar_layout = logo,workspaces,chips,clock,media,stats,volume,network,battery,tray,status
bar_font = Inter
launcher_font = Inter
popover_font = Inter
toast_font = Inter
bar_fg = #eef2f8
bar_bg = #0e1320
```

`bar_layout` selects visible modules and orders the right-hand cluster from
right to left (the first listed module is closest to the right edge). Recognized
names are `logo` (`mark`), `workspaces` (`workspace`), `chips`
(`title`/`windows`), `clock` (`date`), `battery`, `network`, `volume` (`audio`),
`stats` (`cpu`/`memory`), `media`, `tray`, `status`, `layout`, `groups`, `mode`,
and `effects`; unknown names are ignored. The last four expose compositor
context and are not in the default layout. Logo, workspace pills, and window
chips stay anchored.
`bar-font`, `launcher-font`, `popover-font`, and `toast-font` fall back to
`font`. The `*-fg` and `*-bg` keys override foreground/background per surface.
`panel_bg`/`panel_fg` themselves are the base for the `panel.background` and
`panel.foreground` theme roles and the per-surface defaults; the bar's actual
colors are `bar-bg`/`bar-fg` (or those theme roles). Bar background and
foreground `output-rule` keys still apply per output. The right cluster is
responsive: battery hides at width ≤900, tray at ≤980, network at ≤1000, volume
at ≤1080, stats at ≤1180, and media at ≤1250. Window chips show at most six;
an overflow `+N` badge counts only chips skipped for width before the six-chip
cap, so windows beyond the cap are not necessarily counted.

`logo_text` replaces the `TESSA` wordmark and `logo_icon` replaces the
five-petal mark with a PNG. The icon is scaled to fit a 22 px box inside the
28 px button while preserving its aspect ratio. An empty `logo_text` shows the
icon/mark alone; an empty or unreadable `logo_icon` keeps the built-in mark.
Long labels are shortened with `..` so they do not run into the workspace
pills. Vertical bars have no label area, so they show the icon or mark only.
Both keys are reread on config reload.

For CJK text the panel appends a locale-appropriate fallback list after `font`
(`Noto Sans CJK JP`, `Noto Sans JP`, `Source Han Sans JP`, `IPAGothic`, and
`TakaoPGothic` for Japanese). The explicit Japanese list keeps shared kanji in
Japanese glyph variants instead of letting fontconfig select the Korean CJK
face. Install `noto-fonts-cjk` (Arch), `fonts-noto-cjk` (Debian/Ubuntu), or
`noto-fonts-cjk-sans` (NixOS) if CJK text still renders as empty boxes.

Semantic theme roles let one value drive the compositor and panel:

```ini
theme-role = accent = #e2684f
theme-role = window.border.active = #8fd3ff
theme-role = window.border.inactive = #243040
theme-role = window.background = #0a0f1a
theme-role = panel.background = #0e1320
theme-role = panel.foreground = #eef2f8
theme-role = wallpaper.top = #162038
theme-role = wallpaper.bottom = #070a12
```

Supported roles are `accent`, `window.border.active`,
`window.border.inactive`, `window.background`, `panel.background`,
`panel.foreground`, `bar.background`, `bar.foreground`, `launcher.background`,
`launcher.foreground`, `popover.background`, `popover.foreground`,
`toast.background`, `toast.foreground`, `wallpaper.top`, and
`wallpaper.bottom`. Roles are applied after direct keys, so a role wins over
`accent`, `border_active`, `border_inactive`, `bg`, and the corresponding
panel keys. `panel.background`/`panel.foreground` also fill any per-surface
background/foreground that was not set explicitly. A matching `output-rule`
theme still overrides the global role for that output.

### Borders and shadows

```ini
border_width = 2
border_active = #e2684f
border_inactive = #293347
shadows = true
```

An empty `border_active` uses `accent`. Fullscreen windows have no border or
rounded corners.

### Animation

```ini
animations = true
animation_ms = 160
animation_open_ms = 160
animation_workspace_ms = 220
animation_close_ms = 180
animation_curve = ease-out-cubic
animation_open_curve = ease-out-quint
animation_workspace_curve = ease-in-out-cubic
animation_close_curve = smoothstep
bezier = snap, 0.16, 1.0, 0.3, 1.0
spring = bounce, 0.35, 1.4
animation_open_x = 0
animation_open_y = 18
animation_workspace_offset = 54
animation_close_scale = 0.92
animation_close_fade = true
reduce_motion = false
reduce_motion_animations = fade
reduce_motion_fade_ms = 120
```

- Built-in curves: `linear`, `ease-out-cubic`, `ease-in-out-cubic`,
  `ease-out-quint`, `ease-in-out-quint`, `smoothstep`, `overshoot`, `spring`,
  `spring-soft`, and `spring-bouncy`
- `bezier = name, x1, y1, x2, y2` defines a custom cubic-bezier curve
- `spring = name, damping, frequency` defines a normalized spring curve.
  `damping` is 0.05–2 and `frequency` is 0.25–4 oscillations over the
  animation; lower damping overshoots more, and the curve always ends at 1
- Open: configurable x/y offset (default 0/18 px) with the open curve
- Workspace: configurable ±offset (default 54 px) with the workspace curve
- Close: compositor-initiated closes keep the surface buffer, scale to
  `animation_close_scale`, and optionally fade with the close curve
- Per-kind durations override `animation_ms`; `-1` inherits it
- Client-initiated closes are immediate because the buffer is gone at unmap
- `reduce_motion = true` disables open/workspace movement
- `reduce_motion_animations = fade` keeps only a close fade, with no scale or
  slide, for `reduce_motion_fade_ms`
- `reduce_motion_animations = none` (default) disables close effects too
- Durations are 0–1000 ms; `0` disables that animation

Window rules can override motion per window:

```ini
window-rule = app-id=kitty; animation=false
window-rule = title=Picture-in-Picture; animation-ms=260; animation-curve=spring-soft; animation-close-ms=180; animation-close-curve=bounce
```

| Rule key | Meaning |
| --- | --- |
| `animation=true/false` | Enable or disable all motion for the window |
| `animation-ms=N` | Base duration override (0–1000) |
| `animation-open-ms`, `animation-workspace-ms`, `animation-close-ms` | Per-kind duration override |
| `animation-curve=NAME` | Open/workspace curve override |
| `animation-open-curve`, `animation-workspace-curve`, `animation-close-curve` | Per-kind curve override |

`animation-curve` applies to open and workspace transitions; close uses
`animation-close-curve` (or the global close curve). These overrides are
re-evaluated with the other decorative window-rule fields. The global
`animations = false` and `reduce_motion = true` switches still take precedence.

Lifecycle hooks: `animation-start`, `animation-done`,
`close-animation-start`, and `close-animation-done`.

### scenefx corners and blur

Only in scenefx builds (the default):

```ini
corner_radius = 10
blur = true
blur_radius = 6
blur_passes = 3
```

`corner_radius` applies to client content, border, and shadow. `blur` applies
to translucent clients and top/overlay/popup layers; opaque windows show no
blur. This build requires GLES2 and does not support pixman.

---

## 11. Input

### Keyboard

```ini
kb_layout = us,de
kb_variant =
kb_options = grp:alt_shift_toggle
kb_model =
kb_rules =
repeat_rate = 25
repeat_delay = 600
```

`Super+R` rebuilds keymaps. Empty `kb_*` values use the environment defaults.

### Cursor theme

```ini
cursor_theme = Adwaita
cursor_size = 24
```

The theme is an Xcursor name resolved through the usual `XCURSOR_THEME`,
`XCURSOR_PATH`, `$XDG_DATA_HOME/icons`, and `/usr/share/icons` search path.
Leave `cursor_theme` empty to use the system default. `cursor_size` is clamped
to 16–96 logical pixels. Config reload recreates the cursor manager immediately;
if the new theme cannot be loaded, Tessa logs a warning and keeps the previous
cursor instead of leaving the pointer invisible.

### Per-device input policy

Tessa applies libinput settings with repeatable `input` (or `input-rule`)
lines. Rules are matched against each physical libinput device, merged in file
order, and the last value for each field wins:

```ini
input = type=touchpad; tap=true; tap-drag=true; natural-scroll=true
input = type=touchpad; name=*Precision*; accel-profile=flat; accel-speed=-0.3
input = type=mouse; name=*Mouse*; natural-scroll=false; scroll-method=button; scroll-button=275
input = type=touchpad; dwt=false; click-method=clickfinger
input = type=pointer; left-handed=true
```

Match clauses:

| Key | Meaning |
| --- | --- |
| `type=` / `device-type=` / `kind=` | `any`, `keyboard`, `pointer`, `touchpad`, `mouse`, `touch`, `tablet`, `tablet-pad`, or `switch`; default `any` |
| `name=` / `device=` | libinput device name; `*` and `?` wildcards; omitted matches every device |

Settings:

| Key | Applies to | Values |
| --- | --- | --- |
| `tap=` | touchpad | `true`/`false` |
| `tap-drag=` | touchpad | `true`/`false` |
| `tap-drag-lock=` | touchpad | `true`/`false` |
| `natural-scroll=` | pointer/touchpad | `true`/`false` |
| `left-handed=` | pointer | `true`/`false` |
| `middle-emulation=` | pointer | `true`/`false` |
| `dwt=` / `disable-while-typing=` | touchpad | `true`/`false` |
| `accel-profile=` | pointer | `adaptive` or `flat` |
| `accel-speed=` | pointer | `-1.0` … `1.0` |
| `scroll-method=` | pointer/touchpad | `none`, `two-finger`, `edge`, `button`, or `circular` |
| `scroll-button=` | pointer | evdev button code, `1`–`767` |
| `click-method=` | touchpad | `none`, `button-areas`, or `clickfinger` |
| `tap-button-map=` | touchpad | `lrm` or `lmr` |
| `clickfinger-button-map=` | touchpad | `lrm` or `lmr` |

The type classification uses libinput: a pointer with tap-finger support is a
touchpad, otherwise it is a mouse. Touchpad-specific clauses have no effect on
a mouse, and vice versa. Settings are applied when a device is added and again
on every config reload. Tessa snapshots each device's original libinput state,
so removing a rule restores that state instead of leaving the old override
behind. Only libinput devices are configurable; virtual devices and devices
owned by another backend are left alone.

Headless tests can validate parsing and JSON output but cannot exercise tap or
scroll behavior. Verify touchpad and mouse tuning on real hardware with
`libinput list-devices` for the exact device name.

### Input modes

```ini
mode = resize
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default
mode = default
bind = SUPER+SHIFT+r enter-mode resize
```

Mode bindings match without modifiers and take priority over global bindings.
Set `mode_timeout = 300` inside a mode section to return to `default` after
300 ms without a matching key.

A leader chord enters the `leader` mode:

```ini
leader = SUPER+SPACE
leader_timeout = 1000

mode = leader
bind = f spawn firefox
bind = t spawn kitty
bind = Escape enter-mode default
```

The leader is recognized only in the default mode. Pressing it again, binding
`Escape`, or waiting `leader_timeout` exits. A matching leader-mode binding
runs one action and returns to default unless the action enters another mode.
`leader_timeout = 0` keeps leader mode active until an explicit exit.

### Gestures

```ini
gestures = true
gesture_fingers = 3
gesture_workspace_threshold = 400
gesture_launcher_threshold = 300
```

By default, a horizontal three-finger swipe changes workspace and an upward
swipe opens the launcher. Other finger counts and pinch/hold gestures are
forwarded to the focused client.

### Touch and tablet

```ini
touch = true
tablet = true
pointer_constraints = true
```

Touch includes panel UI. tablet-v2 supports pressure, tilt, rotation, tool
buttons, rings, and strips. pointer-constraints-v1 activates locked/confined
pointers based on focus.

### IME / XIM

Wayland IME uses `text-input-v3` and `input-method-v2`; Fcitx5 + Mozc is
verified in the launcher. For X11, set `XMODIFIERS` and optionally start the
XIM server:

```ini
xim = true
xim_server = fcitx
xim_start = fcitx5 -d
```

`xim_start` runs after the X display socket appears.

Fcitx5 keeps a keyboard grab while it runs. Tessa passes the input method's
virtual-keyboard output back to the focused client, including clients that do
not use `text-input-v3` (for example Firefox), and does not re-enter keyboard
focus when that virtual keyboard is created or destroyed.

---

## 12. Shell Features

### Launcher

- `Super+D`, the `TESSA` mark, or `tessa-ctl launcher`
- Scans normal `.desktop` entries
- Type to filter; `Up`/`Down`, `Enter`, `Esc`, or click
- IME input works
- `launcher_entry = Name | command` adds custom entries
- Config reload updates launcher entries

### Clipboard history

- `Super+V` or the bar
- Up to eight text entries, 16 KiB each, memory only
- Select to put an entry back on the clipboard

`wlr-data-control-v1` is exposed to the session, so any trusted client can read
the selection without keyboard focus. Treat session applications as trusted.

### Screenshot

- `Super+Shift+S`
- Drag for a region, click or `Enter` for the full output
- `Esc` or right-click cancels
- Captures the focused output with `wlr-screencopy`
- Saves PNGs to `screenshot_dir`

### Calendar and power

- Click the clock for the month calendar
- `Left`/`Right`, arrows, or wheel change months; `Home` returns to today
- Right-click `TESSA` for the power menu
- `Up`/`Down`, `Enter`, `Esc`, or click
- Lock/Suspend/Reboot/Power Off commands are configurable

### Control center

`panel_style = classic` (default) keeps the separate clock, volume, media,
tray, Wi-Fi, and Bluetooth popovers. `panel_style = unified` adds a Controls
button to the bar and replaces the bar's popover entry points with one control
center:

- Wi-Fi: NetworkManager scan, signal, WPA2/WPA3-PSK and open networks, hidden
  SSIDs, saved connections, connect/disconnect/forget, radio on/off
- Bluetooth: BlueZ adapter power, discovery, device list, pair/connect/
  disconnect/forget, battery percentage, pairing confirmation and passkey
  prompts
- Focus (do-not-disturb), notification history (50 entries), clear, actions
- Volume and brightness sliders, power profile (power-profiles-daemon)
- Media card with local `file://` artwork, progress, and click-to-seek
- THEME page with six full palettes, accent swatches, base tones, and reset;
  changes apply to the panel, window borders, and wallpaper together
- Battery, lock/suspend/reboot/power off, screenshot, clipboard, settings, and
  up to four `control_action` buttons

`control_features` hides individual features (for example
`control_features = wifi, bluetooth, volume, notifications`). In classic mode
the same key gates the Wi-Fi/Bluetooth popovers and the Bluetooth indicator.
The clock still opens the calendar, the tray opens the tray view, and the
power menu opens the power view in unified mode. From IPC:

```sh
tessa-ctl panel control
tessa-ctl panel wifi
tessa-ctl panel bluetooth
tessa-ctl panel notifications
tessa-ctl panel theme
```

The THEME page is available in unified mode. It writes
`theme-colors.conf` next to the main config and asks the compositor to reload,
so the panel, window borders, and wallpaper change together. The file is
loaded after the main config and any `theme` package; `RESET` deletes it and
returns to the configured palette. Selecting a full palette also stores its
surface backgrounds and foregrounds, while the accent and base rows change one
half of the current palette.

Wi-Fi uses the system NetworkManager D-Bus API. Basic WPA2/WPA3-PSK, open, and
hidden networks are supported; 802.1X/EAP, VPNs, and captive portals are not.
Bluetooth uses BlueZ directly. The pairing agent is registered only by the
primary panel, so pairing on a secondary output is intentionally unavailable.
Notification history is in memory and is shown by the notification-owner panel
only.

Brightness uses `/sys/class/backlight` and logind `SetBrightness`; desktops
without a backlight hide the slider. Power profiles require
power-profiles-daemon. NetworkManager, BlueZ, power-profiles-daemon, and logind
are optional runtime services. If a service is missing, the control center
shows an unavailable state instead of failing the panel.

### Window switcher

`Alt+Tab` opens the task switcher with **all windows on every output and
workspace**, ordered most-recently-used first. `Tab` / `Shift+Tab`, the arrow
keys, and the wheel move the selection; `Enter`, a click, or releasing Alt
commits; `Esc` cancels. `Alt+Shift+Tab` starts from the other end. Committing a
window on another workspace or output switches there, then focuses it. Named
special workspaces are restored too; scratchpad windows are omitted. The
defaults can be overridden with the `window-switcher` action:

```
bind = ALT+Tab window-switcher
bind = ALT+Shift+Tab window-switcher prev
```

`window_switcher` selects the presentation:

- `snapshot` (default): each mapped window is rendered live into a private
  offscreen GPU scene, including subsurfaces, and copied into the panel over
  `ext-image-copy-capture`. Previews update when the window is damaged and are
  capped at 512 px on the longest edge, so 4K and fractional-scale windows are
  never read back at full resolution. Floating and hidden-workspace windows
  get previews too. Each card draws a blurred thumbnail backdrop behind the
  sharp preview.
- `icons`: app monograms only, without capture.
- `off`: the binding does nothing.

The switcher keeps the 12 most recent windows. It requires the
`ext-foreign-toplevel-list-v1`, `ext-image-capture-source-v1`, and
`ext-image-copy-capture-v1` globals, which Tessa provides. If they are
unavailable, it falls back to a single screencopy frame cropped by window
rectangles. `tessa-ctl panel switcher` opens it from IPC.

### Scenes

A Scene is a reusable workspace template: layout, layout tuning, and the
windows/apps that belong there. Save the current workspace, then apply it later
or switch to it from the Scene deck.

```sh
tessa-ctl scene save coding        # save the focused workspace
tessa-ctl scene activate coding    # switch to its workspace and apply it
tessa-ctl scene apply coding 2     # apply the template to workspace 2
tessa-ctl scene list
tessa-ctl scene delete coding
tessa-ctl scene clear              # drop scene tuning on the active workspace
tessa-ctl scene reload             # rescan files edited outside Tessa
```

`Super+Shift+Tab` opens the Scene deck. `Tab` / `Shift+Tab` and the arrow keys
move the selection; `Enter`, a click, or `Space` applies the scene; `Esc` closes
it. Cards show the scene name, workspace, layout, app/live window
counts, and up to four live window previews.

Scene files live in `~/.config/tessa/scenes/<name>.scene` (next to the main
config; override the directory with `TESSA_SCENE_DIR`). They are plain text and
can be edited by hand:

```ini
name = coding
workspace = 3
layout = master
gaps = 10
outer_gaps = 18
master_ratio = 0.62
master_count = 1
mosaic_ratio = 0.64
mosaic_min_size = 180
grid_columns = 0
column_width = 50%
center_focused_column = never

[app]
command = kitty
app_id = kitty
title = ~/src/tessa
floating = false
```

A scene can also carry a visual layer:

```ini
[theme]
accent = #7aa2f7
bg = #070b14
border_active = #7aa2f7
border_inactive = #26324a
panel_bg = #0e1626
panel_fg = #e8eefc
bg_top = #16233f
bg_bottom = #060810

[wallpaper]
image = ~/Pictures/Wallpapers/indigo.png
fit = cover
art = false
```

When the scene is active on a workspace, its accent, window background, and
border colors are used for that output/workspace. The panel process for that
output also applies the scene's bar/launcher/popover/toast colors and switches
to its wallpaper image. Moving to a workspace without a scene clears the
override and restores the base config/output theme. Other outputs keep their
own active scene. A scene without `[theme]`/`[wallpaper]` leaves the base
colors and wallpaper untouched.

Saving reads the effective layout tuning, the current visual tokens, the
configured wallpaper, and the command line of each window from
`/proc/<pid>/cmdline`, so restore can relaunch native Wayland apps. Saving while
another scene is active captures that scene's visual tokens and wallpaper.
XWayland windows (served through `xwayland-satellite`) have no per-window PID;
they are saved by `app_id`/`title` but cannot be relaunched automatically.
Commands are stored as shell-quoted argv in a mode-0600 file; do not publish
scene files that contain secrets in their arguments.

Applying is **non-destructive**: windows already on the target workspace stay,
and only missing scene apps are launched. This means a scene switch can share a
workspace with other windows; use a separate workspace when you want a clean
context. Missing apps are matched as they map and moved to
the scene workspace.

### Notifications

The panel owns `org.freedesktop.Notifications`:

- Replacement, close, expiry
- A 50-entry in-memory history with Focus/DND, clear, and actions in the
  unified control center
- Action buttons and the `default` action
- `image-data`, `image-path`, `icon-name`
- Pango markup
- Routing to the focused output
- `tessa-ctl notify-action <id> <key>`

Not supported: rich HTML beyond Pango, notification sounds, per-notification
output pinning.

### Bar

- Workspace pills
- Window chips (click focus, right-click close)
- CPU/RAM
- Clock/calendar
- Battery
- Default-route network state
- MPRIS media (first player, local album artwork in the control center)
- StatusNotifier tray (no DBusMenu)
- Volume (`wpctl`/`pactl`/`amixer`)
- Up to eight custom status entries

The panel is supervised by the compositor. Tessa watches the panel process with
a Linux pidfd and restarts it with bounded exponential backoff after a crash
(500 ms, 1 s, 2 s, 4 s, then 8 s; after a stable ≥10 s run the failure counter
resets, so the next crash starts at 500 ms again). The notification-owner panel keeps that role across
restarts. Deliberate shutdown and output removal do not restart it. This is
covered by `tests/panel-recovery.sh`.

### Volume

```ini
volume_status = wpctl get-volume @DEFAULT_AUDIO_SINK@
volume_up = wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
volume_down = wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
volume_mute = wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
```

Empty commands auto-detect `wpctl`, `pactl`, then `amixer`.

The audio card has `OUTPUT` and `INPUT` tabs. Each tab shows the active volume,
mute, and the sink/source list; click a device to make it the default output or
input. Input volume and mute use `@DEFAULT_AUDIO_SOURCE@` (`Capture` with
amixer). `Tab` switches tabs, `Up`/`Down` changes the active volume, `m`
toggles mute, and `d` cycles the default device. In unified mode, `panel audio`
and the SOUND card in the control center open the same controls as a page.
Device selection needs `wpctl` or `pactl`; the custom `volume_*` commands
override output only.

### Lock and idle

- `ext-session-lock-v1`
- Default `Super+Escape` runs `swaylock`
- While locked, desktop trees are hidden and virtual-keyboard input is ignored
- If the lock client dies, Tessa terminates the session
- Idle timing is external; use `swayidle`
- `idle-inhibit-v1`, `ext-idle-notify-v1`, and
  `wlr-output-power-management-v1` are exposed
- `wlopm` can power outputs on/off

```sh
swayidle -w \
  timeout 300 'swaylock -f' \
  timeout 600 'wlopm --off "*"' \
  resume 'wlopm --on "*"'
```

### Screen sharing

Install `tessa.portal`, `xdg-desktop-portal-wlr`, and PipeWire. Screenshot and
ScreenCast requests route to the wlr backend when
`XDG_CURRENT_DESKTOP=Tessa`.

---

## 13. Extension API

### 13.1 Socket and commands

The socket is `$TESSA_IPC` or `$XDG_RUNTIME_DIR/tessa.sock`, mode 0600. A
connection receives nothing until it subscribes.

```text
HELLO <version> [<extension-token>]
CMD subscribe state|events|all
CMD state
CMD state-json
CMD config
CMD config-json
CMD extensions
CMD extensions-json
CMD extension-enable <id> on|off
CMD config-compare <path>
CMD perf
CMD perf-json
CMD perf-reset
CMD rendering
CMD rendering-json
CMD workspace <1..9|name> [output]
CMD move-workspace <1..9|name>
CMD toggle-scratchpad
CMD move-to-scratchpad
CMD special <name>
CMD move-to-special <name>
CMD toggle-group
CMD group-next
CMD group-prev
CMD group-add
CMD group-remove
CMD focus <id>
CMD close <id>
CMD spawn <shell command>
CMD launcher [query]
CMD panel <control|theme|wifi|bluetooth|notifications|scenes|scenes-prev|switcher|calendar|power|clipboard|screenshot|media|tray|audio|extensions> [output]
CMD panel module <widget-id>
CMD scene <save|apply|activate|delete|clear|reload|list> ...
CMD layout [name] [output]
CMD column-focus <left|right|first|last>
CMD column-move <left|right|first|last>
CMD column-width <set|cycle|cycle-back|maximize|center> [value]
CMD column-consume
CMD column-expel
CMD window-move <up|down>
CMD swap <id> <id>
CMD reorder <id> <before|after> <target-id>
CMD resize <dx> <dy>
CMD float <id>
CMD status <id> <text>          (or tab-separated for a click command)
CMD reload
CMD notification-action <id> <key>
CMD quit
```

`HELLO <version> [<token>]` is optional and may be sent first. Tessa replies
`VERSION\t1` and a tab-separated `CAPABILITIES` line, then keeps the connection
open for commands. The capability list includes `extensions`, `effects2`, and
`shell-modules`. Unknown/newer versions negotiate down to 1; a non-numeric
version gets `ERR\tinvalid-version`. A supervised extension appends its
`TESSA_EXTENSION_TOKEN`; Tessa replies with `EXTENSION\t<id>\t<permissions>`
after the capability line. An unknown token gets `ERR\tunauthorized`; a
malformed `HELLO` that contains a token is fail-closed and keeps no
permissions. A token handshake clears subscriptions made before authentication,
so re-subscribe afterwards. Scoped clients get
`ERR\tunknown-command\t<command>` for unknown commands.
Clients that send commands directly remain compatible (line protocol 0) and
keep full access. `tessa-ctl hello` prints the negotiated version and
capability list.

`STATE`/`CONFIG` snapshots end with `END`. `OUT` is
`name workspace focused layout`. `WIN` is tab-separated:
`id, workspace, focused, floating, fullscreen, app_id, title, output, x, y, w, h, scratchpad, visible, group-id, group-active, on-screen, column, tile`.
The trailing fields describe scrolling state and are also present in other
layouts: `on-screen` is 1 when the window is currently placed on screen (inside
the scrolling viewport, or the visible monocle/stacking card), `column` is its
scrolling column id (0 when it has none), and `tile` is its 0-based position
inside that column.
`PANEL` is `output, pid, supervised, notify-owner` for the built-in panel
supervisor. The same snapshot also contains:

```
ACTIVE <workspace>
WORKSPACE <n> <name>
MODE <name>
SPECIAL <output> <name>
OCC <workspace> <count>
FOCUSED <window-id>
STATUS<TAB><id><TAB><text><TAB><click-command>
LAYER<TAB><namespace><TAB><output><TAB><layer><TAB><opacity><TAB><radius><TAB><blur>
```

`LAYER` reports mapped layer-shell surfaces (`tessa-background`, `tessa-bar`,
`tessa-overlay`, `tessa-notifications`, or external namespaces). `layer` is
0=background, 1=bottom, 2=top, 3=overlay. `STATUS` and `LAYER` are tab-separated
because their text fields may contain spaces. Raw line clients can set a click
command with `CMD<TAB>status<TAB><id><TAB><text><TAB><command>`;
`tessa-ctl status ... --exec <command>` uses that form.

Scrolling outputs additionally emit one `VIEW` line and one `COL` line per
column. Both use 0-based column indexes and pixel coordinates:

```
VIEW <output> <workspace> <offset> <content-width> <viewport-width> <column-count> <focus-index>
COL  <output> <workspace> <index> <x> <width> <focused> <maximized> <tabbed> <window-count>
```

`offset` is the horizontal scroll position of the column strip, `x` is the
column's screen position (already offset), and `tabbed` marks a column that
holds a window group.

`EXT` lines describe supervised extensions:
`EXT <id> <state> <api> <pid> <ready> <restarts> <enabled> <permissions>`.
States are `disabled`, `blocked`, `stopped`, `starting`, `running`, `ready`,
and `failed`; `starting` is reserved and not currently emitted. A `ready` flag
means the process authenticated with its token; a running process that has not
done so is still `running`.

`tessa-ctl` wraps the common operations:

```sh
tessa-ctl state
tessa-ctl hello
tessa-ctl extensions [--json]
tessa-ctl extension-enable weather off
tessa-ctl config
tessa-ctl config-check [file]
tessa-ctl config-diff file
tessa-ctl config-edit [file]
tessa-ctl perf [--json] [--reset]
tessa-ctl perf --watch=2
tessa-ctl rendering [--json]
tessa-ctl events [topic]
tessa-ctl workspace 3 [output]
tessa-ctl special notes
tessa-ctl move-to-special notes
tessa-ctl spawn foot -T notes
tessa-ctl launcher fire
tessa-ctl panel calendar
tessa-ctl panel extensions
tessa-ctl layout grid
tessa-ctl column-focus right
tessa-ctl column-move left
tessa-ctl column-width cycle
tessa-ctl consume
tessa-ctl expel
tessa-ctl window-move down
tessa-ctl swap 3 7
tessa-ctl reorder 7 before 3
tessa-ctl mode resize
tessa-ctl resize 40 30
tessa-ctl dispatch reload
tessa-ctl quit
```

`config-check <file>` validates a candidate without applying it. `config-diff`
loads the candidate transactionally, reports diagnostics, and prints lines from
the compositor's effective configuration that would change; panel-only settings
and comments do not appear in that diff. `config-edit` copies the running config
to a temporary file, opens `$VISUAL`/`$EDITOR`, shows the check/diff, and writes
it back and reloads only after confirmation. If only panel settings or comments
changed, it still offers to save and reload.

`perf` reports render-commit timing from the compositor (`avg_us`, `p50_us`,
`p95_us`, `max_us`, over-budget frames, and whether scenefx is active). The
budget comes from `frame_time_budget`; `--reset` clears the sample window.
`--json` includes an `outputs` array, and the text form appends one `OUTPUT`
line per output. Per-output counters include `presented`, `zero_copy`, `vsync`,
`missed`, `scanout`, `tearing`, and `tearing_fail`. `perf --watch[=SECS]`
repeats the snapshot every second (or the requested interval). `--reset`
clears both the global and per-output windows. `tests/performance.sh` uses this
for the headless animation and full-effect benchmarks.

`rendering [--json]` reports static and runtime rendering capabilities:
direct-scanout mode, tearing mode and whether `wp-tearing-control-v1` is
advertised, whether `linux-drm-syncobj-v1` is active, renderer/backend timeline
support, output color-transform support, scenefx, DRM fds, and per-output
scanout/zero-copy/tearing counters. Use `zero_copy` and `scanout_frames` to
confirm that direct scanout actually happened on real DRM hardware; headless
outputs exercise the state machine but cannot scan out. HDR color management is
not advertised yet; `color_management 0` is expected, and the reason and future
requirements are documented in [RENDERING.md](RENDERING.md).

To disable a feature for troubleshooting:

```ini
direct_scanout = false
tearing = off
explicit_sync = false   # requires a compositor restart
```

### 13.2 JSON and JSON-RPC

- `state --json`: schema 1 plus `tessa`, `line_protocol`, `extension_api`,
  `layout_api`, `effect_api`, outputs, occupancy, focus, statuses, windows,
  layers, and an `extensions` array. Window objects include `tint`, an
  `animation` override object, `tearing`, `on_screen`, `column`, and `tile`
  (the text `WIN` line does not include these).
- `config --json`: schema 1 plus the same API versions, effective config,
  layouts and cycle, workspace tuning, rules, output rules, hooks, event rules,
  profiles, theme roles, `panel_modules`, `animation_view_ms`/`_curve`,
  extension manifests, and diagnostics.
- Reject unknown schema versions

The same socket accepts JSON-RPC 2.0 requests as one-line JSON objects:

```sh
tessa-ctl rpc '{"jsonrpc":"2.0","id":1,"method":"hello"}'
tessa-ctl rpc '{"jsonrpc":"2.0","id":7,"method":"state"}'
tessa-ctl rpc '{"jsonrpc":"2.0","id":"cfg","method":"config"}'
tessa-ctl rpc '{"jsonrpc":"2.0","id":"sub-1","method":"subscribe"}'
```

Methods: `hello`/`capabilities`, `ping`, `state`, `config`, `subscribe`, and
`unsubscribe`. Every response echoes the request `id`. `hello` reports
`protocol: "tessa-jsonrpc"`, `version: 1`, `line_protocol: 1`, `tessa`,
`extension_api`, `layout_api`, `effect_api`, and the capabilities `state`,
`config`, `events`, `subscriptions`, `request-ids`, `extensions`, `effects2`.
Errors use standard JSON-RPC codes (`-32700` parse error, `-32601` unknown
method).

After `subscribe`, lifecycle events arrive as notifications:

```json
{"jsonrpc":"2.0","method":"event","params":{"name":"workspace-change","ws":2,"previous-ws":1,"output":"eDP-1","subscription":"sub-1"}}
```

The event plane remains line-oriented for existing clients; JSON-RPC
subscribers receive JSON notifications with the same fields.

### 13.3 Events

Events are `EVENT\t<topic>\tkey=value...`, delivered only to subscribers and
best-effort.

| Topic | When | Fields |
| --- | --- | --- |
| `startup` | Startup complete | — |
| `shutdown` | Shutdown | — |
| `window-open` | Toplevel mapped | id, ws, app, title, output |
| `window-close` | Mapped toplevel destroyed | id, ws, app, title, output |
| `window-focus` | Focus changed/cleared | id, previous, ws, app, title, output |
| `workspace-change` | Output workspace changed | ws, previous-ws, output |
| `special-change` | Special workspace shown/hidden or window moved | ws, output, arg (name; omitted when restoring) |
| `window-moved` | Window moved workspace | id, ws, previous-ws, app, title, output |
| `layout-change` | Layout changed | ws, output, arg |
| `mode-change` | Input mode changed | arg |
| `config-reload` | Successful reload | — |
| `launcher` | Launcher requested | arg, output |
| `panel` | Panel popover requested | arg, output |
| `notification-action` | Notification action | id, action |
| `output-added` | Output initialized | output, arg |
| `output-removed` | Output removed | output, arg |
| `animation-start` | Open/workspace slide starts | id, ws, output, arg (`open`/`workspace`) |
| `animation-done` | Open/workspace slide finishes | id, ws, output, arg |
| `close-animation-start` | Close snapshot starts | id, ws, output, arg (`close`) |
| `close-animation-done` | Close snapshot finishes | id, ws, output, arg |
| `extension-start` | Supervised extension process started | arg (extension id) |
| `extension-ready` | Extension authenticated with its token | arg |
| `extension-failed` | Extension exited unexpectedly | arg |
| `extension-stop` | Extension disabled or stopped deliberately | arg |

### 13.4 Hooks

```ini
hook = window-open notify-send "Window opened" "$TESSA_TITLE"
hook = animation-done echo "$TESSA_ARG $TESSA_WINDOW_ID" >> ~/.cache/tessa-anim.log
```

Hooks run asynchronously through `/bin/sh` with the session user's privileges.
Multiple hooks per event are allowed but not ordered.

Environment: `TESSA_EVENT`, `TESSA_WINDOW_ID`, `TESSA_PREVIOUS_ID`,
`TESSA_WORKSPACE`, `TESSA_PREVIOUS_WORKSPACE`, `TESSA_APP_ID`, `TESSA_TITLE`,
`TESSA_OUTPUT`, `TESSA_ARG`, `TESSA_FOCUSED_ID`, `TESSA_ACTIVE_WORKSPACE`, and
`TESSA_FOCUSED_OUTPUT`.

### 13.5 Status entries

```sh
tessa-ctl status weather "Tokyo 18C"
tessa-ctl status weather "Tokyo 18C" --exec "weather-app"
tessa-ctl status weather --clear
```

An id is stable; updates replace in place. Max eight entries, up to 159 bytes,
shared across outputs. Clicking sends `CMD spawn <command>`.

### 13.6 Supervised extensions

An extension is a config-declared, supervised process. It speaks the same
control socket as other clients:

```ini
extension = id=weather; command=weatherd; api=1; permissions=read,status
extension = id=theme; command=tessa-theme; api=1; requires=weather; after=weather
```

`api` must be supported by the compositor (currently 1). `permissions` is a
comma-separated subset of `read`, `events`, `status`, `window`, `workspace`,
`layout`, `spawn`, `panel`, `control`, `extensions`; use `all` or `none` for the
extremes. The default is `read,status`. `requires` and `after` are dependency
ids; unknown ids, duplicates, self-dependencies, and cycles are config errors.
`requires` waits until the dependency is `ready`, while `after` only sets the
startup order. The supervisor uses pidfd exit detection and exponential restart
backoff (1 s, 2 s, 4 s, then 8 s), and passes `TESSA_EXTENSION_ID`,
`TESSA_EXTENSION_TOKEN`, `TESSA_EXTENSION_API`, and
`TESSA_EXTENSION_PERMISSIONS`. `extension_ready_timeout` (default 10000 ms,
`0` disables) kills a process that never authenticates. Tokens rotate on every
start; stopping, disabling, crashing, or reloading an extension revokes its
authenticated connections.

The process identifies itself before sending commands:

```text
HELLO 1 $TESSA_EXTENSION_TOKEN
VERSION 1
CAPABILITIES ...
EXTENSION weather read,status
```

A missing or wrong permission gets `ERR forbidden <command>`. Unknown commands
from a scoped extension return `ERR unknown-command <command>`. A malformed
`HELLO` that contains a token is fail-closed and does not regain full access.
This is a cooperative scope check, not a sandbox: the extension runs as the same
user and can read files, the token, or the socket directly. Clients that do not
send a token keep the legacy full-access behavior, including `tessa-panel` and
`tessa-ctl`.

`CMD extensions` and `CMD extensions-json` list the runtime state. `EXT` state
lines use
`EXT <id> <state> <api> <pid> <ready> <restarts> <enabled> <permissions>`;
states are `disabled`, `blocked`, `stopped`, `starting`, `running`, `ready`,
and `failed` (`starting` is reserved and not currently emitted). The JSON
`extensions` array also includes `last_error`, `failures`, and
`next_restart_ms`. `CMD extension-enable <id> on|off` changes the current session
only. The
panel's Extensions popover is opened with `tessa-ctl panel extensions` and
toggles the selected entry with Enter. The full compatibility contract is in
[EXTENSION-API.md](EXTENSION-API.md).

### 13.7 Launcher entries

```ini
launcher_entry = Notes | foot -e nvim ~/notes.md
launcher_entry = Lock screen | swaylock
```

The part before `|` is the display name; the rest is a `/bin/sh` command.

---

## 14. Example Configs

### Minimal

```ini
terminal = foot
panel = true
xwayland = true
animations = true
```

### Two monitors and pinned workspaces

```ini
terminal = foot
gaps = 8
outer_gaps = 12
layout = master

workspace_pin = eDP-1 1
workspace_pin = HDMI-A-1 3

output-rule = output=eDP-1; layout=master; master-ratio=0.6
output-rule = output=HDMI-A-1; layout=grid; gaps=15; outer-gaps=20
output-rule = output=HDMI-A-1; ws=3; layout=columns; gaps=6

window-rule = app-id=pavucontrol; float=true; size=800x600
window-rule = title=Picture-in-Picture; float=true; position=1300,80
```

### Appearance-focused

```ini
accent = #e2684f
bg_top = #162038
bg_bottom = #070a12
wallpaper_art = true

bar_height = 46
bar_top_margin = 12
bar_side_margin = 18
panel_bg = #0d1422
panel_fg = #f1f4fa
font = JetBrains Mono

border_width = 2
border_active = #e2684f
border_inactive = #293347
shadows = true
animation_ms = 220
corner_radius = 14
blur = true
blur_radius = 8
blur_passes = 3

hook = animation-done echo "$TESSA_ARG $TESSA_WINDOW_ID" >> ~/.cache/tessa-anim.log
hook = close-animation-done echo "closed $TESSA_WINDOW_ID" >> ~/.cache/tessa-anim.log
```

### Automation

```ini
startup = fcitx5 -d
hook = workspace-change ~/.config/tessa/on-workspace.sh
hook = window-open [ "$TESSA_APP_ID" = firefox ] && echo "$TESSA_TITLE"

bind = SUPER+SHIFT+r enter-mode resize
mode = resize
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default
mode = default
```

---

## 15. Troubleshooting

### DRM will not start / screen stays black

- Run from a TTY as your normal user, not root
- Confirm the logind/seat session is active
- Confirm access to input devices
- Over SSH, use headless or nested Wayland
- Try `WLR_RENDERER=pixman` on a system without working GL

### Configuration does not apply

```sh
tessa-ctl config-check
tessa-ctl config
```

A reload with errors is rejected. `config-check` checks the last loaded
configuration, so reload after editing.

### Arch build fails: wrong Zig or wlroots

Tessa requires Zig 0.17 and wlroots 0.20. Both are in the official Arch
repositories as `zig` and `wlroots0.20`; build with the PKGBUILD from section
2.2.

```sh
zig version
pkg-config --modversion wlroots-0.20
```

The first command must print `0.17.x`; the second must print `0.20.x`. If
pkg-config finds `/usr/local`, remove that prefix from the build environment or
point `PKG_CONFIG_PATH` at the official installation.

### Arch Debug build fails with R_X86_64_PC64

```text
fatal linker error: unhandled relocation type R_X86_64_PC64
note: in .../Scrt1.o:.sframe
```

Old Zig self-hosted linking could not handle the `.sframe` relocations emitted
by glibc 2.43 and GCC 16. The current `build.zig` forces LLVM/LLD for all three
programs, so this tree is not affected. On an older clone, use a release build
(`-Doptimize=ReleaseSafe`), which already selects LLVM/LLD, or apply the
`use_llvm = true` and `use_lld = true` settings to each executable.

### Panel missing

- Is `tessa-panel` in `PATH`?
- Is `panel = true`?
- Is `TESSA_NO_PANEL` set?
- Check `TESSA_PANEL_BIN`
- Use `TESSA_PANEL_DEBUG=1`

Manual start:

```sh
TESSA_PANEL_OUTPUT=HEADLESS-1 tessa-panel
```

### Cursor is missing

Tessa 0.1.0 did not set a default cursor before a client requested a shape,
so the pointer could stay invisible over the wallpaper or bar. 0.2.0 sets the
default cursor at startup. 0.2.2 also restores it when the pointer enters a
layer surface such as the panel or wallpaper after a client has cleared its
cursor. No `wlr_cursor_warp_closest` or manual output-init refresh is needed;
wlroots applies the cursor image when an output is added.

Install an Xcursor theme on minimal systems:

```sh
sudo apt install xcursor-themes
# Optional modern theme:
sudo apt install adwaita-icon-theme
```

The `tessa` package depends on `xcursor-themes`. Some legacy themes only provide
`left_ptr`; Tessa 0.2.3 checks `default`, `left_ptr`, and `arrow` and logs which
name it selected. If a configured `cursor_theme` cannot be loaded, Tessa logs a
warning and falls back to the system cursor; check the compositor output or
your display-manager journal (Tessa does not create a log file by default).

On a virtual machine, a broken DRM cursor plane can hide a correctly loaded
cursor. Tessa 0.2.3 detects vmwgfx, vboxvideo, bochs, qxl, cirrus, and
virtio_gpu and sets `WLR_NO_HARDWARE_CURSORS=1` automatically, including when
launched directly. `tessa-session` also enables it for other detected VMs. To
force it manually:

```sh
WLR_NO_HARDWARE_CURSORS=1 tessa
```

### Terminal does not start

The default terminal is `kitty`, but older packages only suggested it and did
not install it. Install a terminal:

```sh
sudo apt install kitty
# or, especially on a VM without working 3D acceleration:
sudo apt install foot
```

Tessa 0.2.3 resolves a missing default terminal through `foot`, `kitty`,
`alacritty`, `wezterm`, then `xterm`, and logs which command it uses. An
explicitly configured `terminal = ...` is never replaced. Kitty needs a working
EGL/GL stack; on virtual machines without GPU acceleration use `foot` or set
`terminal = foot`. Check the terminal's stderr and Tessa's log before assuming
the compositor failed to spawn it.

### Kitty appears and then exits

A window that maps and immediately disappears is normally Kitty (or Kitty's
shell) exiting, not a compositor unmap. Check it from a `foot` terminal inside
the same session:

```sh
tessa-ctl spawn foot
WAYLAND_DEBUG=1 kitty
```

- **No `new toplevel` line in Tessa's log:** the command never connected. Check
  `terminal`, `PATH`, and the launcher entry.
- **`new toplevel` followed by the window closing:** Kitty exited. Look for EGL,
  GBM, DBus, or shell-startup errors in Kitty's output. On a VM without working
  3D, use `foot`; forcing software rendering with `LIBGL_ALWAYS_SOFTWARE=1`
  works only when Mesa's software EGL stack is installed.
- **`importing the supplied dmabufs failed` / broken pipe on vmwgfx:** this is a
  vmwgfx linux-dmabuf failure, not a Kitty bug. Tessa 0.2.3 disables
  `linux-dmabuf-v1` on vmwgfx so clients use `wl_shm`. Set
  `TESSA_ALLOW_LINUX_DMABUF=1` only for debugging if you need to re-enable it.
- **A `Terminal=true` desktop entry closes after its command finishes:** this is
  expected. Tessa runs it as `terminal sh -c '<command>'`, so a short-lived
  command produces a short-lived terminal. `kitty.desktop` itself is
  `Terminal=false`.

### X11 apps do not start

- Is `xwayland-satellite` in `PATH` or set via `TESSA_XWAYLAND_BIN`?
- Is `xwayland = true`?
- Is `TESSA_NO_XWAYLAND` set?
- Does the log contain `xwayland: '...' not found; X11 apps disabled`?
- Does the log contain `xwayland: connected on :N`? Tessa 0.2.3 sets `DISPLAY`
  only after this point.

Tessa does not invent a `DISPLAY` value when the satellite cannot start, so an
X11 app should fail clearly rather than connect to a nonexistent server.
`XMODIFIERS` is also exported only with a ready X display and `xim = true`.
When XWayland is enabled, `startup` hooks and `TESSA_STARTUP` run after that
point, so commands such as `fcitx5 -d` see the X environment. Without a
satellite they run immediately.

### IME does not work

- Is an `input-method-v2` IME running?
- Is `XMODIFIERS=@im=fcitx` exported to X11 clients?
- Is `xim_start` running after the display appears?
- Ensure Fcitx5 is not started twice.
- With XWayland disabled there is no X display, so `XMODIFIERS` is intentionally
  not exported.
- If keys stop working in Firefox or another client after Fcitx5 starts, check
  the log for repeated `virtual keyboard added` / `input method grabbed
  keyboard` lines. Current builds avoid that text-input focus loop; restart the
  session after updating.

### External bar or launcher does not work

- Check that the surface exists: `tessa-ctl state | grep LAYER` should show its
  namespace (for example `waybar` or `wofi`).
- If both Tessa Panel and an external bar are anchored to the same edge, both
  reserve space. Set `panel = false` when the external bar should be the only
  bar.
- On Waybar 0.14+ use `ext/workspaces`; the old `wlr/workspaces` module was
  removed. `wlr/taskbar` needs `wlr-foreign-toplevel-management`, which Tessa
  provides.
- Wofi uses layer-shell by default. `--normal-window` is supported but keyboard
  focus depends on the compositor's normal toplevel focus; layer mode is
  recommended.
- Layer surfaces that request `EXCLUSIVE` keyboard focus are focused on map;
  `ON_DEMAND` surfaces are focused when clicked. A client that never requests
  keyboard interactivity cannot receive typed input.
- Tessa Panel, Waybar, and Quickshell all try to own
  `org.kde.StatusNotifierWatcher`; only one tray will be populated.

### Screen sharing fails

- Install `xdg-desktop-portal`, `xdg-desktop-portal-wlr`, and PipeWire
- Install `tessa.portal`
- Check xdpw `chooser_type` and `output_name`
- Set `XDG_CURRENT_DESKTOP=Tessa`

### Corners/blur missing

- Use the default scenefx build (do not pass `-Dscenefx=false`)
- Confirm `scenefx 1` in `tessa-ctl config`
- Make the scenefx library visible at runtime
- Do not use `WLR_RENDERER=pixman`
- Blur is invisible on opaque windows

### Output settings reset

- Check `TESSA_OUTPUT_CONFIG`
- Check `outputs.conf` permissions/content
- Confirm output names are stable
- Disabled-output state is not persisted

### Headless inspection

```sh
./scripts/run-headless.sh
# another shell
export PATH="$PWD/zig-out/bin:$PATH"
export XDG_RUNTIME_DIR=/tmp/tessa-headless
tessa-ctl state
./scripts/screenshot.sh /tmp/tessa.png
```

### Logs

```sh
TESSA_DEBUG=1 ./zig-out/bin/tessa
TESSA_PANEL_DEBUG=1 tessa-panel
TESSA_CTL_DEBUG=1 tessa-ctl state
```

---

## 16. Known Limitations

- **Physical DRM/libinput is exercised on Arch Linux, with device-specific
  gaps.** A real Arch Linux session (including display-manager startup), DRM
  output, keyboard, mouse, IME, and XWayland clients have been validated on
  0.2.4. The 0.2.5 headless suite (97 test scripts) passes on Arch Linux with Zig 0.17,
  wlroots 0.20, and scenefx 0.5 in both plain and scenefx builds, including
  portal ScreenCast, tray, notifications, and pointer interaction. A real
  DRM/libinput session on the new toolchain is still pending. Per-device
  touchpad tuning, VRR/adaptive-sync commits, and unusual multi-GPU/monitor
  combinations still need validation on the matching hardware.
- **Arch packaging uses the official toolchain.** The PKGBUILD targets the
  official `zig` 0.17, `wlroots0.20`, and `scenefx` packages; the effects build
  is the default. Report `makepkg` failures with the compiler and pkg-config
  versions from the troubleshooting section.
- **Fractional scaling is partial.** Fractional-scale-aware Wayland clients get
  the exact scale, but the panel uses integer Cairo buffers and unsupported
  clients use the ceiling. XWayland depends on `xwayland-satellite` and is not
  hardware-validated.
- **Disabled outputs are not persisted.** `wlr-randr --off` is runtime-only.
- **One panel per output.** This isolates crashes but uses more memory.
- **Lock testing is basic.** `ext-session-lock-v1` is implemented; a real
  swaylock/PAM setup still needs a physical-session test.
- **Idle timing is external.** Use `swayidle`, `wlopm`, etc.
- **Clipboard history is text-only and in memory.** Eight entries, 16 KiB each.
- **Notifications are basic.** No rich HTML beyond Pango, sounds, or
  per-notification output pinning.
- **No tray menus.** StatusNotifier registration/icons/activation/status/removal
  work; DBusMenu does not.
- **Media controls the first MPRIS player only.** No album art.
- **System indicators are basic.** Battery reads `/sys/class/power_supply`;
  network uses the default route and `operstate`.
- **Corners/blur are in the default build.** Requires scenefx 0.5 and GLES2;
  use `-Dscenefx=false` for the plain wlroots scene and pixman.
- **Window effects are simple.** Close snapshots only apply to
  compositor-initiated closes; client self-closes are immediate.
- **Profiles cover layout/tuning, not theme values.** Use per-output
  `output-rule` theme keys for output-specific colors and panel dimensions.
- **Structural window rules still need a map or reload.** Decorative rule fields
  (colors, opacity, rounding, blur, shadow, border width) react immediately to
  title/app-id changes, but `float`, `workspace`, `size`, `position`, and
  `fullscreen` are not re-applied on metadata changes.
- **Layout-helper replies are complete snapshots.** Per-output asynchronous
  helpers, focus/urgent metadata, and version negotiation are implemented;
  partial streaming rectangle updates are not.
- **JSON-RPC is read-only plus event subscriptions.** Mutation still uses the
  line commands.
- **Config editing is terminal-based.** `tessa-ctl config-check FILE`,
  `config-diff FILE`, and `config-edit` provide validation, effective-config
  diff previews, and confirmed apply/reload while the compositor is running.
  `config-edit` uses `$VISUAL`/`$EDITOR`; there is no separate GUI editor.
  Validation and diff preview require a running compositor.
- Output `enabled` state, notification output pinning, and custom notification
  sounds are not implemented.

---

## 17. Related Documentation

- [README.md](../README.md) — overview, build, screenshots, default bindings
- [CUSTOMIZATION.md](CUSTOMIZATION.md) — rules, layouts, themes, panel,
  helper protocol
- [EXTENDING.md](EXTENDING.md) — IPC, events, hooks, JSON, status, examples
- [ARCHITECTURE.md](ARCHITECTURE.md) — scene graph, IPC, input, rendering,
  panel internals
- [ROADMAP.md](ROADMAP.md) — implemented and planned items
- [DEVELOPMENT.md](DEVELOPMENT.md) — headless development, tests,
  screenshots, XWayland/IME checks
