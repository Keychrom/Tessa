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
- [ ] Add a small integration test that starts the headless compositor and
      asserts the panel state/IPC.
- [x] Decide the license (MIT).
- [ ] Package for Arch/Ubuntu and pin wlroots 0.19.

## 0.2 — input and apps

- [x] `zwp_text_input_v3` + `input-method-v2` support (Fcitx5/Mozc), including
      input-popup placement and launcher IME input.
- [x] XWayland through `xwayland-satellite`, with automatic display selection,
      `DISPLAY` export, xdg-decoration, and a fallback keyboard for headless
      startup.
- [ ] Layer-shell popup rendering (menus from third-party layer clients).
- [ ] Keyboard layout/options in config (`XKB_DEFAULT_*` is used today).
- [ ] Touchpad gesture support (workspace swipe, launcher gesture).
- [ ] Touch and tablet support.
- [ ] Pointer constraints / relative pointer for games.
- [x] Primary selection (`wlr_primary_selection_v1`).
- [ ] XIM integration for X11 applications.

## 0.3 — shell and desktop integration

- [ ] Bars on every output; per-output active workspace.
- [ ] Tray / StatusNotifier, media controls, battery, network, audio.
- [ ] Calendar/clock popup.
- [ ] Power menu and session lock (`ext-session-lock-v1`).
- [ ] Idle inhibit and DPMS.
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
- [ ] More tiling layouts and per-workspace layout profiles.
- [ ] Mosaic layout minimum-size handling and keyboard resize.
- [ ] HiDPI/scale and output mode configuration.
- [ ] Multi-monitor workspace pinning.

## 1.0 — stability

- [ ] Config validation with useful errors.
- [ ] IPC schema/versioning and a JSON option for external tools.
- [ ] Fuzzing/ASan runs of config and IPC parsers.
- [ ] Crash recovery for the panel.
- [ ] Documentation with a full user guide and theme guide.
- [ ] Reproducible packages and a release process.

## Non-goals

- A TypeScript/JS config runtime or a plugin VM. ShojiWM does that better.
- Chasing every Hyprland effect/plugin. Tessa should stay a coherent, quiet
  desktop rather than a bag of effects.
- A built-in terminal. Kitty/foot are better terminals than a rushed one, and
  the user explicitly allowed using one.
