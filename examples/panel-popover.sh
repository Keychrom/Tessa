#!/bin/sh
# Reference external module with a declarative popover for Tessa Panel.
#
# The module owns its data. It writes a tiny UI file, then publishes a status
# widget that points at it. Tessa Panel renders the popover with the active
# theme, handles hover/keyboard input, and runs the action commands.
#
#   examples/panel-popover.sh "Weather" "Tokyo, clear, 18 C" "18C"
#
# Click the widget in the bar to open it, or run:
#   tessa-ctl panel module demo
set -eu

id=${TESSA_WIDGET_ID:-demo}
title=${1:-"Tessa module"}
body=${2:-"Rendered by Tessa Panel. The module only writes this file."}
text=${3:-"demo"}
icon=${4:-"◆"}

dir=${XDG_RUNTIME_DIR:-/tmp}/tessa-widgets
mkdir -p "$dir"
ui="$dir/$id.popover"

cat > "$ui" <<EOF
title = $title
body = $body
action = Open launcher | tessa-ctl launcher
action = Open calendar | tessa-ctl panel calendar
action = Remove widget | tessa-ctl status $id --clear
EOF

tessa-ctl status "$id" "$text" --icon "$icon" --popover "$ui"
