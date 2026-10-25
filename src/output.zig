const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");

const Server = types.Server;
const Output = types.Output;
const LayerSurface = types.LayerSurface;

fn lSurface(ls: *c.wlr_layer_surface_v1) *c.wlr_surface {
    return @ptrCast(@alignCast(ls.surface));
}
fn lTree(sl: *c.wlr_scene_layer_surface_v1) *c.wlr_scene_tree {
    return @ptrCast(@alignCast(sl.tree));
}

pub fn init(server: *Server) void {
    server.new_output.notify = onNewOutput;
    c.wl_signal_add(&server.backend.events.new_output, &server.new_output);

    server.new_layer_surface.notify = onNewLayerSurface;
    c.wl_signal_add(&server.layer_shell.events.new_surface, &server.new_layer_surface);
}

fn layerTree(server: *Server, layer: anytype) *c.wlr_scene_tree {
    const n: u32 = @intCast(layer);
    if (n == 0) return server.tree_bg;
    if (n == 1) return server.tree_bottom;
    if (n == 2) return server.tree_top;
    return server.tree_overlay;
}

fn findOutput(server: *Server, wlr: *c.wlr_output) ?*Output {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |out| {
            if (out.wlr == wlr) return out;
        }
    }
    return null;
}

pub fn arrangeLayers(out: *Output) void {
    const server = out.server;
    var full: c.wlr_box = undefined;
    core.outputBox(server, out, &full);
    var usable = full;

    const layers = [_]u32{ 3, 2, 1, 0 };

    var pass: usize = 0;
    while (pass < 2) : (pass += 1) {
        const want_exclusive = pass == 0;
        for (layers) |layer| {
            var i: usize = 0;
            while (i < server.layers.len) : (i += 1) {
                const ls = server.layers[i] orelse continue;
                if (ls.output != out) continue;
                if (!ls.wlr.initialized) continue;
                if (@as(u32, @intCast(ls.wlr.current.layer)) != layer) continue;
                const is_exclusive = ls.wlr.current.exclusive_zone > 0;
                if (is_exclusive != want_exclusive) continue;
                c.wlr_scene_layer_surface_v1_configure(ls.scene_layer, &full, &usable);
            }
        }
    }

    if (usable.x != out.usable.x or usable.y != out.usable.y or
        usable.width != out.usable.width or usable.height != out.usable.height)
    {
        out.usable = usable;
        layout.arrangeOutput(server, out);
        core.markDirty(server);
    }
}

fn onOutputFrame(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const out: *Output = @fieldParentPtr("frame", listener.?);
    const so = c.wlr_scene_get_scene_output(out.server.scene, out.wlr) orelse return;
    _ = c.wlr_scene_output_commit(so, null);
    var now: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    c.wlr_scene_output_send_frame_done(so, &now);
}

fn onOutputRequestState(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const out: *Output = @fieldParentPtr("request_state", listener.?);
    const event: *c.wlr_output_event_request_state = @ptrCast(@alignCast(data.?));
    _ = c.wlr_output_commit_state(out.wlr, event.state);
}

fn onOutputDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const out: *Output = @fieldParentPtr("destroy", listener.?);
    const server = out.server;

    c.wl_list_remove(&out.frame.link);
    c.wl_list_remove(&out.request_state.link);
    c.wl_list_remove(&out.destroy.link);
    c.wlr_scene_node_destroy(&out.bg_rect.node);

    const idx = core.outputIndexOf(server, out) orelse {
        c.free(out);
        return;
    };

    if (server.output_count <= 1) {
        core.logInfo("last output disappeared, terminating", .{});
        c.wl_display_terminate(server.display);
        return;
    }

    core.removeAt(types.Output, server.outputs[0..], &server.output_count, idx);

    var fallback: ?*Output = null;
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |o| {
            fallback = o;
            break;
        }
    }
    if (fallback) |fb| {
        var k: usize = 0;
        while (k < server.clients.len) : (k += 1) {
            const cl = server.clients[k] orelse continue;
            if (cl.output == out) {
                cl.output = fb;
                cl.float_x = fb.full.x;
                cl.float_y = fb.full.y;
            }
        }
    }

    core.logInfo("output removed: {s}", .{core.cstr(out.wlr.name)});
    c.free(out);
    layout.arrangeAll(server);
    core.markDirty(server);
}

fn onNewOutput(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_output", listener.?);
    const wlr_out: *c.wlr_output = @ptrCast(@alignCast(data.?));

    if (!c.wlr_output_init_render(wlr_out, server.allocator, server.renderer)) {
        core.logInfo("failed to init render for output {s}", .{core.cstr(wlr_out.name)});
        return;
    }

    var state: c.wlr_output_state = undefined;
    c.wlr_output_state_init(&state);
    c.wlr_output_state_set_enabled(&state, true);
    c.wlr_output_state_set_scale(&state, 1.0);
    if (c.wlr_output_is_headless(wlr_out)) {
        c.wlr_output_state_set_custom_mode(&state, 1920, 1080, 60000);
    } else if (c.wlr_output_preferred_mode(wlr_out)) |mode| {
        c.wlr_output_state_set_mode(&state, mode);
    }
    if (!c.wlr_output_commit_state(wlr_out, &state)) {
        core.logInfo("failed to commit initial state for output {s}", .{core.cstr(wlr_out.name)});
    }
    c.wlr_output_state_finish(&state);

    const out = @as(*Output, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Output)).?)));
    out.server = server;
    out.wlr = wlr_out;

    out.frame.notify = onOutputFrame;
    c.wl_signal_add(&wlr_out.events.frame, &out.frame);
    out.request_state.notify = onOutputRequestState;
    c.wl_signal_add(&wlr_out.events.request_state, &out.request_state);
    out.destroy.notify = onOutputDestroy;
    c.wl_signal_add(&wlr_out.events.destroy, &out.destroy);

    out.layout_output = c.wlr_output_layout_add_auto(server.output_layout, wlr_out);
    out.scene_output = c.wlr_scene_output_create(server.scene, wlr_out);
    c.wlr_scene_output_layout_add_output(server.scene_layout, out.layout_output, out.scene_output);

    const bg = [4]f32{ 0.025, 0.04, 0.075, 1.0 };
    out.bg_rect = c.wlr_scene_rect_create(server.tree_bg, 1, 1, &bg);

    core.outputBox(server, out, &out.full);
    out.usable = out.full;
    core.updateBackground(out);

    if (server.output_count < server.outputs.len) {
        server.outputs[server.output_count] = out;
        server.output_count += 1;
    } else {
        core.logInfo("too many outputs, ignoring {s}", .{core.cstr(wlr_out.name)});
        c.free(out);
        return;
    }

    core.logInfo("output added: {s} {d}x{d} @ {d},{d}", .{
        core.cstr(wlr_out.name),
        out.full.width,
        out.full.height,
        out.full.x,
        out.full.y,
    });

    arrangeLayers(out);
    layout.arrangeAll(server);
    core.markDirty(server);
}

