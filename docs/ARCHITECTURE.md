# Architecture

Tessa is two processes:

1. **`tessa`** — the wlroots compositor and window manager.
2. **`tessa-panel`** — a Wayland client that owns the wallpaper, taskbar, and
   launcher.

They communicate over a Unix stream socket. Keeping the shell in a separate
process means a panel crash does not take down the compositor, and it keeps all
text/font/UI code out of the compositor's hot path.

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
                         │  wlr-screencopy-v1           │
                         │  wl_data_device (clipboard)  │
                         │  seat / cursor / keyboard    │
                         └──────────────┬──────────────┘
                                        │ $XDG_RUNTIME_DIR/tessa.sock
                                        │ line protocol, 0600
                         ┌──────────────▼──────────────┐
                         │ tessa-panel                  │
                         │  wl_compositor + wl_shm      │
                         │  wl_seat (keyboard/pointer)  │
                         │  zwlr_layer_shell_v1         │
                         │  Cairo + Pango               │
                         └─────────────────────────────┘
```

Wayland is used for clients and the panel. The compositor↔panel control channel
is deliberately not a custom Wayland protocol: a line-based socket protocol is
easy to debug with `socat` and does not require regenerating bindings.

## Scene graph order

All scene trees are children of `wlr_scene.root`, in this order (bottom to top):

```text
tree_bg          wallpaper / background layer surfaces, fallback bg rect
tree_bottom      layer-shell bottom
tree_windows     tiled client frames
tree_floating    floating client frames
tree_top         taskbar (layer-shell top)
tree_fullscreen  fullscreen client frames
tree_overlay     launcher (layer-shell overlay)
```

The fullscreen tree is intentionally above the top layer, so a fullscreen client
covers the bar. The launcher overlay is above fullscreen, so it is always
reachable.

A client frame is a `wlr_scene_tree` containing:

- one `wlr_scene_rect` behind the surface, used as the border/accent,
- the xdg surface tree returned by `wlr_scene_xdg_surface_create`.

The frame tree's `node.data` points to the `Client`. Pointer hit testing walks
parent trees until it finds that pointer. The xdg surface's `data` points to its
surface scene tree so popups can be parented in the right place.

## Layer-shell sizing

Layer surfaces are configured by `output.zig` in the order overlay → top →
bottom → background; exclusive surfaces first, then non-exclusive surfaces.
`wlr_scene_layer_surface_v1_configure()` computes the surface box and shrinks
the usable area.

The panel bar is 44 px high, anchored to the top, with a 12 px top margin and a
44 px exclusive zone. The tiling area therefore starts at 56 px plus the
`outer_gaps` value.

`arrangeLayers()` only reflows tiled clients when the usable area changes. It is
called on layer commit/map/unmap and output creation.

Keyboard focus for an interactive layer is taken on map (`keyboard_interactive
!= 0`, layer >= top). On unmap, focus is restored to the previously focused
toplevel. The launcher requests `EXCLUSIVE`; the bar requests `NONE`.

## Input

`input.zig`:

- creates the seat, cursor, and xcursor manager,
- attaches every pointer to `wlr_cursor`,
- creates an XKB keymap from the user's environment,
- routes keyboard events to the focused surface or to key bindings,
- implements click-to-focus, floating move/resize, and pointer forwarding,
- handles `request_set_cursor` and `request_set_selection`.

Key bindings compare the normalized modifier mask (Shift/Ctrl/Alt/Logo) and the
keysym. For shifted digits and Tab, the level-0 keysym is also tried, so
`Super+Shift+1` and `Super+Shift+Tab` work regardless of the layout's shifted
keysyms.

When a layer has keyboard focus, WM shortcuts are bypassed and all keys are
forwarded to the layer. This is what lets the launcher receive typing.

## Tiling and workspaces

`layout.zig` holds the state transitions:

- **master**: one master area (ratio, default 0.58) and a vertical stack.
- **mosaic**: recursive spiral. Each remaining window takes a 62% slice of the
  current rectangle; the direction rotates left → top → right → bottom. The last
  window gets the center. Up to eight windows use the spiral, then it falls back
  to master/stack.
- Workspaces are 1–9. A workspace's windows are hidden by disabling the frame
  scene node; hidden workspaces still report occupancy to the panel.
- Floating windows live in `tree_floating`; they start at 55% × 60% of the
  usable area, centered.
- Fullscreen uses the full output (including the bar area) and the fullscreen
  scene tree.
- Focus is spatial for directional bindings; swapping is done by exchanging
  positions in the clients array, which changes tiling order.

The tiling area is the output's usable area (after the bar's exclusive zone)
minus `outer_gaps`. Gaps between windows are `gaps`. Borders are part of each
frame's rect.

## IPC

Socket: `$XDG_RUNTIME_DIR/tessa.sock` (or `$TESSA_IPC`), mode 0600.

The panel receives a complete state snapshot after each change:

```text
STATE
ACTIVE 1
OCC 1 2
OCC 2 0
...
FOCUSED 7
WIN\t7\t1\t1\t0\t0\tkitty\tnotes
WIN\t8\t1\t0\t0\t0\tfoot\tshell
END
```

`WIN` fields are tab-separated: `WIN`, id, workspace, focused, floating,
fullscreen, app_id, title. Backslash, tab, CR, and LF are escaped in the two
string fields.

Panel → compositor:

```text
CMD workspace <1..9>
CMD focus <id>
CMD close <id>
CMD spawn <shell command>
CMD launcher [query]
CMD layout
CMD float <id>
CMD quit
```

`CMD launcher [query]` is primarily a development hook; the bar uses the
`EVENT launcher` broadcast from the compositor for `Super+D`.

The compositor broadcasts `EVENT launcher` to all panel connections. State
broadcasts are coalesced through a Wayland event-loop idle source.

## Panel

`panel/model.zig` holds state, config, clock, CPU/RAM sampling, and search
results. `panel/draw.zig` contains all Cairo drawing. `panel/main.zig` owns the
Wayland client, IPC, input callbacks, animations, and the poll loop.

### Surfaces

- **background**: layer background, anchors all edges, exclusive zone -1, empty
  input region. Draws the wallpaper once per configure.
- **bar**: layer top, top/left/right anchors, 44 px high, 12/16 px margins,
  exclusive zone 44. Hit rectangles for the menu, workspace pills, and window
  chips are recomputed on each draw.
- **launcher**: created on demand, layer overlay, anchors all edges, exclusive
  zone -1, keyboard EXCLUSIVE. It is a full-screen transparent/ARGB surface:
  the dim backdrop and the centered panel are drawn into it, so clicks outside
  the panel can close it.

The launcher fades/scales over 150 ms. It is destroyed only after the fade-out;
destroying the layer surface lets the compositor restore toplevel focus.

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

Single-threaded, `poll()` on the Wayland display fd and IPC fd. Timers (1 s
clock, 2 s CPU/RAM, 500 ms caret, 16 ms animation) are implemented with poll
timeouts; `wl_display_prepare_read`/`read_events` are used to avoid blocking
inside libwayland.

## Build and generated protocols

`build.zig` builds both executables. The compositor's C import includes
wlroots 0.19 with `WLR_USE_UNSTABLE`. The panel compiles generated client
protocol C for layer-shell (which transitively needs xdg-shell's
`xdg_popup_interface`).

The generated headers/C under `protocol/` are committed:

- `xdg-shell-protocol.h` — for wlroots headers
- `wlr-layer-shell-unstable-v1-protocol.h` — for wlroots headers
- `layer-shell-client-protocol.h/.c` — panel
- `xdg-shell-client-protocol.h/.c` — panel/runtime symbol

## Failure behavior

- A panel disconnect is cleaned up by the compositor; the panel exits on IPC EOF.
- A panel crash leaves the compositor alive; restart `tessa-panel` manually.
- Output removal moves clients to the first remaining output. Removing the last
  output terminates the compositor.
- Invalid app/desktop entries are skipped; invalid settings are clamped.
- Layer popups from third-party clients are not rendered yet (known limitation).
