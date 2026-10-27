**English** | [日本語](ARCHITECTURE.ja.md)

# Architecture

Tessa is three programs:

1. **`tessa`** — the wlroots compositor and window manager.
2. **`tessa-panel`** — a Wayland client that owns the wallpaper, taskbar, and
   launcher. Tessa starts one panel process per output; each panel is bound to
   one `wl_output` through `TESSA_PANEL_OUTPUT`.
3. **`tessa-ctl`** — an optional CLI and reference implementation of the
   extension protocol. Extensions may be any local process, not just this CLI.

They communicate over a Unix stream socket. Keeping the shell in a separate
process means a panel crash does not take down the compositor, and it keeps all
text/font/UI code out of the compositor's hot path. The customization model and
its configuration reference are in [CUSTOMIZATION.md](CUSTOMIZATION.md).

## Process and protocol map

```text
                         ┌─────────────────────────────┐
                         │ tessa                        │
                         │  wl_display                  │
  DRM / headless /  ───▶ │  wlr_backend                 │
  nested Wayland         │  wlr_renderer / allocator    │
                         │  wlr_scene (global)          │
                         │  xdg-shell                   │
                         │  wlr-layer-shell             │
                         │  xdg-decoration             │
                         │  xdg-activation / cursor-shape│
                         │  text-input-v3 / input-method-v2│
                         │  wlr-screencopy-v1           │
                         │  linux-dmabuf-v1             │
                         │  ext-image-copy-capture-v1   │
                         │  ext-output-image-capture... │
                         │  ext-foreign-toplevel-list   │
                         │  wlr-foreign-toplevel-mgmt   │
                         │  wl_data_device + primary    │
                         │  wlr-data-control-v1         │
                         │  virtual-keyboard-v1         │
                         │  seat / cursor / keyboard    │
                         └──────┬───────────────┬───────┘
                                │               │
             Wayland clients    │               │ spawn + DISPLAY
             + tessa-panel      │               ▼
             (one per output)
                ────────────────┘        xwayland-satellite
                                                │
                                                ▼
                                            X11 apps
```

Wayland is used for clients and the panel. The compositor↔panel control channel
is deliberately not a custom Wayland protocol: a line-based socket protocol is
easy to debug with `socat` or `tessa-ctl`, works from any language, and does not
require regenerating bindings. `events.zig` is the event plane: it formats
events, runs configured hooks, and publishes the same records to subscribed IPC
clients.

## Scene graph order

All scene trees are children of `wlr_scene.root`, in this order (bottom to top):

```text
tree_bg          wallpaper / background layer surfaces, fallback bg rect
tree_bottom      layer-shell bottom
tree_windows     tiled client frames
tree_floating    floating client frames
tree_top         taskbar (layer-shell top)
tree_fullscreen  fullscreen client frames
tree_effects     close-animation snapshots (above normal windows)
tree_overlay     launcher (layer-shell overlay)
tree_popup       input-method candidate popups (created by ime.zig, topmost)
```

The fullscreen tree is intentionally above the top layer, so a fullscreen client
covers the bar. The launcher overlay is above fullscreen, so it is always
reachable. The IME popup tree is created after all of these, so candidate
windows stay above the launcher and clients.

A client frame is a `wlr_scene_tree` containing:

- three translucent `wlr_scene_rect` shadow layers, growing outward from the
  frame,
- one `wlr_scene_rect` behind the surface, used as the border/accent,
- the xdg surface tree returned by `wlr_scene_xdg_surface_create`.

The frame tree's `node.data` points to the `Client`. Pointer hit testing walks
parent trees until it finds that pointer. The xdg surface's `data` points to its
surface scene tree so popups can be parented in the right place.

Toplevel popups are parented through the toplevel's scene tree. Layer-shell
popups have no xdg parent when their `xdg_popup` is created; the layer surface's
`new_popup` event fires when `zwlr_layer_surface_v1.get_popup` assigns the
parent. `output.zig` listens for that event and creates the popup scene tree
under the layer surface's tree. This is what makes third-party panel menus and
dropdowns visible.

## Window motion, close effects, and shadows

Motion is a position offset on the client frame node; layout still records the
logical `x`/`y` in the `Client`. `startOpenAnimation()` offsets a newly mapped
window by 18 px vertically. `startWorkspaceAnimation()` offsets every mapped
window on the incoming workspace by ±54 px horizontally, choosing the sign from
the direction of travel. `tickAnimations()` evaluates a cubic ease-out against
`animation_ms` and writes `x + off_x`, `y + off_y` to the scene node. `applyFrame`
also adds the current offset, so a relayout during a transition does not snap the
window. Output frame callbacks drive the clock: `onOutputFrame` ticks active
animations before committing and schedules another frame while any remain.

`animations = false`, `reduce_motion = true`, or `animation_ms = 0` skip the
offset entirely. A config reload clears active animations before applying new
geometry.

