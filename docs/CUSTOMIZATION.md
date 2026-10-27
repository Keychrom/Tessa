**English** | [日本語](CUSTOMIZATION.ja.md)

# Customization

Tessa aims to be highly customizable without embedding a JavaScript/TypeScript
runtime or a native plugin VM. Customization has three layers:

1. **Declarative configuration** — key bindings, window rules, layout tuning,
   colors, includes, and live reload.
2. **A process extension surface** — hooks, structured events, status entries,
   the launcher, and the Unix-socket IPC used by `tessa-ctl`.
3. **Protocols for external policy engines** — the long-lived layout-helper
   protocol is available now; richer effect control is next. The design goal is
   that a policy engine can live in any language without loading code into the
   compositor.

The flat `key = value` format is intentional: it keeps the parser small,
supports positional includes, and makes effective values and parsed rules
inspectable with `tessa-ctl config`.

## Window rules

A window rule is one line. Match clauses and actions are separated by `;`:

```ini
window-rule = app-id=pavucontrol; float=true
window-rule = title=Picture-in-Picture; float=true; position=40,40
window-rule = app-id=firefox; workspace=2
window-rule = title=GIMP*; float=false
```

Match clauses:

| Key | Meaning |
| --- | --- |
| `app-id`, `app_id`, `class` | xdg application id |
| `title` | window title |
| `output`, `monitor` | output name |

Patterns support shell-style `*` and `?` wildcards and are case-sensitive.
`*` matches any sequence, including an empty one:

```ini
window-rule = title=*Picture-in-Picture*; float=true
window-rule = app-id=org.example.*; workspace=3
```

Action clauses:

| Key | Meaning |
| --- | --- |
| `float=true/false` | open floating or tiled |
| `tile=true/false` | inverse of `float` |
| `fullscreen=true/false` | open fullscreen |
| `workspace=1..9` | assign the window to a workspace |
| `size=WxH` | floating size, for example `size=900x600` |
| `width=N`, `height=N` | floating size, one axis at a time |
| `position=X,Y` | floating position |

`size` and `position` imply floating unless the same rule says `float=false`.
Rules are evaluated in file order; a later matching rule can override an earlier
one. They run when a window maps and are re-evaluated for existing windows on
`Super+R` / `tessa-ctl dispatch reload`. A title change after mapping does not
retrigger rules until the next reload.

Values may be quoted when they contain spaces. A `;` inside a value is not
supported in the flat format.

## Layout tuning

| Key | Default | Meaning |
| --- | --- | --- |
| `gaps` | `10` | gap between tiles |
| `outer_gaps` | `16` | gap around the tiling area |
| `master_ratio` | `0.58` | master-column width ratio |
| `master_count` | `1` | windows stacked in the master column |
| `mosaic_ratio` | `0.62` | slice ratio for the mosaic spiral |
| `mosaic_min_size` | `160` | minimum tile before mosaic falls back to grid |
| `grid_columns` | `0` | fixed grid columns; `0` uses `ceil(sqrt(n))` |
| `layout` | `master` | default layout |
| `layout_1` … `layout_9` | inherited | initial layout per workspace |

Runtime layout choices are stored per output and workspace in `outputs.conf`.
A config reload updates workspaces that have no runtime override. `layout_N`
only seeds workspaces without a saved or runtime choice.

`workspace-rule` overrides layout and spacing per workspace:

```ini
workspace-rule = ws=2; layout=grid; gaps=4; outer-gaps=8; master-ratio=0.65
```

| Clause | Meaning |
| --- | --- |
| `ws=1..9` | target workspace (required) |
| `layout=master/mosaic/grid/columns/custom` | initial layout seed |
| `gaps=N` | gap between tiles on this workspace |
| `outer-gaps=N` | outer gap on this workspace |
| `master-ratio=0.15..0.9` | master-column width on this workspace |

A runtime layout choice still wins over the seed and is persisted. The
`Super+Ctrl+H/L` ratio binding adjusts the active workspace's ratio for the
current session; config reload restores configured ratio values.

