const std = @import("std");
const build_options = @import("build_options");
const c = @import("c.zig").c;
const types = @import("types.zig");
const scene_util = @import("scene_util.zig");
const rules = @import("rules.zig");

const Server = types.Server;
const Client = types.Client;
const LayerSurface = types.LayerSurface;
const ImPopup = types.ImPopup;

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
            // The probe only exists to allocate the shared blur buffer. It
            // must not add a render-list entry above fullscreen clients.
            c.wlr_scene_node_set_enabled(&@as(*c.wlr_scene_blur, @ptrCast(@alignCast(probe))).node, false);
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

fn ensureClientBlur(client: *Client) ?*c.wlr_scene_blur {
    if (client.blur_node) |node| return @ptrCast(@alignCast(node));
    const blur_raw = c.wlr_scene_blur_create(client.frame, 1, 1);
    if (blur_raw == null) return null;
    const blur: *c.wlr_scene_blur = @ptrCast(@alignCast(blur_raw));
    client.blur_node = &blur.node;
    client.server.perf.blur_nodes += 1;
    // The blur samples everything below it in the scene graph. Keep it below
    // the window's own border, shadow, and content.
    c.wlr_scene_node_lower_to_bottom(&blur.node);
    return blur;
}

pub fn applyClient(client: *Client, border_enabled: bool) void {
    if (ensureContentBuffer(client)) |buffer| {
        c.wlr_scene_buffer_set_opacity(buffer, types.effectiveClientOpacity(client));
    }
    applyTint(client, border_enabled);
    if (comptime enabled) applyClientImpl(client, border_enabled);
}

fn applyTint(client: *Client, border_enabled: bool) void {
    const configured_bw = types.effectiveClientBorderWidth(client);
    const bw: i32 = if (!border_enabled)
        0
    else if (configured_bw >= 0)
        configured_bw
    else
        client.server.config.border_width;
    const tint = types.effectiveClientTint(client);
    const visible = tint[3] > 0.001 and client.w > bw * 2 and client.h > bw * 2;
    c.wlr_scene_node_set_enabled(&client.tint_rect.node, visible);
    if (!visible) return;
    const w = @max(1, client.w - bw * 2);
    const h = @max(1, client.h - bw * 2);
    c.wlr_scene_rect_set_size(client.tint_rect, w, h);
    c.wlr_scene_node_set_position(&client.tint_rect.node, bw, bw);
    c.wlr_scene_rect_set_color(client.tint_rect, &tint);
    if (comptime enabled) {
        const configured_radius = types.effectiveClientRadius(client);
        const base_radius = if (configured_radius >= 0) configured_radius else client.server.config.corner_radius;
        const max_radius = @divTrunc(@max(1, @min(client.w, client.h)), 2);
        const radius: c_int = if (client.fullscreen or !border_enabled) 0 else @min(base_radius, max_radius);
        c.wlr_scene_rect_set_corner_radius(client.tint_rect, @min(radius, @divTrunc(@max(1, @min(w, h)), 2)));
    }
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
    const content = ensureContentBuffer(client);
    const blur_on = clientBlur(client) and content != null;
    const opacity = types.effectiveClientOpacity(client);
    const tint = types.effectiveClientTint(client);

    if (client.applied_valid and
        client.applied_opacity == opacity and
        client.applied_radius == radius and
        client.applied_border_width == bw and
        std.meta.eql(client.applied_tint, tint) and
        client.applied_blur == blur_on and
        client.applied_w == client.w and
        client.applied_h == client.h and
        client.applied_buffer == content)
    {
        client.server.perf.effect_skips += 1;
        return;
    }

    if (content) |buffer| {
        c.wlr_scene_buffer_set_corner_radius(buffer, content_radius);
    }
    c.wlr_scene_rect_set_corner_radius(client.border_rect, border_radius);

    var i: usize = 0;
    while (i < client.shadow_rects.len) : (i += 1) {
        const rect = client.shadow_rects[i] orelse continue;
        c.wlr_scene_rect_set_corner_radius(
            rect,
            if (radius > 0) @min(radius + 6, max_radius + 6) else 0,
        );
    }

    if (ensureClientBlur(client)) |blur| {
        const bw_i = @max(0, bw);
        c.wlr_scene_blur_set_size(
            blur,
            @max(1, client.w - bw_i * 2),
            @max(1, client.h - bw_i * 2),
        );
        c.wlr_scene_node_set_position(&blur.node, bw_i, bw_i);
        c.wlr_scene_blur_set_corner_radius(blur, content_radius);
        // A blur node without a transparency mask would also blur the window's
        // own transparent regions, so only enable it once the content buffer
        // exists and per-client blur resolves to on.
        c.wlr_scene_node_set_enabled(&blur.node, blur_on);
        if (content) |buffer| {
            c.wlr_scene_blur_set_transparency_mask_source(blur, buffer);
        }
    }

    client.applied_opacity = opacity;
    client.applied_radius = radius;
    client.applied_border_width = bw;
    client.applied_tint = tint;
    client.applied_blur = blur_on;
    client.applied_w = client.w;
    client.applied_h = client.h;
    client.applied_buffer = content;
    client.applied_valid = true;
    client.server.perf.effect_applies += 1;
}

