**English** | [日本語](ROADMAP.ja.md)

# Roadmap

Tessa is intentionally small. The roadmap is ordered by what makes it usable as
a daily Japanese desktop, then by polish.

## Toolchain transition (completed in 0.2.5)

0.2.4 was the final planned `.deb` release built against Zig 0.16 and wlroots
0.19. The 0.2.5 source tree now targets **Zig 0.17**, **wlroots 0.20**, and
**scenefx 0.5**:

- [x] Replace `@cImport` with the external `translate-c` package and explicit
      compositor, panel, and CLI header modules.
- [x] Adapt to wlroots 0.20 signal renames, output timestamp changes, and the
      generated wayland-protocols enum headers.
- [x] Rebuild scenefx blur as dedicated `wlr_scene_blur` nodes for clients,
      layers, and IME popups, with transparency masks.
- [x] Update the Zig build system for 0.17 and replace removed standard-library
      APIs.
- [x] Update Arch packaging to the official `zig` and `wlroots0.20` packages.
- [x] Run the full headless suite on the new toolchain in both plain
      and scenefx builds (Arch Linux, Zig 0.17.0 / wlroots 0.20.2 / scenefx
      0.5), including portal ScreenCast, tray, notifications, and interaction.
- [ ] Run a real DRM/libinput session on the new toolchain before the next
      source release.
- [ ] Update CI and the compatibility matrix alongside packaging.

0.2.4 remains the 0.16/0.19 maintenance point. New work targets 0.17/0.20 and
must keep packaging, docs, and the compatibility matrix in sync.

## External shell compatibility

Migration users can keep a familiar bar or launcher while Tessa Panel remains
the default.

- [x] Layer-shell bars/launchers (Waybar, Wofi, Quickshell), exclusive zones,
      popup unconstraining, `EXCLUSIVE`/`ON_DEMAND` keyboard focus, and safe
      layer teardown on output removal.
- [x] `ext-workspace-v1` groups with nine workspaces per output and an activate
      request; Waybar `ext/workspaces` and Quickshell `WindowManager` work.
- [x] Foreign-toplevel output enter/leave tracking for taskbars.
- [ ] Optional Quickshell feature protocols: `keyboard-shortcuts-inhibit-v1`
      and `wlr-gamma-control-v1`.

## Rendering and game features

Close the compositor gap for games and fullscreen video while keeping the
default desktop safe.

- [x] Per-output frame-time, presented/zero-copy/vsync/missed, scanout, and
      tearing counters, with `tessa-ctl perf --watch` and `tessa-ctl rendering`.
- [x] Direct scanout for full-output fullscreen clients, hiding the background,
      lower layer surfaces, other visible clients, and the candidate's blur node
      while a single render-list entry is possible.
- [x] Opt-in `wp-tearing-control-v1` with per-window rules, a driver
      test-commit, and a normal-flip fallback.
- [x] Gated `linux-drm-syncobj-v1` explicit sync when renderer/backend timelines
      and a DRM fd are available.
- [x] Investigate HDR/color management: wlroots 0.20 exposes color-management
      v1 and output color transforms, but Tessa's GLES2/scenefx path and the
      absence of tone mapping require a Vulkan-renderer design first.
- [ ] HDR output and tone mapping on a Vulkan renderer.
- [ ] Record a GPU/driver validation matrix (Intel i915, AMD, NVIDIA, vmwgfx)
      for scanout, tearing, and explicit sync.

## Layout expansion

Close the layout gap with Niri and MangoWC without changing the default
experience. The original four modes and four-mode `Super+T` cycle remain the
default.

- [x] Scrolling layout: a Niri-style horizontal column strip with multiple
      windows per column, proportional or fixed column widths, width presets,
      maximization, focus centering, consume/expel, and groups as tabbed
      columns.
- [x] Animated viewport following (`animation_view_ms`) and per-workspace/output
      `default-column-width` and `center-focused-column` tuning.
- [x] Monocle layout and a Deck-style stacking layout (master area plus
      overlapping stack cards).
- [x] Dynamic insertion reorder (`reorder`, `swap`), directional moves, and
      window moves inside scrolling columns.
- [x] Mouse placement: Super+left-drag reorders tiled windows with a drop-target
      highlight; in scrolling it inserts columns. Super+wheel scrolls the
      viewport.
