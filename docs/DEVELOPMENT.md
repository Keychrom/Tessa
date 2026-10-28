**English** | [日本語](DEVELOPMENT.ja.md)

# Development

Tessa can be developed entirely on a headless Linux machine over SSH. The
compositor and panel are ordinary Wayland programs, and `grim` can capture the
headless output for quick visual checks. A virtual keyboard (`wtype`) and Fcitx5
make it possible to test keyboard and IME paths without a physical display.

## Build

```sh
chmod +x scripts/*.sh scripts/tessa-session
./scripts/build.sh -Doptimize=ReleaseSafe
```

For a debug build:

```sh
./scripts/build.sh
```

Rounded corners and backdrop blur use scenefx 0.4.1. Install it, then build
with `-Dscenefx=true`. This binary uses the scenefx GLES2 renderer and cannot
use the pixman renderer.

```sh
./scripts/build.sh -Dscenefx=true
```

Prerequisites are listed in the main README. In short: Zig 0.16, wlroots 0.19,
Wayland, xkbcommon, pixman, DRM/input/seat development headers, Cairo, Pango,
and fonts. For X11 testing, also install `xwayland-satellite` in `PATH`.

Check the libraries:

```sh
pkg-config --modversion wlroots-0.19
ldconfig -p | grep wlroots
fc-list | grep -i -E 'Inter|JetBrains|Noto Sans CJK'
```

## Headless session

Terminal 1:

```sh
./scripts/run-headless.sh
```

This creates `/tmp/tessa-headless`, forces the pixman renderer, and starts the
panel from `zig-out/bin`. The output is a 1920×1080 headless display named
`HEADLESS-1`.

Terminal 2:

```sh
# capture the screen
./scripts/screenshot.sh /tmp/tessa.png

# spawn a terminal inside the session
printf 'CMD spawn foot -T notes\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# master <-> mosaic
printf 'CMD layout\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# launcher (optionally with a prefilled query)
printf 'CMD launcher\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD launcher ter\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# switch workspace / focus a window
printf 'CMD workspace 2\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
```

Tessa creates a fallback keyboard when the headless backend has no physical
input devices, so the panel, IME, and XWayland can start correctly. Inject
keyboard input through the virtual-keyboard protocol:

```sh
export XDG_RUNTIME_DIR=/tmp/tessa-headless
export WAYLAND_DISPLAY=wayland-0

printf 'CMD launcher\n' | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
wtype "foot"
wtype -k Return
```

`wtype` types into whichever surface currently has keyboard focus.

`tessa-ctl` is the preferred way to drive the session. Put the build output in
`PATH` and point it at the same runtime directory:

```sh
export PATH="$PWD/zig-out/bin:$PATH"
export XDG_RUNTIME_DIR=/tmp/tessa-headless

tessa-ctl state
tessa-ctl spawn foot -T notes
tessa-ctl dispatch layout
tessa-ctl launcher ter
tessa-ctl status demo "hello from an extension"
tessa-ctl events window-focus
```

`tessa-ctl status --clear` removes an entry. `tessa-ctl events` only receives
events after subscribing, so it is safe to run as a long-lived script.

### IME test

Start Fcitx5 inside the session, select Mozc, and type into the launcher:

```sh
printf 'CMD spawn fcitx5\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD launcher\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

wtype "nihongo"      # preedit
wtype -k space       # conversion
wtype -k Return      # commit
grim -o HEADLESS-1 /tmp/ime.png
```

Point `XDG_CONFIG_HOME` at a temporary directory with an `fcitx5/profile` that
selects `mozc` to avoid touching your real Fcitx configuration. The candidate
popup is drawn through input-method popup surfaces below the search field.

### XWayland test

With `xwayland-satellite` in `PATH` (or `TESSA_XWAYLAND_BIN` set), Tessa chooses
a free display automatically and exports `DISPLAY`. On a clean machine this is
usually `:0`.

