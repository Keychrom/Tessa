**English** | [日本語](GUIDE.ja.md)

# Tessa Setup & Customization Guide

This guide collects the setup and customization surface of the current Tessa
tree. It covers the implementation through the 0.6 roadmap; layout-helper v2
and the interactive config editor are the remaining 0.6 items.

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

For a normal install on Ubuntu 26.04, use the prebuilt `.deb` in section 2.1.
On Arch Linux, use the AUR-backed PKGBUILD in section 2.2. The Zig/wlroots
development requirements below apply only to source and package builds.

- Linux (development is tested on Ubuntu 26.04)
- Zig **0.16.0**
- wlroots **0.19** development files
- Wayland, wayland-protocols, xkbcommon, pixman, libdrm, libinput, libseat,
  libudev, EGL/GLES
- Cairo, Pango, GLib/GIO for the panel and notifications
- Fonts: Inter, JetBrains Mono, Noto Sans CJK JP (or equivalent)
- A terminal; the default command is `kitty` (`terminal = foot` is fine)

Ubuntu 26.04 example:

```sh
sudo apt install build-essential pkg-config git \
  libwayland-dev wayland-protocols libwlroots-0.19-dev \
  libxkbcommon-dev libpixman-1-dev libdrm-dev libinput-dev \
  libseat-dev libudev-dev libegl-dev libgles2-mesa-dev \
  libcairo2-dev libpango1.0-dev libglib2.0-dev libfontconfig1-dev \
  fonts-inter fonts-jetbrains-mono fonts-noto-cjk \
  xwayland xauth xterm fcitx5 fcitx5-mozc
```

On Arch Linux, the official `zig` (0.17) and `wlroots0.20` do not match the
Zig 0.16 / wlroots 0.19 ABI. Use AUR `zig0.16-bin` and `wlroots0.19` as shown in
section 2.2 instead.

If wlroots is installed under `/usr/local`, verify that pkg-config and the
shared library are visible:

```sh
pkg-config --modversion wlroots-0.19
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
- scenefx **0.4.1** only for rounded corners and backdrop blur

---

## 2. Install or Build

### 2.1 Binary package (Ubuntu 26.04)

The recommended install uses the `v0.1.0` amd64 package:

```sh
sudo apt update
sudo apt install curl
curl -fLO https://github.com/Keychrom/Tessa/releases/download/v0.1.0/tessa_0.1.0_amd64.deb
curl -fLO https://github.com/Keychrom/Tessa/releases/download/v0.1.0/SHA256SUMS
grep ' tessa_0.1.0_amd64.deb$' SHA256SUMS | sha256sum -c -
sudo apt install ./tessa_0.1.0_amd64.deb
```

The package installs:

- `/usr/bin/tessa`, `/usr/bin/tessa-panel`, `/usr/bin/tessa-ctl`
- `/usr/bin/tessa-session`
- `/usr/share/wayland-sessions/tessa.desktop`
- `/usr/share/tessa/config.example`
- `/usr/share/xdg-desktop-portal/portals/tessa.portal`
- man pages and documentation

Log out and select **Tessa** in GDM, SDDM, greetd, or another display manager.
The session entry starts the installed compositor and panel directly; the
source session installer in section 3.2 is only for development.

Useful optional packages:

```sh
sudo apt install kitty wlr-randr grim dbus \
  fcitx5 fcitx5-mozc \
  xdg-desktop-portal xdg-desktop-portal-wlr pipewire
```

`xwayland-satellite` is not packaged in Ubuntu 26.04. Install it from upstream
if X11 applications are needed; otherwise `xwayland = true` will log a warning
and X11 clients will not start.

Verify the package and configuration:

```sh
dpkg -s tessa
command -v tessa tessa-panel tessa-ctl
tessa-ctl config-check
```

If Tessa was previously installed manually under `/usr/local`, keep only one
installation. `/usr/local/bin` normally precedes `/usr/bin` in `PATH`, so the
manual binaries would otherwise win.

### 2.2 Arch Linux (AUR)

Arch's official repositories currently provide `zig` 0.17 and `wlroots0.20`.
Tessa is built against Zig 0.16 and the wlroots 0.19 ABI, so install the AUR
packages `zig0.16-bin` and `wlroots0.19` first. Do not build against the
official `zig` or `wlroots0.20`.

With an AUR helper, after installing paru or yay:

```sh
sudo pacman -Syu --needed base-devel git
paru -S --needed zig0.16-bin wlroots0.19
```

Without a helper:

```sh
sudo pacman -S --needed base-devel git meson ninja glslang \
  vulkan-headers wayland-protocols xorg-xwayland minisign
