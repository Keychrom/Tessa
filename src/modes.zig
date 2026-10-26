const std = @import("std");
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

pub fn set(server: *Server, name: []const u8) bool {
    const index = cfg.findMode(&server.config, name) orelse return false;
    if (server.active_mode == index and
        std.mem.eql(u8, currentName(server), name)) return true;
    server.active_mode = index;
    core.copyString(&server.active_mode_name, &server.active_mode_name_len, name);
    events.emit(server, .{
        .name = event_names.mode_change,
        .arg = name,
    });
    core.markDirty(server);
    core.logInfo("mode: {s}", .{name});
    return true;
}

pub fn setDefault(server: *Server) void {
    _ = set(server, "default");
}

pub fn sync(server: *Server) void {
    const name = currentName(server);
    if (cfg.findMode(&server.config, name)) |index| {
        server.active_mode = index;
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
    core.logInfo("mode: active mode missing after reload; returning to default", .{});
}