- [x] `VIEW`/`COL` state lines, JSON fields, and `tessa-ctl` wrappers for
      columns, consume/expel, swap, and reorder.
- [ ] Validate Scrolling, drag reorder, and wheel scrolling in a real
      DRM/libinput session, including fractional scaling and touchpad gestures.

## 0.1.x — make the foundation trustworthy

- [x] Run on DRM + libinput on the target machine and fix layout/input issues.
      Verified on Arch Linux with a real eDP-1 DRM session, keyboard/mouse,
      IME, XWayland clients, and the built-in bar. Per-device touchpad tuning
      and VRR/adaptive-sync remain tracked as hardware-specific follow-ups.
- [x] Automated headless coverage for bar workspace clicks, window-chip
      right-click close, floating drag/resize, click-to-focus, and launcher
      typing (`tests/interaction.sh`, using `wlr-virtual-pointer-v1`).
- [x] Fullscreen, xdg client popups, clipboard, and multi-window focus are
      covered by `tests/interaction.sh`, `tests/popups.sh`, and
      `tests/clipboard.sh`. Physical keyboard/mouse behavior is covered by the
      Arch DRM validation above.
- [ ] Fix transient client repaint gaps after float/resize. Interactive
      grabs now re-arrange and publish final geometry on release; visual
      validation during the drag still needs a real display.
- [x] Add a small integration test that starts the headless compositor and
      asserts state/IPC and extension hooks (`tests/smoke.sh`).
- [x] Decide the license (MIT).
- [x] Arch PKGBUILD and Debian packaging definitions, with the wlroots
      version explicitly pinned by the build and package dependencies.
- [ ] CI-built signed packages and release artifacts.

## 0.2 — input and apps

- [x] `zwp_text_input_v3` + `input-method-v2` support (Fcitx5/Mozc), including
      input-popup placement and launcher IME input.
- [x] XWayland through `xwayland-satellite`, with automatic display selection,
      `DISPLAY` export, xdg-decoration, and a fallback keyboard for headless
      startup.
- [x] Layer-shell popup rendering (menus from third-party layer clients).
- [x] Keyboard layout, variant, model, options, and repeat settings in config.
- [x] Touchpad gestures: workspace swipe and launcher swipe, with adjustable
      finger count and thresholds; other gestures are forwarded to clients.
- [x] Touch input (seat touch capability, scene hit-testing, panel touch UI) and
      tablet-v2 tools/pads (pen pressure, tilt, rotation, buttons, pad rings and
      strips). Physical touch/tablet hardware validation is still needed.
- [x] Relative pointer (`relative-pointer-v1`).
- [x] Pointer constraints (`pointer-constraints-v1`), including activation on
      focus, locked and confined pointer motion, and cursor hints.
- [x] Primary selection (`wlr_primary_selection_v1`).
- [x] XIM integration for X11 applications: exports `XMODIFIERS`, waits for the
      X display, and can start a configured XIM server.

## 0.3 — shell and desktop integration

- [x] Bars on every output; per-output active workspace.
- [x] Process-based extension API: `tessa-ctl`, structured event stream, config
      hooks, and startup commands.
- [x] Custom bar status segments with optional click commands.
- [x] Config includes and custom launcher entries.
- [x] Battery and network indicators.
- [x] MPRIS media chip and controls.
- [x] Tray / StatusNotifier integration: watcher/host, item icons, status,
      activation, and a keyboard tray popover. DBusMenu menus are still pending.
- [x] Audio volume controls through `wpctl`, `pactl`, or `amixer`, with a bar
      indicator, popover, and configurable command overrides.
- [x] Calendar/clock popup.
- [x] Power menu with configurable lock/suspend/reboot/shutdown commands.
- [x] Session lock (`ext-session-lock-v1`).
- [x] Idle inhibit, idle notifications, and output-power management (external swayidle/wlopm).
- [x] Screenshot UI: region/full-output capture through `wlr-screencopy`, saved
      as PNG.
- [x] `xdg-desktop-portal` integration and PipeWire screen sharing: screencopy,
      linux-dmabuf, output capture sources, image-copy capture, foreign-toplevel
      lists, and a packaged `tessa.portal` selector for
      `xdg-desktop-portal-wlr`. End-to-end monitor ScreenCast is tested; window
      capture depends on the portal backend's protocol support.