mkdir -p ~/aur && cd ~/aur
for pkg in zig0.16-bin wlroots0.19; do
  git clone "https://aur.archlinux.org/$pkg.git"
  (cd "$pkg" && makepkg -si)
done
```

Then build and install Tessa:

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa/packaging/arch
makepkg -si
```

`makepkg` does not fetch AUR dependencies automatically; the two packages
above must already be installed. The resulting `tessa-git` package installs
the same files as the `.deb` (binaries, session entry, config example, portal
selector, man pages, and documentation) under `/usr`.

Verify:

```sh
tessa-ctl config-check
command -v tessa tessa-panel tessa-ctl
```

Useful optional packages:

```sh
sudo pacman -S --needed kitty wlr-randr grim dbus fcitx5 fcitx5-mozc \
  xdg-desktop-portal xdg-desktop-portal-wlr pipewire
```

For X11 applications, use AUR `xwayland-satellite-git`. `scenefx0.4` is only
needed for a custom `-Dscenefx=true` build; the PKGBUILD's default build does
not enable rounded corners or blur. The Arch packaging path has not yet been
exercised on a physical Arch installation; if `makepkg` reports an ABI or
dependency problem, confirm `zig-0.16 version` is 0.16.x and
`pkg-config --modversion wlroots-0.19` is 0.19.x.

### 2.3 Build from source (development)

From the repository root:

```sh
chmod +x scripts/*.sh scripts/tessa-session
./scripts/build.sh
```

Release build:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe
```

`scripts/build.sh` prefers `zig-0.16` when it exists and otherwise uses `zig`;
set `ZIG=/path/to/zig` to choose an explicit 0.16 toolchain. On Arch, this
picks up `/usr/bin/zig-0.16` from `zig0.16-bin`.

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

The default build uses the upstream wlroots scene and supports both GL and
pixman. For rounded corners and backdrop blur, install scenefx 0.4.1 and build:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe -Dscenefx=true
```

This build uses scenefx's GLES2 renderer and cannot run with
`WLR_RENDERER=pixman`. If scenefx is installed under a non-system prefix, set
its pkg-config and library paths for both build and run:

```sh
export PKG_CONFIG_PATH=$HOME/.local/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=$HOME/.local/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
./scripts/build.sh -Dscenefx=true
```

The `corner_radius` and `blur` keys are accepted in the default build but have
no visual effect.

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

The `.deb` and Arch `tessa-git` packages already install the session entry.
Use this only for a source build:

```sh
# Per-user install
./scripts/install-session.sh

# System-wide install
sudo PREFIX=/usr/local ./scripts/install-session.sh
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

---

## 4. Environment Variables

| Variable | Meaning |
| --- | --- |
| `TESSA_CONFIG` | Config path; defaults to `$XDG_CONFIG_HOME/tessa/config` or `~/.config/tessa/config` |
| `TESSA_IPC` | IPC socket path; defaults to `$XDG_RUNTIME_DIR/tessa.sock` |
| `TESSA_OUTPUT_CONFIG` | Output/layout state file; defaults to `$XDG_CONFIG_HOME/tessa/outputs.conf` |
| `TESSA_DEBUG` | Verbose Tessa/wlroots logging |
| `TESSA_PANEL_DEBUG` | Verbose panel logging |
| `TESSA_CTL_DEBUG` | Verbose `tessa-ctl` logging |
| `TESSA_NO_PANEL` | Disable automatic panel start |
| `TESSA_PANEL_BIN` | Override the panel executable |
| `TESSA_PANEL_OUTPUT` | Output name for a manually started panel |
| `TESSA_NO_XWAYLAND` | Disable XWayland start |
| `TESSA_XWAYLAND_BIN` | Path to `xwayland-satellite` |
| `TESSA_SOCKET_NAME` | Explicit Wayland socket name |
| `TESSA_STARTUP` | Extra startup command (prefer the `startup` config key) |
| `WLR_BACKENDS` | `drm`, `headless`, `wayland`, etc. |
| `WLR_RENDERER` | `gles2` or `pixman` (scenefx builds use GLES2) |
| `WLR_HEADLESS_OUTPUTS` | Number of headless outputs |
| `TESSA_RUNTIME_DIR` | Runtime directory used by the headless/screenshot scripts |

---

## 5. Configuration Basics

Copy the example:

```sh
mkdir -p ~/.config/tessa
cp config/config.example ~/.config/tessa/config
```

Format rules:

- `key = value`
- Lines beginning with `#` are comments
- `include = path` loads another file; relative paths are resolved next to the
  including file
