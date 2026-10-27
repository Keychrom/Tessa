const build_options = @import("build_options");
const c = @import("c.zig").c;
const types = @import("types.zig");
const scene_util = @import("scene_util.zig");

const Server = types.Server;
const Client = types.Client;

const enabled = build_options.scenefx;

pub fn available() bool {
    return enabled;
}

pub fn configure(server: *Server) void {
    if (comptime enabled) configureImpl(server);
}

var blur_probe_created = false;

fn configureImpl(server: *Server) void {
    const cfg = &server.config;
    c.wlr_scene_set_blur_data(
        server.scene,
        @intCast(cfg.blur_passes),
        @intCast(cfg.blur_radius),
        0.0,
        1.0,
        1.0,
        1.0,
    );
    if (!blur_probe_created) {
        // scenefx logs a fallback warning on every blur unless its optimized
        // blur framebuffer has been allocated once. A 1x1 node is invisible
        // but primes that shared buffer for the regular blur path.
        const probe = c.wlr_scene_optimized_blur_create(&server.scene.tree, 1, 1);
        if (probe != null) {
            c.wlr_scene_optimized_blur_mark_dirty(probe);
            blur_probe_created = true;
        }
    }
}

pub fn applyClient(client: *Client, border_enabled: bool) void {
    if (comptime enabled) applyClientImpl(client, border_enabled);
}

fn applyClientImpl(client: *Client, border_enabled: bool) void {
    const cfg = &client.server.config;
    const bw: i32 = if (border_enabled) cfg.border_width else 0;
    const max_radius = @divTrunc(@max(1, @min(client.w, client.h)), 2);
    const radius: c_int = if (client.fullscreen or !border_enabled)
        0
    else
        @min(cfg.corner_radius, max_radius);
    const content_max = @divTrunc(@max(1, @min(client.w - bw * 2, client.h - bw * 2)), 2);
    const content_radius: c_int = @min(radius, @max(0, content_max));
    const border_radius: c_int = if (radius > 0) @min(radius + bw, max_radius) else 0;

    if (client.content_buffer == null) {
        const base: *c.wlr_xdg_surface = @ptrCast(@alignCast(client.xdg.base));
        const surface: *c.wlr_surface = @ptrCast(@alignCast(base.surface));
        client.content_buffer = scene_util.surfaceBuffer(client.surface_tree, surface);
    }
    if (client.content_buffer) |buffer| {
        c.wlr_scene_buffer_set_corner_radius(buffer, content_radius, c.CORNER_LOCATION_ALL);
        c.wlr_scene_buffer_set_backdrop_blur(buffer, cfg.blur);
        c.wlr_scene_buffer_set_backdrop_blur_optimized(buffer, false);
        c.wlr_scene_buffer_set_backdrop_blur_ignore_transparent(buffer, true);
    }
    c.wlr_scene_rect_set_corner_radius(client.border_rect, border_radius, c.CORNER_LOCATION_ALL);

    var i: usize = 0;
    while (i < client.shadow_rects.len) : (i += 1) {
        const rect = client.shadow_rects[i] orelse continue;
        c.wlr_scene_rect_set_corner_radius(
            rect,
            if (radius > 0) @min(radius + 6, max_radius + 6) else 0,
            c.CORNER_LOCATION_ALL,
        );
    }
}

fn layerBlurCallback(buffer_raw: [*c]c.wlr_scene_buffer, sx: c_int, sy: c_int, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const state: *const struct { enabled: bool } = @ptrCast(@alignCast(data.?));
    const buffer: *c.wlr_scene_buffer = @ptrCast(@alignCast(buffer_raw));
    c.wlr_scene_buffer_set_backdrop_blur(buffer, state.enabled);
    c.wlr_scene_buffer_set_backdrop_blur_optimized(buffer, false);
    c.wlr_scene_buffer_set_backdrop_blur_ignore_transparent(buffer, true);
}

fn applyLayersImpl(server: *Server) void {
    var state = .{ .enabled = server.config.blur };
    const trees = [_]*c.wlr_scene_tree{
        server.tree_top,
        server.tree_overlay,
        server.tree_popup,
    };
    for (trees) |tree| {
        c.wlr_scene_node_for_each_buffer(&tree.node, layerBlurCallback, &state);
    }
}

pub fn applyLayers(server: *Server) void {
    if (comptime enabled) applyLayersImpl(server);
}

pub fn applyCloseContent(buffer: *c.wlr_scene_buffer, radius: i32) void {
    if (comptime enabled) {
        c.wlr_scene_buffer_set_corner_radius(buffer, @max(0, radius), c.CORNER_LOCATION_ALL);
    }
}

pub fn applyAll(server: *Server) void {
    if (comptime !enabled) return;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (!client.mapped) continue;
        applyClientImpl(client, !client.fullscreen);
    }
    applyLayersImpl(server);
}

pub fn reload(server: *Server) void {
    if (comptime !enabled) return;
    configureImpl(server);
    applyAll(server);
}
