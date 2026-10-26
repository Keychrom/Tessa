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
- master/stack, Tessa "mosaic" spiral, grid, and equal-column layouts, with
  per-workspace layout profiles (`Super+T` cycles); configurable master count,
  mosaic ratio/size, grid columns, and per-workspace gaps/master ratio; explicit
  runtime choices are restored on restart, and config reload updates workspaces
  without a runtime override
- declarative window rules matched by app-id/title/output, with floating,
  workspace, fullscreen, size, and position actions
- external layout-helper protocol for custom tiling algorithms, with a timeout,
  process restart, and built-in fallback
- file/line config diagnostics, transactional reload, and versioned JSON
  state/config snapshots for external tools
- named input modes with mode-specific key bindings and `enter-mode`
- configurable bar height, top/side margins, and bar background/foreground colors
- nine workspaces per output, floating windows, fullscreen, click-to-focus
- multi-monitor support: a bar/background and independent active workspace on
  every output; panels are auto-started per output; output management via
  `wlr-randr`, persisted across restarts; integer HiDPI panel buffer scaling
- external extension API: event subscriptions, config hooks, custom bar status
  entries, custom launcher entries, and the `tessa-ctl` automation client
- `relative-pointer-v1` for games and pointer-look applications
- layer-shell popups from third-party clients (panel menus, dropdowns)
- `ext-session-lock-v1` session locking, plus `ext-idle-notify-v1`,
  `idle-inhibit-v1`, and output-power management for tools such as swayidle and
  wlopm
- keyboard layout/variant/options and key-repeat settings in the config, with
  `Super+R` reload
- text-input-v3 + input-method-v2 IME relay with input-popup placement;
  verified end to end with Fcitx5 + Mozc in the launcher and Wayland clients
- XWayland through `xwayland-satellite`: rootless X11 apps are managed as normal
  Tessa toplevels, and `DISPLAY` is exported to spawned applications
- integrated panel in Zig + Cairo/Pango:
  - ink/sun wallpaper
  - floating taskbar with workspace pills, window chips, clock, CPU/RAM
  - searchable application launcher with keyboard navigation and IME input
- line-based IPC with explicit state/event subscriptions and a `tessa-ctl` CLI
- line-based configuration file with includes and event hooks