- [x] Notification daemon: `org.freedesktop.Notifications` toasts with
      replacement, close, expiry, action buttons, `default` activation,
      image-data/icon-name icons, Pango markup, and routing to the focused
      output.
- [x] Clipboard history for text, using `wlr-data-control-v1` (memory only).

## 0.4 — visual and layout depth

- [x] Window open and workspace transition animations, with `animations`,
      `animation_ms`, and `reduce_motion` settings.
- [x] Window close animations and scale/fade easing snapshots for
      compositor-initiated closes.
- [x] Rounded corners and backdrop blur through the opt-in scenefx 0.5
      renderer (`-Dscenefx=true`; GLES2).
- [x] Window drop shadows using layered scene geometry (`shadows = true`).
- [x] Theme/config for bar height, margins, fonts, and palette.
- [x] Configurable wallpaper gradients (`bg_top`/`bg_bottom`) and an art toggle
      (`wallpaper_art`).
- [x] Grid and equal-column layouts, with per-workspace layout profiles and
      runtime layout cycling.
- [x] Mosaic minimum-size fallback and keyboard floating resize.
- [x] Persist runtime per-workspace layouts and propagate config reloads to
      existing outputs.
- [x] Output mode/position/scale management via `wlr-output-management-v1` (`wlr-randr`).
- [x] HiDPI-aware panel buffer scaling for integer output scales.
- [x] Persist output mode, position, scale, and transform across restarts.
- [x] Fractional desktop scaling through `wp_fractional_scale_v1`, including
      runtime scale changes. XWayland scaling uses xwayland-satellite's
      fractional-scale support.
- [x] Multi-monitor workspace pinning with `workspace_pin`, including
      cross-output window moves.

## 0.5 — deep customization

- [x] Declarative window rules (app-id/title/output patterns; float,
      fullscreen, workspace, size, and position actions).
- [x] Rule re-evaluation on config reload.
- [x] Layout tuning: master count, mosaic ratio/minimum, fixed grid columns.
- [x] Active/inactive border colors.
- [x] `tessa-ctl config` for effective configuration and parsed-rule inspection.
- [x] Per-workspace layout, gap, and master-ratio rules.
- [x] Per-output layout/gap rules (`output-rule`, optional `ws=`), with
      output+workspace precedence over workspace rules.
- [x] A long-lived external layout-helper protocol with a timeout, restart,
      and built-in fallback.
- [x] Configurable animation/effect hooks (`animation-start`, `animation-done`,
      `close-animation-start`, `close-animation-done`).
- [x] Config validation with file/line diagnostics, `tessa-ctl config-check`,
      and transactional reload (failed reloads keep the previous config).
- [x] JSON state/config output with documented `schema: 1`.

## 0.6 — customization depth

- [x] Regex/boolean window-rule expressions and per-rule decoration colors.
- [x] Named input modes with mode-specific bindings and `enter-mode`.
- [x] Leader-key/chord sequences and per-mode timeouts.
- [x] Per-output theme rules and named workspace/output profiles.
- [x] Layout-helper v2: per-output instances, asynchronous/coalesced updates,
      focus/urgent metadata, and protocol version negotiation.
- [x] Config-defined event-to-action rules for policy automation.
- [x] Theme role system and configurable, reduced-motion-aware animations.
- [x] JSON-RPC/event stream with request ids and capability negotiation.
- [x] Interactive config editor/check with diff preview.

## 0.7 — customization parity

The target is to make the core Hyprland/Niri customization surface expressible
from one validated Tessa config, with live reload and without embedding a
JavaScript or plugin VM. Complete the two open 0.6 items (layout-helper v2 and
the interactive config editor/diff preview) before or alongside this work.

- [x] Automatic config reload through inotify, with debounce and transactional
      validation. A failed edit keeps the previous configuration.
- [x] Motion v2 curves: named cubic-bezier definitions, per-kind curves,
      configurable open/workspace offsets, and close scale/fade.
- [x] Motion v2 extensions: normalized spring curves (`spring = name, damping,
      frequency`) and per-window animation enable, duration, and curve
      overrides.
- [x] Window and layer rule v3: per-window opacity, rounding, blur, shadow, and
      border width; layer-shell rules; reactive decorative re-evaluation on
      title/app-id changes. Structural actions remain map/reload-time.
