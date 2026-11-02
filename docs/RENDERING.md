**English** | [日本語](RENDERING.ja.md)

# Rendering and game features

Tessa exposes direct scanout, tearing, explicit synchronization, and per-output
rendering statistics through upstream wlroots 0.20 APIs. HDR is investigated in
this document but is not implemented yet.

## Quick status

```sh
tessa-ctl rendering
tessa-ctl rendering --json
tessa-ctl perf
tessa-ctl perf --json
tessa-ctl perf --watch=2
```

`rendering` reports static capabilities and per-output scanout counters. `perf`
reports frame-time samples and the same per-output counters in a rolling window.
Both are safe to poll; `--json` is intended for scripts and dashboards.

A real DRM session should show `drm_fd >= 0` and (when the renderer supports
timelines) `explicit_sync_active 1`. A headless pixman session exercises the
state machine but always reports `backend_drm_fd -1` and `color_management 0`.

## Direct scanout

The scene compositor can hand a client's DMA-BUF directly to the display
controller only when the render list has exactly one entry. Tessa's normal scene
contains the background rectangle, a wallpaper/background layer surface, bars,
window borders and shadows, blur nodes, and other windows, so direct scanout
needs a deliberate fullscreen mode.

When an output has a mapped fullscreen client that:

- covers the complete output at opacity 1,
- has no non-zero `tint` alpha,
- is visible on the active workspace and is not animating,
- has a content buffer,

`src/render.zig` hides the compositor-owned nodes that would block a single-entry
commit:

- `out.bg_rect` and layer-shell surfaces in the background, bottom, and top
  layers,
- other visible client frames on that output,
- the candidate's scenefx blur node.

Overlay-layer surfaces, input-method popups, close-animation snapshots, and
notifications are left above the fullscreen window. If any of them is visible,
wlroots sees more than one entry and composites normally; the desktop remains
correct, it just does not scan out that frame. Leaving fullscreen, unmapping the
candidate, or destroying it restores the background, mapped layer trees, visible
client frames, and blur state.

Configuration:

```ini
direct_scanout = true   # default
```

Set `direct_scanout = false` to disable the scanout state machine entirely. It
can be changed at runtime; the next commit restores or hides the scene nodes.

Limitations:

- The client needs a single full-output buffer. Apps with many subsurfaces fall
  back to composition; opaque content is strongly recommended because the
  background is hidden during scanout.
- `wlr_buffer_is_opaque()` has false negatives for many DMA-BUFs, so Tessa does
  not reject scanout solely on that result; the scene validates the plane format
  and the compositor falls back if the backend rejects the commit.
- The cursor must be usable as a hardware cursor. A software-cursor fallback can
  prevent scanout.
- Scenefx blur and rounded corners are disabled for the scanout candidate; the
  rest of the scene keeps its effects.

### Confirming it worked

`tessa-ctl rendering` exposes:

```text
OUTPUT eDP-1 1920x1080 scanout_active=1 scanout_frames=123 \
  zero_copy=120 tearing_requests=0 tearing_failures=0
```

- `scanout_active` means the compositor entered its single-entry mode.
- `scanout_frames` counts `wlr_scene_buffer` output samples with
  `direct_scanout == true`.
- `zero_copy` counts output presents with `WLR_OUTPUT_PRESENT_ZERO_COPY`. On DRM
  this is the most direct proof that composition was skipped.

Headless backends never increment `zero_copy`; use `scanout_active` there.

## Tearing

Tearing uses `wp-tearing-control-v1`. It is never enabled just because a client
is fullscreen: the client must set the async presentation hint, and the
compositor must be configured to honor it.

```ini
tearing = off         # default: never request async page flips
tearing = fullscreen  # fullscreen clients with an async hint
tearing = force       # any async-hinted client (expert)
```

Per-window opt-in while the global default stays off:

```ini
window-rule = app-id=gamescope; tearing=true
window-rule = app-id=mpv; tearing=off
```

The commit path builds the scene state, sets `state.tearing_page_flip`, and calls
`wlr_output_test_state()` before committing. If the driver rejects the async
flip, Tessa clears the flag, increments `tearing_failures`, and performs a normal
page flip. A live commit failure is logged and the next frame retries normally.

Some drivers, including some Intel i915 configurations, reject async flips. That
is expected: the feature is a hint, not a guarantee. Use `tearing_requests` and
`tearing_failures` in `tessa-ctl rendering` to tell whether the kernel/display
accepted it. Tearing is opt-in because it can visibly tear every frame.

## Explicit synchronization

When all of the following are true, Tessa creates
`wlr_linux_drm_syncobj_manager_v1_create()` before clients connect:

- `explicit_sync = true` (default),
- `renderer.features.timeline`,
- `backend.features.timeline`,
- a backend DRM fd (`wlr_backend_get_drm_fd() >= 0`); the renderer DRM fd is
  used for the syncobj manager when it is available.

wlroots' scene graph then carries acquire/release timelines automatically; Tessa
does not need per-surface fence code. Scenefx/GLES2 builds may not report
timeline support, and headless or nested backends are intentionally excluded.

`tessa-ctl rendering` reports:

```text
explicit_sync 1
explicit_sync_active 1
renderer_timeline 1
backend_timeline 1
```