Compositor-initiated closes use a snapshot path in `effects.zig`. Before
sending `wlr_xdg_toplevel_send_close`, `requestClose()` locks the surface's
current client buffer with `wlr_buffer_lock` and records its source box,
transform, and surface size. The extra lock stays on the `Client` until unmap,
so the client's buffer cannot be recycled before the animation starts.
`clientUnmapped()` then creates a temporary scene tree under `tree_effects`
containing a shadow rectangle, four border rectangles forming an outline, and
a `wlr_scene_buffer` using the locked buffer. The scene buffer takes its own
reference before the client's lock is released. `tick()` drives the snapshot
toward 92% scale with a smoothstep ease and fades content, border, and shadow to
zero opacity over `animation_ms`. The output frame callback ticks close effects
after layout animations and requests another frame while any remain.
`tree_effects` sits above fullscreen clients and below the launcher overlay,
and session lock hides it with the other desktop trees. A client that closes
itself is removed immediately: its surface buffer is typically gone by the time
the unmap event arrives, so there is nothing to display.

Shadows are the three pre-created scene rectangles described above;
`updateShadows()` scales them with the frame and `shadows = false` disables
them.

## Layer-shell sizing

Layer surfaces are configured by `output.zig` in the order overlay → top →
bottom → background; exclusive surfaces first, then non-exclusive surfaces.
`wlr_scene_layer_surface_v1_configure()` computes the surface box and shrinks
the usable area.

The panel bar defaults to 44 px high, anchored to the top, with a 12 px top
margin and a 44 px exclusive zone. `bar_height`, `bar_top_margin`, and
`bar_side_margin` change these values; a config reload recreates the bar layer
surface when they change. The tiling area therefore starts at the bar top plus
height plus the
`outer_gaps` value.

`arrangeLayers()` only reflows tiled clients when the usable area changes. It is
called on layer commit/map/unmap and output creation.

Keyboard focus for an interactive layer is taken on map (`keyboard_interactive
!= 0`, layer >= top). On unmap, focus is restored to the previously focused
toplevel. The launcher requests `EXCLUSIVE`; the bar requests `NONE`. Text input
focus follows the same transition: `layout.focusLayer()` and
`layout.focusClient()` call `ime.focusSurface()` with the surface origin, so the
client's active text input receives `enter`/`leave`.

Each panel process creates its layer surfaces with an explicit output object, so
a bar/background is placed on its own monitor. The launcher is created on the
panel's output when that panel receives the launcher event; panels for other
outputs ignore it. The compositor uses the focused output for new toplevels,
layer surfaces without an explicit output, and keyboard workspace bindings.

## Input

`input.zig`:

- creates the seat, cursor, and xcursor manager,
- attaches every pointer to `wlr_cursor`,
- creates an XKB keymap from the user's environment and the config
  (`kb_layout`, `kb_variant`, `kb_options`, `kb_model`, `kb_rules`,
  `repeat_rate`, `repeat_delay`); `Super+R` rebuilds keymaps without restarting,
- creates a fallback `wlr_keyboard` when no physical keyboard is present, so
  seat keymaps and XWayland work in headless sessions,
- attaches every physical/virtual keyboard and re-sends focus when a keyboard
  appears or its keymap changes,
- routes keyboard events to the focused surface or to key bindings,
- supports named input modes: mode-specific bindings take priority, match
  without modifiers, and fall back to global bindings; unbound keys reach the
  focused client. The active mode is exposed as `MODE` in state and in JSON.
- implements click-to-focus, floating move/resize, and pointer forwarding,
- handles `request_set_cursor`, cursor-shape-v1, selection requests, and
  relative-pointer motion for games,
- advertises `pointer-gestures-v1`, consumes configured shell swipes, and
  forwards other swipes/pinch/hold gestures to the focused client,
- advertises `wlr-virtual-pointer-v1`; virtual pointers are attached to the
  same cursor, which lets headless tests drive bar clicks, focus, and drags
  without physical hardware,
- attaches touch and tablet devices to the cursor, routes touch points through
  scene hit-testing, and forwards tablet-v2 tool/pad events,
- enforces active pointer constraints before cursor motion,
- advertises `wlr-data-control-v1` so the panel can observe selection changes
  without keyboard focus and become a clipboard manager,
- reports user activity to the idle notifier on key/pointer/touch input.

When an input method has grabbed the keyboard, raw key events and modifier
changes are forwarded to `wlr_input_method_keyboard_grab_v2_set_keyboard` before
WM bindings or the focused client see them. The input method receives a private
copy of the keymap and decides what to commit back through text-input-v3.

`xdg-activation-v1` requests switch to the client's workspace and focus it.
`xdg-decoration` is advertised in server-side mode so GTK/XWayland clients do
not draw client-side titlebars on top of Tessa's borders.

## Touch, tablet, gestures, and pointer constraints

`gestures.zig` listens to the libinput swipe/pinch/hold signals on `wlr_cursor`
and creates the `pointer-gestures-v1` global. Swipes whose finger count matches
`gesture_fingers` are consumed by the shell while no layer has keyboard focus:
horizontal distance beyond `gesture_workspace_threshold` switches workspace via
`layout.switchWorkspaceOnOutput()`, and upward distance beyond
`gesture_launcher_threshold` emits the launcher event. All other gestures, and
every gesture when `gestures = false`, are forwarded to clients with the
`wlr_pointer_gestures_v1_send_*` helpers.

