#!/bin/sh
# Show the focused window title in the Tessa bar.
# Requires tessa-ctl in PATH. Run it from a terminal started by Tessa, or set
# TESSA_IPC explicitly.
set -eu

field() {
    printf '%s\n' "$1" | tr '\t' '\n' | sed -n "s/^$2=//p" | head -n 1
}

clear_status() {
    tessa-ctl status active --clear >/dev/null 2>&1 || true
}

trap clear_status EXIT INT TERM
clear_status

tessa-ctl events window-focus | while IFS= read -r line; do
    id=$(field "$line" id)
    app=$(field "$line" app)
    title=$(field "$line" title)

    if [ "${id:-0}" = "0" ] || { [ -z "$app" ] && [ -z "$title" ]; }; then
        clear_status
        continue
    fi

    label=${app:-window}
    if [ -n "$title" ]; then
        label="$label - $title"
    fi
    tessa-ctl status active "$label"
done