Workspaces can be bound to monitors so the shortcut always brings that monitor
forward:

```ini
workspace_pin = eDP-1 1
workspace_pin = HDMI-A-1 3
```

Keyboard, gesture, IPC, and bar switches to a pinned workspace redirect to its
output. `Super+Shift+<n>` moves the focused window to that workspace, changing
its output when the workspace is pinned elsewhere. A missing output releases the
pin until that output appears. `tessa-ctl workspace <n> <output>` still names the
requested monitor, but a pin takes precedence.

Mosaic is deliberately bounded: when the configured minimum tile size cannot be
maintained, the whole workspace uses the grid layout instead of overlapping or
producing unusable slivers.

## External layout helper

Custom tiling lives in a long-lived helper process. Select it with
`layout = custom`, point `layout_helper` at a command, and bind it if you want
it outside the `Super+T` cycle:

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

Tessa sends one tab-separated request describing the usable area and the tiled
windows, then reads a response with one rectangle per window. `	` below means
a literal tab:

```text
LAYOUT	1
OUTPUT	HEADLESS-1
AREA	0	0	1920	1080
OUTER_GAP	16
GAP	10
BORDER	2
SCALE	1.000
TRANSFORM	0
COUNT	2
WINDOW	7	foot	notes
WINDOW	8	kitty	shell
END
```

The helper replies:

```text
RECT	7	16	16	940	1048
RECT	8	966	16	938	1048
END
```

Coordinates are absolute logical compositor coordinates. Rectangle width and
height are frame sizes including the border. Floating and fullscreen windows are
not sent. A response must contain exactly one rectangle for every request window
and may not contain unknown ids. Return `ERR` instead of rectangles to reject
the frame.

The helper is started lazily, kept across layout changes, and shared by all
outputs. It is restarted when `layout_helper` changes or after a failure. A
missing command, timeout, crash, malformed response, or rectangle mismatch
falls back to the master layout for that arrangement; after a failure the same
command is retried after one second. The request is limited to 64 tiled windows.
The default timeout is 100 ms and the allowed range is 10–1000 ms.

`stdout` is reserved for the protocol. Write diagnostics to `stderr`. The
command runs as your user through `/bin/sh`, like a hook. See
[`examples/layout-cascade.py`](../examples/layout-cascade.py) for a minimal
working helper.

## Input modes

Modes group bindings and are entered with the `enter-mode` action:

```ini
mode = resize
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default

mode = default
bind = SUPER+SHIFT+r enter-mode resize
```

`mode = <name>` changes the parse context for following `bind` lines until the
next `mode` line. Names may contain letters, digits, `_`, and `-`. Includes
restore the caller's mode after returning.

Mode bindings are matched even when no modifiers are held; global (`default`)
bindings still work, and keys with no match reach the focused client. This makes
modal resize, navigation, or launcher-like keymaps possible without a separate
compositor. `tessa-ctl mode <name>` switches from a script, and the active mode
is exposed as `MODE <name>` in `tessa-ctl state`, `"mode"` in state JSON,
`"modes"` in config JSON, and the `mode-change` event.

## Validation and JSON

Configuration is parsed with file and line tracking. Unknown keys, invalid
numbers/booleans/colors, malformed rules, and missing includes are reported
instead of being silently ignored:

```sh
tessa-ctl config-check
```

`Super+R` / `tessa-ctl dispatch reload` rejects a configuration with errors and
keeps the previously active one. `tessa-ctl config` shows the effective values
plus `diagnostic error <path>:<line>: <message>` lines. `config-check` exits
non-zero when errors remain.

For tools, both snapshots have a schema version and are available as JSON:

```sh
tessa-ctl state --json
tessa-ctl config --json
```

State JSON contains `schema: 1`, outputs, occupancy, focused id, statuses, and
window geometry. Config JSON contains scalar settings, per-workspace layouts and
tuning, rules, hooks, and diagnostics. The full wire format is in
[EXTENDING.md](EXTENDING.md).