`touch.zig` handles `wlr_cursor` touch down/motion/up/cancel/frame. Normalized
device coordinates are converted to layout coordinates with
`wlr_cursor_absolute_to_layout_coords()`, the scene is hit-tested, and the
point is sent with `wlr_seat_touch_notify_*`. A tapped client is focused;
keyboard-interactive layer surfaces are focused as layers. Motion for an
existing touch point uses `scene_util.surfaceOrigin()` so coordinates remain
surface-local even if the point leaves the surface bounds. Input devices are
tracked so the seat advertises `WL_SEAT_CAPABILITY_TOUCH` only when a touch
device exists. The panel exposes the same bar/overlay hit rectangles to touch.

`tablet.zig` creates `wlr_tablet_manager_v2`, one `wlr_tablet_v2_tablet` per
device, and lazily creates `wlr_tablet_v2_tablet_tool` state per tool. Tablet
axis events move the cursor, establish tablet-v2 proximity, and forward motion,
pressure, distance, tilt, rotation, slider, and wheel state. Tips and tool
buttons use tablet-v2 when the surface accepts it and otherwise fall back to
left/right pointer buttons. Pads forward button, ring, strip, and mode events to
the focused surface. `scene_util.zig` provides the shared surface/client/
layer lookup and surface-origin scan used by touch, tablet, and constraints.

`constraints.zig` owns `wlr_pointer_constraints_v1`. A new constraint is tracked
with set-region/destroy listeners; `layout.focusClient()` and
`layout.focusLayer()` call `constraints.focusSurface()` so the constraint for
the newly focused surface activates and any previous constraint deactivates.
Locked pointers zero relative-motion deltas after relative-pointer events have
been emitted; confined pointers run `wlr_region_confine()` against the
surface-local region. Activation and region changes warp the cursor into the
region when needed, and locked-pointer cursor hints are applied when the
constraint deactivates. A config reload deactivates constraints when
`pointer_constraints = false` or re-evaluates the focused surface.

## Input methods

`ime.zig` implements the compositor side of `zwp_text_input_v3` and
`zwp_input_method_v2`:

- one `TextInput` wrapper per client text-input object, tracking enable/commit/
  disable and the current surrounding text and cursor rectangle,
- `focusSurface()` sends `enter`/`leave` and activates/deactivates the input
  method with the focused client's state,
- input-method `commit` converts preedit/commit/delete requests back into
  text-input-v3 events and sends `done`,
- `grab_keyboard` is forwarded from the focused seat keyboard, and the grab is
  released when the input method disconnects,
- input-method popup surfaces are scene nodes in `tree_popup` and are positioned
  from the text-input cursor rectangle, with output-edge clamping.

Input-method state is sent regardless of the text-input `active_features` mask.
Fcitx5 sends its state in the enable commit before giving the compositor a
cursor rectangle, so relying only on `active_features` froze the candidate popup
at the origin. The compositor therefore uses the latest committed cursor
rectangle when it is non-zero.

## XWayland

Tessa spawns `xwayland-satellite` after the backend starts, instead of using
wlroots' in-process XWayland. Satellite owns the X server, runs an XWM, and
presents X11 windows to Tessa as xdg-shell toplevels, so the existing tiling,
workspaces, focus, and taskbar code handle X11 apps unchanged.

Important details:

- The fallback keyboard must exist before satellite starts. Xwayland 24.x
  compiles its keymap from the parent seat keymap during startup; without a
  keyboard it fails with `XKB: Failed to compile keymap`.
- Spawned children reset `SIGCHLD` to `SIG_DFL`. Tessa ignores `SIGCHLD` for its
  own children; inheriting that disposition made Xwayland's xkbcomp helper wait
  fail and the keymap compile abort.
- `DISPLAY` is chosen automatically by scanning `/tmp/.X11-unix/X<n>` and
  `/tmp/.X<n>-lock` for the first free display, then exported to Tessa's
  environment so all spawned clients inherit it.
- `xim.zig` exports `XMODIFIERS=@im=<xim_server>` before clients start. When
  `xim_start` is set, a timer polls for the selected X socket and only then
  spawns the XIM server, avoiding a server that starts before its display
  exists. XIM itself remains an X11 client/server protocol; Tessa provides the
  environment and startup ordering rather than proxying it.
- `xdg-decoration` is handled server-side. Without it satellite falls back to
  client-side decorations and draws its own titlebars.


Key bindings compare the normalized modifier mask (Shift/Ctrl/Alt/Logo) and the
keysym. For shifted digits and Tab, the level-0 keysym is also tried, so
`Super+Shift+1` and `Super+Shift+Tab` work regardless of the layout's shifted
keysyms.

When a layer has keyboard focus, WM shortcuts are bypassed and all keys are
forwarded to the layer. This is what lets the launcher receive typing.

