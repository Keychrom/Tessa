const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;
const Output = types.Output;

pub const WorkspaceRef = struct {
    out: *Output,
    ws: usize,
};

pub fn init(server: *Server) void {
    const raw = c.wlr_ext_workspace_manager_v1_create(server.display, 1) orelse {
        core.logInfo("ext-workspace-v1 unavailable", .{});
        return;
    };
    server.ext_workspace_manager = @ptrCast(@alignCast(raw));
    core.logInfo("ext-workspace-v1 enabled", .{});
}

pub fn outputAdded(out: *Output) void {
    const server = out.server;
    const manager = server.ext_workspace_manager orelse return;

    const group_raw = c.wlr_ext_workspace_group_handle_v1_create(manager, 0) orelse return;
    const group: *c.wlr_ext_workspace_group_handle_v1 = @ptrCast(@alignCast(group_raw));
    group.data = @ptrCast(out);
    out.ext_workspace_group = group;
    c.wlr_ext_workspace_group_handle_v1_output_enter(group, out.wlr);

    var ws: usize = 1;
    while (ws <= types.WS_COUNT) : (ws += 1) {
        var id_buf: [128]u8 = undefined;
        const id = std.fmt.bufPrint(&id_buf, "{s}:{d}", .{ core.outputName(out), ws }) catch continue;
        if (id.len >= id_buf.len - 1) continue;
        id_buf[id.len] = 0;

        const handle_raw = c.wlr_ext_workspace_handle_v1_create(
            manager,
            @ptrCast(&id_buf),
            c.EXT_WORKSPACE_HANDLE_V1_WORKSPACE_CAPABILITIES_ACTIVATE,
        ) orelse continue;
        const handle: *c.wlr_ext_workspace_handle_v1 = @ptrCast(@alignCast(handle_raw));
        handle.data = @ptrCast(out);
        out.ext_workspaces[ws - 1] = handle;
        c.wlr_ext_workspace_handle_v1_set_group(handle, group);
        var coord = [_]u32{@intCast(ws - 1)};
        c.wlr_ext_workspace_handle_v1_set_coordinates(handle, @ptrCast(&coord), coord.len);
    }
    syncOutput(out);
}

pub fn outputRemoved(out: *Output) void {
    var ws: usize = 0;
    while (ws < types.WS_COUNT) : (ws += 1) {
        if (out.ext_workspaces[ws]) |handle| {
            c.wlr_ext_workspace_handle_v1_destroy(handle);
            out.ext_workspaces[ws] = null;
        }
    }
    if (out.ext_workspace_group) |group| {
        c.wlr_ext_workspace_group_handle_v1_destroy(group);
        out.ext_workspace_group = null;
    }
}

pub fn syncOutput(out: *Output) void {
    const server = out.server;
    var ws: usize = 1;
    while (ws <= types.WS_COUNT) : (ws += 1) {
        const handle = out.ext_workspaces[ws - 1] orelse continue;
        var name_buf: [65:0]u8 = undefined;
        const name = workspaceLabel(server, ws, &name_buf);
        c.wlr_ext_workspace_handle_v1_set_name(handle, name);
        c.wlr_ext_workspace_handle_v1_set_active(handle, out.active_ws == ws);
        c.wlr_ext_workspace_handle_v1_set_urgent(handle, workspaceUrgent(out, ws));
    }
}

pub fn syncAll(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        syncOutput(out);
    }
}

pub fn workspaceRef(server: *Server, handle: *c.wlr_ext_workspace_handle_v1) ?WorkspaceRef {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        var ws: usize = 0;
        while (ws < types.WS_COUNT) : (ws += 1) {
            if (out.ext_workspaces[ws] == handle) {
                return .{ .out = out, .ws = ws + 1 };
            }
        }
    }
    return null;
}

fn workspaceLabel(server: *Server, ws: usize, buf: *[65:0]u8) [*:0]const u8 {
    const name = types.workspaceName(&server.config, ws);
    if (name.len > 0) {
        core.copyZ(buf[0..], name);
        return @ptrCast(buf);
    }
    const text = std.fmt.bufPrint(buf[0 .. buf.len - 1], "{d}", .{ws}) catch {
        buf[0] = 0;
        return @ptrCast(buf);
    };
    buf[text.len] = 0;
    return @ptrCast(buf);
}

fn workspaceUrgent(out: *Output, ws: usize) bool {
    const server = out.server;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.output == out and cl.ws == ws and cl.urgent) return true;
    }
    return false;
}
