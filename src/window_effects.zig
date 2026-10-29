const build_options = @import("build_options");
const c = @import("c.zig").c;
const types = @import("types.zig");
const scene_util = @import("scene_util.zig");
const rules = @import("rules.zig");

const Server = types.Server;
const Client = types.Client;
const LayerSurface = types.LayerSurface;

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

fn clientBlur(client: *Client) bool {
    return switch (types.effectiveClientBlur(client)) {
        .on => true,
        .off => false,
        .unset => client.server.config.blur,
    };
}

fn ensureContentBuffer(client: *Client) ?*c.wlr_scene_buffer {
    if (client.content_buffer == null) {
        const base: *c.wlr_xdg_surface = @ptrCast(@alignCast(client.xdg.base));
        const surface: *c.wlr_surface = @ptrCast(@alignCast(base.surface));
        client.content_buffer = scene_util.surfaceBuffer(client.surface_tree, surface);
    }
    return client.content_buffer;
}

pub fn applyClient(client: *Client, border_enabled: bool) void {
    if (ensureContentBuffer(client)) |buffer| {
        c.wlr_scene_buffer_set_opacity(buffer, types.effectiveClientOpacity(client));
    }
    if (comptime enabled) applyClientImpl(client, border_enabled);
}

fn applyClientImpl(client: *Client, border_enabled: bool) void {
    const cfg = &client.server.config;
    const configured_bw = types.effectiveClientBorderWidth(client);
    const bw: i32 = if (!border_enabled)
        0
    else if (configured_bw >= 0)
        configured_bw
    else
        cfg.border_width;
    const configured_radius = types.effectiveClientRadius(client);
    const base_radius = if (configured_radius >= 0) configured_radius else cfg.corner_radius;
    const max_radius = @divTrunc(@max(1, @min(client.w, client.h)), 2);
    const radius: c_int = if (client.fullscreen or !border_enabled)
        0
    else
        @min(base_radius, max_radius);
    const content_max = @divTrunc(@max(1, @min(client.w - bw * 2, client.h - bw * 2)), 2);
    const content_radius: c_int = @min(radius, @max(0, content_max));
    const border_radius: c_int = if (radius > 0) @min(radius + bw, max_radius) else 0;

    if (ensureContentBuffer(client)) |buffer| {
        c.wlr_scene_buffer_set_corner_radius(buffer, content_radius, c.CORNER_LOCATION_ALL);
        c.wlr_scene_buffer_set_backdrop_blur(buffer, clientBlur(client));
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

const LayerState = struct {
    opacity: f32,
    blur: bool,
    radius: i32,
};

fn layerBufferCallback(buffer_raw: [*c]c.wlr_scene_buffer, sx: c_int, sy: c_int, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const state: *const LayerState = @ptrCast(@alignCast(data.?));
    const buffer: *c.wlr_scene_buffer = @ptrCast(@alignCast(buffer_raw));
    c.wlr_scene_buffer_set_opacity(buffer, state.opacity);
    if (comptime enabled) {
        c.wlr_scene_buffer_set_corner_radius(buffer, state.radius, c.CORNER_LOCATION_ALL);
        c.wlr_scene_buffer_set_backdrop_blur(buffer, state.blur);
        c.wlr_scene_buffer_set_backdrop_blur_optimized(buffer, false);
        c.wlr_scene_buffer_set_backdrop_blur_ignore_transparent(buffer, true);
    }
}

pub fn applyLayer(server: *Server, layer: *LayerSurface) void {
    const cfg = &server.config;
    const layer_n: u32 = @intCast(layer.wlr.current.layer);
    const blur = switch (layer.blur) {
        .on => true,
        .off => false,
        .unset => cfg.blur and layer_n >= 2,
    };
    var state = LayerState{
        .opacity = layer.opacity,
        .blur = blur,
        .radius = layer.corner_radius,
    };
    const tree = layerTree(layer);
    c.wlr_scene_node_for_each_buffer(&tree.node, layerBufferCallback, &state);
}

fn layerTree(layer: *LayerSurface) *c.wlr_scene_tree {
    return @ptrCast(@alignCast(layer.scene_layer.tree));
}

fn legacyBlurCallback(buffer_raw: [*c]c.wlr_scene_buffer, sx: c_int, sy: c_int, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const state: *const struct { enabled: bool } = @ptrCast(@alignCast(data.?));
    const buffer: *c.wlr_scene_buffer = @ptrCast(@alignCast(buffer_raw));
    c.wlr_scene_buffer_set_backdrop_blur(buffer, state.enabled);
    c.wlr_scene_buffer_set_backdrop_blur_optimized(buffer, false);
    c.wlr_scene_buffer_set_backdrop_blur_ignore_transparent(buffer, true);
}

fn applyLegacyTopBlur(server: *Server) void {
    var state = .{ .enabled = server.config.blur };
    const trees = [_]*c.wlr_scene_tree{
        server.tree_top,
        server.tree_overlay,
        server.tree_popup,
    };
    for (trees) |tree| {
        c.wlr_scene_node_for_each_buffer(&tree.node, legacyBlurCallback, &state);
    }
}

pub fn applyLayers(server: *Server) void {
    // Preserve global blur on non-layer nodes such as IME popups, then let
    // per-layer rules override the layer surfaces.
    if (comptime enabled) applyLegacyTopBlur(server);
    var i: usize = 0;
    while (i < server.layers.len) : (i += 1) {
        const layer = server.layers[i] orelse continue;
        applyLayer(server, layer);
    }
}

pub fn applyCloseContent(buffer: *c.wlr_scene_buffer, radius: i32) void {
    if (comptime enabled) {
        c.wlr_scene_buffer_set_corner_radius(buffer, @max(0, radius), c.CORNER_LOCATION_ALL);
    }
}

pub fn applyAll(server: *Server) void {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (!client.mapped) continue;
        applyClient(client, !client.fullscreen);
    }
    applyLayers(server);
}

pub fn reload(server: *Server) void {
    if (comptime enabled) configureImpl(server);
    rules.applyAllLayers(server);
    applyAll(server);
}