```sh
printf 'CMD spawn xeyes\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD spawn xclock\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
sleep 2
DISPLAY=:0 xdpyinfo | head
grim -o HEADLESS-1 /tmp/xwayland.png
printf 'STATE\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
```

The `STATE` output should list `XEyes` and `XClock` as normal windows. Use
`xev` and `wtype` to check that key events reach X11 clients; note that wtype
installs its own small keymap, so a physical keyboard is better for realistic
text-entry tests.

### Multi-monitor test

The headless backend can expose several outputs:

```sh
WLR_HEADLESS_OUTPUTS=2 ./scripts/run-headless.sh
```

Tessa starts one `tessa-panel` per output. Check that `pgrep -f tessa-panel`
shows two processes, and that the state contains one `OUT` line per output:

```sh
printf 'STATE
'   | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock | head -12
```

`CMD workspace 2 HEADLESS-2` changes only the second output's workspace;
`HEADLESS-1` keeps its own. Capture each monitor with:

```sh
./scripts/screenshot.sh /tmp/left.png HEADLESS-2
./scripts/screenshot.sh /tmp/right.png HEADLESS-1
```

Output position/mode/scale can be exercised with `wlr-randr` if it is
installed. Applied settings and runtime layout overrides are saved to
`outputs.conf` and restored on the next start.

### HiDPI and output persistence test

Set a 2x scale and capture the panel. The bar should be 88 physical pixels high
on a 1920x1080 mode and text should stay crisp:

```sh
wlr-randr --output HEADLESS-1 --scale 2
grim -o HEADLESS-1 /tmp/hidpi.png
```

`wlr-randr` apply also writes `~/.config/tessa/outputs.conf` (or
`$XDG_CONFIG_HOME/tessa/outputs.conf`). Set `TESSA_OUTPUT_CONFIG` or the
`output_config` config key to redirect it. The headless test is self-contained:

```sh
WLR_RANDR=/path/to/wlr-randr sh tests/output-persistence.sh
```

It applies a 1280x720 custom mode, scale 2, and position 40,30, verifies the
file, sets a runtime layout, restarts, and checks the restored
mode/scale/position and layout. The launcher at 2x uses the same fitted 760x620
design, so its hit rectangles and IME cursor follow the visual scaling.

### Layout test

Launch several terminals inside the session, then cycle or set layouts with
`tessa-ctl` (or `Super+T`):

```sh
for n in one two three four; do tessa-ctl spawn foot -T "layout-$n"; done
tessa-ctl layout grid
./scripts/screenshot.sh /tmp/grid.png
tessa-ctl layout columns
./scripts/screenshot.sh /tmp/columns.png
tessa-ctl layout mosaic
```

`OUT` in `tessa-ctl state` ends with the current layout name. Per-workspace
initial layouts come from `layout_1` … `layout_9`. Runtime changes are kept per
output and workspace, written as `layout` lines in `outputs.conf`, and restored
on the next start. A config reload updates workspaces that have no runtime
override. `Super+Alt+H/J/K/L` or `tessa-ctl resize <dx> <dy>` resizes the
focused floating window, with a 160×120 minimum.

`tests/layout-geometry.sh` spawns eight windows, selects mosaic, and verifies
that no tiles overlap and every tile is at least 160×160. It also checks the
configured `master_count`, `grid_columns`, and per-workspace gap/master-ratio
values.

### Rules and customization test

`tests/customization.sh` starts a private headless session, applies float,
workspace, fullscreen, size, and position rules to `foot` windows, verifies
`tessa-ctl config`, rewrites the rule file, reloads, and checks that existing
windows are re-evaluated.

```sh
sh tests/customization.sh
```

### Layout helper test

`tests/layout-helper.sh` starts the compositor with `layout = custom`, uses a
small Python helper to return known rectangles, verifies the geometry, switches
to a broken helper to check the master-layout fallback, and then restores the
working helper to verify restart-after-reload.