It has been built and tested on Ubuntu 26.04 with Zig 0.16.0 and wlroots
0.19.2, primarily in the headless pixman backend with `grim`, `wtype`, Fcitx5 +
Mozc, and X11 clients through `xwayland-satellite`. Dual-headless-output
workspaces, per-output panels, session locking across outputs, and `wlr-randr`
output management were also verified. Event hooks, the event stream, custom
status entries, custom launcher entries, config reload, per-workspace
master/mosaic/grid/columns layouts, 2x HiDPI panel scaling, and output
mode/position/scale and layout persistence across restarts were exercised by
`tests/smoke.sh`, `tests/output-persistence.sh`, `tests/layout-geometry.sh`,
`tests/customization.sh`, `tests/layout-helper.sh`, `tests/config-validation.sh`,
`tests/json-ipc.sh`, `tests/modes.sh`, `tests/panel-theme.sh`, and panel
screenshots.
**DRM/tty and real keyboard/mouse testing still needs to be done on the target
machine.** See [Known limitations](#known-limitations).

## Why another tiling WM?

Tessa's goal is not to out-feature Hyprland. It is a different, more compact
desktop:

- **Integrated shell.** The bar, launcher, wallpaper, and tiling live together.
  The palette and behavior are consistent because they are one project.
- **A different layout.** Besides master/stack, Tessa has a spiral "tessera"
  mosaic layout, a balanced grid, and equal columns (`Super+T` cycles them).
  The name Tessa comes from tessellation.
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
- optional: `wlr-randr` for runtime output mode/position/scale changes

Distribution packaging definitions live in `packaging/` and `debian/`:
`packaging/arch/PKGBUILD` and the debhelper `debian/` tree both install the
compositor, panel, CLI, session file, and example config. See
[packaging/README.md](packaging/README.md).

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
- `zig-out/bin/tessa-panel` — the shell panel (one process per output, auto-started by tessa)
- `zig-out/bin/tessa-ctl` — state/event/automation client for scripts and extensions

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

wlroots autodetects the DRM backend and libinput. Tessa starts one
`tessa-panel` process per output from `PATH`, so include `zig-out/bin` or
install the binaries. The default terminal is `kitty`; install it, or set
`terminal = foot` in the config.

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

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the headless workflow and
[docs/EXTENDING.md](docs/EXTENDING.md) for scripting and extension APIs.

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

## Lock and idle

Tessa implements `ext-session-lock-v1`, `ext-idle-notify-v1`, and
`idle-inhibit-v1`. A lock client and an idle daemon are separate programs:

```sh
sudo apt install swaylock swayidle
```

`Super+Escape` runs `swaylock` by default. If you prefer another locker, change
that binding with `bind = SUPER+Escape spawn <command>`. While locked, normal
desktop scene trees are hidden, virtual-keyboard injection is ignored, and the
lock surface receives keyboard/pointer focus. If the lock client dies while
locked, Tessa terminates the session instead of exposing the desktop.

`swayidle` can combine idle detection with locking and DPMS, for example:

```sh
sudo apt install wlopm
swayidle -w \
  timeout 300 'swaylock -f' \
  timeout 600 'wlopm --off "*"' \
  resume 'wlopm --on "*"'
```

Idle notifications and inhibitor handling work, and a visible video/player can
inhibit idle through `idle-inhibit-v1`. Tessa implements the output-power
management protocol, so `wlopm` can turn outputs off and back on.

## Multiple monitors

![Two headless outputs with independent bars and workspaces](docs/images/multi-monitor.png)

Every output gets its own background, bar, and independent active workspace.
`Super+1` … `Super+9` change the workspace of the focused output. Clicking or
scrolling a bar changes that monitor's workspace and focuses that output.
The launcher opens on the focused output, and new windows are placed there.
`Super+Shift+H/J/K/L` swaps within the current output first; when there is no
window in that direction it moves the focused window to the adjacent monitor.

Tessa auto-starts one `tessa-panel` process per output with
`TESSA_PANEL_OUTPUT=<name>`. If you disable auto-start (`panel = false` or
`TESSA_NO_PANEL=1`), start a panel for each output manually:

```sh
TESSA_PANEL_OUTPUT=HEADLESS-1 tessa-panel
```

Output modes, positions, scales, and transforms can be changed with `wlr-randr`;
Tessa implements `wlr-output-management-unstable-v1`. Applied settings are
saved to `$XDG_CONFIG_HOME/tessa/outputs.conf` (or
`~/.config/tessa/outputs.conf`) and restored when the outputs appear again.
Override the path with `output_config` in the main config or
`TESSA_OUTPUT_CONFIG`. Panels follow `wl_output` scale, so integer HiDPI scales
render the bar and launcher crisply. Fractional scales use the ceiling of the output scale as
the integer buffer scale, and X11 clients still render at scale 1.

## Extensions

![Extension status entries and a custom launcher entry](docs/images/extensions.png)

Tessa does not embed a plugin VM. Extensions are normal processes that speak the
compositor's Unix-socket API; they can be written in any language. `tessa-ctl`
exposes state snapshots, structured events, status entries, and commands:

```sh
tessa-ctl state
tessa-ctl state --json
tessa-ctl config
tessa-ctl config --json
tessa-ctl config-check
tessa-ctl events window-focus
tessa-ctl status weather "Tokyo 18C"
tessa-ctl dispatch reload
```

`state --json` and `config --json` return schema-versioned snapshots for tools.
`config-check` prints file/line diagnostics and exits non-zero while the loaded
configuration has errors. Configuration can also start commands at login and
react to compositor events:

```ini
startup = fcitx5 -d
hook = window-open notify-send "Window opened" "$TESSA_TITLE"
launcher_entry = Notes | foot -e nvim ~/notes.md
include = /home/you/.config/tessa/launcher-entries.conf
```

The panel displays up to eight extension status entries and can run a command
when one is clicked. See [docs/EXTENDING.md](docs/EXTENDING.md) for the complete
event schema, hook environment, and status API.

## Key bindings

| Binding | Action |
| --- | --- |
| `Super+Return` | terminal (`terminal` config value) |
| `Super+D` | launcher |
| `Super+T` | cycle master → mosaic → grid → columns |
| `Super+Q` | close focused window |
| `Super+Shift+E` | quit Tessa |
| `Super+R` | reload config |
| `Super+1` … `Super+9` | switch workspace |
| `Super+Shift+1` … `Super+Shift+9` | move window to workspace |
| `Super+H/J/K/L` | focus left/down/up/right |
| `Super+Shift+H/J/K/L` | swap with window in that direction; if there is none, move the window to the adjacent output |
| `Super+Space` | toggle floating |
| `Super+F` | toggle fullscreen |
| `Super+Escape` | lock the session (runs `swaylock`; install it first) |
| `Super+Tab` / `Super+Shift+Tab` | cycle windows |
| `Super+Ctrl+H/L` | shrink/grow master ratio |
| `Super+Alt+H/L` | shrink/grow a floating window horizontally |
| `Super+Alt+J/K` | grow/shrink a floating window vertically |

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
At runtime `Super+R` reloads the config. A reload with errors is rejected and
the previous configuration stays active; `tessa-ctl config-check` reports the
diagnostics. Selected keys:

| Key | Meaning |
| --- | --- |
| `terminal` | command used for `Super+Return` and `Terminal=true` desktop apps |
| `gaps` | gap between tiled windows |
| `outer_gaps` | gap around the tiling area |
| `border_width` | active/inactive frame thickness |
| `master_ratio` | master area ratio (0.15–0.9) |
| `master_count` | windows stacked in the master column |
| `mosaic_ratio` | slice ratio for mosaic (0.25–0.85) |
| `mosaic_min_size` | minimum mosaic tile before falling back to grid |
| `grid_columns` | fixed grid columns; `0` chooses `ceil(sqrt(n))` |
| `layout_helper` | command for the long-lived external layout helper |
| `layout_helper_timeout` | helper response timeout in milliseconds (10–1000) |
| `layout` | default layout: `master`, `mosaic`, `grid`, `columns`, or `custom` |
| `layout_1` … `layout_9` | initial layout for a workspace without a saved override |
| `panel` | auto-start `tessa-panel` |
| `xwayland` | start `xwayland-satellite` and export `DISPLAY` |
| `xwayland_display` | `auto`, or an explicit display such as `:0` |
| `kb_layout` | XKB layout, for example `us` or `us,de` |
| `kb_variant` | XKB variant (optional) |
| `kb_options` | XKB options, for example `grp:alt_shift_toggle` |
| `kb_model` | XKB model (optional) |
| `kb_rules` | XKB rules file (optional) |
| `repeat_rate` | key repeat rate in repeats per second |
| `repeat_delay` | delay before key repeat starts, in milliseconds |
| `accent` | accent color used by borders, bar, launcher |
| `bg` | base background color for the wallpaper |
| `font` | UI family for the panel |
| `include` | include another config file |
| `startup` | command run once at startup |
| `hook` | run a command for a compositor event |
| `launcher_entry` | extra launcher item (`Name \| command`) |
| `output_config` | path for persisted output mode/position/scale/transform and layout overrides |
| `bar_height` | panel bar height (32–96 logical pixels) |
| `bar_top_margin` | panel distance from the top edge (0–64) |
| `bar_side_margin` | panel left/right margin (0–128) |
| `panel_bg` | panel bar background color |
| `panel_fg` | panel bar primary text color |
| `border_active` | focused border color (defaults to `accent`) |
| `border_inactive` | unfocused border color |
| `window-rule` | declarative rule; see the customization guide |
| `workspace-rule` | per-workspace layout, gaps, and master ratio |
| `mode` | start a named input-mode section for following `bind` lines |

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
`focus-next`, `focus-prev`, `launcher`, `reload`, `ratio`, `toggle-layout`,
`set-layout`, `resize-width`, `resize-height`, `enter-mode`.

`Super+T` cycles the focused workspace through all four layouts. Runtime layout
choices are kept per output and workspace and saved to `outputs.conf`. `layout_N`
only seeds workspaces that have no saved or runtime override; a config reload
updates every workspace you have not overridden and leaves your runtime choices
alone. `resize-width` and `resize-height` take a pixel delta and act on the focused
floating window.

Window rules are one line each. Match app-id, title, or output with `*`/`?`
patterns and apply actions in order:

```ini
window-rule = app-id=pavucontrol; float=true
window-rule = title=Picture-in-Picture; float=true; position=40,40
window-rule = app-id=firefox; workspace=2
window-rule = title=GIMP*; float=false
```

Rules are applied when a window maps and re-evaluated on config reload. Run
`tessa-ctl config` to inspect the effective values and parsed rules. See
[docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) for the complete reference.

Input modes group bindings and activate them with `enter-mode`:

```ini
mode = resize
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default

mode = default
bind = SUPER+SHIFT+r enter-mode resize
```

While a mode is active, its bindings match even without Super. Global bindings
still work, and unbound keys reach the focused client. `tessa-ctl mode resize`
switches modes from a script. The active mode is shown as `MODE <name>` in
`tessa-ctl state`.

Per-workspace tuning uses the same `key=value; ...` style:

```ini
workspace-rule = ws=2; layout=grid; gaps=4; outer-gaps=8; master-ratio=0.65
```

Custom tiling is selectable with `layout = custom`. Tessa starts the configured
helper once and sends it the active tiled windows and usable area; the helper
returns frame rectangles. The helper is not part of the `Super+T` cycle, so bind
it explicitly if wanted:

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

Timeouts, crashes, malformed replies, and missing rectangles fall back to the
master layout for that frame. See
[docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md#external-layout-helper) for the
protocol.

## How it works

- [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) — window rules, layout
  tuning, appearance, and the customization model
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
  ├─ master/stack + mosaic + grid + columns, 9 workspaces, floating, fullscreen
  └─ IPC: $XDG_RUNTIME_DIR/tessa.sock
                 ▲
tessa-panel × outputs (Wayland client, Zig + Cairo/Pango)
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
WIN\t1\t1\t1\t0\t0\tkitty\tnotes\teDP-1\t40\t30\t1100\t700
END

CMD workspace 3 eDP-1
CMD focus 4
CMD close 4
CMD spawn kitty
CMD launcher [query]
CMD layout [name] [output]
CMD resize <dx> <dy>
CMD float <id>
CMD quit
```

The IPC socket is created as mode `0600` under `$XDG_RUNTIME_DIR`.

## Known limitations

These are real and important:

- **DRM/keyboard/mouse not yet validated on real hardware.** Development uses
  the headless backend with `wtype`/Fcitx5 and software rendering. Interactive
  pointer behavior and DRM mode setting still need a physical test pass.
- **Fractional scaling is partial.** The panel uses an integer Wayland buffer
  scale and X11 clients render at scale 1. Integer HiDPI scales work, but
  fractional desktop scaling needs a dedicated fractional-scale implementation.
- **Disabled outputs are not persisted.** `wlr-randr --off` is runtime-only;
  the saved output entry re-enables that output on the next start.
- **One panel process per output.** This keeps each bar independent but uses
  more memory than a single multi-surface panel; a panel crash only affects its
  monitor.
- **Lock-screen testing is basic.** `ext-session-lock-v1` is implemented and was
  tested with a minimal lock client; a real swaylock/PAM setup still needs a
  physical-session test. If the lock client disappears while locked, Tessa
  terminates rather than silently unlocking.
- **Idle timing is external.** Tessa exposes idle notifications, inhibitors, and
  output power management; `swayidle`/`wlopm` (or another idle daemon) must be
  running if you want automatic blanking or locking.
- **IME coverage.** Wayland text-input-v3 clients and the panel are verified
  with Fcitx5 + Mozc. X11/XIM input methods, dead keys through unusual layouts,
  and input-method popup repositioning during scroll are not covered.
- **XWayland needs `xwayland-satellite`.** Tessa does not bundle it. If it is
  missing, X11 applications simply do not start; Wayland clients are unaffected.
- **No portals, screen sharing, gamma, or output configuration UI.**
- **Extensions are trusted local processes.** They run with the session user's
  full privileges; there is no sandbox. State/config snapshots are versioned JSON,
  but the command/event plane is still line-oriented and has no JSON-RPC
  request/version negotiation. Status entries are limited to eight short strings.
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
