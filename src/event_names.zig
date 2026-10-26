const std = @import("std");

pub const startup = "startup";
pub const shutdown = "shutdown";
pub const window_open = "window-open";
pub const window_close = "window-close";
pub const window_focus = "window-focus";
pub const workspace_change = "workspace-change";
pub const window_moved = "window-moved";
pub const layout_change = "layout-change";
pub const mode_change = "mode-change";
pub const config_reload = "config-reload";
pub const launcher = "launcher";
pub const panel = "panel";
pub const output_added = "output-added";
pub const output_removed = "output-removed";

pub const known = [_][]const u8{
    startup,
    shutdown,
    window_open,
    window_close,
    window_focus,
    workspace_change,
    window_moved,
    layout_change,
    mode_change,
    config_reload,
    launcher,
    panel,
    output_added,
    output_removed,
};

pub fn isKnown(name: []const u8) bool {
    for (known) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}