fn onLayerCommit(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LayerSurface = @fieldParentPtr("commit", listener.?);

    if (ls.wlr.initialized) {
        const target = layerTree(ls.server, ls.wlr.current.layer);
        const tree = lTree(ls.scene_layer);
        const parent: ?*c.wlr_scene_tree = if (tree.node.parent) |p|
            @ptrCast(@alignCast(p))
        else
            null;
        if (parent != target) {
            c.wlr_scene_node_reparent(&tree.node, target);
        }
    }

    if (ls.wlr.initial_commit or ls.wlr.current.committed != 0 or
        lSurface(ls.wlr).mapped != ls.mapped)
    {
        arrangeLayers(ls.output);
    }
}

fn onLayerMap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LayerSurface = @fieldParentPtr("map", listener.?);
    ls.mapped = true;

    const interactive: u32 = @intCast(ls.wlr.current.keyboard_interactive);
    const layer_n: u32 = @intCast(ls.wlr.current.layer);
    core.logInfo("layer map: {s} layer={d} keyboard={d}", .{
        core.cstr(ls.wlr.namespace),
        layer_n,
        interactive,
    });
    if (interactive != 0 and layer_n >= 2) {
        layout.focusLayer(ls.server, ls);
    }

    arrangeLayers(ls.output);
    core.markDirty(ls.server);
}

fn onLayerUnmap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LayerSurface = @fieldParentPtr("unmap", listener.?);
    ls.mapped = false;
    layout.restoreFocusAfterLayer(ls.server, ls);
    arrangeLayers(ls.output);
    core.markDirty(ls.server);
}

fn onLayerDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LayerSurface = @fieldParentPtr("destroy", listener.?);
    const server = ls.server;
    const out = ls.output;

    c.wl_list_remove(&ls.commit.link);
    c.wl_list_remove(&ls.map.link);
    c.wl_list_remove(&ls.unmap.link);
    c.wl_list_remove(&ls.destroy.link);

    if (server.focused_layer == ls) {
        server.focused_layer = null;
    }

    if (core.layerIndexOf(server, ls)) |idx| {
        core.removeAt(types.LayerSurface, server.layers[0..], &server.layer_count, idx);
    }

    arrangeLayers(out);
    core.markDirty(server);
    c.free(ls);
}

fn onNewLayerSurface(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_layer_surface", listener.?);
    const wlr_ls: *c.wlr_layer_surface_v1 = @ptrCast(@alignCast(data.?));

    var out: ?*Output = null;
    if (wlr_ls.output) |wlr_out| {
        out = findOutput(server, wlr_out);
    }
    if (out == null) out = core.focusedOutput(server);
    if (out == null) out = core.firstOutput(server);
    if (out == null) {
        c.wlr_layer_surface_v1_destroy(wlr_ls);
        return;
    }

    wlr_ls.output = out.?.wlr;

    const scene_layer_raw = c.wlr_scene_layer_surface_v1_create(
        layerTree(server, wlr_ls.current.layer),
        wlr_ls,
    ) orelse {
        c.wlr_layer_surface_v1_destroy(wlr_ls);
        return;
    };
    const scene_layer: *c.wlr_scene_layer_surface_v1 = @ptrCast(@alignCast(scene_layer_raw));

    const ls = @as(*LayerSurface, @ptrCast(@alignCast(c.calloc(1, @sizeOf(LayerSurface)).?)));
    ls.server = server;
    ls.wlr = wlr_ls;
    ls.scene_layer = scene_layer;
    ls.output = out.?;
    ls.mapped = false;

    ls.commit.notify = onLayerCommit;
    c.wl_signal_add(&lSurface(wlr_ls).events.commit, &ls.commit);
    ls.map.notify = onLayerMap;
    c.wl_signal_add(&lSurface(wlr_ls).events.map, &ls.map);
    ls.unmap.notify = onLayerUnmap;
    c.wl_signal_add(&lSurface(wlr_ls).events.unmap, &ls.unmap);
    ls.destroy.notify = onLayerDestroy;
    c.wl_signal_add(&wlr_ls.events.destroy, &ls.destroy);

    if (server.layer_count < server.layers.len) {
        server.layers[server.layer_count] = ls;
        server.layer_count += 1;
    } else {
        c.wlr_layer_surface_v1_destroy(wlr_ls);
        return;
    }

    core.logInfo("layer surface: {s} layer={d}", .{
        core.cstr(wlr_ls.namespace),
        @as(u32, @intCast(wlr_ls.current.layer)),
    });
}
