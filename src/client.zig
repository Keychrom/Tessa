const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const effects = @import("effects.zig");
const scene_util = @import("scene_util.zig");
const rules = @import("rules.zig");
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
        server.xdg_decoration_manager = mgr;
        server.new_toplevel_decoration.notify = onNewToplevelDecoration;
        c.wl_signal_add(&mgr.events.new_toplevel_decoration, &server.new_toplevel_decoration);
    }

    const activation_raw = c.wlr_xdg_activation_v1_create(server.display);
    if (activation_raw != null) {
        const activation: *c.wlr_xdg_activation_v1 = @ptrCast(@alignCast(activation_raw));
        server.xdg_activation = activation;
        server.request_activate.notify = onActivationRequest;
        c.wl_signal_add(&activation.events.request_activate, &server.request_activate);
    }

    const foreign_raw = c.wlr_foreign_toplevel_manager_v1_create(server.display);
    if (foreign_raw != null) {
        server.foreign_toplevel_manager = @ptrCast(@alignCast(foreign_raw));
        core.logInfo("foreign-toplevel-management enabled", .{});
    }

    const ext_foreign_raw = c.wlr_ext_foreign_toplevel_list_v1_create(server.display, 1);
    if (ext_foreign_raw != null) {
        server.ext_foreign_toplevel_list = @ptrCast(@alignCast(ext_foreign_raw));
        core.logInfo("ext-foreign-toplevel-list enabled", .{});
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
    if (client.foreign_toplevel) |handle| {
        c.wlr_foreign_toplevel_handle_v1_set_title(handle, @ptrCast(&client.title));
        c.wlr_foreign_toplevel_handle_v1_set_app_id(handle, @ptrCast(&client.app_id));
    }
    if (client.ext_foreign_toplevel) |handle| {
        var state = c.struct_wlr_ext_foreign_toplevel_handle_v1_state{
            .title = @ptrCast(&client.title),
            .app_id = @ptrCast(&client.app_id),
        };
        c.wlr_ext_foreign_toplevel_handle_v1_update_state(handle, &state);
    }
}

fn onForeignActivate(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = listener;
    const event: *c.wlr_foreign_toplevel_handle_v1_activated_event = @ptrCast(@alignCast(data.?));
    const handle: *c.wlr_foreign_toplevel_handle_v1 = @ptrCast(@alignCast(event.toplevel));
    const client: *Client = @ptrCast(@alignCast(handle.data.?));
    if (!client.mapped) return;
    if (client.ws != client.output.active_ws) {
        layout.switchWorkspaceOnOutput(client.server, client.output, client.ws);
    }
    layout.focusClient(client.server, client);
}

fn onForeignClose(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("foreign_close", listener.?);
    effects.requestClose(client.server, client);
}

fn onForeignFullscreen(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const client: *Client = @fieldParentPtr("foreign_fullscreen", listener.?);
    const event: *c.wlr_foreign_toplevel_handle_v1_fullscreen_event = @ptrCast(@alignCast(data.?));
    client.fullscreen = event.fullscreen;
    _ = c.wlr_xdg_toplevel_set_fullscreen(client.xdg, client.fullscreen);
    if (client.foreign_toplevel) |handle| {
        c.wlr_foreign_toplevel_handle_v1_set_fullscreen(handle, client.fullscreen);
    }
    layout.arrangeOutput(client.server, client.output);
    core.markDirty(client.server);
}

fn onForeignDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const client: *Client = @fieldParentPtr("foreign_destroy", listener.?);
    c.wl_list_remove(&client.foreign_activate.link);
    c.wl_list_remove(&client.foreign_close.link);
    c.wl_list_remove(&client.foreign_fullscreen.link);
    c.wl_list_remove(&client.foreign_destroy.link);
    client.foreign_toplevel = null;
}