## Output management

`output.zig` creates `wlr-output-manager-v1` and keeps its head list current
with the actual layout positions. `wlr-randr --output ... --mode/--pos/--scale/
--transform` is supported. Apply requests are tested atomically with
`wlr_backend_test`, committed, then the output layout is updated from the
configuration head states; the layer layout is reconfigured and positions are
republished to clients.

A successful apply, and every explicit runtime layout choice, atomically
writes the current output set to `outputs.conf`
(`$XDG_CONFIG_HOME/tessa/outputs.conf` by default). Each `output` line stores
name, pixel mode, refresh, layout position, scale, and transform. `layout`
lines follow it for runtime overrides only (`layout OUTPUT WORKSPACE MODE`);
config defaults are not written. On `new_output`, a matching output entry is
applied before the scene output is added; the layout position comes from the
saved box, and a failed saved mode falls back to the preferred/headless default.
Saved layout lines then replace the config seed for the matching output and
mark those workspaces overridden. Invalid or missing entries are ignored. The
file is mode 0600 and is only rewritten when settings change, not at startup.
Output `enabled` state is not persisted yet. The output power-management
protocol is separate and handled in `idle.zig`.

## Fractional scaling

`main.zig` creates `wp_fractional_scale_manager_v1` before the shell globals.
`wlr_scene_surface` already notifies fractional scale and the preferred integer
buffer scale when a surface's primary output changes. Tessa additionally listens
to each `wlr_output.events.commit`: when `WLR_OUTPUT_STATE_SCALE` changes, it
walks the scene graph, finds every scene surface whose `primary_output` is that
output, and calls `wlr_fractional_scale_v1_notify_scale()` followed by
`wlr_surface_set_preferred_buffer_scale(ceil(scale))`. This is what makes
`wlr-randr --scale 1.25` update already-mapped clients instead of only new ones.

Fractional-scale-aware clients render at the exact scale. Other clients use the
integer ceiling and are downsampled by the scene renderer. The panel is a
separate client and still uses the ceiling as its integer Cairo buffer scale.
XWayland scaling is delegated to `xwayland-satellite`, which consumes the same
advertised fractional scale. `tests/fractional-scale.sh` checks the 1.0 → 1.5 →
2.0 notification path with a compiled client.

## Session lock

`lock.zig` implements `ext-session-lock-v1`. On a new lock it:

- hides the normal desktop scene trees (`bg`, layers, windows, effects,
  overlay, IME popups) and commits a blank frame to every output,
- clears keyboard/pointer focus and deactivates text input,
- creates one scene surface per lock surface in `tree_lock`, which is created
  after all other trees and therefore renders above the desktop,
- gives the lock surface keyboard and pointer focus, and ignores virtual
  keyboard events while locked so a client cannot type a password through
  `virtual-keyboard-v1`,
- sends `locked` only after the desktop is hidden.

On `unlock_and_destroy`, listeners are removed but the lock resource is left for
the client's request to destroy; calling `wlr_session_lock_v1_destroy` from the
unlock signal recursed into wlroots' `lock_destroy` assertion. If the client
disconnects while locked, Tessa logs the abandoned lock and terminates the
session rather than exposing normal clients.

## Idle and output power

`idle.zig` creates `ext-idle-notify-v1`, `idle-inhibit-v1`, and
`wlr-output-power-management-v1` globals. Input events call
`wlr_idle_notifier_v1_notify_activity`. Visible inhibitors are counted; while
any inhibitor exists or the session is locked,
`wlr_idle_notifier_v1_set_inhibited(true)` is sent. Output power requests set the
output state's enabled flag and commit it, which is what makes `wlopm` work.
Timers and policy stay outside the compositor; swayidle is the expected driver.

## Tiling and workspaces

`layout.zig` holds the state transitions:

- Each output owns an `active_ws`, a per-workspace `ws_layouts[]` and
  `layout_overridden[]` table, and a `last_focused[]` table. Workspaces and
  layout choices are therefore independent per monitor, and `Super+1`…`9`
  applies to the focused output.
- **master**: one master area (ratio, default 0.58) and a vertical stack.
- **mosaic**: recursive spiral. Each remaining window takes a 62% slice of the
  current rectangle; the direction rotates left → top → right → bottom. The last
  window gets the center. Up to eight windows use the spiral. Before arranging,
  the engine checks that every slice can keep a tile at least 160 logical pixels;
  if not, it uses the grid layout for the whole workspace instead of overlapping
  or producing unusable slivers. More than eight windows start directly in
  master/stack.
- **grid**: balanced rows/columns (`ceil(sqrt(n))` columns); the last row is
  centered when it is incomplete.
- **columns**: equal-width full-height columns.
- `Super+T` cycles master → mosaic → grid → columns for the focused output and
  workspace. `set-layout <name>` accepts `master`, `mosaic`/`spiral`, `grid`,
  `columns`/`column`, or `custom`. Explicit runtime choices mark the workspace overridden and
  are written to `outputs.conf`; `layout_N` only seeds workspaces without a
  saved or runtime override. A config reload updates every non-overridden
  workspace on existing outputs and preserves overridden ones. Each change
  emits `layout-change` with workspace and output fields.