const LayerState = struct {
    opacity: f32,
    blur: bool,
    radius: i32,
    mask: ?*c.wlr_scene_buffer = null,
};

fn layerBufferCallback(buffer_raw: [*c]c.wlr_scene_buffer, sx: c_int, sy: c_int, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const state: *LayerState = @ptrCast(@alignCast(data.?));
    const buffer: *c.wlr_scene_buffer = @ptrCast(@alignCast(buffer_raw));
    c.wlr_scene_buffer_set_opacity(buffer, state.opacity);
    if (comptime enabled) {
        c.wlr_scene_buffer_set_corner_radius(buffer, state.radius);
        if (state.blur and state.mask == null) state.mask = buffer;
    }
}

fn ensureLayerBlur(layer: *LayerSurface) ?*c.wlr_scene_blur {
    if (layer.blur_node) |node| return @ptrCast(@alignCast(node));
    const blur_raw = c.wlr_scene_blur_create(layerTree(layer), 1, 1);
    if (blur_raw == null) return null;
    const blur: *c.wlr_scene_blur = @ptrCast(@alignCast(blur_raw));
    layer.blur_node = &blur.node;
    // Layer buffers and popups are appended above the blur node.
    c.wlr_scene_node_lower_to_bottom(&blur.node);
    return blur;
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

    if (comptime enabled) {
        if (ensureLayerBlur(layer)) |blur_node| {
            const surface: *c.wlr_surface = @ptrCast(@alignCast(layer.wlr.surface));
            const width = @max(1, @as(i32, @intCast(surface.current.width)));
            const height = @max(1, @as(i32, @intCast(surface.current.height)));
            c.wlr_scene_blur_set_size(blur_node, width, height);
            c.wlr_scene_blur_set_corner_radius(blur_node, state.radius);
            c.wlr_scene_node_set_enabled(&blur_node.node, state.blur and state.mask != null);
            // One node covers the primary layer buffer. XDG popups attached to
            // the layer keep their own buffers and are not blurred separately.
            if (state.mask) |mask| {
                c.wlr_scene_blur_set_transparency_mask_source(blur_node, mask);
            }
        }
    }
}

fn layerTree(layer: *LayerSurface) *c.wlr_scene_tree {
    return @ptrCast(@alignCast(layer.scene_layer.tree));
}

fn ensurePopupBlur(popup: *ImPopup) ?*c.wlr_scene_blur {
    if (popup.blur_node) |node| return @ptrCast(@alignCast(node));
    const blur_raw = c.wlr_scene_blur_create(popup.scene, 1, 1);
    if (blur_raw == null) return null;
    const blur: *c.wlr_scene_blur = @ptrCast(@alignCast(blur_raw));
    popup.blur_node = &blur.node;
    c.wlr_scene_node_lower_to_bottom(&blur.node);
    return blur;
}

const PopupMask = struct {
    buffer: ?*c.wlr_scene_buffer = null,
};

fn popupMaskCallback(buffer_raw: [*c]c.wlr_scene_buffer, sx: c_int, sy: c_int, data: ?*anyopaque) callconv(.c) void {
    _ = sx;
    _ = sy;
    const state: *PopupMask = @ptrCast(@alignCast(data.?));
    if (state.buffer == null) state.buffer = @ptrCast(@alignCast(buffer_raw));
}

fn applyImPopupImpl(popup: *ImPopup) void {
    if (popup.popup.surface == null) return;
    if (ensurePopupBlur(popup)) |blur| {
        const surface: *c.wlr_surface = @ptrCast(@alignCast(popup.popup.surface));
        var mask = PopupMask{};
        c.wlr_scene_node_for_each_buffer(&popup.scene.node, popupMaskCallback, &mask);
        c.wlr_scene_blur_set_size(
            blur,
            @max(1, @as(i32, @intCast(surface.current.width))),
            @max(1, @as(i32, @intCast(surface.current.height))),
        );
        c.wlr_scene_node_set_enabled(&blur.node, popup.server.config.blur and mask.buffer != null);
        if (mask.buffer) |buffer| {
            c.wlr_scene_blur_set_transparency_mask_source(blur, buffer);
        }
    }
}

/// Applies the global blur setting to an input-method popup scene tree.
pub fn applyImPopup(popup: *ImPopup) void {
    if (comptime enabled) applyImPopupImpl(popup);
}

pub fn applyLayers(server: *Server) void {
    var i: usize = 0;
    while (i < server.layers.len) : (i += 1) {
        const layer = server.layers[i] orelse continue;
        applyLayer(server, layer);
    }
}

pub fn applyCloseContent(buffer: *c.wlr_scene_buffer, radius: i32) void {
    if (comptime enabled) {
        c.wlr_scene_buffer_set_corner_radius(buffer, @max(0, radius));
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
    if (comptime enabled) {
        var i: usize = 0;
        while (i < server.im_popup_count) : (i += 1) {
            const popup = server.im_popups[i] orelse continue;
            applyImPopup(popup);
        }
    }
}
