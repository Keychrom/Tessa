const std = @import("std");
const build_options = @import("build_options");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const enabled = build_options.shaders;

var handle: ?*c.TessaWindowShader = null;
var drm_fd: c_int = -1;
var attempted = false;

pub fn available() bool {
    if (comptime !enabled) return false;
    const h = handle orelse return false;
    return c.tessa_window_shader_ready(h) != 0;
}

pub fn init(server: *types.Server) void {
    if (comptime !enabled) return;
    // The EGL context is created lazily: configurations without shader rules
    // pay nothing at startup.
    drm_fd = c.wlr_renderer_get_drm_fd(server.renderer);
}

fn ensure() bool {
    if (comptime !enabled) return false;
    if (handle) |h| return c.tessa_window_shader_ready(h) != 0;
    if (attempted) return false;
    attempted = true;
    if (c.getenv("TESSA_SHADER_DISABLE")) |raw| {
        const value = std.mem.span(raw);
        if (value.len > 0 and value[0] != '0') {
            core.logInfo("window shader: disabled by TESSA_SHADER_DISABLE", .{});
            return false;
        }
    }
    handle = c.tessa_window_shader_create(drm_fd);
    const h = handle orelse {
        core.logInfo("window shader: unavailable (out of memory)", .{});
        return false;
    };
    if (c.tessa_window_shader_ready(h) != 0) {
        core.logInfo("window shader: {s}", .{std.mem.span(c.tessa_window_shader_info(h))});
        return true;
    }
    core.logInfo("window shader: unavailable ({s})", .{
        std.mem.span(c.tessa_window_shader_error(h)),
    });
    return false;
}

pub fn shutdown() void {
    if (comptime !enabled) return;
    if (handle) |h| c.tessa_window_shader_destroy(h);
    handle = null;
    attempted = false;
}

pub fn isActive(client: *const types.Client) bool {
    if (comptime !enabled) return false;
    const node = client.shader_node orelse return false;
    return node.node.enabled;
}

fn effectId(kind: types.WindowShader) c_int {
    return switch (kind) {
        .none => 0,
        .mono => 1,
        .crt => 2,
        .vignette => 3,
        .pixelate => 4,
        .wave => 5,
    };
}

fn rejectInput(
    buffer: [*c]c.wlr_scene_buffer,
    sx: [*c]f64,
    sy: [*c]f64,
) callconv(.c) bool {
    _ = buffer;
    _ = sx;
    _ = sy;
    return false;
}

fn destroyNode(client: *types.Client) void {
    if (client.shader_node) |node| {
        c.wlr_scene_node_destroy(&node.node);
        client.shader_node = null;
    }
}

fn needsRender(client: *types.Client) bool {
    return client.shader_node == null or
        client.shader_rendered_seq != client.shader_seq or
        client.shader_rendered_kind != client.shader or
        client.shader_rendered_strength != client.shader_strength or
        client.shader_rendered_param != client.shader_param;
}

fn markRendered(client: *types.Client) void {
    client.shader_rendered_seq = client.shader_seq;
    client.shader_rendered_kind = client.shader;
    client.shader_rendered_strength = client.shader_strength;
    client.shader_rendered_param = client.shader_param;
}