- Per-workspace `workspace-rule` entries supply gaps, outer gaps, and the
  master ratio to `arrangeOutput`; runtime `Super+Ctrl+H/L` updates the active
  workspace's ratio for the current session.
- `layout_helper.zig` owns an optional long-lived child process connected by a
  `socketpair`. The `custom` layout sends a tab-separated request
  (`LAYOUT`, `AREA`, `WINDOW`, `END`) and reads `RECT` lines. Requests use a
  bounded poll timeout; a crash, timeout, malformed reply, or id mismatch stops
  the child and falls back to master for that arrangement. The helper is
  restarted when its command changes and terminated during shutdown.
- `rules.zig` evaluates declarative window rules after metadata is known at
  map time, and re-evaluates them for existing windows on config reload. Match
  fields are app-id, title, and output using a small `*`/`?` wildcard matcher;
  actions set floating/fullscreen state, workspace, and floating geometry. A
  rule-driven move updates the per-workspace focus history, and the reload path
  calls `ensureVisibleFocus` after arranging so keyboard focus cannot remain on
  a hidden window.
- Workspaces are 1–9. A workspace's windows are hidden by disabling the frame
  scene node; hidden workspaces still report occupancy to the panel.
- Tiled and floating clients stay assigned to the output they were opened on.
  Directional focus can cross into an adjacent output; moving a window in a
  direction with no same-output neighbor transfers it to that output.
- Floating windows live in `tree_floating`; they start at 55% × 60% of the
  usable area, centered. `Super+Alt+H/J/K/L` resize the focused floating window
  from its top-left corner; the size is clamped to 160×120 (or the xdg-shell
  minimum) and to the output.
- Fullscreen uses the full output (including the bar area) and the fullscreen
  scene tree.
- Focus is spatial for directional bindings; swapping is done by exchanging
  positions in the clients array, which changes tiling order.

The tiling area is the output's usable area (after the bar's exclusive zone)
minus `outer_gaps`. Gaps between windows are `gaps`. Borders are part of each
frame's rect.

## Configuration and diagnostics

`config.zig` parses `key = value` files and positional includes while tracking
the source path and line number. The parser validates numbers, booleans, colors,
layout names, bindings, hooks, window rules, and include targets. Problems are
stored in `Server.config_issues` and exposed through `CMD config` as
`diagnostic error path:line: message`.

On reload, the previous `Config` value is snapshotted before parsing. If the new
file has errors, the snapshot is restored, keymaps are not reloaded, and no
window rules or layouts are applied. This makes a failed `Super+R` a no-op. The
diagnostics remain available so `tessa-ctl config-check` can explain why.
Initial startup is lenient: defaults and any valid lines are used, but the
diagnostics are still reported.

`json_snapshot.zig` builds schema-versioned `state-json` and `config-json`
snapshots. The line-based command protocol remains the transport; JSON is sent
between `STATE_JSON`/`CONFIG_JSON` and `END` markers so existing clients are
unaffected.

## IPC

Socket: `$XDG_RUNTIME_DIR/tessa.sock` (or `$TESSA_IPC`), mode 0600.

A new connection receives nothing until it subscribes. The panel sends
`CMD subscribe all`; the compositor then sends a complete state snapshot on each
change:

```text
STATE
ACTIVE 1
OUT eDP-1 1 1 master
OUT HDMI-A-1 2 0 mosaic
OCC 1 2
OCC 2 0
...
FOCUSED 7
STATUS\tweather\tTokyo 18C\t
WIN\t7\t1\t1\t0\t0\tkitty\tnotes\teDP-1\t40\t30\t1100\t700
WIN\t8\t1\t0\t0\t0\tfoot\tshell\teDP-1\t1200\t560\t640\t480
END
```

`OUT` lines give each output's name, active workspace, focused flag, and current
layout name. `WIN` fields are tab-separated: `WIN`, id, workspace, focused,
floating, fullscreen, app_id, title, output name, x, y, width, height. Geometry
is in logical compositor coordinates. `STATUS` has id, text, and an optional
click command.
Backslash, tab, CR, and LF are escaped in string fields. Each panel filters
`WIN` and `OUT` lines to its own output and recomputes workspace occupancy
locally. Status entries are shared by all outputs.

Subscriptions and client → compositor commands:

```text
CMD subscribe state|events|all
CMD state
CMD workspace <1..9> [output]
CMD focus <id>
CMD close <id>
CMD spawn <shell command>
CMD launcher [query]
CMD panel <calendar|power|clipboard|screenshot|media|tray|audio> [output]
CMD layout [name] [output]
CMD resize <dx> <dy>
CMD config
CMD reload
CMD float <id>
CMD status <id> <text>            (tab-separated form supports --exec)
CMD quit
```

