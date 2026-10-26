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
- [ ] Package for Arch/Ubuntu and pin wlroots 0.19.

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
- [ ] Tray / StatusNotifier, media controls, battery, network, audio.
- [ ] Calendar/clock popup.
- [ ] Power menu.
- [x] Session lock (`ext-session-lock-v1`).
- [x] Idle inhibit, idle notifications, and output-power management (external swayidle/wlopm).
- [ ] Screenshot UI and `xdg-desktop-portal` integration; PipeWire screen
      sharing.
- [ ] Notification daemon integration.
- [ ] Clipboard history.

## 0.4 — visual and layout depth

- [ ] Window open/close/workspace transition animations (optional, with a
      reduced-motion setting).
- [ ] Rounded corners and blur via custom wlroots shaders.
- [ ] Proper drop shadows.
- [ ] Theme/config for bar height, margins, fonts, palette, wallpaper art.
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
- [ ] A long-lived external layout-helper protocol with a timeout and built-in
      fallback.
- [ ] Configurable animation/effect hooks.
- [ ] Config validation with file/line diagnostics.
- [ ] JSON state/config output and a documented schema version.

## 1.0 — stability

- [ ] Config validation with useful errors.
- [ ] IPC schema/versioning and a JSON option for external tools.
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