- Include depth is limited to 8
- Values can be quoted when they contain spaces
- A `;` cannot be used inside a flat value

Reload and inspect:

```sh
tessa-ctl config                 # effective settings and parsed rules
tessa-ctl config --json          # schema-1 JSON
tessa-ctl config-check           # non-zero on errors
tessa-ctl dispatch reload        # same as Super+R
```

A reload with errors is rejected and the previous configuration remains active.
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
| `layout` | `master` | Default: `master`, `mosaic`, `grid`, `columns`, or `custom` |
| `layout_1` … `layout_9` | inherited | Initial layout for a workspace without a saved/runtime override |
| `layout_helper` | empty | One asynchronous custom layout helper per output |
| `layout_helper_timeout` | `100` | Helper timeout in ms (10–1000) |
| `output_config` | `~/.config/tessa/outputs.conf` | Output and layout persistence file |
| `workspace_pin` | — | `OUTPUT WORKSPACE` pin; repeatable |
| `workspace-rule` | — | Per-workspace layout/spacing rule |
| `output-rule` | — | Per-output (optionally per-workspace) layout, spacing, and theme rule |
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
motion.

### 6.3 Panel and shell

| Key | Default | Meaning |
| --- | --- | --- |
| `panel` / `autostart_panel` | `true` | Auto-start `tessa-panel` per output |
| `bar_height` | `44` | Bar height (32–96) |
| `bar_top_margin` | `12` | Distance from the top (0–64) |
| `bar_side_margin` | `16` | Left/right margin (0–128) |
| `panel_bg` | `#0e1320` | Bar background |
| `panel_fg` | `#eef2f8` | Bar primary text |
| `launcher_entry` | — | Extra launcher item `Name \| command`; repeatable |
| `power_lock` | `loginctl lock-session` | Power-menu Lock |
| `power_suspend` | `systemctl suspend` | Suspend |
| `power_reboot` | `systemctl reboot` | Reboot |
| `power_off` | `systemctl poweroff` | Power Off |
| `screenshot_dir` | `~/Pictures/Screenshots` | PNG output directory |
| `volume_status` | empty | Volume status command; auto-detects `wpctl`/`pactl`/`amixer` |
| `volume_up` | empty | Volume-up command |
| `volume_down` | empty | Volume-down command |
| `volume_mute` | empty | Mute-toggle command |

Changing bar geometry recreates the bar layer surface and updates its exclusive
zone.

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

`Super+R` also rebuilds keymaps.

### 6.5 X11 and IME

| Key | Default | Meaning |
| --- | --- | --- |
| `xwayland` | `true` | Start `xwayland-satellite` and export `DISPLAY` |
| `xwayland_display` | `auto` | `auto` or an explicit `:0` etc. |
| `xim` | `true` | Export `XMODIFIERS` for X11 clients |
| `xim_server` | `fcitx` | XIM server name |
| `xim_start` | empty | Command started after the X display appears |

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
| `Super+T` | Cycle master → mosaic → grid → columns |
| `Super+Q` | Close focused window |
| `Super+Shift+E` | Quit Tessa |
| `Super+R` | Reload config |
| `Super+1` … `Super+9` | Switch workspace |
| `Super+Shift+1` … `9` | Move window to workspace |
| `Super+H/J/K/L` | Focus left/down/up/right |
| `Super+Shift+H/J/K/L` | Swap/move in that direction, or to an adjacent output |
| `Super+Space` | Toggle floating |
| `Super+F` | Toggle fullscreen |
| `Super+Escape` | Spawn `swaylock` |
| `Super+Tab` / `Super+Shift+Tab` | Cycle windows |
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
`focus-next`, `focus-prev`, `launcher`, `clipboard`, `screenshot`, `media`,
`tray`, `audio`, `reload`, `ratio`, `toggle-layout`, `set-layout`,
`resize-width`, `resize-height`, and `enter-mode`.

