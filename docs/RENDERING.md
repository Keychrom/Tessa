**English** | [日本語](RENDERING.ja.md)

<!-- tessa-site-notice:start -->
> [!NOTE]
> This document has been ported to the website. Read the current version at <https://keychrom.github.io/docs/rendering/>.
<!-- tessa-site-notice:end -->

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

## Low-end and integrated GPUs

The default scenefx build favors visual quality. If `tessa-ctl perf` reports
`over_budget`, or moving windows feels heavy, lower the effect cost first:

```ini
blur = false
shadows = false
animations = false
corner_radius = 0
```

- `blur` is the largest GPU cost. Disabling it removes the backdrop blur pass;
  fullscreen windows already skip blur automatically.
- `shadows` removes three translucent rectangles per window.
- `animations = false` stops per-frame scheduling for transitions.
- `corner_radius = 0` avoids rounded-corner shader work while keeping scenefx.

If you want some blur, `blur_passes = 1` with a small `blur_radius` is cheaper
than the default three passes. Tessa creates blur and shadow scene nodes lazily:
a build with `blur = false` or `shadows = false` does not allocate them for
ordinary windows. `effect_skips` should grow while the scene is idle;
`effect_applies` should only grow when a rule or window geometry changes.

If the GPU or driver cannot provide GLES2, use a plain build:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe -Dscenefx=false
```

Run it with `WLR_RENDERER=pixman tessa` when needed. `direct_scanout = true`
remains the best path for fullscreen video and games; `tessa-ctl rendering` and
the `scanout_frames` counter show whether it is active.

## GPU panel background (opt-in)

`tessa-panel` normally renders with Cairo into `wl_shm` buffers. Setting
`panel_renderer = gpu` changes how the background layer is presented. With the
default `wallpaper_engine = cairo`:

1. On configure, scale change, or config reload, the panel renders the existing
   wallpaper (gradient, ink, sun, image or shader frame, and signature) into a
   Cairo image at the physical output resolution.
2. The image is uploaded as an RGBA texture.
3. A `wl_egl_window` plus an EGL/GLES2 context presents a fullscreen triangle.
   The fragment shader samples the texture and adds restrained water ripples,
   ink drift, and a slow sun pulse.

With `wallpaper_engine = procedural`, steps 1-2 are skipped for the background:
the shader generates the gradient, wash, ink, sun, water lines, grain, and
vignette directly. The small corner mark is still rendered by Cairo once and
uploaded as a transparent texture. Palette changes cross-fade over 300 ms.
`wallpaper_image` and `wallpaper_shader` continue to use the texture path.
4. `wallpaper_animation = on` schedules redraws at `wallpaper_fps` (default
   30). `auto` additionally pauses on battery power and after
   `wallpaper_idle_pause` seconds without input. Both modes pause while an
   overlay or a fullscreen window is visible, and when `animations = false` or
   `reduce_motion = true`.

The launcher, bar, popovers, and toasts stay on the Cairo path by default.
`overlay_renderer = gpu` is an opt-in first stage for the launcher, control
center, and popovers: Cairo renders the final overlay content once per state
change, uploads it as a texture, and the GPU applies the open/close scale, fade,
and settle. During a control-center view transition or a toggle-pill animation
the cached base is re-rendered for those frames, then cached again. Row stagger
and the sliding launcher selection marker remain Cairo-only in this phase; a
later layered renderer can restore them on the GPU.

This is the first stage of the GPU panel renderer, not a full UI rewrite.

Requirements and fallback:

- The client-side EGL/GLES stack must be able to create a window surface and
  present it to the compositor. Mesa's llvmpipe can do this even in a headless
  pixman session, as exercised by the test suite.
- If EGL initialization, shader compilation, texture upload, or presentation
  fails, the panel logs `tessa-panel: gpu: ...; using Cairo` and continues with
  `wl_shm`.
- `TESSA_GPU_DISABLE=1` forces the Cairo path.
- A build with `-Dgpu=false` removes the EGL/GLES dependency; the panel always
  uses Cairo.
- The GPU path uses full-buffer updates and a timer, not partial damage or frame
  callbacks. It is opt-in because continuous animation costs power.

The automated test covers Mesa llvmpipe in a headless session. On real hardware,
enable `panel_renderer = gpu` and `wallpaper_animation = true`, then capture two
frames with `grim` to confirm motion. Real-GPU validation remains part of the
driver checklist below.

On the reference i5-6300U / Intel HD 520 at 1920x1080, 30 fps animation used
about 2.5% of one core in the background-only test and 3.7% with the full panel.
Static GPU rendering and the Cairo path stayed near 0% after startup.

## Window switcher preview capture

The Alt+Tab switcher and Scene deck use live per-window previews rather than
static screenshots. Tessa advertises
`ext_foreign_toplevel_image_capture_source_manager_v1` and
`ext_image_copy_capture_v1`; the panel asks for each foreign toplevel's capture
source, and the compositor renders it into a private offscreen scene. Frames are
damage-driven and capped at 512 px on the long edge, then copied into the panel
surface. This works for windows on inactive workspaces and outputs without
bringing them on screen. If the capture protocols or buffer format are
unavailable, the switcher falls back to app monograms.

## Per-window GPU shaders (opt-in)

Window rules can apply an offscreen GPU effect to a matching toplevel:

```ini
window-rule = app-id=mpv; shader=crt; shader-strength=0.8
window-rule = app-id=foot; shader=mono
window-rule = app-id=org.example.notes; shader=pixelate; shader-param=12
```

Built-in effects are `mono`, `crt`, `vignette`, `pixelate`, and `wave`.
`shader-strength` scales the effect from 0 to 1, and `shader-param` is the
pixelate block size. `shader=none` clears a rule. Rules are opt-in and are
re-evaluated on config reload and on title/app-id changes.

Pipeline:

1. Tessa creates a private surfaceless EGL/GLES2 context on first use. It never
   changes the scenefx renderer or its GL state; the previous EGL context is
   restored around each shader operation.
2. On a content commit, the client buffer is locked. DMA-BUFs are imported with
   `EGL_EXT_image_dma_buf_import`; shared-memory buffers are uploaded after a
   format conversion.
3. A fragment shader renders the effect into an RGBA8 FBO, and the result is
   read back as a top-down RGBA buffer.
4. The result becomes a read-only wlroots buffer. Tessa adds a scene buffer
   below the real content in the same scene tree, copies the content's source
   box, destination size, transform, filter mode, and corner radius, and draws
   the real content with opacity 0.
5. Because the effect node sits below the content node, scene hit-testing still
   resolves to the real client surface. The extra scene entry also keeps the
   window out of direct scanout while the effect is active.

Limitations:

- Effects are re-rendered on content commits, not on a per-frame timer. There
  are no animated shader uniforms yet.
- The close animation uses the unfiltered snapshot; the effect reappears when
  the window maps again.
- The effect applies to the toplevel buffer. Subsurfaces and popups keep their
  own content.
- DMA-BUF import requires a format supported by the EGL stack. Multi-plane/YUV
  and cross-GPU buffers can fail; the window then keeps its normal content and
  the log reports `window shader: effect unavailable`.
- The offscreen pass adds a readback and a texture upload per content update.
  It is intended for a few marked windows, not every window.

`TESSA_SHADER_DISABLE=1` forces the normal path, and a `-Dshaders=false` build
removes the EGL/GLES dependency from the compositor. The automated
`tests/window-shader.sh` runs the whole pipeline on Mesa llvmpipe in a headless
pixman session: it applies `mono` to foot, checks that the window content
becomes grayscale, removes the rule through the config watcher, and checks that
the colour returns.

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
