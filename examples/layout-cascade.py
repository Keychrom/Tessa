#!/usr/bin/env python3
"""Minimal Tessa external layout helper.

Tessa starts this process once per output and keeps it alive. For each layout
request it writes tab-separated lines to stdin; the helper writes RECT lines to
stdout and terminates the response with END. Replies are asynchronous from the
compositor's point of view, so the previous rectangles remain visible until the
new response is complete.

This example is intentionally a cascade, not a practical daily layout. Copy it
as a starting point for your own tiling algorithm.

Protocol fields:
  HELLO     protocol version advertised by the compositor
  LAYOUT    protocol version
  OUTPUT    output name
  AREA      absolute x, y, width, height of the usable output area
  OUTER_GAP
  GAP
  BORDER
  SCALE
  TRANSFORM
  COUNT
  WINDOW    id, app_id, title, focused, urgent (tab/backslash/newline escaped)
  END
"""

import sys

windows = []
area = (0, 0, 0, 0)
gap = 10


def flush_layout():
    if not windows:
        print("END", flush=True)
        return

    ax, ay, aw, ah = area
    tile_w = max(160, int((aw - gap * 2) * 0.62))
    tile_h = max(120, int((ah - gap * 2) * 0.62))
    step = max(16, min(tile_w, tile_h) // 10)

    for index, window_id in enumerate(windows):
        offset = index % 6
        x = ax + gap + offset * step
        y = ay + gap + offset * step
        print(f"RECT\t{window_id}\t{x}\t{y}\t{tile_w}\t{tile_h}", flush=True)
    print("END", flush=True)


for raw in sys.stdin:
    fields = raw.rstrip("\n").split("\t")
    if not fields:
        continue
    tag = fields[0]
    if tag == "HELLO":
        # Announce protocol 2 support once. Older compositors ignore this.
        print("VERSION\t2", flush=True)
    elif tag == "AREA" and len(fields) >= 5:
        area = tuple(int(value) for value in fields[1:5])
    elif tag == "GAP" and len(fields) >= 2:
        gap = int(fields[1])
    elif tag == "WINDOW" and len(fields) >= 2:
        windows.append(fields[1])
    elif tag == "END":
        flush_layout()
        windows = []