## Input, gestures, and XIM

| Key | Meaning |
| --- | --- |
| `gestures` | enable compositor swipe gestures (default `true`) |
| `gesture_fingers` | finger count for shell swipes, 2–5 (default 3) |
| `gesture_workspace_threshold` | horizontal distance needed for a workspace switch (default 400) |
| `gesture_launcher_threshold` | upward distance needed for the launcher (default 300) |
| `touch` | accept touch input devices (default `true`) |
| `tablet` | enable tablet-v2 tools and pads (default `true`) |
| `pointer_constraints` | enable `pointer-constraints-v1` (default `true`) |
| `xim` | export `XMODIFIERS` for X11 clients (default `true`) |
| `xim_server` | XIM server name; empty disables the variable (default `fcitx`) |
| `xim_start` | optional XIM server command started after the X display appears |

A swipe with exactly `gesture_fingers` fingers is handled by the shell when no
keyboard-focused layer surface is open. Swiping left goes to the next
workspace, swiping right to the previous one, and swiping up opens the launcher.
Set `gestures = false` to forward every gesture to clients. Gestures with other
finger counts, plus pinch and hold, are always sent to the focused client through
`pointer-gestures-v1`. Tune the thresholds in 20–1000; smaller values react
sooner.

Touch devices are attached to the shared cursor and routed through scene
hit-testing. Tapping a client focuses it; the panel accepts touch directly.
Tablet-v2 tools receive proximity, tip, pressure, distance, tilt, rotation,
slider, wheel, and button events, and fall back to pointer clicks on surfaces
that do not support tablet-v2. Tablet pads forward buttons, rings, strips, and
mode changes to the keyboard-focused surface.

Pointer constraints are activated when their surface receives keyboard focus
and deactivated on a focus change. Locked pointers stop cursor movement while
relative motion continues to reach the client; confined pointers are clipped to
the constraint region. Set `pointer_constraints = false` to ignore constraint
requests.

For X11 input methods, Tessa exports `XMODIFIERS=@im=<xim_server>` once XWayland
is running. `xim_start` is optional and is started only after the X socket
exists, which avoids starting Fcitx before its display is ready:

```ini
xim = true
xim_server = fcitx
xim_start = fcitx5 -d
```

If Fcitx or IBus already starts from `startup`, leave `xim_start` empty. XIM
settings are applied at compositor startup; restart Tessa after changing them.
Use `xim = false` when another input method stack manages `XMODIFIERS`.

## Appearance

| Key | Meaning |
| --- | --- |
| `accent` | accent used by borders, panel, and launcher |
| `bg` | wallpaper/background color |
| `border_active` | focused-window border color; empty means use `accent` |
| `border_inactive` | unfocused border color |
| `border_width` | border thickness in logical pixels |
| `font` | panel/launcher family |
| `bar_height` | bar height in logical pixels (32–96) |
| `bar_top_margin` | distance from the top edge (0–64) |
| `bar_side_margin` | left/right margin (0–128) |
| `panel_bg` | bar background color |
| `panel_fg` | bar primary text color |
| `bg_top` | top color of the wallpaper gradient; unset derives it from `bg` |
| `bg_bottom` | bottom color of the wallpaper gradient; unset derives it from `bg` |
| `wallpaper_art` | draw the decorative wallpaper art (default `true`) |
| `animations` | animate window open, close, and workspace transitions (default `true`) |
| `animation_ms` | motion duration in milliseconds, 0–1000 (default 160) |
| `reduce_motion` | disable motion regardless of `animations` (default `false`) |
| `shadows` | draw layered window drop shadows (default `true`) |
| `corner_radius` | rounded window radius in logical pixels, 0–64 (default `10`; scenefx builds) |
| `blur` | backdrop blur for translucent clients and shell layers (default `true`; scenefx builds) |
| `blur_radius` | blur radius, 1–32 (default `6`) |
| `blur_passes` | blur quality passes, 1–5 (default `3`) |
| `power_lock` | command for the power menu's Lock action (default `loginctl lock-session`) |
| `power_suspend` | command for Suspend (default `systemctl suspend`) |
| `power_reboot` | command for Reboot (default `systemctl reboot`) |
| `power_off` | command for Power Off (default `systemctl poweroff`) |
| `screenshot_dir` | screenshot PNG directory (default `~/Pictures/Screenshots`) |
| `volume_status` | optional status command (prints a percentage); empty auto-detects `wpctl`/`pactl`/`amixer` |
| `volume_up` | optional volume-up command override |
| `volume_down` | optional volume-down command override |
| `volume_mute` | optional mute-toggle command override |

