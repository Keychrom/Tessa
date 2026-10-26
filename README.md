**English** | [日本語](README.ja.md)

# Tessa

A quiet, tiled Wayland desktop written in Zig on top of wlroots.

Tessa is a compositor **and** a small shell: a floating taskbar, a searchable
launcher, the wallpaper, tiling layouts, workspaces, and the window borders are
all part of this repository. There is no Waybar/Rofi/wofi dependency.

![Tessa mosaic layout](docs/images/mosaic.png)

![Tessa launcher](docs/images/launcher.png)

The screenshots above are from a headless development session, using foot as the
terminal.

## Status

This is an MVP (`0.1.0`), but it is usable and the core pieces are implemented:

- wlroots 0.19 compositor in Zig (DRM, headless, and nested backends via
  wlroots' autodetection)
- xdg-shell toplevels, layer-shell, data-device and primary-selection
  (clipboard), xdg-activation, xdg-decoration, cursor-shape-v1, and
  wlr-screencopy (grim works)
- master/stack layout **and** the Tessa "mosaic" spiral layout (`Super+T`)
- nine workspaces, floating windows, fullscreen, click-to-focus
- text-input-v3 + input-method-v2 IME relay with input-popup placement;
  verified end to end with Fcitx5 + Mozc in the launcher and Wayland clients
- XWayland through `xwayland-satellite`: rootless X11 apps are managed as normal
  Tessa toplevels, and `DISPLAY` is exported to spawned applications
- integrated panel in Zig + Cairo/Pango:
  - ink/sun wallpaper
  - floating taskbar with workspace pills, window chips, clock, CPU/RAM
  - searchable application launcher with keyboard navigation and IME input
- simple line-based IPC between compositor and panel
- line-based configuration file

It has been built and tested on Ubuntu 26.04 with Zig 0.16.0 and wlroots
0.19.2, primarily in the headless pixman backend with `grim`, `wtype`, Fcitx5 +
Mozc, and X11 clients through `xwayland-satellite`.
**DRM/tty and real keyboard/mouse testing still needs to be done on the target
machine.** See [Known limitations](#known-limitations).

## Why another tiling WM?

Tessa's goal is not to out-feature Hyprland. It is a different, more compact
desktop:

- **Integrated shell.** The bar, launcher, wallpaper, and tiling live together.
  The palette and behavior are consistent because they are one project.
- **A different layout.** Besides master/stack, Tessa has a spiral "tessera"
  mosaic layout (`Super+T`). The name Tessa comes from tessellation.
- **Sumi-e visual language.** Indigo paper, ink washes, a vermilion sun, grain,
  and a floating glass-like bar. The panel is not a generic status bar with a
  theme on top.
- **Small, direct implementation.** Zig + wlroots, a C shim only for Pango
  text, a simple line config, and a line IPC protocol.
- **No JavaScript/TypeScript runtime.** Unlike ShojiWM, the shell and config are
  fixed and small. If you want to program every pixel in TSX, ShojiWM is the
  better tool. If you want animations, blur, and a huge plugin ecosystem,
  Hyprland is the better tool. Tessa sits in the "quiet, integrated, hackable
  Zig compositor" niche.

The terminal is intentionally not implemented from scratch. The default
terminal is **kitty**; set `terminal = foot` if you prefer foot.

## Build

Requirements:

- Zig **0.16.0** (the Ubuntu 26.04 `zig` package is 0.14 and is not enough)
- wlroots **0.19** development files, discoverable with
  `pkg-config --modversion wlroots-0.19`
- Wayland, xkbcommon, pixman, libdrm, libinput, libseat, libudev, EGL/GLES
- Cairo and Pango development files for the panel
- fonts: Inter, JetBrains Mono, and a CJK font such as Noto Sans CJK JP
- optional: [`xwayland-satellite`](https://github.com/Supreeeme/xwayland-satellite)
  for X11 applications (auto-started when `xwayland = true`)
- optional: Fcitx5 + Mozc (or another input method that implements
  `zwp_input_method_v2`) for Japanese input

On Ubuntu 26.04:

```sh
sudo apt install build-essential pkg-config git \
  libwayland-dev wayland-protocols libwlroots-0.19-dev \
  libxkbcommon-dev libpixman-1-dev libdrm-dev libinput-dev \
  libseat-dev libudev-dev libegl-dev libgles2-mesa-dev \
  libcairo2-dev libpango1.0-dev libfontconfig1-dev \
  fonts-inter fonts-jetbrains-mono fonts-noto-cjk \
  xwayland xauth xterm fcitx5 fcitx5-mozc
```

`xwayland-satellite` is not packaged everywhere; install it into `PATH` (for
example `~/.local/bin/xwayland-satellite`), or set `TESSA_XWAYLAND_BIN` to its
absolute path. Tessa does not use wlroots' built-in XWayland; satellite gives
rootless X11 windows to the compositor as ordinary xdg-shell toplevels.

If wlroots 0.19 is installed under `/usr/local` (for example when built from source),
make sure its `.pc` file and shared library are found:

```sh
pkg-config --modversion wlroots-0.19
ldconfig -p | grep wlroots
```

Build:

```sh
chmod +x scripts/*.sh scripts/tessa-session   # once, if not preserved
./scripts/build.sh -Doptimize=ReleaseSafe
```

This produces:

- `zig-out/bin/tessa` — the compositor
- `zig-out/bin/tessa-panel` — the shell panel (auto-started by tessa)

The generated Wayland protocol headers are committed under `protocol/`, so a
wlroots installation without generated `xdg-shell-protocol.h` still builds.

## Run

### From a TTY (recommended first test)

Log in on the target machine's console, not over SSH, and run from the active
virtual terminal:

```sh
cd /path/to/Tessa
PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

wlroots autodetects the DRM backend and libinput. Tessa starts
`tessa-panel` from `PATH`, so include `zig-out/bin` or install the binaries.
The default terminal is `kitty`; install it, or set `terminal = foot` in the
config.

### Display manager / session file

```sh
# install to ~/.local
./scripts/install-session.sh

# or system-wide
sudo PREFIX=/usr/local ./scripts/install-session.sh
```

Then log out and choose **Tessa** in GDM/SDDM/greetd. The session file runs
`tessa-session`, which puts its own directory at the front of `PATH` and starts
`tessa`.

### Headless development over SSH

This is the headless workflow used during development. Start the compositor:

```sh
./scripts/run-headless.sh
```

In another shell, take a screenshot:

```sh
./scripts/screenshot.sh /tmp/tessa.png
```

Because the headless backend starts without physical input devices, Tessa
creates a fallback keyboard with a standard XKB keymap. This lets the panel,
IME, and XWayland start correctly. Use IPC for mouse/state changes, or inject
keyboard input with `wtype`:

```sh
XDG_RUNTIME_DIR=/tmp/tessa-headless WAYLAND_DISPLAY=wayland-0 \
  wtype "foot"
XDG_RUNTIME_DIR=/tmp/tessa-headless WAYLAND_DISPLAY=wayland-0 \
  wtype -k Return
```

`wtype` connects through the virtual-keyboard protocol; it types into whichever
surface currently has keyboard focus. This is also how the IME and panel
keyboard paths are tested without a TTY.

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the headless workflow.

## Input methods

![Japanese preedit and Fcitx5 candidates in the launcher](docs/images/ime.png)

Tessa implements the `zwp_text_input_v3` (client) and
`zwp_input_method_v2` (input method) protocols and relays focus, surrounding
text, cursor rectangles, preedit, committed text, and deletion. Input-method
popup surfaces (the candidate window) are positioned below the text cursor with
output-edge clamping.

Tested with **Fcitx5 + Mozc**:

```sh
sudo apt install fcitx5 fcitx5-mozc
```

Start Fcitx5 inside the Tessa session (for example through `TESSA_STARTUP` or
your compositor's spawn command). You do not need to set `GTK_IM_MODULE` or
`QT_IM_MODULE` for Wayland-native clients: they use the Wayland text-input
protocol. For X11 clients, install and configure Fcitx's XIM module separately;
XIM is outside the wayland text-input path.

Open the launcher with `Super+D` and type; the preedit is drawn in the search
field and the Fcitx candidate popup appears below it. `Enter` commits the
selection, and the committed text becomes part of the launcher query.

## X11 applications

![xeyes and xclock running through xwayland-satellite](docs/images/xwayland.png)

Tessa starts `xwayland-satellite` after the Wayland socket is ready and exports
the chosen display as `DISPLAY`. X11 applications are rootless: each X11
toplevel appears as a normal Tessa window and participates in tiling,
workspaces, focus, and the taskbar. Tessa advertises `xdg-decoration` in
server-side mode, so satellite does not draw its own titlebars; Tessa's accent
border is used instead.

The display is chosen automatically by default (`xwayland_display = auto`),
starting at `:0` and skipping displays whose sockets already exist. Set it to an
explicit value such as `:1` if needed. Disable XWayland with `xwayland = false`
or `TESSA_NO_XWAYLAND=1`. If satellite is installed outside `PATH`, set
`TESSA_XWAYLAND_BIN=/path/to/xwayland-satellite`.

X11 applications render at scale 1. Fractional scaling and XWayland's XSETTINGS
integration are not implemented yet.

## Key bindings

| Binding | Action |
| --- | --- |
| `Super+Return` | terminal (`terminal` config value) |
| `Super+D` | launcher |
| `Super+T` | toggle master ↔ mosaic layout |
| `Super+Q` | close focused window |
| `Super+Shift+E` | quit Tessa |
| `Super+R` | reload config |
| `Super+1` … `Super+9` | switch workspace |
| `Super+Shift+1` … `Super+Shift+9` | move window to workspace |
| `Super+H/J/K/L` | focus left/down/up/right |
| `Super+Shift+H/J/K/L` | swap with window in that direction |
| `Super+Space` | toggle floating |
| `Super+F` | toggle fullscreen |
| `Super+Tab` / `Super+Shift+Tab` | cycle windows |
| `Super+Ctrl+H/L` | shrink/grow master ratio |

Mouse:

- Click a window to focus. Click a taskbar chip to focus it.
- Right-click a taskbar chip to close that window.
- Scroll over the bar to cycle workspaces.
- `Super+Left-drag` moves a floating window; `Super+Right-drag` resizes it.
- Client-side titlebar drags work for floating windows too.
- Click the petal/`TESSA` mark, or press `Super+D`, for the launcher.
- In the launcher: type to search, `Up`/`Down`, `Enter`, `Esc`, or click a row.

## Configuration

Copy the example:

```sh
mkdir -p ~/.config/tessa
cp config/config.example ~/.config/tessa/config
```

The format is `key = value`. Comments are lines starting with `#`.
At runtime `Super+R` reloads the config. Selected keys:

| Key | Meaning |
| --- | --- |
| `terminal` | command used for `Super+Return` and `Terminal=true` desktop apps |
| `gaps` | gap between tiled windows |
| `outer_gaps` | gap around the tiling area |
| `border_width` | active/inactive frame thickness |
| `master_ratio` | master area ratio (0.15–0.9) |
| `layout` | `master` or `mosaic` |
| `panel` | auto-start `tessa-panel` |
| `xwayland` | start `xwayland-satellite` and export `DISPLAY` |
| `xwayland_display` | `auto`, or an explicit display such as `:0` |
| `accent` | accent color used by borders, bar, launcher |
| `bg` | base background color for the wallpaper |
| `font` | UI family for the panel |

Additional bindings use XKB keysym names:

```ini
bind = SUPER+Return terminal
bind = SUPER+1 workspace 1
bind = SUPER+SHIFT+1 move-to-workspace 1
bind = SUPER+h focus left
bind = SUPER+SHIFT+h move left
bind = SUPER+ctrl+h ratio -0.03
```

Available actions: `terminal`, `spawn`, `close`, `quit`, `workspace`,
`move-to-workspace`, `focus`, `move`, `toggle-float`, `toggle-fullscreen`,
`focus-next`, `focus-prev`, `launcher`, `reload`, `ratio`, `toggle-layout`.

## How it works

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — components, scene graph, IPC,
  layer-shell sizing, panel rendering
- [docs/ROADMAP.md](docs/ROADMAP.md) — what is missing and what comes next
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — the SSH/headless development
  loop used for this repository

Short version:

```text
tessa (wlroots compositor, Zig)
  ├─ backend: DRM / headless / nested Wayland
  ├─ wlr_scene: wallpaper < layer background < windows < floating < top bar
  │              < fullscreen < launcher overlay
  ├─ master/stack + mosaic tiling, 9 workspaces, floating, fullscreen
  └─ IPC: $XDG_RUNTIME_DIR/tessa.sock
                 ▲
tessa-panel (Wayland client, Zig + Cairo/Pango)
  ├─ background layer (ink/sun wallpaper)
  ├─ top layer (floating taskbar)
  └─ overlay layer (launcher, exclusive keyboard)
```

The panel uses three `wl_shm` buffers per surface, draws with Cairo, and renders
text through the small C shim in `panel/text.c` (Pango). The compositor and panel
exchange a deliberately simple line protocol:

```text
STATE
ACTIVE 1
OCC 1 2
...
WIN\t1\t1\t1\t0\t0\tkitty\tnotes
END

CMD workspace 3
CMD focus 4
CMD close 4
CMD spawn kitty
CMD launcher [query]
CMD layout
CMD float <id>
CMD quit
```

The IPC socket is created as mode `0600` under `$XDG_RUNTIME_DIR`.

## Known limitations

These are real and important:

- **DRM/keyboard/mouse not yet validated on real hardware.** Development uses
  the headless backend with `wtype`/Fcitx5 and software rendering. Interactive
  pointer behavior and DRM mode setting still need a physical test pass.
- **One panel.** The bar/background are created on the first output. Multiple
  outputs tile windows, but they share one active workspace and only one bar.
- **No layer-shell popups from third-party clients.** Toplevel xdg popups and
  input-method popups work; popups attached to layer surfaces are not wired into
  the scene yet.
- **Scale is fixed to 1.** HiDPI output scale is not configurable, and X11
  clients are not scaled.
- **IME coverage.** Wayland text-input-v3 clients and the panel are verified
  with Fcitx5 + Mozc. X11/XIM input methods, dead keys through unusual layouts,
  and input-method popup repositioning during scroll are not covered.
- **XWayland needs `xwayland-satellite`.** Tessa does not bundle it. If it is
  missing, X11 applications simply do not start; Wayland clients are unaffected.
- **No portals, screen sharing, lock screen, idle-inhibit, gamma, or output
  configuration UI.**
- **No session lock.** Do not treat this as a hardened/secure desktop yet.
- Layer-shell/kbd focus uses wlroots 0.19 unstable APIs; pin the wlroots
  version when packaging.
- The launcher scans `.desktop` files; if you have only a few installed, the
  list will be short. It does not use icon themes yet (monogram tiles instead).

## License

Tessa is released under the **MIT License**. See [LICENSE](LICENSE).

## Credits

Built from scratch for this project, with wlroots and the tinywl example as the
reference for the compositor's event-loop structure. Cairo/Pango draw the shell;
the Pango shim exists because Zig's translate-c currently chokes on GLib's
`_Pragma` deprecation macros. Foot is used as the test terminal; kitty is the
default terminal.