### Mouse

- Click a window to focus; click a bar chip to focus it
- Right-click a bar chip to close the window
- Scroll over the bar to cycle workspaces
- `Super+left-drag` moves a floating window
- `Super+right-drag` resizes a floating window
- Client-side titlebar drags work for floating windows
- Click `TESSA` for the launcher, right-click for the power menu
- Click the clock for the calendar

---

## 8. Layouts and Rules

### 8.1 Built-in layouts

- **master**: master area plus a vertical stack; `master_ratio`, `master_count`
- **mosaic**: recursive spiral for up to eight windows; falls back to **grid**
  when the configured minimum tile cannot be maintained
- **grid**: `ceil(sqrt(n))` columns; the last row is centered; `grid_columns`
  can fix the column count
- **columns**: equal-width full-height columns
- **custom**: external layout helper

`Super+T` cycles the four built-in layouts. `custom` is not in that cycle;
select it explicitly with `set-layout custom`. `layout_N` only seeds workspaces
with no saved/runtime choice. Runtime choices are persisted in `outputs.conf`.

### 8.2 `workspace-rule`

```ini
workspace-rule = ws=2; layout=grid; gaps=4; outer-gaps=8; master-ratio=0.65
```

Keys: required `ws=1..9`, plus `layout`, `gaps`, `outer-gaps`,
`master-ratio=0.15..0.9`, `master-count=1..8`, `mosaic-ratio=0.25..0.85`,
`mosaic-min-size=80..600`, `grid-columns=0..8`, and `profile=NAME`.

### 8.3 `output-rule`

```ini
output-rule = output=HDMI-A-1; layout=grid; gaps=8; outer-gaps=12
output-rule = output=HDMI-A-1; ws=2; layout=master; master-ratio=0.62
output-rule = output=HDMI-A-1; profile=compact; gaps=4
output-rule = output=HEADLESS-*; accent=#8fd3ff; bg=#0c1118
output-rule = output=HEADLESS-*; border-active=#8fd3ff; border-inactive=#243040
output-rule = output=HEADLESS-*; panel-bg=#111827; panel-fg=#eef2f8
output-rule = output=HEADLESS-*; wallpaper-top=#162038; wallpaper-bottom=#070a12
output-rule = output=HEADLESS-*; bar-height=52; bar-top-margin=8; bar-side-margin=20
```

Layout/tuning keys:

- `output=` / `monitor=`: required; supports `*` and `?`
- `ws=1..9`: optional; omitted means all workspaces
- `layout=...`
- `gaps=N`, `outer-gaps=N`
- `master-ratio=0.15..0.9`, `master-count=1..8`
- `mosaic-ratio=0.25..0.85`, `mosaic-min-size=80..600`
- `grid-columns=0..8`
- `profile=NAME`: apply a named profile before this rule's explicit keys

Theme keys (all workspaces only):

- `accent=#RRGGBB`, `bg=#RRGGBB`
- `border-active=#RRGGBB`, `border-inactive=#RRGGBB`
- `panel-bg=#RRGGBB`, `panel-fg=#RRGGBB`
- `bg-top=#RRGGBB`, `bg-bottom=#RRGGBB`
- `bar-height=32..96`, `bar-top-margin=0..64`, `bar-side-margin=0..128`

The compositor applies the output background and border colors. The panel
re-reads the same rule for its own output, so bar height, margins, wallpaper,
and panel colors stay in sync. Theme fields are ignored when `ws=` is present.

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
| `workspace=1..9` | Assign workspace |
| `size=WxH` | Floating size |
| `width=N`, `height=N` | One floating axis |
| `position=X,Y` | Floating position |
| `border-active=#RRGGBB` | Per-window focused border |
| `border-inactive=#RRGGBB` | Per-window unfocused border |
| `opacity=0.0..1.0` | Window and decoration opacity |
| `corner-radius=0..64` | Per-window rounding (`rounding` is an alias) |
| `blur=true/false` | Per-window backdrop blur |
| `shadow=true/false` | Per-window layered shadow |
| `border-width=0..16` | Per-window border thickness; `0` hides it |
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
`border-width`) also re-evaluate immediately when the title or app-id changes.
Motion rule keys (`animation*`) use the same pass and apply to the next
transition. Per-rule colors, border width, opacity, rounding, and shadow state
are carried into the close snapshot effect. `corner-radius` and `blur` require a
`-Dscenefx=true` build; opacity, shadows, and border width work in every build.

