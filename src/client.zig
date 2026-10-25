const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");

const Server = types.Server;
const Client = types.Client;
const Popup = types.Popup;

fn tBase(xdg: *c.wlr_xdg_toplevel) *c.wlr_xdg_surface {
    return @ptrCast(@alignCast(xdg.base));
}
fn tSurface(xdg: *c.wlr_xdg_toplevel) *c.wlr_surface {
    return @ptrCast(@alignCast(tBase(xdg).surface));
}
fn pBase(popup: *c.wlr_xdg_popup) *c.wlr_xdg_surface {
    return @ptrCast(@alignCast(popup.base));
}
fn pSurface(popup: *c.wlr_xdg_popup) *c.wlr_surface {
    return @ptrCast(@alignCast(pBase(popup).surface));
}

pub fn init(server: *Server) void {
    server.new_xdg_toplevel.notify = onNewToplevel;
    c.wl_signal_add(&server.xdg_shell.events.new_toplevel, &server.new_xdg_toplevel);

    server.new_xdg_popup.notify = onNewPopup;
    c.wl_signal_add(&server.xdg_shell.events.new_popup, &server.new_xdg_popup);
}

fn copyMeta(client: *Client) void {
    if (client.xdg.title) |t| {
        core.copyString(&client.title, &client.title_len, std.mem.span(t));
    } else {
        client.title_len = 0;
        client.title[0] = 0;
    }
    if (client.xdg.app_id) |a| {
        core.copyString(&client.app_id, &client.app_id_len, std.mem.span(a));
    } else {
        client.app_id_len = 0;
        client.app_id[0] = 0;
    }
}

fn nextClientOnWorkspace(server: *Server, exclude: *Client) ?*Client {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl != exclude and cl.mapped and cl.ws == server.active_ws) return cl;
    }
    return null;
}

fn clearLastFocused(server: *Server, client: *Client) void {
    var i: usize = 0;
    while (i < server.last_focused.len) : (i += 1) {
        if (server.last_focused[i] == client) server.last_focused[i] = null;
    }
}

fn onMap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("map", listener.?);
    client.mapped = true;
    copyMeta(client);
    layout.arrangeAll(client.server);
    layout.focusClient(client.server, client);
    core.markDirty(client.server);
}

fn onUnmap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("unmap", listener.?);
    const server = client.server;
    client.mapped = false;
    c.wlr_scene_node_set_enabled(&client.frame.node, false);

    if (server.grabbed == client) layout.resetInteractive(server);

    if (server.focused == client) {
        const next = nextClientOnWorkspace(server, client);
        server.focused = null;
        if (server.focused_layer == null) layout.focusClient(server, next);
    }

    layout.arrangeAll(server);
    core.markDirty(server);
}

fn onCommit(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("commit", listener.?);
    const g = tBase(client.xdg).geometry;

    if (tBase(client.xdg).initial_commit) {
        copyMeta(client);
        layout.setProvisionalSize(client);
    }

    if (g.x != client.last_gx or g.y != client.last_gy or
        g.width != client.last_gw or g.height != client.last_gh)
    {
        client.last_gx = g.x;
        client.last_gy = g.y;
        client.last_gw = g.width;
        client.last_gh = g.height;
        if (client.mapped) {
            layout.arrangeAll(client.server);
            core.markDirty(client.server);
        }
    }
}

fn onDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("destroy", listener.?);
    const server = client.server;
    const was_focused = server.focused == client;

    c.wl_list_remove(&client.map.link);
    c.wl_list_remove(&client.unmap.link);
    c.wl_list_remove(&client.commit.link);
    c.wl_list_remove(&client.destroy.link);
    c.wl_list_remove(&client.request_move.link);
    c.wl_list_remove(&client.request_resize.link);
    c.wl_list_remove(&client.request_maximize.link);
    c.wl_list_remove(&client.request_fullscreen.link);
    c.wl_list_remove(&client.set_title.link);
    c.wl_list_remove(&client.set_app_id.link);

    if (server.grabbed == client) layout.resetInteractive(server);
    if (was_focused) server.focused = null;
    clearLastFocused(server, client);

    if (core.clientIndex(server, client)) |idx| {
        core.removeAt(types.Client, server.clients[0..], &server.client_count, idx);
    }

    c.wlr_scene_node_destroy(&client.frame.node);

    if (was_focused and server.focused_layer == null) {
        var next: ?*Client = null;
        var i: usize = 0;
        while (i < server.clients.len) : (i += 1) {
            const cl = server.clients[i] orelse continue;
            if (cl.mapped and cl.ws == server.active_ws) {
                next = cl;
                break;
            }
        }
        layout.focusClient(server, next);
    }

    c.free(client);
    layout.arrangeAll(server);
    core.markDirty(server);
}

fn onRequestMove(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("request_move", listener.?);
    if (client.floating) layout.beginInteractive(client, .move, 0);
}

fn onRequestResize(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const client: *Client = @fieldParentPtr("request_resize", listener.?);
    const event: *c.wlr_xdg_toplevel_resize_event = @ptrCast(@alignCast(data.?));
    if (client.floating) layout.beginInteractive(client, .resize, event.edges);
}