`CMD config` replies with a `CONFIG` marker, one `key value` line per
effective setting, `layout_ws` and `workspace_tuning` lines for each workspace,
one `rule <raw>` line per parsed window rule, `diagnostic` lines, and `END`. It
is what `tessa-ctl config` prints and is intended for control panels and
debugging. `CMD state-json` and `CMD config-json` return schema-versioned JSON
snapshots for tools.

`CMD workspace <n> <output>` changes the workspace on a specific monitor; the
compositor's keyboard bindings use the focused output when the output is
omitted. `CMD launcher [query]` emits a structured launcher event with the
focused output; only the matching panel opens. `CMD panel
calendar|power|clipboard|screenshot|media` likewise emits a `panel` event with the
requested popover and target output.
State broadcasts are coalesced
through a Wayland event-loop idle source and only go to state subscribers.
Events are sent only to event subscribers.

## Extension plane

The extension API is intentionally process-based; there is no in-process plugin
VM. `event_names.zig` defines the public topics. `events.zig` builds the wire
record (`EVENT\t<topic>\tkey=value...`), broadcasts it to subscribed clients,
and runs matching config hooks with `TESSA_*` environment variables. Event
delivery is best-effort and never blocks the compositor; a client whose socket
buffer is full is disconnected.

`ipc.zig` owns status entries and state snapshots. Status updates are ordinary
commands, capped at eight entries and included in every subsequent snapshot.
`tessa-ctl` demonstrates the protocol and is useful for shell scripts. The
complete schema and examples live in [EXTENDING.md](EXTENDING.md).

## Panel

`panel/model.zig` holds state, config, clock, CPU/RAM sampling, and search
results. `panel/draw.zig` contains all Cairo drawing. `panel/main.zig` owns the
Wayland client, IPC, input callbacks, animations, and the poll loop. Tessa
starts one panel per output; each panel binds `wl_output` globals, selects its
target by `TESSA_PANEL_OUTPUT`, and passes that output to layer-shell. State
lines are filtered to the target output, so each bar shows only its monitor's
active workspace and windows. A panel without a target falls back to the first
output.

### Surfaces

- **background**: layer background, anchors all edges, exclusive zone -1, empty
  input region. Draws the wallpaper once per configure: a vertical gradient
  derived from `bg` or explicit `bg_top`/`bg_bottom`, plus optional accent art
  (`wallpaper_art`).
- **bar**: layer top, top/left/right anchors, configurable height
  (`bar_height`, default 44), top/side margins, exclusive zone equal to the
  height. A geometry change recreates this surface. Hit rectangles for the menu,
  clock, workspace pills, window chips, and extension status pills are
  recomputed on each draw. The panel reloads its own config and rescans apps
  when it receives `config-reload`.
- All panel surfaces use the target `wl_output` scale. Buffers are allocated at
  `logical_size * scale`, drawing applies a Cairo scale, and hit/IME rectangles
  stay in logical coordinates. The 760x620 launcher design is uniformly fitted
  to the logical surface; the same transform maps its visual hit rects and IME
  cursor rectangle.
- **overlay**: created on demand, layer overlay, anchors all edges, exclusive
  zone -1, keyboard EXCLUSIVE. It is a full-screen transparent/ARGB surface.
  Its mode selects the centered launcher or one of the anchored popovers
  (calendar below the clock, power menu below the Tessa mark, centered
  clipboard history, or the screenshot selection surface). The dim backdrop and panel are drawn into the same
  surface, so clicks outside the active panel close it. Popover hit rectangles
  are in popover-local coordinates plus the panel origin, and keyboard input
  switches to `Up`/`Down`/`Enter` navigation for the power menu and clipboard. Opening a popover emits a `panel` event, which the panel
  process consumes like the `launcher` event.

The overlay fades/scales over 150 ms. It is destroyed only after the fade-out;
destroying the layer surface lets the compositor restore toplevel focus. The
launcher also enables text-input-v3 while every other overlay mode disables it.

### Text input in the panel

The launcher creates a `zwp_text_input_v3` object for the seat when it opens. On
`enter` it sends content type, surrounding text, change cause, and the search
cursor rectangle, then commits. Preedit strings are drawn in the accent color
with an underline at the insertion point; committed strings are appended to the
query, and delete-surrounding requests are applied. While Fcitx has grabbed the
keyboard, the compositor forwards keys to the input method instead of the panel,
so committed IME text is not duplicated by the panel's raw-key fallback.

The panel's `wl_keyboard` keymap is loaded with
`xkb_keymap_new_from_buffer(..., size, XKB_KEYMAP_FORMAT_TEXT_V1,
XKB_KEYMAP_COMPILE_NO_FLAGS)`. Using `xkb_keymap_new_from_string` with the size
as the flags argument caused xkbcommon to reject every keymap, which silently
disabled raw typing even though key events arrived.

### Clipboard history

The panel uses `zwlr_data_control_manager_v1` rather than the ordinary
`wl_data_device` for clipboard history. wlroots sends ordinary selection events
only to the focused client, so a bar process would otherwise see only the
current item when it happened to gain focus. Data-control devices receive every
selection update without focus and may set the selection without a serial.

