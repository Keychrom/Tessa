#!/bin/sh
# Reference external panel widget for Tessa Panel.
#
# The process owns its state and pushes a declarative entry over IPC; Tessa
# Panel renders it with the active bar theme and handles clicks. Run this from
# a timer, an extension, or a long-lived loop:
#
#   examples/panel-widget.sh "18C" "☀" 50
#
# Higher priority entries stay visible when the bar is narrow.
set -eu

text=${1:-"Tessa"}
icon=${2:-"◆"}
priority=${3:-50}
id=${TESSA_WIDGET_ID:-demo}

tessa-ctl status "$id" "$text" --icon "$icon" --priority "$priority" \
    --exec "tessa-ctl panel calendar"
