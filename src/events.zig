const std = @import("std");
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;

/// Events are the public extension surface. A configured hook gets the same
/// fields as environment variables that an IPC event subscriber sees.
pub const Event = struct {
    name: []const u8,
    id: ?u64 = null,
    previous_id: ?u64 = null,
    workspace: ?usize = null,
    previous_workspace: ?usize = null,
    app_id: []const u8 = "",
    title: []const u8 = "",
    output: []const u8 = "",
    arg: []const u8 = "",
};

fn append(out: *[]u8, value: []const u8) void {
    const n = @min(value.len, out.*.len);
    @memcpy(out.*[0..n], value[0..n]);
    out.* = out.*[n..];
}

fn appendEscaped(out: *[]u8, value: []const u8) void {
    for (value) |ch| {
        switch (ch) {
            '\\' => append(out, "\\\\"),
            '\n' => append(out, "\\n"),
            '\r' => append(out, "\\r"),
            '\t' => append(out, "\\t"),
            else => {
                if (out.*.len == 0) return;
                out.*[0] = ch;
                out.* = out.*[1..];
            },
        }
        if (out.*.len == 0) return;
    }
}

fn appendField(out: *[]u8, key: []const u8, value: []const u8) void {
    append(out, "\t");
    append(out, key);
    append(out, "=");
    appendEscaped(out, value);
}

fn buildLine(ev: Event, buf: []u8) []const u8 {
    var out = buf[0..];
    append(&out, "EVENT\t");
    appendEscaped(&out, ev.name);

    var num_buf: [32]u8 = undefined;
    if (ev.id) |id| {
        const s = std.fmt.bufPrint(&num_buf, "{d}", .{id}) catch return buf[0 .. buf.len - out.len];
        appendField(&out, "id", s);
    }
    if (ev.previous_id) |id| {
        const s = std.fmt.bufPrint(&num_buf, "{d}", .{id}) catch return buf[0 .. buf.len - out.len];
        appendField(&out, "previous", s);
    }
    if (ev.workspace) |ws| {
        const s = std.fmt.bufPrint(&num_buf, "{d}", .{ws}) catch return buf[0 .. buf.len - out.len];
        appendField(&out, "ws", s);
    }
    if (ev.previous_workspace) |ws| {
        const s = std.fmt.bufPrint(&num_buf, "{d}", .{ws}) catch return buf[0 .. buf.len - out.len];
        appendField(&out, "previous-ws", s);
    }
    if (ev.app_id.len > 0) appendField(&out, "app", ev.app_id);
    if (ev.title.len > 0) appendField(&out, "title", ev.title);
    if (ev.output.len > 0) appendField(&out, "output", ev.output);
    if (ev.arg.len > 0) appendField(&out, "arg", ev.arg);
    append(&out, &[_]u8{10});

    return buf[0 .. buf.len - out.len];
}

/// Broadcast a structured event to every IPC client and run matching hooks.
pub fn emit(server: *Server, ev: Event) void {
    var line_buf: [4096]u8 = undefined;
    const line = buildLine(ev, &line_buf);
    if (server.broadcast_line) |broadcast| broadcast(server, line);

    if (server.config.hook_count == 0) return;

    var envs: [14]core.EnvVar = undefined;
    var env_count: usize = 0;
    const add = struct {
        fn one(list: *[14]core.EnvVar, count: *usize, name: [*:0]const u8, value: []const u8) void {
            if (count.* >= list.len) return;
            list[count.*] = .{ .name = name, .value = value };
            count.* += 1;
        }
    }.one;

    add(&envs, &env_count, "TESSA_EVENT", ev.name);
    var id_buf: [32]u8 = undefined;
    if (ev.id) |id| {
        const s = std.fmt.bufPrint(&id_buf, "{d}", .{id}) catch "";
        add(&envs, &env_count, "TESSA_WINDOW_ID", s);
    }
    var prev_buf: [32]u8 = undefined;
    if (ev.previous_id) |id| {
        const s = std.fmt.bufPrint(&prev_buf, "{d}", .{id}) catch "";
        add(&envs, &env_count, "TESSA_PREVIOUS_ID", s);
    }
    var ws_buf: [16]u8 = undefined;
    if (ev.workspace) |ws| {
        const s = std.fmt.bufPrint(&ws_buf, "{d}", .{ws}) catch "";
        add(&envs, &env_count, "TESSA_WORKSPACE", s);
    }
    var prev_ws_buf: [16]u8 = undefined;
    if (ev.previous_workspace) |ws| {
        const s = std.fmt.bufPrint(&prev_ws_buf, "{d}", .{ws}) catch "";
        add(&envs, &env_count, "TESSA_PREVIOUS_WORKSPACE", s);
    }
    add(&envs, &env_count, "TESSA_APP_ID", ev.app_id);
    add(&envs, &env_count, "TESSA_TITLE", ev.title);
    add(&envs, &env_count, "TESSA_OUTPUT", ev.output);
    add(&envs, &env_count, "TESSA_ARG", ev.arg);

    var focused_buf: [32]u8 = undefined;
    if (server.focused) |focused| {
        const s = std.fmt.bufPrint(&focused_buf, "{d}", .{focused.id}) catch "";
        add(&envs, &env_count, "TESSA_FOCUSED_ID", s);
    } else {
        add(&envs, &env_count, "TESSA_FOCUSED_ID", "0");
    }
    var active_ws_buf: [16]u8 = undefined;
    const active_ws = std.fmt.bufPrint(&active_ws_buf, "{d}", .{server.active_ws}) catch "";
    add(&envs, &env_count, "TESSA_ACTIVE_WORKSPACE", active_ws);
    if (core.focusOutput(server)) |out| {
        add(&envs, &env_count, "TESSA_FOCUSED_OUTPUT", core.outputName(out));
    }

    var i: usize = 0;
    while (i < server.config.hook_count) : (i += 1) {
        const hook = &server.config.hooks[i];
        if (!std.mem.eql(u8, hook.event[0..hook.event_len], ev.name)) continue;
        core.spawnWithEnv(hook.command[0..hook.command_len], envs[0..env_count]);
    }
}