### 8.5 `layer-rule`

Layer-shell surfaces (bars, notifications, wallpaper providers, and other
`zwlr_layer_shell_v1` clients) use a separate rule list:

```ini
layer-rule = namespace=tessa-bar; opacity=0.94; corner-radius=12; blur=true
layer-rule = namespace=tessa-notifications; layer=overlay; opacity=1; blur=false
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
default to `0`. The rules re-apply on `Super+R` / config reload. `corner-radius`
and `blur` require a `-Dscenefx=true` build. `tessa-ctl state` and
`tessa-ctl state --json` expose the effective layer values, and
`tessa-ctl config` / `config --json` list the parsed rules.

### 8.6 External layout helper

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

Tessa starts one helper per output and sends requests asynchronously; the
compositor never blocks waiting for a reply. It advertises `HELLO 2` and sends
`LAYOUT 2`, `OUTPUT`, `AREA`, `OUTER_GAP`, `GAP`, `BORDER`, `SCALE`,
`TRANSFORM`, `COUNT`, and `WINDOW` lines ending in `END`. A protocol-2 helper
announces `VERSION 2`; after that each `WINDOW` carries `id`, app-id, title,
focused, and urgent fields. The first request uses the three-field protocol-1
form. Replies contain an optional `VERSION 2`, `RECT id x y w h` lines, and
`END`. Coordinates are absolute logical coordinates; rectangles include the
border. A helper that ignores the `HELLO` and version lines remains compatible.

The previous rectangles stay visible while a reply is pending; the first reply
falls back to the built-in layout until it arrives. Timeout, crash, malformed
reply, ID mismatch, or missing rectangles fall back to master for that output.
Helpers are retried after one second. `stdout` is reserved for the protocol;
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

### Bar and fonts

```ini
bar_height = 44
bar_top_margin = 12
bar_side_margin = 16
panel_bg = #0e1320
panel_fg = #eef2f8
font = Inter
```

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
`panel.foreground`, `wallpaper.top`, and `wallpaper.bottom`. Roles are applied
after direct keys, so a role wins over `accent`, `border_active`,
`border_inactive`, `bg`, and the corresponding panel keys. A matching
`output-rule` theme still overrides the global role for that output.

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

Only in `-Dscenefx=true` builds:

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

### Notifications

The panel owns `org.freedesktop.Notifications`:

- Replacement, close, expiry
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
- MPRIS media (first player, no album art)
- StatusNotifier tray (no DBusMenu)
- Volume (`wpctl`/`pactl`/`amixer`)
- Up to eight custom status entries

### Volume

```ini
volume_status = wpctl get-volume @DEFAULT_AUDIO_SINK@
volume_up = wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
volume_down = wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
volume_mute = wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
```

Empty commands auto-detect `wpctl`, `pactl`, then `amixer`.

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
CMD subscribe state|events|all
CMD state
CMD state-json
CMD config
CMD config-json
CMD workspace <1..9> [output]
CMD move-workspace <1..9>
CMD focus <id>
CMD close <id>
CMD spawn <shell command>
CMD launcher [query]
CMD panel <calendar|power|clipboard|screenshot|media|tray|audio> [output]
CMD layout [name] [output]
CMD resize <dx> <dy>
CMD float <id>
CMD status <id> <text> [--exec command]
CMD reload
CMD notification-action <id> <key>
CMD quit
```

`STATE`/`CONFIG` snapshots end with `END`. `OUT` is
`name workspace focused layout`. `WIN` is tab-separated:
`id, workspace, focused, floating, fullscreen, app_id, title, output, x, y, w, h`.

`tessa-ctl` wraps the common operations:

