const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const window_effects = @import("window_effects.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");
const motion = @import("motion.zig");

const Server = types.Server;
const Client = types.Client;
const CloseEffect = types.CloseEffect;

fn tBase(xdg: *c.wlr_xdg_toplevel) *c.wlr_xdg_surface {
    return @ptrCast(@alignCast(xdg.base));
}

fn closeAnimationMs(server: *Server) i32 {
    const cfg = &server.config;
    if (cfg.reduce_motion) {
        return if (cfg.reduce_motion_animations == .fade) cfg.reduce_motion_fade_ms else 0;
    }
    return if (cfg.animation_close_ms >= 0) cfg.animation_close_ms else cfg.animation_ms;
}

fn closeEffectsEnabled(server: *Server) bool {
    return server.config.animations and closeAnimationMs(server) > 0;
}

fn capture(client: *Client) bool {
    const surface: *c.wlr_surface = @ptrCast(@alignCast(tBase(client.xdg).surface));
    const client_buffer = surface.buffer;
    if (client_buffer == null) return false;
    const width = surface.current.width;
    const height = surface.current.height;
    if (width <= 0 or height <= 0) return false;

    var src: c.wlr_fbox = undefined;
    c.wlr_surface_get_buffer_source_box(surface, &src);
    if (src.width <= 0 or src.height <= 0) return false;

    const buffer = c.wlr_buffer_lock(&client_buffer[0].base) orelse return false;
    client.close_snapshot = buffer;
    client.close_snapshot_src = src;
    client.close_snapshot_transform = surface.current.transform;
    client.close_snapshot_w = width;
    client.close_snapshot_h = height;
    return true;
}

pub fn requestClose(server: *Server, client: *Client) void {
    if (closeEffectsEnabled(server) and client.mapped and
        client.ws == client.output.active_ws and client.close_snapshot == null)
    {
        _ = capture(client);
    }
    c.wlr_xdg_toplevel_send_close(client.xdg);
}

pub fn discardSnapshot(client: *Client) void {
    if (client.close_snapshot) |buffer| {
        c.wlr_buffer_unlock(buffer);
        client.close_snapshot = null;
    }
    client.close_snapshot_w = 0;
    client.close_snapshot_h = 0;
}

fn activeBorderColor(server: *Server) [4]f32 {
    const cfg = &server.config;
    const rgb = if (cfg.border_active_len > 0) cfg.border_active_rgb else cfg.accent_rgb;
    return .{ rgb[0], rgb[1], rgb[2], 1.0 };
}

fn inactiveBorderColor(server: *Server) [4]f32 {
    const cfg = &server.config;
    if (cfg.border_inactive_len > 0) {
        return .{ cfg.border_inactive_rgb[0], cfg.border_inactive_rgb[1], cfg.border_inactive_rgb[2], 1.0 };
    }
    return .{ 0.16, 0.20, 0.28, 1.0 };
}