```sh
sh tests/layout-helper.sh
```

`tests/layout-helper-v2.sh` compiles the xdg-shell test window and starts two
headless outputs. It moves one window to the second output, verifies that each
output gets its own helper process, checks protocol-2 negotiation, and measures
that a 600 ms helper delay does not block an IPC state request. It also verifies
that focused/urgent metadata reaches the helper after a focus change and
`tessa-ctl dispatch urgent`.

```sh
sh tests/layout-helper-v2.sh
```

### Config validation and JSON test

`tests/config-validation.sh` writes an invalid config with unknown keys, bad
values, a malformed rule, and a missing include. It checks the reported line
numbers, verifies that reload keeps the previous configuration, and checks that
`tessa-ctl config-check` fails until the file is fixed.

`tests/json-ipc.sh` parses `state --json` and `config --json` with Python,
checks schema version 1 and window geometry, then verifies JSON diagnostics for
a rejected reload.

```sh
sh tests/config-validation.sh
sh tests/json-ipc.sh
```

### Input mode test

`tests/modes.sh` defines a `resize` mode, enters it with `tessa-ctl mode`,
sends unmodified `l`/`Escape` through `wtype`, and checks that the mode-specific
binding is consumed and that normal keys pass through after returning to the
default mode.

```sh
sh tests/modes.sh
```

### Panel theme test

`tests/panel-theme.sh` starts the real panel with a custom bar height, margins,
and palette, checks its startup log, changes the geometry, reloads, and verifies
that the bar layer surface was recreated at the new size without killing the
panel.

```sh
sh tests/panel-theme.sh
```

### Animation and visual test

`tests/animations.sh` starts a private headless compositor without the panel,
enables 500 ms animations and shadows, and sets an explicit wallpaper gradient.
It launches `foot` and checks the debug log for the open transition
(`animation: start id=1 from=0,18` and a matching done line), switches to
workspace 2 and back to verify the horizontal transition (`from=-54,0`), then
closes window 1 and checks that the close snapshot starts and finishes
(`close animation: start id=1` / `close animation: done id=1`) and that the
window disappears from `tessa-ctl state`. When `grim` and ImageMagick are
installed, it also samples the center of the closing snapshot and fails if the
content is missing. Hooks for `animation-start`, `animation-done`,
`close-animation-start`, and `close-animation-done` append to a log; the test
waits for the `open`/`workspace` and `close` phases there. It finishes with
`tessa-ctl config-check` to confirm the visual keys and hooks are accepted.

```sh
sh tests/animations.sh
```

### Config reload test

`tests/config-watch.sh` starts a headless session and replaces the config with
an atomic `mv`. It waits for the debounced inotify reload to change `gaps`, then
writes an invalid value and verifies that the previous configuration survives
and the rejection is logged.

```sh
sh tests/config-watch.sh
```

### Motion configuration test

`tests/motion.sh` parses named cubic-bezier and spring curves, per-kind curves,
open and workspace offsets, close scale/fade, custom `bezier`/`spring`
definitions, and per-window animation overrides. It reads the values through
`tessa-ctl config`, then appends unknown/invalid curves and checks that the
transactional reload keeps the previous settings while reporting the
diagnostic.

```sh
sh tests/motion.sh
```

### Motion override test

`tests/motion-overrides.sh` compiles the xdg-shell test window and starts three
clients with different app ids. One rule disables motion, one sets a 600 ms
base duration, and one selects a custom spring plus separate open/close
durations. The test maps, switches workspaces, and closes the clients, checking
the debug log for the expected `ms=` and `curve=spring` values and verifying
that the disabled window never starts an animation.

```sh
sh tests/motion-overrides.sh
```

### Rule visual test

