**English** | [日本語](CUSTOMIZATION.ja.md)

# Customization

Tessa aims to be highly customizable without embedding a JavaScript/TypeScript
runtime or a native plugin VM. Customization has three layers:

1. **Declarative configuration** — key bindings, window rules, layout tuning,
   colors, includes, and live reload.
2. **A process extension surface** — hooks, structured events, status entries,
   the launcher, and the Unix-socket IPC used by `tessa-ctl`.
3. **Protocols for external policy engines** — a layout-helper protocol and
   richer effect control are the next steps. The design goal is that a policy
   engine can live in any language without loading code into the compositor.

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

Mosaic is deliberately bounded: when the configured minimum tile size cannot be
maintained, the whole workspace uses the grid layout instead of overlapping or
producing unusable slivers.

## Appearance

| Key | Meaning |
| --- | --- |
| `accent` | accent used by borders, panel, and launcher |
| `bg` | wallpaper/background color |
| `border_active` | focused-window border color; empty means use `accent` |
| `border_inactive` | unfocused border color |
| `border_width` | border thickness in logical pixels |
| `font` | panel/launcher family |

The panel rereads `accent`, `bg`, `font`, and launcher entries when the
compositor emits `config-reload`. Panel height, margins, and a fully separated
theme file are planned so the shell can be themed independently of the
compositor.

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

- Per-workspace and per-output layout/gap rules.
- A long-lived external **layout helper** protocol: the compositor sends a
  window list and canvas, the helper returns rectangles. This enables custom
  tiling algorithms without a plugin ABI.
- Configurable animations and shader/effect hooks for window movement,
  workspace changes, borders, and the shell.
- Schema validation with file/line diagnostics, and a JSON view of state and
  configuration for third-party control panels.
- More shell theming: bar size/margins, independent palette roles, and
  replaceable shell surfaces.

The roadmap is in [ROADMAP.md](ROADMAP.md). A TypeScript/TSX configuration
runtime remains a non-goal; Tessa's answer to ShojiWM-style composition is a
process protocol plus declarative rules, not an embedded JS VM.
