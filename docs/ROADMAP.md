**English** | [日本語](ROADMAP.ja.md)

# Roadmap

Tessa is intentionally small. The roadmap is ordered by what makes it usable as
a daily Japanese desktop, then by polish.

## 0.1.x — make the foundation trustworthy

- [ ] Run on DRM + libinput on the target machine and fix layout/input issues.
- [x] Automated headless coverage for bar workspace clicks, window-chip
      right-click close, floating drag/resize, click-to-focus, and launcher
      typing (`tests/interaction.sh`, using `wlr-virtual-pointer-v1`).
- [x] Fullscreen, xdg client popups, clipboard, and multi-window focus are
      covered by `tests/interaction.sh`, `tests/popups.sh`, and
      `tests/clipboard.sh`. Physical mouse/keyboard validation remains part of
      the DRM item above.
- [ ] Fix transient client repaint gaps after float/resize. Interactive
      grabs now re-arrange and publish final geometry on release; visual
      validation during the drag still needs a real display.
- [x] Add a small integration test that starts the headless compositor and
      asserts state/IPC and extension hooks (`tests/smoke.sh`).
- [x] Decide the license (MIT).
- [x] Arch PKGBUILD and Debian packaging definitions, with wlroots 0.19
      explicitly pinned by the build and package dependencies.
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
- [x] Rounded corners and backdrop blur through the opt-in scenefx 0.4
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
- [ ] Layout-helper v2: per-output instances, asynchronous/incremental updates,
      focus/urgent metadata, and protocol version negotiation.
- [x] Config-defined event-to-action rules for policy automation.
- [x] Theme role system and configurable, reduced-motion-aware animations.
- [x] JSON-RPC/event stream with request ids and capability negotiation.
- [ ] Interactive config editor/check with diff preview.

## 0.7 — customization parity

The target is to make the core Hyprland/Niri customization surface expressible
from one validated Tessa config, with live reload and without embedding a
JavaScript or plugin VM. Complete the two open 0.6 items (layout-helper v2 and
the interactive config editor/diff preview) before or alongside this work.

- [ ] Automatic config reload through inotify, with debounce and transactional
      validation. A failed edit keeps the previous configuration.
- [ ] Motion v2: named cubic-bezier and spring curves, per-kind curves,
      per-window animation overrides, and configurable open/close fade, scale,
      and translation.
- [ ] Window and layer rule v3: per-window opacity, rounding, blur, shadow, and
      border width; layer-shell rules; reactive re-evaluation on title/app-id
      changes without a full reload.
- [ ] Workspace/layout v2: named workspaces, special/scratchpad workspaces,
      window groups, and the completed asynchronous per-output layout helper.
- [ ] Input/output policy: per-device touchpad/mouse rules (tap, natural
      scrolling, acceleration, scroll method, button map), monitor rules by
      make/model/serial, VRR/adaptive-sync policy, and cursor theme/size.
- [ ] Shell v2: composable bar modules/layout, per-surface font and color
      roles, wallpaper image/shader sources, and layer-rule-aware popovers and
      toasts.
- [ ] Shader/effect hooks through the long-lived process protocol; no
      in-process plugin VM.
- [ ] Performance guardrails: headless benchmarks and a frame-time budget for
      blur, rounded corners, and animations on the target laptop.

The success criterion is that a typical Hyprland/Niri theme and workflow can be
reproduced from one Tessa config, changed without logging out, and extended
through the process API. The goal is coherent expressiveness and validation,
not feature-for-feature plugin parity.

## 1.0 — stability

- [x] Config validation with useful errors and transactional reload.
- [x] JSON state/config snapshots with schema version 1.
- [ ] IPC line-protocol version negotiation and JSON-RPC request ids.
- [ ] Fuzzing/ASan runs of config and IPC parsers.
- [ ] Crash recovery for the panel.
- [ ] Documentation with a full user guide and theme guide.
- [ ] Reproducible packages and a release process.

## Non-goals

- Embedding a TypeScript/JS config runtime or a native plugin VM. Tessa's
  answer to ShojiWM-style composition is declarative rules plus process
  protocols, so extensions do not load code into the compositor.
- Chasing every Hyprland effect/plugin. Tessa should stay a coherent, quiet
  desktop rather than a bag of effects.
- A built-in terminal. Kitty/foot are better terminals than a rushed one, and
  the user explicitly allowed using one.
