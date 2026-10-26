const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;

fn displayReady(display: []const u8) bool {
    if (display.len < 2 or display[0] != ':') return false;
    var number: u8 = 0;
    var digits: usize = 0;
    for (display[1..]) |ch| {
        if (ch < '0' or ch > '9') break;
        number = number *| 10 +| (ch - '0');
        digits += 1;
    }
    if (digits == 0) return false;
    var path_buf: [64:0]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/tmp/.X11-unix/X{d}", .{number}) catch return false;
    return c.access(path, c.F_OK) == 0;
}

fn onTimeout(data: ?*anyopaque) callconv(.c) c_int {
    const server: *Server = @ptrCast(@alignCast(data.?));
    server.xim_attempts += 1;
    if (displayReady(server.xim_display[0..server.xim_display_len])) {
        if (server.xim_timer) |src| {
            _ = c.wl_event_source_remove(src);
            server.xim_timer = null;
        }
        if (!server.xim_started) {
            server.xim_started = true;
            core.logInfo("xim: starting '{s}'", .{server.config.xim_start[0..server.config.xim_start_len]});
            core.spawn(server.config.xim_start[0..server.config.xim_start_len]);
        }
        return 0;
    }
    if (server.xim_attempts >= 100) {
        if (server.xim_timer) |src| {
            _ = c.wl_event_source_remove(src);
            server.xim_timer = null;
        }
        core.logInfo("xim: X display {s} did not appear; not starting XIM server", .{server.xim_display[0..server.xim_display_len]});
        return 0;
    }
    if (server.xim_timer) |src| _ = c.wl_event_source_timer_update(src, 100);
    return 0;
}

pub fn init(server: *Server, display: []const u8) void {
    if (!server.config.xim) return;
    if (server.config.xim_server_len > 0 and c.getenv("XMODIFIERS") == null) {
        var value: [96:0]u8 = undefined;
        const text = std.fmt.bufPrintZ(&value, "@im={s}", .{server.config.xim_server[0..server.config.xim_server_len]}) catch return;
        _ = c.setenv("XMODIFIERS", text, 1);
        core.logInfo("xim: XMODIFIERS={s}", .{text});
    }
    if (server.config.xim_start_len == 0) return;

    server.xim_display_len = @min(display.len, server.xim_display.len);
    @memcpy(server.xim_display[0..server.xim_display_len], display[0..server.xim_display_len]);
    server.xim_attempts = 0;
    const loop = c.wl_display_get_event_loop(server.display);
    server.xim_timer = c.wl_event_loop_add_timer(loop, onTimeout, server);
    if (server.xim_timer) |src| {
        _ = c.wl_event_source_timer_update(src, 50);
        core.logInfo("xim: waiting for X display {s} before starting XIM server", .{display});
    }
}

pub fn cleanup(server: *Server) void {
    if (server.xim_timer) |src| {
        _ = c.wl_event_source_remove(src);
        server.xim_timer = null;
    }
}
