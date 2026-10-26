#!/bin/sh
# Capture the headless development output. Requires grim.
set -eu
runtime="${TESSA_RUNTIME_DIR:-/tmp/tessa-headless}"
out="${1:-/tmp/tessa-shot.png}"
output="${2:-HEADLESS-1}"
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
exec grim -o "$output" "$out"
