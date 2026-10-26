**English** | [日本語](EXTENDING.ja.md)

# Extending Tessa

Tessa deliberately has no plugin VM and no JavaScript configuration runtime.
Extensions are ordinary processes that speak the compositor's Unix-socket API.
That keeps the core small, makes extensions possible in any language, and avoids
loading untrusted code into the compositor process.

The socket is created with mode `0600` under `$XDG_RUNTIME_DIR` (normally
`tessa.sock`). The same user can run any command through the API, exactly as if
they had run it in a terminal.

![External status entries and a custom launcher entry](images/extensions.png)

## tessa-ctl

`tessa-ctl` is the reference client. It is installed next to `tessa` and
`tessa-panel`.

```sh
tessa-ctl state                         # one snapshot
tessa-ctl config                        # effective configuration + rules
tessa-ctl events                        # stream all events
tessa-ctl events window-focus           # stream one topic
tessa-ctl workspace 3                   # focused output
tessa-ctl workspace 3 HEADLESS-2        # a specific output
tessa-ctl spawn foot -T notes
tessa-ctl launcher fire                 # query is optional
tessa-ctl panel calendar                # toggle a panel popover
tessa-ctl panel clipboard              # clipboard history
tessa-ctl panel power HEADLESS-2        # target a specific output
tessa-ctl layout grid                   # set/cycle current workspace layout
tessa-ctl mode resize                   # switch input mode
tessa-ctl resize 40 30                  # grow the focused floating window
tessa-ctl dispatch reload               # any compositor command
tessa-ctl quit
```

`dispatch` adds `CMD` and sends the rest of the line as a compositor command.
The socket path is `$TESSA_IPC`, or `$XDG_RUNTIME_DIR/tessa.sock`.

## State and subscriptions

A newly accepted connection receives nothing until it subscribes. The panel
sends:

```text
CMD subscribe all
```

Other clients can choose:

```text
CMD subscribe state     # snapshots only
CMD subscribe events    # events only
CMD state               # request one snapshot without subscribing
```

Snapshots are line-oriented and end with `END`. `STATE` begins a new snapshot;
the panel reconstructs its entire bar from each snapshot. `CONFIG` is a separate
request/response snapshot used by `tessa-ctl config`; it contains effective
settings, `layout_ws`/`workspace_tuning` lines for each workspace, and
`rule <raw>` lines. The most useful state lines are:

```text
MODE default
OUT HEADLESS-1 3 1 grid
FOCUSED 7
STATUS	weather	Tokyo 18C	
WIN	7	3	1	0	0	foot	notes	HEADLESS-1	40	30	1100	700
```

`MODE` is the active input mode. `OUT` is `name workspace focused layout`.
`WIN` fields are tab-separated: id,
workspace, focused, floating, fullscreen, escaped app_id, escaped title, output,
x, y, width, height. Geometry is in logical compositor coordinates and is
included for tooling that tracks windows. `STATUS` is covered below.

## JSON snapshots

For tools, state and effective configuration are available as versioned JSON.
The text commands still work:

```text
CMD state-json
STATE_JSON
{"schema":1,"active_workspace":1,"mode":"default","outputs":[...],"occupancy":[...],"focused":7,"statuses":[...],"windows":[...]}
END

CMD config-json
CONFIG_JSON
{"schema":1,"errors":0,"terminal":"kitty",...,"layouts":[...],"workspace_tuning":[...],"rules":[...],"hooks":[...],"diagnostics":[]}
END
```

`tessa-ctl state --json` and `tessa-ctl config --json` print only the JSON line.
`STATE_JSON` and `CONFIG_JSON` are framing markers, not part of the JSON.
State JSON includes the active `mode`; config JSON includes a `modes` array.
`schema` is currently `1`; consumers should reject unknown versions.

State windows contain `id`, `workspace`, `focused`, `floating`, `fullscreen`,
`app_id`, `title`, `output`, `x`, `y`, `width`, and `height`. Config
`diagnostics` entries contain `severity`, `path`, `line`, and `message`.

Text `CMD config` also includes diagnostics in this human-readable form:

```text
diagnostic error /home/you/.config/tessa/config:12: unknown key 'widht'
```

A reload with errors is rejected and keeps the previous configuration.
`tessa-ctl config-check` prints diagnostics and exits non-zero while errors
remain. It checks the most recently loaded or rejected configuration, so run a
reload after editing.

## Events