fn onRequestMaximize(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("request_maximize", listener.?);
    if (tBase(client.xdg).initialized) {
        _ = c.wlr_xdg_surface_schedule_configure(tBase(client.xdg));
    }
}

fn onRequestFullscreen(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("request_fullscreen", listener.?);
    client.fullscreen = client.xdg.requested.fullscreen;
    _ = c.wlr_xdg_toplevel_set_fullscreen(client.xdg, client.fullscreen);
    layout.arrangeOutput(client.server, client.output);
    core.markDirty(client.server);
}

fn onSetTitle(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("set_title", listener.?);
    copyMeta(client);
    core.markDirty(client.server);
}

fn onSetAppId(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("set_app_id", listener.?);
    copyMeta(client);
    core.markDirty(client.server);
}

fn onNewToplevel(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_xdg_toplevel", listener.?);
    const xdg: *c.wlr_xdg_toplevel = @ptrCast(@alignCast(data.?));

    const out = core.focusedOutput(server) orelse {
        c.wlr_xdg_toplevel_send_close(xdg);
        return;
    };

    const client = @as(*Client, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Client)).?)));
    client.server = server;
    client.xdg = xdg;
    client.output = out;
    client.ws = server.active_ws;
    client.mapped = false;
    client.floating = false;
    client.fullscreen = false;
    client.id = server.next_client_id;
    server.next_client_id += 1;

    client.frame = c.wlr_scene_tree_create(server.tree_windows);
    client.frame.node.data = @ptrCast(client);

    const inactive = [4]f32{ 0.16, 0.20, 0.28, 1.0 };
    client.border_rect = c.wlr_scene_rect_create(client.frame, 1, 1, &inactive);

    client.surface_tree = c.wlr_scene_xdg_surface_create(client.frame, tBase(xdg));
    tBase(xdg).data = @ptrCast(client.surface_tree);

    client.map.notify = onMap;
    c.wl_signal_add(&tSurface(xdg).events.map, &client.map);
    client.unmap.notify = onUnmap;
    c.wl_signal_add(&tSurface(xdg).events.unmap, &client.unmap);
    client.commit.notify = onCommit;
    c.wl_signal_add(&tSurface(xdg).events.commit, &client.commit);

    client.destroy.notify = onDestroy;
    c.wl_signal_add(&xdg.events.destroy, &client.destroy);
    client.request_move.notify = onRequestMove;
    c.wl_signal_add(&xdg.events.request_move, &client.request_move);
    client.request_resize.notify = onRequestResize;
    c.wl_signal_add(&xdg.events.request_resize, &client.request_resize);
    client.request_maximize.notify = onRequestMaximize;
    c.wl_signal_add(&xdg.events.request_maximize, &client.request_maximize);
    client.request_fullscreen.notify = onRequestFullscreen;
    c.wl_signal_add(&xdg.events.request_fullscreen, &client.request_fullscreen);
    client.set_title.notify = onSetTitle;
    c.wl_signal_add(&xdg.events.set_title, &client.set_title);
    client.set_app_id.notify = onSetAppId;
    c.wl_signal_add(&xdg.events.set_app_id, &client.set_app_id);

    copyMeta(client);

    if (server.client_count < server.clients.len) {
        server.clients[server.client_count] = client;
        server.client_count += 1;
    } else {
        core.logInfo("too many clients", .{});
        c.wlr_xdg_toplevel_send_close(xdg);
        c.wlr_scene_node_destroy(&client.frame.node);
        c.free(client);
        return;
    }

    core.logInfo("new toplevel: {s} ({s}) id={d}", .{
        client.title[0..client.title_len],
        client.app_id[0..client.app_id_len],
        client.id,
    });
}

fn onPopupCommit(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup: *Popup = @fieldParentPtr("commit", listener.?);
    if (pBase(popup.xdg_popup).initial_commit) {
        _ = c.wlr_xdg_surface_schedule_configure(pBase(popup.xdg_popup));
    }
}

fn onPopupDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup: *Popup = @fieldParentPtr("destroy", listener.?);
    c.wl_list_remove(&popup.commit.link);
    c.wl_list_remove(&popup.destroy.link);
    c.free(popup);
}

fn onNewPopup(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const xdg_popup: *c.wlr_xdg_popup = @ptrCast(@alignCast(data.?));

    const popup = @as(*Popup, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Popup)).?)));
    popup.xdg_popup = xdg_popup;

    popup.commit.notify = onPopupCommit;
    c.wl_signal_add(&pSurface(xdg_popup).events.commit, &popup.commit);
    popup.destroy.notify = onPopupDestroy;
    c.wl_signal_add(&xdg_popup.events.destroy, &popup.destroy);

    const parent = c.wlr_xdg_surface_try_from_wlr_surface(@ptrCast(@alignCast(xdg_popup.parent)));
    if (parent) |p| {
        const parent_surface: *c.wlr_xdg_surface = @ptrCast(@alignCast(p));
        if (parent_surface.data) |raw| {
            const parent_tree: *c.wlr_scene_tree = @ptrCast(@alignCast(raw));
            pBase(xdg_popup).data = @ptrCast(c.wlr_scene_xdg_surface_create(parent_tree, pBase(xdg_popup)));
        }
    }
}