fn apply(effect: *CloseEffect, eased: f64) void {
    const scale = if (effect.fade_only)
        1.0
    else
        1.0 - (1.0 - effect.close_scale) * eased;
    const opacity = std.math.clamp(
        if (effect.fade_only or effect.close_fade) 1.0 - eased else 1.0,
        0.0,
        1.0,
    );

    const frame_cx = effect.frame_x + effect.frame_w / 2.0;
    const frame_cy = effect.frame_y + effect.frame_h / 2.0;
    const frame_w = @max(1.0, effect.frame_w * scale);
    const frame_h = @max(1.0, effect.frame_h * scale);
    const frame_x = frame_cx - frame_w / 2.0;
    const frame_y = frame_cy - frame_h / 2.0;
    const border_w = @max(1.0, effect.border_width * scale);

    const content_w = @max(1.0, effect.content_w * scale);
    const content_h = @max(1.0, effect.content_h * scale);
    const content_cx = frame_cx + (effect.content_x + effect.content_w / 2.0 - frame_cx) * scale;
    const content_cy = frame_cy + (effect.content_y + effect.content_h / 2.0 - frame_cy) * scale;
    const content_x = content_cx - content_w / 2.0;
    const content_y = content_cy - content_h / 2.0;

    const border_color = [4]f32{
        effect.border_color[0],
        effect.border_color[1],
        effect.border_color[2],
        effect.border_color[3] * @as(f32, @floatCast(opacity)),
    };
    for (effect.border) |border| c.wlr_scene_rect_set_color(border, &border_color);

    c.wlr_scene_node_set_position(&effect.border[0].node, @intFromFloat(@round(frame_x)), @intFromFloat(@round(frame_y)));
    c.wlr_scene_rect_set_size(effect.border[0], @intFromFloat(@round(frame_w)), @intFromFloat(@round(border_w)));

    c.wlr_scene_node_set_position(
        &effect.border[1].node,
        @intFromFloat(@round(frame_x)),
        @intFromFloat(@round(frame_y + frame_h - border_w)),
    );
    c.wlr_scene_rect_set_size(effect.border[1], @intFromFloat(@round(frame_w)), @intFromFloat(@round(border_w)));

    c.wlr_scene_node_set_position(&effect.border[2].node, @intFromFloat(@round(frame_x)), @intFromFloat(@round(frame_y + border_w)));
    c.wlr_scene_rect_set_size(
        effect.border[2],
        @intFromFloat(@round(border_w)),
        @intFromFloat(@max(1.0, frame_h - border_w * 2.0)),
    );

    c.wlr_scene_node_set_position(
        &effect.border[3].node,
        @intFromFloat(@round(frame_x + frame_w - border_w)),
        @intFromFloat(@round(frame_y + border_w)),
    );
    c.wlr_scene_rect_set_size(
        effect.border[3],
        @intFromFloat(@round(border_w)),
        @intFromFloat(@max(1.0, frame_h - border_w * 2.0)),
    );

    c.wlr_scene_node_set_position(&effect.shadow.node, @intFromFloat(@round(frame_x - 12.0)), @intFromFloat(@round(frame_y - 9.0)));
    c.wlr_scene_rect_set_size(
        effect.shadow,
        @intFromFloat(@max(1.0, @round(frame_w + 24.0))),
        @intFromFloat(@max(1.0, @round(frame_h + 22.0))),
    );
    const shadow_color = [4]f32{
        effect.shadow_color[0],
        effect.shadow_color[1],
        effect.shadow_color[2],
        effect.shadow_color[3] * @as(f32, @floatCast(opacity)),
    };
    c.wlr_scene_rect_set_color(effect.shadow, &shadow_color);

    c.wlr_scene_node_set_position(&effect.content.node, @intFromFloat(@round(content_x)), @intFromFloat(@round(content_y)));
    c.wlr_scene_buffer_set_dest_size(
        effect.content,
        @intFromFloat(@max(1.0, @round(content_w))),
        @intFromFloat(@max(1.0, @round(content_h))),
    );
    c.wlr_scene_buffer_set_opacity(effect.content, @floatCast(opacity));
}

fn scheduleFrames(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        c.wlr_output_schedule_frame(out.wlr);
    }
}