fn createForeignToplevel(client: *Client) void {
    const manager = client.server.foreign_toplevel_manager orelse return;
    const handle_raw = c.wlr_foreign_toplevel_handle_v1_create(manager);
    if (handle_raw == null) return;
    const handle: *c.wlr_foreign_toplevel_handle_v1 = @ptrCast(@alignCast(handle_raw));
    client.foreign_toplevel = handle;
    handle.data = @ptrCast(client);
    client.foreign_activate.notify = onForeignActivate;
    c.wl_signal_add(&handle.events.request_activate, &client.foreign_activate);
    client.foreign_close.notify = onForeignClose;
    c.wl_signal_add(&handle.events.request_close, &client.foreign_close);
    client.foreign_fullscreen.notify = onForeignFullscreen;
    c.wl_signal_add(&handle.events.request_fullscreen, &client.foreign_fullscreen);
    client.foreign_destroy.notify = onForeignDestroy;
    c.wl_signal_add(&handle.events.destroy, &client.foreign_destroy);
    c.wlr_foreign_toplevel_handle_v1_set_title(handle, @ptrCast(&client.title));
    c.wlr_foreign_toplevel_handle_v1_set_app_id(handle, @ptrCast(&client.app_id));
    c.wlr_foreign_toplevel_handle_v1_output_enter(handle, client.output.wlr);
}

fn createExtForeignToplevel(client: *Client) void {
    const list = client.server.ext_foreign_toplevel_list orelse return;
    var state = c.struct_wlr_ext_foreign_toplevel_handle_v1_state{
        .title = @ptrCast(&client.title),
        .app_id = @ptrCast(&client.app_id),
    };
    const handle_raw = c.wlr_ext_foreign_toplevel_handle_v1_create(list, &state);
    if (handle_raw == null) return;
    client.ext_foreign_toplevel = @ptrCast(@alignCast(handle_raw));
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
    rules.applyToClient(client);
    layout.startOpenAnimation(client);
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
    effects.clientUnmapped(client);

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
    effects.discardSnapshot(client);
    if (was_focused) server.focused = null;
    clearLastFocused(server, client);

    if (core.clientIndex(server, client)) |idx| {
        core.removeAt(types.Client, server.clients[0..], &server.client_count, idx);
    }

    if (client.foreign_toplevel) |handle| {
        c.wl_list_remove(&client.foreign_activate.link);
        c.wl_list_remove(&client.foreign_close.link);
        c.wl_list_remove(&client.foreign_fullscreen.link);
        c.wl_list_remove(&client.foreign_destroy.link);
        client.foreign_toplevel = null;
        c.wlr_foreign_toplevel_handle_v1_destroy(handle);
    }
    if (client.ext_foreign_toplevel) |handle| {
        client.ext_foreign_toplevel = null;
        c.wlr_ext_foreign_toplevel_handle_v1_destroy(handle);
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
    if (client.foreign_toplevel) |handle| {
        c.wlr_foreign_toplevel_handle_v1_set_fullscreen(handle, client.fullscreen);
    }
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

    const shadow_alphas = [3]f32{ 0.045, 0.055, 0.070 };
    var si: usize = 0;
    while (si < client.shadow_rects.len) : (si += 1) {
        const col = [4]f32{ 0, 0, 0, shadow_alphas[si] };
        client.shadow_rects[si] = c.wlr_scene_rect_create(client.frame, 1, 1, &col);
    }

    const inactive_rgb = if (server.config.border_inactive_len > 0)
        server.config.border_inactive_rgb
    else
        [3]f32{ 0.16, 0.20, 0.28 };
    const inactive = [4]f32{ inactive_rgb[0], inactive_rgb[1], inactive_rgb[2], 1.0 };
    client.border_rect = c.wlr_scene_rect_create(client.frame, 1, 1, &inactive);

    client.surface_tree = c.wlr_scene_xdg_surface_create(client.frame, tBase(xdg));
    client.content_buffer = scene_util.surfaceBuffer(client.surface_tree, tSurface(xdg));
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
    createForeignToplevel(client);
    createExtForeignToplevel(client);

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
