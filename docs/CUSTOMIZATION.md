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
| `power_lock` | command for the power menu's Lock action (default `loginctl lock-session`) |
| `power_suspend` | command for Suspend (default `systemctl suspend`) |
| `power_reboot` | command for Reboot (default `systemctl reboot`) |
| `power_off` | command for Power Off (default `systemctl poweroff`) |

The panel rereads the palette, launcher entries, bar geometry, and power
commands when the compositor emits `config-reload`. A geometry change recreates
the bar layer surface, so the reserved area follows immediately. A separately
installed theme file and wallpaper-art controls are still planned.

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
`focus-next`, `focus-prev`, `launcher`, `reload`, `ratio`, `toggle-layout`,
`set-layout`, `resize-width`, and `resize-height`.

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