The panel rereads the palette, launcher entries, bar geometry, and power
commands when the compositor emits `config-reload`. A geometry change recreates
the bar layer surface, so the reserved area follows immediately. `bg_top`,
`bg_bottom`, and `wallpaper_art` repaint the panel background without a restart.
A separately installed theme file is still planned.

## Motion, shadows, and wallpaper

Windows slide in from a small vertical offset when mapped, and workspace
switches slide the incoming workspace horizontally. Both use a cubic ease-out
over `animation_ms`. A window closed through the compositor (a key binding, bar
chip, IPC, or another client) captures its surface and scales/fades that
snapshot with a smoothstep over the same duration. A client that closes itself
disappears immediately because its buffer is already gone. `reduce_motion =
true` disables all such motion while leaving other settings intact;
`animation_ms = 0` and `animations = false` do the same. Popover animation is
controlled separately by the panel.

Shadows are three translucent scene rectangles behind each client frame. They
follow the border geometry and are disabled with `shadows = false`.

In a build made with `-Dscenefx=true`, `corner_radius` rounds client content,
the border, and shadow layers; fullscreen windows stay square. `blur` enables
backdrop blur on translucent windows and on the top/overlay/popup layer
surfaces, using `blur_radius` and `blur_passes`. Both apply immediately on
config reload. These keys are accepted but have no visual effect in the default
wlroots-scene build.

The wallpaper is a vertical gradient. Set `bg_top` and `bg_bottom` to override
the derived default; either key can be omitted independently. Decorative shapes
(the accent wash, ink blots, sun, and tessellation) are drawn only when
`wallpaper_art = true`.

## Calendar and power menu

Click the clock to open the month calendar. `Left`/`Right`, the arrow buttons,
or the scroll wheel change the month; `Home` returns to today. The power menu
opens by right-clicking the `TESSA` mark. It offers Lock, Suspend, Reboot,
Power Off, and Quit Tessa; the first four run the `power_*` commands above.
`Up`/`Down` and `Enter` work from the keyboard, and clicking outside closes
either popover.

Both popovers can also be opened or toggled by an extension:

```sh
tessa-ctl panel calendar
tessa-ctl panel power
tessa-ctl panel power DP-1
```

Opening a popover emits the `panel` event with `arg=calendar` or `arg=power`
and the output name, so hooks can observe or drive the shell as well.

## Clipboard history

`Super+V` opens the clipboard history, and `tessa-ctl panel clipboard` can open
it from an extension or another binding. The panel uses the compositor's
`wlr-data-control-v1` global to observe selections without requiring keyboard
focus. History keeps the latest eight distinct text entries (up to 16 KiB each)
in memory only; it is never written to disk. Selecting an entry promotes it to
the top and makes the panel the new selection source, so any application can
paste it with its normal paste command.

`clipboard` is also available as a key-binding action:

```ini
bind = SUPER+v clipboard
bind = SUPER+SHIFT+v clipboard
```

## Screenshots

`Super+Shift+S` (or `tessa-ctl panel screenshot`) captures the focused output
with `wlr-screencopy`. Drag to select a region, click for the full output, or
press `Enter` for the full output; `Esc` or right-click cancels. The panel draws
the selection on an overlay, punches the selected area out of the dim layer, and
shows the physical pixel size while dragging.

PNGs are written to `screenshot_dir`:

```ini
screenshot_dir = ~/Pictures/Screenshots
```

