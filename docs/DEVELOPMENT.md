**English** | [日本語](DEVELOPMENT.ja.md)

# Development

Tessa can be developed entirely on a headless Linux machine over SSH. The
compositor and panel are ordinary Wayland programs, and `grim` can capture the
headless output for quick visual checks. A virtual keyboard (`wtype`) and Fcitx5
make it possible to test keyboard and IME paths without a physical display.

## Build

```sh
chmod +x scripts/*.sh scripts/tessa-session
./scripts/build.sh -Doptimize=ReleaseSafe
```

For a debug build:

```sh
./scripts/build.sh
```

Prerequisites are listed in the main README. In short: Zig 0.16, wlroots 0.19,
Wayland, xkbcommon, pixman, DRM/input/seat development headers, Cairo, Pango,
and fonts. For X11 testing, also install `xwayland-satellite` in `PATH`.

Check the libraries:

```sh
pkg-config --modversion wlroots-0.19
ldconfig -p | grep wlroots
fc-list | grep -i -E 'Inter|JetBrains|Noto Sans CJK'
```

## Headless session

Terminal 1:

```sh
./scripts/run-headless.sh
```

This creates `/tmp/tessa-headless`, forces the pixman renderer, and starts the
panel from `zig-out/bin`. The output is a 1920×1080 headless display named
`HEADLESS-1`.

Terminal 2:

```sh
# capture the screen
./scripts/screenshot.sh /tmp/tessa.png

# spawn a terminal inside the session
printf 'CMD spawn foot -T notes\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# master <-> mosaic
printf 'CMD layout\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# launcher (optionally with a prefilled query)
printf 'CMD launcher\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD launcher ter\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# switch workspace / focus a window
printf 'CMD workspace 2\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
```

Tessa creates a fallback keyboard when the headless backend has no physical
input devices, so the panel, IME, and XWayland can start correctly. Inject
keyboard input through the virtual-keyboard protocol:

```sh
export XDG_RUNTIME_DIR=/tmp/tessa-headless
export WAYLAND_DISPLAY=wayland-0

printf 'CMD launcher\n' | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
wtype "foot"
wtype -k Return
```

`wtype` types into whichever surface currently has keyboard focus.

### IME test

Start Fcitx5 inside the session, select Mozc, and type into the launcher:

```sh
printf 'CMD spawn fcitx5\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD launcher\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

wtype "nihongo"      # preedit
wtype -k space       # conversion
wtype -k Return      # commit
grim -o HEADLESS-1 /tmp/ime.png
```

Point `XDG_CONFIG_HOME` at a temporary directory with an `fcitx5/profile` that
selects `mozc` to avoid touching your real Fcitx configuration. The candidate
popup is drawn through input-method popup surfaces below the search field.

### XWayland test

With `xwayland-satellite` in `PATH` (or `TESSA_XWAYLAND_BIN` set), Tessa chooses
a free display automatically and exports `DISPLAY`. On a clean machine this is
usually `:0`.

```sh
printf 'CMD spawn xeyes\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD spawn xclock\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
sleep 2
DISPLAY=:0 xdpyinfo | head
grim -o HEADLESS-1 /tmp/xwayland.png
printf 'STATE\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
```

The `STATE` output should list `XEyes` and `XClock` as normal windows. Use
`xev` and `wtype` to check that key events reach X11 clients; note that wtype
installs its own small keymap, so a physical keyboard is better for realistic
text-entry tests.

### Lock and idle test

`ext-session-lock-v1`, `ext-idle-notify-v1`, `idle-inhibit-v1`, and
output-power management are exposed by the compositor. Install clients to test
them:

```sh
sudo apt install swaylock swayidle wlopm
```

Run `swaylock -f` inside the session (or press `Super+Escape`). The desktop
should be completely replaced by the lock surface; a virtual keyboard created
after locking must not type into it, and if the lock client is killed while
locked Tessa should terminate instead of exposing the desktop. For idle
testing, run `swayidle -w timeout 5 'swaylock -f'` and verify that activity
postpones the lock, while a client holding `idle-inhibit-v1` prevents it.

## Debug logging

```sh
# wlroots debug logs, Tessa logs, and IME/popup diagnostics
TESSA_DEBUG=1 ./scripts/run-headless.sh

# panel state snapshots (active workspace, window count)
TESSA_PANEL_DEBUG=1 ./scripts/run-headless.sh

# full Wayland protocol log from a test client
WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/tmp/tessa-headless \
  WAYLAND_DEBUG=1 foot -T debug
```

Environment overrides:

- `TESSA_IPC=/path/to/socket`
- `TESSA_CONFIG=/path/to/config`
- `TESSA_NO_PANEL=1`
- `TESSA_PANEL_BIN=/path/to/tessa-panel`
- `TESSA_NO_XWAYLAND=1`
- `TESSA_XWAYLAND_BIN=/path/to/xwayland-satellite`
- `TESSA_DEBUG=1`
- `TESSA_PANEL_DEBUG=1`

## Real TTY

For DRM and libinput, run Tessa on the machine's **active virtual terminal**.
The compositor needs DRM master and seat access; launching it from an unrelated
SSH session will not give you a usable hardware session.

```sh
cd /path/to/Tessa
PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

The panel is auto-started from `PATH`. If you install with
`scripts/install-session.sh`, the session entry point puts its own directory at
the front of `PATH`, so both binaries are found.

## Iteration tips

- The panel reads its colors/font/terminal at startup. `Super+R` reloads the
  compositor config, keymaps, and key bindings; restart the panel to apply shell
  palette changes.
- `pkill -x tessa` and `pkill -x tessa-panel` are safer than `pkill -f tessa`
  when working over SSH: a `-f` pattern can match the SSH remote command line
  itself and kill the session.
- The headless output name is stable: `grim -o HEADLESS-1`.
- Zig's translate-c cannot process Pango/GLib headers. Text rendering lives in
  `panel/text.c`; keep Pango out of `@cImport`.
- Layer-shell `EXCLUSIVE` is enum value `1`; `2` is `ON_DEMAND`.
- `ReleaseSafe` needs `_FORTIFY_SOURCE=0` for the C imports; this is already set
  in the two `c.zig` files.
- Xwayland 24.x needs a keyboard keymap in the parent seat at startup, or it
  fails with `XKB: Failed to compile keymap`; the fallback keyboard in
  `input.zig` provides one.
- Reset `SIGCHLD` to `SIG_DFL` before exec'ing children. Tessa ignores `SIGCHLD`
  for its own child reaping; inheriting that breaks helpers that spawn and wait,
  including Xwayland's xkbcomp.
- `wlr_xdg_toplevel_decoration_v1_set_mode()` must not schedule a configure
  before the xdg surface's initial commit. If it is not initialized, set
  `scheduled_mode` and apply it after initialization.
