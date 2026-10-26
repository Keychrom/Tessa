const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");

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

    const deco_mgr_raw = c.wlr_xdg_decoration_manager_v1_create(server.display);
    if (deco_mgr_raw != null) {
        const mgr: *c.wlr_xdg_decoration_manager_v1 = @ptrCast(@alignCast(deco_mgr_raw));
        server.new_toplevel_decoration.notify = onNewToplevelDecoration;
        c.wl_signal_add(&mgr.events.new_toplevel_decoration, &server.new_toplevel_decoration);
    }

    const activation_raw = c.wlr_xdg_activation_v1_create(server.display);
    if (activation_raw != null) {
        const activation: *c.wlr_xdg_activation_v1 = @ptrCast(@alignCast(activation_raw));
        server.request_activate.notify = onActivationRequest;
        c.wl_signal_add(&activation.events.request_activate, &server.request_activate);
    }
}

fn onActivationRequest(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_activate", listener.?);
    const event: *c.wlr_xdg_activation_v1_request_activate_event = @ptrCast(@alignCast(data.?));
    if (event.surface == null) return;
    const surface: *c.wlr_surface = @ptrCast(@alignCast(event.surface));

    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (tSurface(cl.xdg) != surface) continue;
        if (!cl.mapped) return;
        if (cl.ws != cl.output.active_ws) {
            layout.switchWorkspaceOnOutput(server, cl.output, cl.ws);
        }
        layout.focusClient(server, cl);
        return;
    }
}

fn onNewToplevelDecoration(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const deco: *c.wlr_xdg_toplevel_decoration_v1 = @ptrCast(@alignCast(data.?));

    const state = @as(*Decoration, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Decoration)).?)));
    state.deco = deco;
    state.request_mode.notify = onDecorationRequestMode;
    c.wl_signal_add(&deco.events.request_mode, &state.request_mode);
    state.destroy.notify = onDecorationDestroy;
    c.wl_signal_add(&deco.events.destroy, &state.destroy);

    applyDecorationMode(deco);
}

const Decoration = struct {
    deco: *c.wlr_xdg_toplevel_decoration_v1,
    request_mode: c.wl_listener,
    destroy: c.wl_listener,
};

fn applyDecorationMode(deco: *c.wlr_xdg_toplevel_decoration_v1) void {
    const toplevel: *c.wlr_xdg_toplevel = @ptrCast(@alignCast(deco.toplevel));
    const base: *c.wlr_xdg_surface = @ptrCast(@alignCast(toplevel.base));
    if (base.initialized) {
        _ = c.wlr_xdg_toplevel_decoration_v1_set_mode(
            deco,
            c.WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE,
        );
    } else {
        deco.scheduled_mode = @intCast(c.WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
    }
}

fn onDecorationRequestMode(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const state: *Decoration = @fieldParentPtr("request_mode", listener.?);
    applyDecorationMode(state.deco);
}

fn onDecorationDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const state: *Decoration = @fieldParentPtr("destroy", listener.?);
    c.wl_list_remove(&state.request_mode.link);
    c.wl_list_remove(&state.destroy.link);
    c.free(state);
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
        if (cl != exclude and cl.mapped and cl.output == exclude.output and
            cl.ws == cl.output.active_ws) return cl;
    }
    return null;
}

fn clearLastFocused(server: *Server, client: *Client) void {
    _ = server;
    var i: usize = 0;
    while (i < client.output.last_focused.len) : (i += 1) {
        if (client.output.last_focused[i] == client) client.output.last_focused[i] = null;
    }
}

fn onMap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("map", listener.?);
    client.mapped = true;
    client.announced = true;
    copyMeta(client);
    layout.arrangeAll(client.server);
    events.emit(client.server, .{
        .name = event_names.window_open,
        .id = client.id,
        .workspace = client.ws,
        .app_id = client.app_id[0..client.app_id_len],
        .title = client.title[0..client.title_len],
        .output = core.outputName(client.output),
    });
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

    if (client.announced) {
        events.emit(server, .{
            .name = event_names.window_close,
            .id = client.id,
            .workspace = client.ws,
            .app_id = client.app_id[0..client.app_id_len],
            .title = client.title[0..client.title_len],
            .output = core.outputName(client.output),
        });
        client.announced = false;
    }

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
            if (cl.mapped and cl.output == client.output and cl.ws == cl.output.active_ws) {
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

    const out = core.focusOutput(server) orelse {
        c.wlr_xdg_toplevel_send_close(xdg);
        return;
    };

    const client = @as(*Client, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Client)).?)));
    client.server = server;
    client.xdg = xdg;
    client.output = out;
    client.ws = out.active_ws;
    client.mapped = false;
    client.announced = false;
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

fn layerSurfaceTree(server: *Server, surface: *c.wlr_surface) ?*c.wlr_scene_tree {
    var i: usize = 0;
    while (i < server.layers.len) : (i += 1) {
        const layer = server.layers[i] orelse continue;
        const layer_surface: *c.wlr_surface = @ptrCast(@alignCast(layer.wlr.surface));
        if (layer_surface == surface) {
            return @ptrCast(@alignCast(layer.scene_layer.tree));
        }
    }
    return null;
}

fn onNewPopup(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_xdg_popup", listener.?);
    const xdg_popup: *c.wlr_xdg_popup = @ptrCast(@alignCast(data.?));

    const popup = @as(*Popup, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Popup)).?)));
    popup.xdg_popup = xdg_popup;

    popup.commit.notify = onPopupCommit;
    c.wl_signal_add(&pSurface(xdg_popup).events.commit, &popup.commit);
    popup.destroy.notify = onPopupDestroy;
    c.wl_signal_add(&xdg_popup.events.destroy, &popup.destroy);

    if (xdg_popup.parent == null) return;
    const parent_surface: *c.wlr_surface = @ptrCast(@alignCast(xdg_popup.parent));
    var parent_tree: ?*c.wlr_scene_tree = null;
    const parent = c.wlr_xdg_surface_try_from_wlr_surface(parent_surface);
    if (parent) |p| {
        const parent_xdg: *c.wlr_xdg_surface = @ptrCast(@alignCast(p));
        if (parent_xdg.data) |raw| {
            parent_tree = @ptrCast(@alignCast(raw));
        }
    } else {
        parent_tree = layerSurfaceTree(server, parent_surface);
    }

    if (parent_tree) |tree| {
        pBase(xdg_popup).data = @ptrCast(c.wlr_scene_xdg_surface_create(tree, pBase(xdg_popup)));
    }
}