Events are key/value records. Tabs separate fields and values are escaped
(`\`, `\t`, `\n`, `\r`). The first two fields are always `EVENT` and the topic:

```text
EVENT	window-focus	id=7	previous=0	ws=3	app=foot	title=notes	output=HEADLESS-1
EVENT	workspace-change	ws=4	previous-ws=3	output=HEADLESS-1
EVENT	launcher	arg=fire	output=HEADLESS-1
EVENT	panel	arg=calendar	output=HEADLESS-1
EVENT	panel	arg=clipboard	output=HEADLESS-1
```

Fields are omitted when they do not apply. `id` and `previous` are ids; `ws` and
`previous-ws` are workspace numbers; `app`, `title`, `output`, and `arg` are
strings. The `window-focus` topic with `id=0` means focus was cleared; `previous`
names the window that lost focus.

| Topic | When | Useful fields |
| --- | --- | --- |
| `startup` | Backend started, XWayland launched | — |
| `shutdown` | Event loop is leaving | — |
| `window-open` | A toplevel is mapped | id, ws, app, title, output |
| `window-close` | A mapped toplevel is destroyed | id, ws, app, title, output |
| `window-focus` | Window focus changes or clears | id, previous, ws, app, title, output |
| `workspace-change` | An output changes workspace | ws, previous-ws, output |
| `window-moved` | Window sent to another workspace | id, ws, previous-ws, app, title, output |
| `layout-change` | Workspace layout changed | ws, output, arg |
| `mode-change` | Active input mode changed | arg (mode name) |
| `config-reload` | Config successfully reloaded | — |
| `launcher` | Launcher requested | arg (query), output |
| `panel` | A panel popover was requested | arg (`calendar`, `power`, or `clipboard`), output |
| `output-added` | Output initialized | output, arg (geometry) |
| `output-removed` | Output removed | output, arg (geometry) |

Events are delivered only to clients that asked for them with
`CMD subscribe events` or `CMD subscribe all`. They are best-effort: a slow
client with a full socket buffer is disconnected rather than blocking the
compositor.

## Hooks

Any event can launch a shell command. Multiple hooks per event are allowed.

```ini
startup = fcitx5 -d
hook = window-open notify-send "Window opened" "$TESSA_TITLE"
hook = workspace-change ~/.config/tessa/workspace.sh
hook = config-reload ~/.config/tessa/reload-shell.sh
```

The hook process inherits the compositor environment (including `TESSA_IPC`,
`WAYLAND_DISPLAY`, and `DISPLAY` when XWayland is active) plus:

| Variable | Meaning |
| --- | --- |
| `TESSA_EVENT` | Topic name |
| `TESSA_WINDOW_ID` | `id` field |
| `TESSA_PREVIOUS_ID` | `previous` field |
| `TESSA_WORKSPACE` | `ws` field |
| `TESSA_PREVIOUS_WORKSPACE` | `previous-ws` field |
| `TESSA_APP_ID` | `app` field |
| `TESSA_TITLE` | `title` field |
| `TESSA_OUTPUT` | `output` field |
| `TESSA_ARG` | `arg` field |
| `TESSA_FOCUSED_ID` | Current focused window id, or `0` |
| `TESSA_ACTIVE_WORKSPACE` | Focused output's active workspace |
| `TESSA_FOCUSED_OUTPUT` | Focused output name |

Hooks are fire-and-forget and run concurrently. They are not ordered, and a hook
that changes state can cause further events. Commands receive the full privileges
of the session user.

## Status entries

A process can publish a small text entry in the bar:

```sh
tessa-ctl status weather "Tokyo 18C"
tessa-ctl status weather "Tokyo 18C" --exec "weather-app"
tessa-ctl status weather --clear
```

The id is stable: updating an existing id replaces its text in place. Entries are
global across outputs. At most eight entries are kept; the oldest is evicted when
a new id arrives and the table is full. Text is stored up to 159 bytes and is
truncated for display. If a click command is supplied, clicking the entry sends
`CMD spawn <command>` to the compositor. Clearing an id removes it.

This is intentionally a text API, not an image/icon protocol. An extension can
update text on a timer or in response to events.

## External layout helper

For custom tiling algorithms, set `layout = custom` and configure
`layout_helper`. Tessa keeps the helper process alive and exchanges a
tab-separated request/response containing the usable area, window ids,
app-id/title metadata, and returned frame rectangles. The full protocol,
timeout behavior, and fallback rules are in
[CUSTOMIZATION.md](CUSTOMIZATION.md#external-layout-helper).

## Launcher entries and includes

The panel's launcher scans normal `.desktop` files. You can also add commands
directly from the config:

```ini
launcher_entry = Notes | foot -e nvim ~/notes.md
launcher_entry = Lock screen | swaylock
```

The name is matched by the normal launcher search; the command after `|` runs
through `/bin/sh`. The panel reloads its config when the compositor emits
`config-reload`, so `Super+R` updates both sides.

Configuration files may include other files:

```ini
include = /home/you/.config/tessa/keybindings.conf
include = /home/you/.config/tessa/launcher-entries.conf
```

Relative includes are resolved next to the including file. Includes are limited
to eight levels. Do not create an include cycle.

## Example

[`examples/active-window.sh`](../examples/active-window.sh) subscribes to
`window-focus` and publishes the focused title as the `active` status entry.
Run it from a terminal started by Tessa:

```sh
sh examples/active-window.sh
```

## Testing an extension

The repository includes a self-contained headless test:

```sh
./scripts/build.sh
sh tests/smoke.sh
```

It checks config includes, startup/workspace/config-reload hooks, the event
stream, status set/clear, IPC half-close behavior, and (when `foot` is installed)
window lifecycle events. `TESSA_CTL_DEBUG=1 tessa-ctl events` prints received
lines to stderr.

## Current limits

The command/event protocol is still line-oriented. JSON snapshots are versioned
with `schema: 1`, but the command plane has no version negotiation or JSON-RPC
request ids yet. There is no extension ordering or sandbox, and fire-and-forget
commands have no acknowledgement. Status entries are text-only.