History keeps eight unique text entries in memory (16 KiB each). On each offer,
the panel chooses the highest-priority text MIME, asks for the data through a
nonblocking pipe, and drains it in the main poll loop. Selecting an entry copies
it into a data-control source, offers UTF-8 and legacy text MIME types, and sets
it as the seat selection. The new selection also comes back to the panel as an
offer; deduplicating against the promoted entry prevents a feedback loop. No
clipboard content is written to disk or logged.

### Screenshots

The panel binds `zwlr_screencopy_manager_v1` version 1. A screenshot request
creates a frame for the target `wl_output`; the frame's `buffer` event supplies
the exact format, physical size, and stride, and the panel allocates a matching
`wl_shm` buffer, calls `copy`, and waits for `ready`. Only then does it open the
`SCREENSHOT` overlay, so the selection UI and dim layer cannot appear in the
captured image.

The overlay darkens the live output and uses Cairo's `CLEAR` operator to punch
the selected rectangle out of that dim layer. Pointer press/motion/release tracks
the region; `Enter` or a click without a drag selects the full output; `Esc` and
right-click cancel. The captured buffer is cropped in physical coordinates
(`logical selection * output scale`) into a Cairo image surface and written as
PNG. The default directory is `~/Pictures/Screenshots`, configurable with
`screenshot_dir`; missing parent directories are created.

### Notifications

The panel links GIO and loads a small C shim, `panel/notifications.c`, which owns
`org.freedesktop.Notifications` on the session bus from a dedicated GLib thread.
The shim implements `Notify`, `CloseNotification`, `GetCapabilities`, and
`GetServerInformation`, and emits `NotificationClosed` and `ActionInvoked`. It
sends notifications to the Zig event loop over a socketpair using a framed binary
protocol; panel dismissal/expiry/action requests go back through a GLib
main-context invocation so all D-Bus access stays on the GDBus thread.

Each notification record contains the id, timeout, app/summary/body, up to four
actions, an optional icon name/path, and a screen icon as premultiplied native
ARGB32. `Notify` parses the `actions` array and the `image-data`/`image_path`/
`icon-name` hints; `image-data` is capped at 64×64 and copied row by row with
alpha premultiplication.

The Zig side keeps four active notifications, applies replacement by id, expires
timed notifications, and draws a top-right layer surface named
`tessa-notifications`. Toast heights grow when action buttons are present.
Clicking the card activates the `default` action if one exists, action buttons
emit `ActionInvoked`, and the close button dismisses. Body text is rendered with
Pango markup when it parses; otherwise it falls back to plain text. Theme icons
are loaded from common XDG icon paths and monogram fallbacks are used when no
icon is available. The panel that owns the D-Bus name renders the toast surface
on the currently focused output and recreates that surface when focus moves, so
new and existing notifications follow the active monitor while a single D-Bus
owner remains responsible for actions.

### System indicators and media

Battery and network status are sampled every five seconds in `panel/model.zig`.
Battery data comes from `/sys/class/power_supply/*/type=Battery`, `capacity`, and
`status`; the default route and interface state come from `/proc/net/route` and
`/sys/class/net`. A `wireless` attribute selects the Wi-Fi label. These are
read-only indicators and are shown in the right side of the bar when width
allows.

`panel/media.c` runs a second GIO thread. It polls the session bus for
`org.mpris.MediaPlayer2.*`, calls `Properties.GetAll` on the first player's
`org.mpris.MediaPlayer2.Player`, and sends playback status, title, artist, and
player name to the panel over a framed socket. Play/pause, next, and previous
commands are marshalled back with `g_main_context_invoke` and issued as MPRIS
method calls. `Super+M` or the bar chip opens a centered control popover; the
panel does not fetch album art or expose the MPRIS player's own menus.

### StatusNotifier tray

`panel/tray.c` owns `org.kde.StatusNotifierWatcher` on the session bus in a
dedicated GIO thread. It implements `RegisterStatusNotifierItem`,
`RegisterStatusNotifierHost`, the watcher properties, and the registration
signals. Registered items are polled every second with `Properties.GetAll`;
their `Title`, `Status`, `IconName`, and `IconPixmap` are sent to the panel over
the same framed socketpair pattern used by notifications and media.

`IconPixmap` is an `a(iiay)` of raw ARGB32 in network byte order. The panel
converts it to Cairo's native ARGB32 byte order, or resolves `IconName` through
common PNG icon-theme paths. Item activation and secondary activation are
marshalled back to the GDBus thread. The bar renders each item; left-click
activates, right-click or `Super+Shift+T` opens a keyboard-navigable tray
popover. DBusMenu is not implemented, so context menus are not exposed.

### Volume

`panel/audio.c` runs a worker thread that detects `wpctl` (PipeWire), `pactl`
(PulseAudio), or `amixer` (ALSA), or uses commands from the panel config. It
polls the mixer once per second, parses the percentage and mute state, and sends
a compact state record to the panel. Up/down/mute commands are marshalled to the
GIO thread and executed asynchronously, then re-polled. The panel draws the bar
indicator and the `Super+Shift+A` popover.

