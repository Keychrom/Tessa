**English** | [日本語](GUIDE.ja.md)

# Tessa Setup & Customization Guide

This guide collects the setup and customization surface of the current Tessa
tree. It covers the implementation through the 0.5 roadmap; 0.6+ items are not
included.

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

## 2. Build

From the repository root:

```sh
chmod +x scripts/*.sh scripts/tessa-session
./scripts/build.sh
```

Release build:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe
```

Artifacts:

- `zig-out/bin/tessa`
- `zig-out/bin/tessa-panel`
- `zig-out/bin/tessa-ctl`

Run tests with:

```sh
sh tests/smoke.sh
sh tests/animations.sh
sh tests/output-rules.sh
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

Run from the active physical console or a TTY, not over SSH:

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
| `layout_helper` | empty | Long-lived custom layout helper command |
| `layout_helper_timeout` | `100` | Helper timeout in ms (10–1000) |
| `output_config` | `~/.config/tessa/outputs.conf` | Output and layout persistence file |
| `workspace_pin` | — | `OUTPUT WORKSPACE` pin; repeatable |
| `workspace-rule` | — | Per-workspace layout/spacing rule |
| `output-rule` | — | Per-output (optionally per-workspace) layout/spacing rule |
| `window-rule` | — | Declarative window rule |
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
| `reduce_motion` | `false` | Disable motion regardless of `animations` |
| `animation_ms` | `160` | Animation duration (0–1000 ms) |
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

Keys: required `ws=1..9`, `layout`, `gaps`, `outer-gaps`, and
`master-ratio=0.15..0.9`.

### 8.3 `output-rule`

```ini
output-rule = output=HDMI-A-1; layout=grid; gaps=8; outer-gaps=12
output-rule = output=HDMI-A-1; ws=2; layout=master; master-ratio=0.62
```

Keys:

- `output=` / `monitor=`: required; supports `*` and `?`
- `ws=1..9`: optional; omitted means all workspaces
- `layout=...`
- `gaps=N`, `outer-gaps=N`
- `master-ratio=0.15..0.9`, `master-count=1..8`
- `mosaic-ratio=0.25..0.85`, `mosaic-min-size=80..600`
- `grid-columns=0..8`

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
```

Match keys:

| Key | Meaning |
| --- | --- |
| `app-id`, `app_id`, `class` | xdg app-id |
| `title` | Window title |
| `output`, `monitor` | Output name |

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

Patterns use `*` and `?`; matching is case-sensitive. Rules run in file order
and later matches win. They run at map time and on config reload; a title change
after mapping does not retrigger them until the next reload.

### 8.5 External layout helper

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

Tessa sends a tab-separated request (`LAYOUT`, `OUTPUT`, `AREA`, `OUTER_GAP`,
`GAP`, `BORDER`, `SCALE`, `TRANSFORM`, `COUNT`, `WINDOW`, `END`) and expects
`RECT id x y w h` lines followed by `END`. Coordinates are absolute logical
coordinates; rectangles include the border.

Timeout, crash, malformed reply, ID mismatch, or missing rectangles fall back
to master for that arrangement. The helper is retried after one second.
`stdout` is reserved for the protocol; diagnostics go to `stderr`. See
`examples/layout-cascade.py` and
[CUSTOMIZATION.md](CUSTOMIZATION.md#external-layout-helper).

### 8.6 Workspace pins

```ini
workspace_pin = eDP-1 1
workspace_pin = HDMI-A-1 3
```

Keyboard, gesture, IPC, bar, and foreign-activation switches redirect to the
pinned output. `Super+Shift+<n>` and `CMD move-workspace <n>` move a window to
that output. A missing output ignores the pin. A later pin for the same
workspace wins.

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

A theme-role system is not implemented yet; these direct values are the current
theme surface.

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
reduce_motion = false
animation_ms = 160
```

- Open: 18 px vertical offset with cubic ease-out
- Workspace: ±54 px horizontal offset with cubic ease-out
- Close: compositor-initiated closes keep the surface buffer, scale to 92%,
  and fade with smoothstep
- Client-initiated closes are immediate because the buffer is gone at unmap
- `animation_ms` is 0–1000

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

### 13.2 JSON

- `state --json`: schema 1, outputs, occupancy, focus, statuses, windows
- `config --json`: schema 1, effective config, layouts, workspace tuning,
  rules, output rules, hooks, diagnostics
- Reject unknown schema versions

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
- **No theme-role system yet.** Theme changes are direct color/size/font values.
- Per-output themes, per-output layout helpers, and asynchronous helpers are
  0.6+ items.
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