That is the default. Subdirectories are created as needed. Files are named
`tessa-YYYYMMDD-HHMMSS-mmm.png`. The capture is taken before the overlay is
shown, so the selection UI and dim layer are not included. The bar is part of
the output and is included unless you select a region below it. `screenshot` is
also a key-binding action:

```ini
bind = SUPER+SHIFT+s screenshot
```

## System indicators and media

When a battery is present under `/sys/class/power_supply`, the bar shows its
charge and colors the fill while charging. The network indicator reads the
default route from `/proc/net/route` and the interface state from
`/sys/class/net`; it shows `Wi-Fi` when the interface has a `wireless` attribute
and `LAN` otherwise. Both refresh every five seconds and need no configuration.

Tessa watches MPRIS on the session bus. The first player discovered contributes
a bar chip with the current title and play/pause state. Click the chip, press
`Super+M`, or run `tessa-ctl panel media` to open the controls: previous,
play/pause, and next. In the popover, `Space` toggles playback and `Left`/`Right`
skip. The MPRIS client is read-only for metadata; album art is not displayed.
Use `media` as a key-binding action, for example:

```ini
bind = SUPER+M media
bind = SUPER+SHIFT+m media
```

## StatusNotifier tray

The panel owns `org.kde.StatusNotifierWatcher` and hosts registered tray items.
Icons from `IconPixmap` or `IconName` appear in the bar. Left-click activates an
item; right-click or `Super+Shift+T` opens a popover with the item titles and
statuses. `Up`/`Down` selects, `Enter` activates, and `Esc` closes. Items can
also be opened with:

```sh
tessa-ctl panel tray
```

`tray` is available as a key-binding action:

```ini
bind = SUPER+SHIFT+t tray
```

DBusMenu context menus and secondary activation are not implemented yet. If a
different watcher already owns the D-Bus name, the tray service logs the failure
and the rest of the panel keeps running.

## Volume

When `wpctl`, `pactl`, or `amixer` is available, the panel shows the default
output volume in the bar. Click it or press `Super+Shift+A` to open the volume
popover. `Up`/`Down` changes the volume, `m` toggles mute, and `Esc` closes.
`tessa-ctl panel audio` opens the same popover, and `audio` is a key-binding
action:

```ini
bind = SUPER+SHIFT+a audio
```

The default commands are:

- `wpctl get-volume @DEFAULT_AUDIO_SINK@`, `wpctl set-volume ... 5%+/-`, and
  `wpctl set-mute ... toggle` for PipeWire
- `pactl get-sink-volume`, `pactl set-sink-volume`, and `pactl set-sink-mute`
  for PulseAudio
- `amixer get Master` and `amixer sset Master ...` for ALSA

Override any part with panel settings. A custom status command should print a
percentage and may contain `MUTED`/`[off]`; custom commands run through
`/bin/sh -c`:

```ini
volume_status = ~/.local/bin/my-volume-status
volume_up = ~/.local/bin/my-volume up
volume_down = ~/.local/bin/my-volume down
volume_mute = ~/.local/bin/my-volume mute
```

## Screen sharing and portals

The compositor exposes the protocols `xdg-desktop-portal-wlr` needs:
`zwlr_screencopy_manager_v1`, linux-dmabuf when the renderer supports it,
`ext-output-image-capture-source-manager-v1`, `ext-image-copy-capture-v1`, and
both foreign-toplevel list protocols. The repository ships
`packaging/portal/tessa.portal`; system packages install it under
`/usr/share/xdg-desktop-portal/portals/`. It selects the wlr backend for
`XDG_CURRENT_DESKTOP=Tessa`.

Install `xdg-desktop-portal`, `xdg-desktop-portal-wlr`, and a running PipeWire
server. If xdpw's automatic chooser is inconvenient, select an output directly:

```ini
# ~/.config/xdg-desktop-portal-wlr/config
[screencast]
chooser_type = none
output_name = HDMI-A-1
max_fps = 30
```

