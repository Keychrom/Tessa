**English** | [日本語](ROADMAP.ja.md)

# Roadmap

Tessa is intentionally small. The roadmap is ordered by what makes it usable as
a daily Japanese desktop, then by polish.

## 0.1.x — make the foundation trustworthy

- [ ] Run on DRM + libinput on the target machine and fix layout/input issues.
- [ ] Test keyboard navigation and mouse interactions end to end (bar clicks,
      right-click close, floating drag/resize, launcher typing).
- [ ] Validate fullscreen, client popups, clipboard, and multi-window focus.
- [ ] Fix any transient client repaint gaps after float/resize.
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
- [ ] Touchpad gesture support (workspace swipe, launcher gesture).
- [ ] Touch and tablet support.
- [x] Relative pointer (`relative-pointer-v1`).
- [ ] Pointer constraints (`pointer-constraints-v1`).
- [x] Primary selection (`wlr_primary_selection_v1`).
- [ ] XIM integration for X11 applications.

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

- [ ] Window open/close/workspace transition animations (optional, with a
      reduced-motion setting).
- [ ] Rounded corners and blur via custom wlroots shaders.
- [ ] Proper drop shadows.
- [x] Theme/config for bar height, margins, fonts, and palette.
- [ ] Configurable wallpaper art/gradients.
- [x] Grid and equal-column layouts, with per-workspace layout profiles and
      runtime layout cycling.
- [x] Mosaic minimum-size fallback and keyboard floating resize.
- [x] Persist runtime per-workspace layouts and propagate config reloads to
      existing outputs.
- [x] Output mode/position/scale management via `wlr-output-management-v1` (`wlr-randr`).
- [x] HiDPI-aware panel buffer scaling for integer output scales.
- [x] Persist output mode, position, scale, and transform across restarts.
- [ ] Fractional desktop scaling and XWayland scaling.
- [ ] Multi-monitor workspace pinning.

## 0.5 — deep customization

- [x] Declarative window rules (app-id/title/output patterns; float,
      fullscreen, workspace, size, and position actions).
- [x] Rule re-evaluation on config reload.
- [x] Layout tuning: master count, mosaic ratio/minimum, fixed grid columns.
- [x] Active/inactive border colors.
- [x] `tessa-ctl config` for effective configuration and parsed-rule inspection.
- [x] Per-workspace layout, gap, and master-ratio rules.
- [ ] Per-output layout/gap rules.
- [x] A long-lived external layout-helper protocol with a timeout, restart,
      and built-in fallback.
- [ ] Configurable animation/effect hooks.
- [x] Config validation with file/line diagnostics, `tessa-ctl config-check`,
      and transactional reload (failed reloads keep the previous config).
- [x] JSON state/config output with documented `schema: 1`.

## 0.6 — customization depth

- [ ] Regex/boolean window-rule expressions and per-rule decoration colors.
- [x] Named input modes with mode-specific bindings and `enter-mode`.
- [ ] Leader-key/chord sequences and per-mode timeouts.
- [ ] Per-output theme rules and named workspace/output profiles.
- [ ] Layout-helper v2: per-output instances, asynchronous/incremental updates,
      focus/urgent metadata, and protocol version negotiation.
- [ ] Config-defined event-to-action rules for policy automation.
- [ ] Theme role system and configurable, reduced-motion-aware animations.
- [ ] JSON-RPC/event stream with request ids and capability negotiation.
- [ ] Interactive config editor/check with diff preview.

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
