# Development

Tessa can be developed entirely on a headless Linux machine over SSH. The
compositor and panel are ordinary Wayland programs, and `grim` can capture the
headless output for quick visual checks.

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
and fonts.

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

The headless backend has no keyboard or pointer. The launcher can be opened and
rendered, but it cannot be typed into in this mode. Use IPC for state changes, or
run the compositor on a real TTY for interactive testing.

## Debug logging

```sh
# wlroots debug logs and Tessa logs
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
  compositor config and key bindings; restart the panel to apply shell palette
  changes.
- `pkill -x tessa` and `pkill -x tessa-panel` are safer than `pkill -f tessa`
  when working over SSH: a `-f` pattern can match the SSH remote command line
  itself and kill the session.
- The headless output name is stable: `grim -o HEADLESS-1`.
- Zig's translate-c cannot process Pango/GLib headers. Text rendering lives in
  `panel/text.c`; keep Pango out of `@cImport`.
- Layer-shell `EXCLUSIVE` is enum value `1`; `2` is `ON_DEMAND`.
- `ReleaseSafe` needs `_FORTIFY_SOURCE=0` for the C imports; this is already set
  in the two `c.zig` files.