fn render(client: *types.Client, content: *c.wlr_scene_buffer) bool {
    const h = handle orelse return false;
    const src = content.buffer orelse return false;
    // wlr_buffer_lock returns the same pointer with an extra reference.
    const locked = c.wlr_buffer_lock(src);
    if (locked == null) return false;
    defer c.wlr_buffer_unlock(locked);

    const id = effectId(client.shader);
    var out_pixels: [*c]u8 = null;
    var out_w: c_int = 0;
    var out_h: c_int = 0;
    var rendered = false;

    var attrs: c.wlr_dmabuf_attributes = undefined;
    if (c.wlr_buffer_get_dmabuf(locked, &attrs)) {
        rendered = c.tessa_window_shader_render_dmabuf(
            h,
            id,
            client.shader_strength,
            client.shader_param,
            &attrs,
            &out_pixels,
            &out_w,
            &out_h,
        ) != 0;
    } else {
        var data: ?*anyopaque = null;
        var format: u32 = 0;
        var stride: usize = 0;
        if (c.wlr_buffer_begin_data_ptr_access(
            locked,
            c.WLR_BUFFER_DATA_PTR_ACCESS_READ,
            &data,
            &format,
            &stride,
        )) {
            defer c.wlr_buffer_end_data_ptr_access(locked);
            if (data) |ptr| {
                rendered = c.tessa_window_shader_render_pixels(
                    h,
                    id,
                    client.shader_strength,
                    client.shader_param,
                    @ptrCast(ptr),
                    format,
                    locked.*.width,
                    locked.*.height,
                    stride,
                    &out_pixels,
                    &out_w,
                    &out_h,
                ) != 0;
            }
        }
    }
    if (!rendered or out_pixels == null or out_w <= 0 or out_h <= 0) return false;

    const wl_buffer = c.tessa_window_shader_buffer(out_pixels, out_w, out_h);
    if (wl_buffer == null) return false;
    defer c.wlr_buffer_drop(wl_buffer);

    if (client.shader_node == null) {
        const parent_raw = content.node.parent;
        if (parent_raw == null) return false;
        const parent: *c.wlr_scene_tree = @ptrCast(@alignCast(parent_raw));
        const node_raw = c.wlr_scene_buffer_create(parent, wl_buffer);
        if (node_raw == null) return false;
        const node: *c.wlr_scene_buffer = @ptrCast(@alignCast(node_raw));
        node.point_accepts_input = rejectInput;
        client.shader_node = node;
        // Keep the effect below the real content buffer. The content is drawn
        // with opacity 0 while the effect is active, so scene hit-testing
        // still resolves to the client surface.
        c.wlr_scene_node_place_below(&node.node, &content.node);
    } else {
        c.wlr_scene_buffer_set_buffer(client.shader_node.?, wl_buffer);
    }

    const node = client.shader_node.?;
    c.wlr_scene_node_set_position(&node.node, content.node.x, content.node.y);
    c.wlr_scene_buffer_set_source_box(node, &content.src_box);
    c.wlr_scene_buffer_set_dest_size(node, content.dst_width, content.dst_height);
    c.wlr_scene_buffer_set_transform(node, content.transform);
    c.wlr_scene_buffer_set_filter_mode(node, content.filter_mode);
    markRendered(client);
    return true;
}

pub fn refresh(client: *types.Client, opacity: f32, radius: i32) void {
    if (comptime !enabled) return;
    if (!client.mapped or client.shader == .none) {
        destroyNode(client);
        if (client.content_buffer) |content| {
            c.wlr_scene_buffer_set_opacity(content, opacity);
        }
        return;
    }
    if (!ensure()) {
        destroyNode(client);
        if (client.content_buffer) |content| {
            c.wlr_scene_buffer_set_opacity(content, opacity);
        }
        return;
    }
    const content = client.content_buffer orelse return;
    if (content.buffer == null) return;
    if (needsRender(client)) {
        if (!render(client, content)) {
            client.shader_failed = true;
            markRendered(client);
            destroyNode(client);
            c.wlr_scene_buffer_set_opacity(content, opacity);
            const reason = if (handle) |h|
                std.mem.span(c.tessa_window_shader_error(h))
            else
                "unavailable";
            core.logInfo("window shader: effect unavailable for window id={d} ({s})", .{
                client.id,
                reason,
            });
            return;
        }
    }
    const node = client.shader_node orelse return;
    c.wlr_scene_node_set_enabled(&node.node, true);
    c.wlr_scene_buffer_set_opacity(node, opacity);
    if (comptime build_options.scenefx) {
        c.wlr_scene_buffer_set_corner_radius(node, radius);
    }
    c.wlr_scene_node_set_position(&node.node, content.node.x, content.node.y);
    c.wlr_scene_buffer_set_opacity(content, 0.0);
}

pub fn release(client: *types.Client) void {
    if (comptime !enabled) return;
    destroyNode(client);
}