`tests/rule-visuals.sh` compiles a small xdg-shell client and a layer-shell
client with the checked-in protocol code. It verifies per-window opacity,
border width, corner radius, blur, and shadow state through
`tessa-ctl state --json`, plus layer-rule namespace/layer matching and effective
layer opacity. The window client changes its title and app-id through
`SIGUSR1`; the test checks that decorative rules re-evaluate immediately while
structural rules stay put. When `grim` is available, it samples the screenshot
through `tests/png-pixel.py` to verify the layer opacity, the black 8 px border,
the dimmed content, and the opaque content after the retitle.

```sh
sh tests/rule-visuals.sh
```

### Fractional-scale test

`tests/fractional-scale.sh` compiles a small xdg-shell client that binds
`wp_fractional_scale_manager_v1`, maps a surface, and prints the preferred scale
in 1/120 units. It starts at 1.0 (`scale 120`), changes the output to 1.5 with
`wlr-randr` and waits for `scale 180`, then switches to 2.0 and waits for
`scale 240`. This covers both the protocol advertisement and the runtime output
commit path that re-notifies existing surfaces.

```sh
sh tests/fractional-scale.sh
```

### Effects test

`tests/effects.sh` checks the scenefx build only; it exits 0 and skips when
`tessa-ctl config` reports `scenefx 0`. It starts with a 24 px corner radius,
a red border, and a black wallpaper, spawns `foot` with a white background, and
samples the screenshot. The window center must be white, the top-left corner
must be background-dark instead of white/red, and the top border midpoint must
be red.

```sh
sh tests/effects.sh
```

### Output rules test

`tests/output-rules.sh` starts a two-output headless session and reloads a
config with an output-wide grid/gap rule plus an output+workspace rule. It
spawns three windows on the second output and verifies the grid cell width,
horizontal/vertical gaps, and centered last row. It then switches that output
to workspace 2, spawns two windows, and verifies that the `ws=` output rule's
outer gap and master layout override the generic workspace rule.

```sh
sh tests/output-rules.sh
```

### Workspace pinning test

`tests/workspace-pinning.sh` starts a two-output headless session, discovers
both output names, reloads a config that pins workspace 3 to the second output,
and spawns `foot` on the first. It checks that `tessa-ctl workspace 3` focuses
the pinned output, that `CMD move-workspace 3` transfers the window and its
focus across outputs, that an explicit `workspace 3 <first-output>` request is
still redirected, and that an unpinned workspace stays on the requested output.

```sh
sh tests/workspace-pinning.sh
```

### Named workspace test

`tests/workspace-names.sh` verifies deferred name resolution for bindings and
window rules, the text/JSON config snapshots, `WORKSPACE` state lines, and the
`tessa-ctl workspace <name>` command. It also checks that a rule referencing an
unknown workspace name rejects the reload and keeps the previous config.

```sh
sh tests/workspace-names.sh
```

### Scratchpad test

`tests/scratchpad.sh` assigns a test toplevel to the scratchpad with a window
rule, verifies that it starts hidden and unfocused, toggles it visible with
`CMD toggle-scratchpad`, checks focus and visibility state, then moves it back
to normal tiling and into the scratchpad again with `CMD move-to-scratchpad`.

```sh
sh tests/scratchpad.sh
```

### Window group test

`tests/window-groups.sh` launches two test toplevels, groups them with
`CMD toggle-group`, verifies that only one member is visible and both share a
group id, switches tabs with `CMD group-next`, ungroups them, and exercises
`CMD group-remove` / `CMD group-add`.

```sh
sh tests/window-groups.sh
```

### Wallpaper image test

`tests/wallpaper-image.sh` generates a solid PNG, starts the panel with
`wallpaper_fit = stretch`, samples a screenshot with `grim`, then reloads with
`wallpaper_fit = contain` and checks the image center and background letterbox
pixels. It skips when `grim` is unavailable.

```sh
sh tests/wallpaper-image.sh
```

### Terminal fallback test

`tests/terminal-fallback.sh` hides `kitty` from `PATH`, provides a fake `foot`,
and verifies that the default terminal resolves to `foot`, that the startup
cursor log is emitted, and that an explicit missing `terminal = ...` is kept
instead of being replaced.