fn start(
    client: *Client,
    buffer: *c.wlr_buffer,
    content_w: i32,
    content_h: i32,
    content_src: c.wlr_fbox,
    content_transform: c.wl_output_transform,
) void {
    const server = client.server;
    var slot: ?usize = null;
    for (server.effects, 0..) |existing, i| {
        if (existing == null) {
            slot = i;
            break;
        }
    }
    const effect_index = slot orelse {
        c.wlr_buffer_unlock(buffer);
        return;
    };

    const tree = c.wlr_scene_tree_create(server.tree_effects);
    const shadow_color = [4]f32{ 0, 0, 0, 0.07 };
    const shadow = c.wlr_scene_rect_create(tree, 1, 1, &shadow_color);
    const output_active = client.output.theme_border_active orelse
        client.output.theme_accent orelse activeBorderColor(server);
    const output_inactive = client.output.theme_border_inactive orelse inactiveBorderColor(server);
    var border_color = if (server.focused == client)
        client.border_active_override orelse output_active
    else
        client.border_inactive_override orelse output_inactive;
    if (client.fullscreen) border_color[3] = 0;
    var border: [4]*c.wlr_scene_rect = undefined;
    for (&border) |*rect| rect.* = c.wlr_scene_rect_create(tree, 1, 1, &border_color);
    const content = c.wlr_scene_buffer_create(tree, buffer);
    c.wlr_buffer_unlock(buffer);
    c.wlr_scene_buffer_set_source_box(content, &content_src);
    c.wlr_scene_buffer_set_transform(content, content_transform);
    if (!client.fullscreen) {
        const max_radius = @divTrunc(@max(1, @min(content_w, content_h)), 2);
        window_effects.applyCloseContent(content, @min(server.config.corner_radius, max_radius));
    }

    const border_width: i32 = if (client.fullscreen) 0 else server.config.border_width;
    const frame_x: f64 = @floatFromInt(client.x);
    const frame_y: f64 = @floatFromInt(client.y);
    const frame_w: f64 = @floatFromInt(@max(1, client.w));
    const frame_h: f64 = @floatFromInt(@max(1, client.h));
    const content_x = frame_x + @as(f64, @floatFromInt(border_width));
    const content_y = frame_y + @as(f64, @floatFromInt(border_width));

    const effect = @as(*CloseEffect, @ptrCast(@alignCast(c.calloc(1, @sizeOf(CloseEffect)).?)));
    effect.server = server;
    effect.client_id = client.id;
    effect.workspace = client.ws;
    const output_name = core.outputName(client.output);
    core.copyString(&effect.output_name, &effect.output_len, output_name);
    effect.tree = tree;
    effect.content = @ptrCast(@alignCast(content));
    effect.border = border;
    effect.shadow = @ptrCast(@alignCast(shadow));
    effect.border_width = if (client.fullscreen) 0 else @floatFromInt(server.config.border_width);
    effect.frame_x = frame_x;
    effect.frame_y = frame_y;
    effect.frame_w = frame_w;
    effect.frame_h = frame_h;
    effect.content_x = content_x;
    effect.content_y = content_y;
    effect.content_w = @floatFromInt(content_w);
    effect.content_h = @floatFromInt(content_h);
    effect.start_ms = core.timeNowMs();
    effect.ms = closeAnimationMs(server);
    effect.fade_only = server.config.reduce_motion;
    effect.curve = motion.close(&server.config);
    effect.close_scale = if (server.config.reduce_motion)
        1.0
    else
        @as(f64, server.config.animation_close_scale);
    effect.close_fade = server.config.reduce_motion or server.config.animation_close_fade;
    effect.border_color = border_color;
    effect.shadow_color = shadow_color;

    c.wlr_scene_buffer_set_filter_mode(effect.content, c.WLR_SCALE_FILTER_BILINEAR);
    apply(effect, 0);
    server.effects[effect_index] = effect;
    server.effect_count += 1;
    scheduleFrames(server);
    events.emit(server, .{
        .name = event_names.close_animation_start,
        .id = client.id,
        .workspace = client.ws,
        .output = output_name,
        .arg = "close",
    });
    core.logDebug("close animation: start id={d} {d}x{d}", .{ client.id, content_w, content_h });
}

pub fn clientUnmapped(client: *Client) void {
    if (client.close_snapshot == null) return;
    const server = client.server;
    const buffer = client.close_snapshot.?;
    const content_w = client.close_snapshot_w;
    const content_h = client.close_snapshot_h;
    const content_src = client.close_snapshot_src;
    const content_transform = client.close_snapshot_transform;
    client.close_snapshot = null;
    client.close_snapshot_w = 0;
    client.close_snapshot_h = 0;
    if (!closeEffectsEnabled(server) or client.ws != client.output.active_ws) {
        c.wlr_buffer_unlock(buffer);
        return;
    }
    start(client, buffer, content_w, content_h, content_src, content_transform);
}

fn finish(server: *Server, index: usize) void {
    const effect = server.effects[index] orelse return;
    core.logDebug("close animation: done id={d}", .{effect.client_id});
    events.emit(server, .{
        .name = event_names.close_animation_done,
        .id = effect.client_id,
        .workspace = effect.workspace,
        .output = effect.output_name[0..effect.output_len],
        .arg = "close",
    });
    c.wlr_scene_node_destroy(&effect.tree.node);
    server.effects[index] = null;
    if (server.effect_count > 0) server.effect_count -= 1;
    c.free(effect);
}

pub fn tick(server: *Server, now: i64) bool {
    var active = false;
    var i: usize = 0;
    while (i < server.effects.len) : (i += 1) {
        const effect = server.effects[i] orelse continue;
        active = true;
        const elapsed = now - effect.start_ms;
        const progress = std.math.clamp(
            @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(effect.ms)),
            0.0,
            1.0,
        );
        const eased = motion.evaluate(effect.curve, progress);
        apply(effect, eased);
        if (progress >= 1.0) finish(server, i);
    }
    return active;
}

pub fn cleanup(server: *Server) void {
    var i: usize = 0;
    while (i < server.effects.len) : (i += 1) {
        const effect = server.effects[i] orelse continue;
        c.wlr_scene_node_destroy(&effect.tree.node);
        c.free(effect);
        server.effects[i] = null;
    }
    server.effect_count = 0;
}