`explicit_sync` is the requested setting and `explicit_sync_active` is the
actual manager state. Changing the setting requires a compositor restart because
the protocol global is created before clients connect. Drivers that advertise
timelines but mishandle them can be worked around with `explicit_sync = false`.

## Performance measurement

Every committed output frame records the frame-handler time from before
animation/scanout refresh through the successful output commit
(`layout.tickAnimations`, `effects.tick`, `render.refreshScanout`, scene state
build, and `wlr_output_commit_state()`) into:

- `Server.perf` (aggregate across outputs), and
- `Output.perf` (per-output rolling samples).

`wlr_scene_output_needs_frame()` is checked first, matching
`wlr_scene_output_commit()`'s early-out, so no-op frames are not counted as
renders. Static scenes should show stable frame counts rather than one sample per
refresh.

Per-output counters:

| Counter | Source | Meaning |
| --- | --- | --- |
| `presented` | `wlr_output.events.present` | Completed presents |
| `zero_copy` | `WLR_OUTPUT_PRESENT_ZERO_COPY` | Present skipped composition |
| `vsync` | `WLR_OUTPUT_PRESENT_VSYNC` | Present was vsync'd |
| `missed` | present `seq` gaps | Missed output sequences |
| `scanout_frames` | `output_sample.direct_scanout` | Client buffers sampled via scanout |
| `tearing_requests` | test-commit accepted | Async flip attempted |
| `tearing_failures` | test/commit rejected | Fell back to a normal flip |

Frame-time fields (`frames`, `samples`, `avg_us`, `p50_us`, `p95_us`, `max_us`,
`last_us`, `budget_ms`, `over_budget`) keep their previous meaning at the top
level and are repeated per output in `outputs[]`. `frame_time_budget` remains
the over-budget threshold. `tessa-ctl perf` also emits top-level
`effect_applies`, `effect_skips`, and `blur_nodes`; these are not repeated in
`outputs[]`. Only frame-time samples are a rolling 4096-frame window; the event
and effect counters are cumulative until `perf --reset`.

## HDR and color management: investigation

HDR is **not implemented** in this change. No `wp-color-management-v1` global is
advertised, and `tessa-ctl rendering` reports `color_management 0`.

What wlroots 0.20 provides:

- `wp-color-management-v1` version 2, including parametric image descriptions,
  mastering display metadata, and the piece-wise sRGB transfer function.
- `wlr_color_manager_v1_create()` with advertised render intents, transfer
  functions, and primaries.
- Output image descriptions and post-blending color transforms in
  `wlr_output_state` (`WLR_OUTPUT_STATE_IMAGE_DESCRIPTION`,
  `WLR_OUTPUT_STATE_COLOR_TRANSFORM`).
- DRM output support for PQ/BT.2020-style HDR metadata where the connector and
  driver expose it.

What is missing in Tessa's current renderer path:

- Tessa uses GLES2 (`wlr_renderer_autocreate()`) or scenefx's GLES2 renderer.
  `renderer.features.output_color_transform` is normally false, so HDR output
  cannot be produced. Sway's HDR10 support also requires the Vulkan renderer.
- wlroots does not provide tone mapping. A compositor must decide how SDR
  content maps into an HDR output, what SDR white level to use, and how HDR
  content is mapped for SDR outputs. Advertising the protocol without that
  policy produces incorrect colors.
- Scenefx's blur/rounding path is GLES2-only and does not fit a Vulkan color
  pipeline.
- Tessa has no per-output HDR/SDR policy, EDID primaries plumbing, or fallback
  when a connector is not HDR-capable.

A future implementation should:

1. Add an optional Vulkan renderer path and make color-management support
   conditional on `output_color_transform`.
2. Detect HDR-capable outputs from EDID/connector properties and expose a
   per-output `hdr = off|auto|on` policy.
3. Advertise only the transfer functions and primaries the renderer and DRM
   backend can actually output; report them in `tessa-ctl rendering`.
4. Implement SDR white / tone mapping and HDR-to-SDR mapping before enabling the
   protocol by default.
5. Validate with HDR test patterns and real HDR displays; keep SDR sessions
   unchanged when the feature is off.

Until then, HDR clients negotiate SDR, and `color_management 0` is the correct
status.

## Driver validation checklist

Run on real DRM hardware, not headless:

1. `tessa-ctl rendering` — record `drm_fd`, `backend_drm_fd`, `renderer_timeline`,
   `backend_timeline`, `explicit_sync_active`, `output_color_transform`.
2. Fullscreen an opaque client (`kitty --start-as=fullscreen`, `foot -F`, or a
   game) and confirm `scanout_active=1`, `scanout_frames` increases, and
   `zero_copy` increases.
3. Run `tests/tearing.sh` or a game that sets the async hint; record
   `tearing_requests` and `tearing_failures`. A nonzero failure count with a
   stable desktop is a valid driver fallback, not a compositor crash.
4. Run a Vulkan/GL game and check the journal for `linux-drm-syncobj` or
   timeline errors; confirm `explicit_sync_active`.
5. Repeat with `direct_scanout=false`, `tearing=off`, and `explicit_sync=false`.
6. Test on Intel i915, AMD, NVIDIA, and vmwgfx where available, and record the
   results in the roadmap's validation matrix.