```sh
sh tests/terminal-fallback.sh
```

### Input, gesture, and pointer-constraint tests

`tests/input.sh` verifies the gesture/touch/tablet/pointer-constraint config
keys, the JSON snapshot, startup logs, and the advertised
`zwp_pointer_gestures_v1`, `zwp_tablet_manager_v2`, and
`zwp_pointer_constraints_v1` globals. It also parses input/cursor rules and
checks connector/EDID output rules plus the cursor-manager reload log. The
headless backend has no touch, touchpad, or VRR-capable hardware, so libinput
behavior and adaptive-sync commits need a physical test pass.

`tests/pointer-constraints.sh` compiles a small xdg-shell client, creates a
persistent locked pointer, and checks `locked`, `unlocked`, and re-`locked`
events as the window loses and regains focus across workspace switches.

```sh
sh tests/input.sh
sh tests/pointer-constraints.sh
```

### XIM test

`tests/xim.sh` re-executes itself under a private `dbus-run-session`, starts
Tessa with XWayland and `xim_start = fcitx5 -d`, and checks that the startup
command inherited `XMODIFIERS`, that Fcitx5 was launched after the X display
appeared, and that Fcitx5 owns the XIM server selection (`XIM_SERVERS`). It
skips when `xwayland-satellite`, `fcitx5`, or `xprop` is unavailable.

```sh
sh tests/xim.sh
```

### Interaction automation test

`tests/interaction.sh` compiles a `wlr-virtual-pointer-v1` client and drives the
real panel and compositor without physical input. It clicks workspace pills,
drags and resizes a floating `foot` window with Super held, toggles fullscreen,
checks click-to-focus with two windows, closes a window through its bar chip
with a right click, and types into the launcher until a custom entry runs. Bar
coordinates are calculated from the panel's reported bar size, so the test is
not tied to one output resolution.

```sh
sh tests/interaction.sh
```

### XDG popup test

`tests/popups.sh` compiles a small xdg-shell client that creates a toplevel and
an anchored red popup. It captures the headless output with `grim` and checks
the popup pixel with ImageMagick, verifying that client popups are mapped and
rendered above their parent. The test skips when `grim` or `convert` is absent.

```sh
sh tests/popups.sh
```

### Panel popover test

`tests/panel-popovers.sh` starts the compositor and panel, opens the calendar
through the `panel` IPC event, changes months with `wtype`, and verifies Escape
closes it. It then opens the power menu, selects Suspend, and confirms that the
configured `power_suspend` command runs instead of reboot/poweroff.

```sh
sh tests/panel-popovers.sh
```

### Clipboard history test

`tests/clipboard.sh` copies two strings with `wl-copy`, opens the history with
`Super+V` through `wtype`, selects the older entry, and verifies with `wl-paste`
that the panel became the new selection source. It then copies a third string,
reopens the history through IPC, and checks that the newest entry is restored.

```sh
sh tests/clipboard.sh
```

The panel monitors selections through `wlr-data-control-v1`. Ordinary
`wl_data_device` selection events go only to the focused client, so a bar-side
ordinary data device cannot collect clipboard history.

### Screenshot test

`tests/screenshot.sh` sets a temporary `screenshot_dir`, opens the screenshot
overlay through IPC, presses `Enter` for the full output, and checks that the
saved file is a 1920×1080 PNG. It also verifies that `Esc` cancels without
creating a file and that the default `Super+Shift+S` binding opens the UI.

```sh
sh tests/screenshot.sh
```

The automated test covers full-output capture. Region dragging uses the normal
pointer path and still needs a physical pointer or a virtual-pointer test.

### Notification test

