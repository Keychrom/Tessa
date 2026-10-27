const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const cfg = @import("config.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");

const Server = types.Server;

pub fn currentName(server: *Server) []const u8 {
    if (server.active_mode_name_len > 0) {
        return server.active_mode_name[0..server.active_mode_name_len];
    }
    if (server.config.mode_count > 0) {
        return server.config.mode_names[0][0..server.config.mode_name_lens[0]];
    }
    return "default";
}

fn timeoutFor(server: *Server, index: u8) i32 {
    if (index == 0) return 0;
    if (@as(usize, index) >= server.config.mode_timeouts.len) return 0;
    return server.config.mode_timeouts[index];
}

fn schedule(server: *Server, timeout_ms: i32) void {
    server.mode_timeout_ms = timeout_ms;
    if (server.mode_timer) |timer| {
        _ = c.wl_event_source_timer_update(timer, timeout_ms);
    }
}

fn onTimeout(data: ?*anyopaque) callconv(.c) c_int {
    const server: *Server = @ptrCast(@alignCast(data.?));
    server.mode_timeout_ms = 0;
    if (server.active_mode != 0) {
        core.logDebug("mode: '{s}' timed out", .{currentName(server)});
        setDefault(server);
    }
    return 0;
}

pub fn init(server: *Server) void {
    const loop = c.wl_display_get_event_loop(server.display);
    server.mode_timer = c.wl_event_loop_add_timer(loop, onTimeout, server);
}

pub fn cleanup(server: *Server) void {
    if (server.mode_timer) |timer| {
        _ = c.wl_event_source_remove(timer);
        server.mode_timer = null;
    }
}

pub fn set(server: *Server, name: []const u8) bool {
    const index = cfg.findMode(&server.config, name) orelse return false;
    if (server.active_mode == index and
        std.mem.eql(u8, currentName(server), name))
    {
        schedule(server, timeoutFor(server, index));
        return true;
    }
    server.active_mode = index;
    core.copyString(&server.active_mode_name, &server.active_mode_name_len, name);
    schedule(server, timeoutFor(server, index));
    events.emit(server, .{
        .name = event_names.mode_change,
        .arg = name,
    });
    core.markDirty(server);
    core.logInfo("mode: {s}", .{name});
    return true;
}

pub fn setLeader(server: *Server) bool {
    if (!set(server, "leader")) return false;
    schedule(server, server.config.leader_timeout);
    return true;
}

pub fn setDefault(server: *Server) void {
    _ = set(server, "default");
}

pub fn sync(server: *Server) void {
    const name = currentName(server);
    if (cfg.findMode(&server.config, name)) |index| {
        server.active_mode = index;
        schedule(server, timeoutFor(server, index));
        return;
    }
    server.active_mode = 0;
    if (server.config.mode_count > 0) {
        core.copyString(
            &server.active_mode_name,
            &server.active_mode_name_len,
            server.config.mode_names[0][0..server.config.mode_name_lens[0]],
        );
    } else {
        server.active_mode_name_len = 0;
    }
    schedule(server, 0);
    core.logInfo("mode: active mode missing after reload; returning to default", .{});
}