```sh
tessa-ctl state
tessa-ctl config
tessa-ctl events [topic]
tessa-ctl workspace 3 [output]
tessa-ctl spawn foot -T notes
tessa-ctl launcher fire
tessa-ctl panel calendar
tessa-ctl layout grid
tessa-ctl mode resize
tessa-ctl resize 40 30
tessa-ctl dispatch reload
tessa-ctl quit
```

### 13.2 JSON and JSON-RPC

- `state --json`: schema 1, outputs, occupancy, focus, statuses, windows
- `config --json`: schema 1, effective config, layouts, workspace tuning,
  rules, output rules, hooks, event rules, profiles, theme roles, diagnostics
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
`protocol: "tessa-jsonrpc"`, `version: 1`, `line_protocol: 1`, and the
capabilities `state`, `config`, `events`, `subscriptions`, `request-ids`.
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
| `window-moved` | Window moved workspace | id, ws, previous-ws, app, title, output |
| `layout-change` | Layout changed | ws, output, arg |
| `mode-change` | Input mode changed | arg |
| `config-reload` | Successful reload | — |
| `launcher` | Launcher requested | arg, output |
| `panel` | Panel popover requested | arg, output |
| `notification-action` | Notification action | id, arg |
| `output-added` | Output initialized | output, arg |
| `output-removed` | Output removed | output, arg |
| `animation-start` | Open/workspace slide starts | id, ws, output, arg (`open`/`workspace`) |
| `animation-done` | Open/workspace slide finishes | id, ws, output, arg |
| `close-animation-start` | Close snapshot starts | id, ws, output, arg (`close`) |
| `close-animation-done` | Close snapshot finishes | id, ws, output, arg |

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

### 13.6 Launcher entries

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

Tessa requires Zig 0.16 and wlroots 0.19. Arch's official `zig` is 0.17 and
`wlroots0.20` is 0.20, so install AUR `zig0.16-bin` and `wlroots0.19` and build
with the PKGBUILD from section 2.2.

```sh
zig-0.16 version
pkg-config --modversion wlroots-0.19
```

The first command must print `0.16.x`; the second must print `0.19.x`. If
`makepkg` cannot find `zig0.16`, install AUR `zig0.16-bin` before building
Tessa. If pkg-config finds `/usr/local`, remove that prefix from the build
environment or point `PKG_CONFIG_PATH` at the AUR installation.

### Arch Debug build fails with R_X86_64_PC64

```text
fatal linker error: unhandled relocation type R_X86_64_PC64
note: in .../Scrt1.o:.sframe
```

Zig 0.16's self-hosted linker cannot handle the `.sframe` relocations emitted
by glibc 2.43 and GCC 16 on Arch. The current `build.zig` forces LLVM/LLD for
all three programs, so update the tree before building. On an older clone, use
a release build (`-Doptimize=ReleaseSafe`), which already selects LLVM/LLD, or
apply the `use_llvm = true` and `use_lld = true` settings to each executable.

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

### X11 apps do not start

- Is `xwayland-satellite` in `PATH` or set via `TESSA_XWAYLAND_BIN`?
- Is `xwayland = true`?
- Is `DISPLAY` inherited by the app?
- Is `TESSA_NO_XWAYLAND` set?

### IME does not work

- Is an `input-method-v2` IME running?
- Is `XMODIFIERS=@im=fcitx` exported to X11 clients?
- Is `xim_start` running after the display appears?
- Ensure Fcitx5 is not started twice.

### Screen sharing fails

- Install `xdg-desktop-portal`, `xdg-desktop-portal-wlr`, and PipeWire
- Install `tessa.portal`
- Check xdpw `chooser_type` and `output_name`
- Set `XDG_CURRENT_DESKTOP=Tessa`

### Corners/blur missing

- Build with `-Dscenefx=true`
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

- **Physical DRM/libinput is not fully validated.** Development uses headless
  pixman, `wtype`, Fcitx5, and `xwayland-satellite`. Real DRM mode setting and
  physical keyboard/mouse/touchpad behavior still need a final hardware pass.
- **Arch packaging is not yet hardware-tested.** The PKGBUILD targets AUR
  `zig0.16-bin` and `wlroots0.19`; report `makepkg` failures with the compiler
  and pkg-config versions from the troubleshooting section.
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
- **Corners/blur are opt-in.** Requires scenefx 0.4.1 and GLES2; no pixman.
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
- **There is no graphical config editor/diff preview yet.**
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