`tests/notifications.sh` re-executes itself under `dbus-run-session`, starts the
headless session, and calls `org.freedesktop.Notifications` through `gdbus`. It
checks server information/capabilities, a toast, `CloseNotification`, expiry,
replacement, and stacking. The rich-notification section uses
`tests/rich-notification.py` to send actions, Pango markup, and a 32×32
`image-data` icon, then invokes an action with
`tessa-ctl notify-action <id> reply` and checks for `ActionInvoked`.

```sh
sh tests/notifications.sh
```

`tests/notification-routing.sh` starts two headless outputs and checks that the
toast layer surface is created on the focused output, moves when focus changes,
and stays there for the next notification.

```sh
sh tests/notification-routing.sh
```

The panel's notification service needs a session D-Bus. If no bus is available,
the rest of the panel still runs and the service logs the failure. Auto-starting
Tessa from a display manager normally provides a session bus.

### System status test

`tests/system-status.sh` supplies a fake `/sys/class/power_supply`, `/sys/class/net`,
and `/proc/net/route` tree through the `TESSA_POWER_SUPPLY_PATH`,
`TESSA_NET_PATH`, and `TESSA_ROUTE_PATH` environment overrides. It verifies the
battery/network startup indicators and that changing battery capacity is picked
up by the five-second poll.

```sh
sh tests/system-status.sh
```

### Media test

`tests/media.sh` starts `tests/fake-mpris.py` on a private session bus, checks
MPRIS discovery and the bar chip, opens the media popover, and verifies
play/pause, next, previous, and the `Super+M` binding. The fake player uses
PyGObject; the test skips when `python3`/GObject introspection bindings are not
available.

```sh
sh tests/media.sh
```

### Tray test

`tests/tray.sh` runs a fake StatusNotifier item on a private session bus. It
checks the watcher properties, item registration, the 22×22 ARGB32 pixmap path,
the tray popover, activation, and the `Super+Shift+T` binding. wtype and
PyGObject are required; the test skips otherwise.

```sh
sh tests/tray.sh
```

### Audio test

`tests/audio.sh` puts a fake `wpctl` in `PATH` and drives the volume popover with
`Up`, `m`, and `Down`. It checks the initial 42% state, mute/unmute, volume
changes, and `Super+Shift+A`.

```sh
sh tests/audio.sh
```

### Foreign-toplevel test

`tests/foreign-toplevels.sh` compiles a small Wayland client against the
`wlr-foreign-toplevel-management` and `ext-foreign-toplevel-list` protocols,
spawns `foot`, and checks the title, app-id, and activated state. It needs
`foot`, `cc`, and `wayland-scanner`, and skips if they are missing. These are the
compositor-side prerequisites for window selection in
`xdg-desktop-portal-wlr`.

```sh
sh tests/foreign-toplevels.sh
```

### Portal and PipeWire screen sharing test

`tests/portal.sh` starts a private headless Tessa session, PipeWire,
`xdg-desktop-portal`, and `xdg-desktop-portal-wlr`, then calls the ScreenCast
portal (CreateSession, SelectSources, Start, OpenPipeWireRemote). It verifies a
stream node and a valid remote fd. The test uses a temporary `tessa.portal`
selector and an xdpw config with `chooser_type=none`; it skips if the portal or
PipeWire binaries are not installed. Point `TESSA_PORTAL_ROOT` at an extracted
package root to test unpackaged builds.

```sh
sh tests/portal.sh
TESSA_PORTAL_ROOT=/tmp/portal-root sh tests/portal.sh
```

### Lock and idle test

`ext-session-lock-v1`, `ext-idle-notify-v1`, `idle-inhibit-v1`, and
output-power management are exposed by the compositor. Install clients to test
them:

```sh
sudo apt install swaylock swayidle wlopm
```

Run `swaylock -f` inside the session (or press `Super+Escape`). The desktop
should be completely replaced by the lock surface; a virtual keyboard created
after locking must not type into it, and if the lock client is killed while
locked Tessa should terminate instead of exposing the desktop. For idle
testing, run `swayidle -w timeout 5 'swaylock -f'` and verify that activity
postpones the lock, while a client holding `idle-inhibit-v1` prevents it.