Monitor screencasting is covered end to end by `tests/portal.sh`. Window
sources depend on the portal backend's support for the image-capture-source
protocols; Tessa currently advertises output capture sources.

## Notifications

The panel implements the `org.freedesktop.Notifications` D-Bus service on the
session bus, so applications can use it without a separate daemon. Up to four
toasts stack below the bar. They support replacement by notification id, timeout
(`0` keeps a notification until dismissed), `CloseNotification`, and
click-to-dismiss. Notifications marked with an expiry time remove themselves and
emit the corresponding signal.

Advertised capabilities are `actions`, `body`, `body-markup`, `icon-static`, and
`persistence`:

- **Actions.** Non-default action pairs become buttons at the bottom of the
  toast. Clicking one emits `ActionInvoked` and closes the notification. A
  `default` action is triggered by clicking the card body. Notification actions
  can also be invoked from an extension with
  `tessa-ctl notify-action <id> <key>`, which is useful for scripted tests and
  keyboard-driven automation.
- **Icons.** `image-data`/`image_data`, `image-path`/`image_path`, the
  `icon-name` hint, and the `app_icon` argument are supported. PNG theme icons
  are searched under the usual XDG icon directories; otherwise a colored
  monogram is shown.
- **Markup.** The body is rendered with Pango markup when it parses cleanly
  (bold, italic, underline, spans, and links). Invalid markup falls back to
  plain text.
- **Routing.** New toasts are created on the currently focused output. When
  focus moves while toasts are visible, the stack moves to the new output.
  Actions still work because a single panel owns the D-Bus name and renders the
  surface on the chosen output.

If another notification daemon is already running, Tessa cannot own the bus name
and leaves notifications to that daemon. Notification sounds and HTML beyond
Pango's supported subset are not implemented.

You can exercise the service with:

```sh
gdbus call --session --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.Notify \
  test-app 0 "" "Build finished" "All targets are up to date" "[]" "{}" 5000
```

## Keys and commands

See [../README.md](../README.md#key-bindings) for the defaults. Additional
bindings use XKB keysym names:

```ini
bind = SUPER+Return terminal
bind = SUPER+g set-layout grid
bind = SUPER+ALT+Left resize-width -30
bind = SUPER+ALT+Right resize-width 30
```

Available actions include `spawn`, `terminal`, `close`, `quit`, `workspace`,
`move-to-workspace`, `focus`, `move`, `toggle-float`, `toggle-fullscreen`,
`focus-next`, `focus-prev`, `launcher`, `clipboard`, `screenshot`, `media`,
`tray`, `audio`, `reload`, `ratio`, `toggle-layout`, `set-layout`,
`resize-width`, and `resize-height`.

## Live inspection and automation

`tessa-ctl config` prints the effective configuration, including parsed rules
and tuning values:

```sh
tessa-ctl config
tessa-ctl state
tessa-ctl events window-open
```

Hooks receive the same structured fields as the event stream. Status entries,
custom launcher entries, runtime layout changes, and window resizing are all
available through IPC. See [EXTENDING.md](EXTENDING.md) for the protocol.

## Planned customization work

- Per-output layout/gap rules (per-workspace rules are available now).
- Per-output helper instances, asynchronous/incremental updates, and protocol
  version negotiation (the current helper is one process with a bounded
  request/response per arrangement).
- Regex/boolean window-rule expressions and per-rule border/background colors.
- Keybinding sequences and leader keys (named input modes are available now).
- Config-defined event-to-action rules and per-output theme roles.
- Configurable animations and shader/effect hooks for window movement,
  workspace changes, borders, and the shell.
- Interactive config editor/check with diff preview, built on the existing
  diagnostics and JSON snapshots.
- More shell theming: font/palette roles per surface, wallpaper art, and
  replaceable shell surfaces (bar size/margins are configurable now).

The roadmap is in [ROADMAP.md](ROADMAP.md). A TypeScript/TSX configuration
runtime remains a non-goal; Tessa's answer to ShojiWM-style composition is a
process protocol plus declarative rules, not an embedded JS VM.