### Portals and screen sharing

The compositor exposes `zwlr_screencopy_manager_v1`, linux-dmabuf where the
renderer has a DRM fd, `ext-output-image-capture-source-manager-v1`,
`ext-image-copy-capture-v1`, `ext-foreign-toplevel-list-v1`, and
`zwlr_foreign_toplevel_manager_v1`. These are the compositor-side protocols used
by `xdg-desktop-portal-wlr` (xdpw) to enumerate sources and copy frames into a
PipeWire stream.

`packaging/portal/tessa.portal` selects the wlr backend for
`XDG_CURRENT_DESKTOP=Tessa`; the session environment is set by `main.zig` and
`scripts/tessa-session`. xdpw can use the screencopy + dmabuf path or the newer
image-copy-capture + shared-memory path. The test harness runs a private
PipeWire daemon, xdg-desktop-portal, and xdpw, then performs
CreateSession/SelectSources/Start/OpenPipeWireRemote and verifies a valid stream
node and remote fd.

### Buffers and rendering

Each surface keeps three `wl_shm` ARGB8888 buffers. A `wl_buffer.release` listener
marks a buffer free; if all three are busy, the redraw is deferred and the poll
timeout becomes zero. Buffers are recreated on configure resize.

Cairo draws rounded rectangles, gradients, the ink blobs, the sun, grain, the
bar, and the launcher. Text is drawn through `panel/text.c`, a tiny C API around
Pango. This shim exists because Zig 0.16's translate-c fails on GLib's
`_Pragma`-based deprecation macros. The Zig side includes only `cairo.h` and
`text.h`, not Pango/GLib.

The application list comes from `.desktop` files in the XDG data directories.
`Name[ja]`/`Comment[ja]` are preferred when present. Search is a scored
case-insensitive match on name, id, and comment. The launcher shows monogram
tiles rather than loading icon themes.

### Event loop

Single-threaded, `poll()` on the Wayland display fd, IPC fd, clipboard pipe, and
the notification/media/tray/audio service socketpairs. Timers (1 s clock, 2 s
CPU/RAM, 500 ms caret, 16 ms animation) are implemented with poll timeouts;
`wl_display_prepare_read`/`read_events` are used to avoid blocking inside
libwayland. D-Bus and command execution happen on worker threads so the
compositor-facing panel loop never blocks.

## Build and generated protocols

`build.zig` builds the compositor, panel, and `tessa-ctl`. The compositor's C
import includes wlroots 0.19 with `WLR_USE_UNSTABLE`. The panel compiles
generated client protocol C for layer-shell (which transitively needs
xdg-shell's `xdg_popup_interface`). `tessa-ctl` only links libc and socket
headers.

The generated headers/C under `protocol/` are committed:

- `xdg-shell-protocol.h` — for wlroots headers
- `wlr-layer-shell-unstable-v1-protocol.h` — for wlroots headers
- `layer-shell-client-protocol.h/.c` — panel
- `xdg-shell-client-protocol.h/.c` — panel/runtime symbol
- `text-input-client-protocol.h/.c` — panel text-input-v3 client
- `wlr-data-control-unstable-v1-client-protocol.h/.c` — panel clipboard history
- `wlr-screencopy-unstable-v1-client-protocol.h/.c` — panel screenshots
- `ext-image-copy-capture-v1-protocol.h` — wlroots capture headers
- `ext-image-capture-source-v1-protocol.h` — wlroots capture headers
- `cursor-shape-v1-protocol.h` — required by `wlr_cursor_shape_v1.h`
- `pointer-constraints-unstable-v1-protocol.h` — required by
  `wlr_pointer_constraints_v1.h`
- `tablet-v2-protocol.h` — required by `wlr_tablet_v2.h`

## Failure behavior

- A panel disconnect is cleaned up by the compositor; the panel exits on IPC EOF.
- A slow event/state subscriber is disconnected instead of stalling the event
  loop. Hooks run in detached shell processes; a failing hook does not affect
  the compositor.
- A panel crash leaves the compositor alive; restart `tessa-panel` manually.
- Output removal moves clients to the first remaining output. Removing the last
  output terminates the compositor.
- Invalid app/desktop entries are skipped; invalid settings are clamped.
- If `xwayland-satellite` is missing, the child exec fails, Tessa continues, and
  X11 clients cannot connect to the exported `DISPLAY`; Wayland clients and the
  panel are unaffected.
- If no input method is connected, text-input enters are still tracked, and
  clients fall back to raw keyboard input. The panel does not require an IME.
- Layer-shell popups are rendered under the layer surface that owns them. A
  layer client that creates a popup before `get_popup` is associated with the
  layer is ignored until that association happens.
- Each panel process exits when its output disappears (its bar layer surface is
  closed); the other monitors keep their panels.
- On compositor shutdown, `shutdown.zig` removes global/per-output/per-keyboard
  listeners before `wl_display_destroy`. wlroots asserts that these signal
  lists are empty; leaving the xdg-shell listener installed aborted the process
  on exit.