## Extension and integration tests

The headless smoke test starts a compositor with config includes, hooks, and a
temporary runtime directory, then checks workspace changes, layout persistence,
config reload propagation with runtime overrides preserved, status set/clear,
event subscriptions, IPC half-close handling, keyboard floating resize, and
(when `foot` is installed) window open/focus/close events:

```sh
./scripts/build.sh
sh tests/smoke.sh
```

Use `TESSA_CTL_DEBUG=1 tessa-ctl events` to print received event lines to stderr.
See [EXTENDING.md](EXTENDING.md) for the API and hook environment.

## Debug logging

```sh
# wlroots debug logs, Tessa logs, and IME/popup diagnostics
TESSA_DEBUG=1 ./scripts/run-headless.sh

# panel state snapshots (active workspace, window count)
TESSA_PANEL_DEBUG=1 ./scripts/run-headless.sh

# full Wayland protocol log from a test client
WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/tmp/tessa-headless \
  WAYLAND_DEBUG=1 foot -T debug
```

Environment overrides:

- `TESSA_IPC=/path/to/socket`
- `TESSA_CONFIG=/path/to/config`
- `TESSA_NO_PANEL=1`
- `TESSA_PANEL_BIN=/path/to/tessa-panel`
- `TESSA_PANEL_OUTPUT=<output name>` (set automatically for per-output panels)
- `TESSA_OUTPUT_CONFIG=/path/to/outputs.conf`
- `TESSA_NO_XWAYLAND=1`
- `TESSA_XWAYLAND_BIN=/path/to/xwayland-satellite`
- `TESSA_DEBUG=1`
- `TESSA_PANEL_DEBUG=1`

## Real TTY

For DRM and libinput, run Tessa on the machine's **active virtual terminal**.
The compositor needs DRM master and seat access; launching it from an unrelated
SSH session will not give you a usable hardware session.

```sh
cd /path/to/Tessa
PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

The panel is auto-started from `PATH`. If you install with
`scripts/install-session.sh`, the session entry point puts its own directory at
the front of `PATH`, so both binaries are found.

## Iteration tips

- After changing panel settings, press `Super+R`: the panel reloads its palette,
  bar geometry, font, terminal, launcher entries, and power commands when the
  compositor emits `config-reload`. Geometry changes recreate the bar layer
  surface.
- Clipboard history depends on the compositor's `wlr-data-control-v1` global.
  `wl_data_device` selection events are focused-client-only, so do not replace
  the panel's data-control device with the ordinary interface.
- `pkill -x tessa` and `pkill -x tessa-panel` are safer than `pkill -f tessa`
  when working over SSH: a `-f` pattern can match the SSH remote command line
  itself and kill the session.
- The headless output name is stable: `grim -o HEADLESS-1`.
- Zig's translate-c cannot process Pango/GLib headers. Text rendering lives in
  `panel/text.c`; keep Pango out of `@cImport`.
- Layer-shell `EXCLUSIVE` is enum value `1`; `2` is `ON_DEMAND`.
- `ReleaseSafe` needs `_FORTIFY_SOURCE=0` for the C imports; this is already set
  in the two `c.zig` files.
- Xwayland 24.x needs a keyboard keymap in the parent seat at startup, or it
  fails with `XKB: Failed to compile keymap`; the fallback keyboard in
  `input.zig` provides one.
- Reset `SIGCHLD` to `SIG_DFL` before exec'ing children. Tessa ignores `SIGCHLD`
  for its own child reaping; inheriting that breaks helpers that spawn and wait,
  including Xwayland's xkbcomp.
- `wlr_xdg_toplevel_decoration_v1_set_mode()` must not schedule a configure
  before the xdg surface's initial commit. If it is not initialized, set
  `scheduled_mode` and apply it after initialization.