- [x] Named workspaces: global non-numeric names used by bar pills, bindings,
      IPC commands, and window-rule `workspace=`, with deferred resolution.
- [x] Scratchpad overlay: per-output hidden floating windows assigned by rule
      or command, toggled from bindings/IPC, with focus and visibility handling.
- [x] Special named workspaces beyond the scratchpad overlay.
- [x] Window groups: tabbed groups of tiled windows on a workspace, tab
      cycling through `Super+Tab`, group add/remove, and IPC control. Groups are
      runtime state and are not persisted.
- [x] Input/output policy: per-device touchpad/mouse rules (tap, natural
      scrolling, acceleration, scroll method, button map), monitor rules by
      make/model/serial, VRR/adaptive-sync policy, and cursor theme/size.
      Verified through config/JSON tests; physical touchpad and VRR behavior
      remains part of the hardware validation pass.
- [x] Wallpaper image sources: PNG backgrounds with cover/contain/stretch fit,
      live reload, and fallback to the generated gradient/art.
- [x] Shell v2 remainder: composable bar modules/layout, per-surface font and
      color roles, wallpaper shader sources, and layer-rule-aware popovers and
      toasts.
- [x] Shader/effect hooks through the long-lived process protocol; no
      in-process plugin VM.
- [x] Performance guardrails: headless benchmarks and a frame-time budget for
      blur, rounded corners, and animations on the target laptop.
      `tests/performance.sh` measures animation-only and full-effect workloads;
      the target-laptop budget remains part of the hardware validation pass.

The success criterion is that a typical Hyprland/Niri theme and workflow can be
reproduced from one Tessa config, changed without logging out, and extended
through the process API. The goal is coherent expressiveness and validation,
not feature-for-feature plugin parity.

## 1.0 — stability

- [x] Config validation with useful errors and transactional reload, plus
      offline preflight (`tessa --check-config [file]`).
- [x] JSON state/config snapshots with schema version 1.
- [x] IPC line-protocol version negotiation and JSON-RPC request ids.
      `HELLO` negotiates line protocol 1; legacy command-only clients remain
      compatible.
- [x] Fuzzing and sanitizer boundary runs of config and IPC parsers.
      `tests/fuzz-parsers.sh` mutates config files and the live line/IPC
      parser; `tests/fuzz-asan.sh` repeats the pass with the system ASan
      runtime preloaded. Zig has no compiler-level ASan instrumentation in
      this setup, so this is an allocator/interceptor pass over the
      Debug-safety build.
- [x] Crash recovery for the panel. One supervisor per output uses pidfd exit
      detection and bounded exponential backoff; deliberate shutdown and output
      removal do not restart it (`tests/panel-recovery.sh`).
- [x] Strict helper timeout guarantees: layout helper 100 ms and effect helper
      200 ms by default, hard-failing to built-in/rule fallbacks
      (`tests/helper-timeouts.sh`).
- [x] Documentation with a full user guide and theme guide.
- [ ] Reproducible packages and a release process.

### Reliability-first design for visual parity

Visual parity with Hyprland/Niri/MangoWC/ShojiWM is a direction, not a reason to
weaken the core:

- Every visual feature must remain optional and declarative. Scene effects,
  animation curves, layer rules, and process helpers have built-in fallbacks.
- External helpers are time-bounded and never block the Wayland event loop.
  The 100 ms layout and 200 ms effect contracts are regression-tested.
- Config changes are preflightable offline and transactionally reloaded; a bad
  edit cannot replace the running config.
- The panel is supervised, so shell/visual work cannot take down the bar for
  the session.
- New effects must keep the headless performance and fuzz suites green. Visual
  parity work should add tests in the same style as `niri-visual-tests`, not
  only screenshots.

## Non-goals

- Embedding a TypeScript/JS config runtime or a native plugin VM. Tessa's
  answer to ShojiWM-style composition is declarative rules plus process
  protocols, so extensions do not load code into the compositor.
- Chasing every Hyprland effect/plugin. Tessa should stay a coherent, quiet
  desktop rather than a bag of effects.
- A built-in terminal. Kitty/foot are better terminals than a rushed one, and
  the user explicitly allowed using one.
