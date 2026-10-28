const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const ime = @import("ime.zig");
const constraints = @import("constraints.zig");
const effects = @import("effects.zig");
const window_effects = @import("window_effects.zig");
const rules = @import("rules.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");
const layout_helper = @import("layout_helper.zig");
const motion = @import("motion.zig");

const Server = types.Server;
const Client = types.Client;
const Output = types.Output;
const LayerSurface = types.LayerSurface;

const Dir = enum { left, right, up, down };

fn tBase(xdg: *c.wlr_xdg_toplevel) *c.wlr_xdg_surface {
    return @ptrCast(@alignCast(xdg.base));
}
fn tSurface(xdg: *c.wlr_xdg_toplevel) *c.wlr_surface {
    return @ptrCast(@alignCast(tBase(xdg).surface));
}

fn parseDir(arg: []const u8) ?Dir {
    if (std.mem.eql(u8, arg, "left")) return .left;
    if (std.mem.eql(u8, arg, "right")) return .right;
    if (std.mem.eql(u8, arg, "up")) return .up;
    if (std.mem.eql(u8, arg, "down")) return .down;
    return null;
}

fn keyboardEnter(server: *Server, surface: *c.wlr_surface) void {
    const kb_raw = c.wlr_seat_get_keyboard(server.seat) orelse {
        c.wlr_seat_keyboard_clear_focus(server.seat);
        return;
    };
    const kb: *c.wlr_keyboard = @ptrCast(@alignCast(kb_raw));
    c.wlr_seat_keyboard_notify_enter(
        server.seat,
        surface,
        &kb.keycodes[0],
        kb.num_keycodes,
        &kb.modifiers,
    );
}

fn keyboardClear(server: *Server) void {
    if (server.focused_layer == null) c.wlr_seat_keyboard_clear_focus(server.seat);
    constraints.deactivate(server);
}

pub fn borderWidth(cl: *Client) i32 {
    if (cl.fullscreen) return 0;
    return if (cl.border_width >= 0) cl.border_width else cl.server.config.border_width;
}

fn clientSurfaceOrigin(cl: *Client) struct { x: i32, y: i32 } {
    const border = borderWidth(cl);
    // wlr_scene_xdg_surface_create() already anchors the scene node at the
    // xdg window geometry, so do not subtract geometry.x/y a second time.
    return .{
        .x = cl.frame.node.x + border,
        .y = cl.frame.node.y + border,
    };
}

fn clientVisible(cl: *Client, out: *Output) bool {
    if (!cl.mapped or cl.output != out) return false;
    if (cl.group_id != 0 and !cl.group_active) return false;
    if (cl.scratchpad) return out.scratchpad_visible;
    return cl.ws == out.active_ws;
}

fn activateGroupMember(target: *Client) void {
    if (target.group_id == 0) return;
    const server = target.server;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.group_id == target.group_id) cl.group_active = cl == target;
    }
}

fn groupActivateNext(group_id: u32, exclude: *Client) void {
    const server = exclude.server;
    var next: ?*Client = null;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl == exclude or cl.group_id != group_id or !cl.mapped) continue;
        if (next == null or cl.id < next.?.id) next = cl;
    }
    if (next) |cl| {
        cl.group_active = true;
    }
}

fn detachFromGroup(cl: *Client) void {
    if (cl.group_id == 0) return;
    const gid = cl.group_id;
    const active = cl.group_active;
    cl.group_id = 0;
    cl.group_active = false;
    if (active) groupActivateNext(gid, cl);
}

pub fn clientClosing(cl: *Client) void {
    detachFromGroup(cl);
}

pub fn raiseClient(client: *Client) void {
    const s = client.server;
    const tree: *c.wlr_scene_tree = if (client.fullscreen)
        s.tree_fullscreen
    else if (client.floating)
        s.tree_floating
    else
        s.tree_windows;

    const parent: ?*c.wlr_scene_tree = if (client.frame.node.parent) |p|
        @ptrCast(@alignCast(p))
    else
        null;
    if (parent != tree) {
        c.wlr_scene_node_reparent(&client.frame.node, tree);
    }
    c.wlr_scene_node_raise_to_top(&client.frame.node);
}

pub fn updateBorders(server: *Server) void {
    const cfg = &server.config;
    const active_rgb = if (cfg.border_active_len > 0) cfg.border_active_rgb else cfg.accent_rgb;
    const inactive_rgb = if (cfg.border_inactive_len > 0)
        cfg.border_inactive_rgb
    else
        [3]f32{ 0.16, 0.20, 0.28 };
    const active = [4]f32{ active_rgb[0], active_rgb[1], active_rgb[2], 1.0 };
    const inactive = [4]f32{ inactive_rgb[0], inactive_rgb[1], inactive_rgb[2], 1.0 };

    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        const is_active = (cl == server.focused) and
            clientVisible(cl, cl.output) and
            server.focused_layer == null;
        const output_active = cl.output.theme_border_active orelse
            cl.output.theme_accent orelse active;
        const output_inactive = cl.output.theme_border_inactive orelse inactive;
        var active_color = cl.border_active_override orelse output_active;
        var inactive_color = cl.border_inactive_override orelse output_inactive;
        active_color[3] *= cl.opacity;
        inactive_color[3] *= cl.opacity;
        c.wlr_scene_rect_set_color(cl.border_rect, if (is_active) &active_color else &inactive_color);
    }
}

pub fn refreshKeyboardFocus(server: *Server) void {
    if (server.focused_layer) |layer| {
        c.wlr_seat_keyboard_clear_focus(server.seat);
        keyboardEnter(server, @ptrCast(@alignCast(layer.wlr.surface)));
    } else if (server.focused) |cl| {
        if (clientVisible(cl, cl.output)) {
            c.wlr_seat_keyboard_clear_focus(server.seat);
            keyboardEnter(server, tSurface(cl.xdg));
        } else {
            keyboardClear(server);
        }
    } else {
        keyboardClear(server);
    }
}

pub fn focusClient(server: *Server, target: ?*Client) void {
    if (server.focused_layer != null) {
        server.focused_layer = null;
    }

    if (target) |cl| {
        activateGroupMember(cl);
        if (!clientVisible(cl, cl.output)) return;
        const was_urgent = cl.urgent;
        cl.urgent = false;
        if (server.focused == cl) {
            server.focused_output = cl.output;
            server.active_ws = cl.output.active_ws;
            if (cl.foreign_toplevel) |handle| {
                c.wlr_foreign_toplevel_handle_v1_set_activated(handle, true);
            }
            raiseClient(cl);
            if (was_urgent) layout_helper.focusChanged(server);
            return;
        }
        if (server.focused) |prev| {
            if (prev != cl) {
                _ = c.wlr_xdg_toplevel_set_activated(prev.xdg, false);
                if (prev.foreign_toplevel) |handle| {
                    c.wlr_foreign_toplevel_handle_v1_set_activated(handle, false);
                }
            }
        }
        const previous_id: u64 = if (server.focused) |prev| prev.id else 0;
        server.focused = cl;
        server.focused_output = cl.output;
        server.active_ws = cl.output.active_ws;
        cl.output.last_focused[cl.ws] = cl;
        _ = c.wlr_xdg_toplevel_set_activated(cl.xdg, true);
        if (cl.foreign_toplevel) |handle| {
            c.wlr_foreign_toplevel_handle_v1_set_activated(handle, true);
        }
        raiseClient(cl);
        keyboardEnter(server, tSurface(cl.xdg));
        const origin = clientSurfaceOrigin(cl);
        ime.focusSurface(server, tSurface(cl.xdg), origin.x, origin.y);
        constraints.focusSurface(server, tSurface(cl.xdg));
        updateBorders(server);
        events.emit(server, .{
            .name = event_names.window_focus,
            .id = cl.id,
            .previous_id = previous_id,
            .workspace = cl.ws,
            .app_id = cl.app_id[0..cl.app_id_len],
            .title = cl.title[0..cl.title_len],
            .output = core.outputName(cl.output),
        });
        layout_helper.focusChanged(server);
        core.markDirty(server);
        return;
    }

    if (server.focused) |prev| {
        _ = c.wlr_xdg_toplevel_set_activated(prev.xdg, false);
        if (prev.foreign_toplevel) |handle| {
            c.wlr_foreign_toplevel_handle_v1_set_activated(handle, false);
        }
    }
    const cleared_id: u64 = if (server.focused) |prev| prev.id else 0;
    const cleared_ws: usize = if (server.focused) |prev| prev.ws else server.active_ws;
    const cleared_output = if (server.focused) |prev| core.outputName(prev.output) else "";
    server.focused = null;
    keyboardClear(server);
    ime.focusSurface(server, null, 0, 0);
    updateBorders(server);
    if (cleared_id != 0) {
        events.emit(server, .{
            .name = event_names.window_focus,
            .id = 0,
            .previous_id = cleared_id,
            .workspace = cleared_ws,
            .output = cleared_output,
        });
        layout_helper.focusChanged(server);
    }
    core.markDirty(server);
}

pub fn ensureVisibleFocus(server: *Server) void {
    if (server.focused) |cl| {
        if (clientVisible(cl, cl.output)) return;
    }
    focusClient(server, null);

    const out = core.focusOutput(server) orelse return;
    var target: ?*Client = null;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (clientVisible(cl, out)) {
            target = cl;
            break;
        }
    }
    focusClient(server, target);
}

pub fn focusLayer(server: *Server, layer: *LayerSurface) void {
    if (server.focused) |cl| {
        _ = c.wlr_xdg_toplevel_set_activated(cl.xdg, false);
        if (cl.foreign_toplevel) |handle| {
            c.wlr_foreign_toplevel_handle_v1_set_activated(handle, false);
        }
    }
    server.focused_layer = layer;
    server.focused_output = layer.output;
    keyboardEnter(server, @ptrCast(@alignCast(layer.wlr.surface)));
    const layer_tree: *c.wlr_scene_tree = @ptrCast(@alignCast(layer.scene_layer.tree));
    ime.focusSurface(
        server,
        @ptrCast(@alignCast(layer.wlr.surface)),
        layer.output.full.x + layer_tree.node.x,
        layer.output.full.y + layer_tree.node.y,
    );
    constraints.focusSurface(server, @ptrCast(@alignCast(layer.wlr.surface)));
    updateBorders(server);
    core.markDirty(server);
}

pub fn restoreFocusAfterLayer(server: *Server, layer: *LayerSurface) void {
    if (server.focused_layer != layer) return;
    server.focused_layer = null;
    if (server.focused) |cl| {
        if (clientVisible(cl, cl.output)) {
            server.focused_output = cl.output;
            server.active_ws = cl.output.active_ws;
            _ = c.wlr_xdg_toplevel_set_activated(cl.xdg, true);
            if (cl.foreign_toplevel) |handle| {
                c.wlr_foreign_toplevel_handle_v1_set_activated(handle, true);
            }
            keyboardEnter(server, tSurface(cl.xdg));
            const origin = clientSurfaceOrigin(cl);
            ime.focusSurface(server, tSurface(cl.xdg), origin.x, origin.y);
            constraints.focusSurface(server, tSurface(cl.xdg));
            updateBorders(server);
            core.markDirty(server);
            return;
        }
    }
    keyboardClear(server);
    ime.focusSurface(server, null, 0, 0);
    updateBorders(server);
    core.markDirty(server);
}

fn animationsEnabledFor(server: *Server, client: *Client) bool {
    if (!server.config.animations or server.config.reduce_motion) return false;
    return client.anim.enabled != .off;
}

fn animationMsFor(client: *Client, kind: types.AnimationKind) i32 {
    const cfg = &client.server.config;
    const global_ms = switch (kind) {
        .open => cfg.animation_open_ms,
        .workspace => cfg.animation_workspace_ms,
        .none => -1,
    };
    const override_ms = switch (kind) {
        .open => client.anim.open_ms,
        .workspace => client.anim.workspace_ms,
        .none => -1,
    };
    if (override_ms >= 0) return override_ms;
    if (client.anim.animation_ms >= 0) return client.anim.animation_ms;
    return if (global_ms >= 0) global_ms else cfg.animation_ms;
}

fn scheduleAnimationFrames(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        c.wlr_output_schedule_frame(out.wlr);
    }
}

fn animationKindName(kind: types.AnimationKind) []const u8 {
    return switch (kind) {
        .open => "open",
        .workspace => "workspace",
        .none => "none",
    };
}

fn beginAnimation(client: *Client, from_x: i32, from_y: i32, kind: types.AnimationKind, duration_ms: i32) void {
    const server = client.server;
    if (!animationsEnabledFor(server, client) or duration_ms <= 0) return;
    client.anim_from_x = from_x;
    client.anim_from_y = from_y;
    client.anim_off_x = from_x;
    client.anim_off_y = from_y;
    client.anim_start_ms = core.timeNowMs();
    client.anim_ms = duration_ms;
    client.anim_curve = switch (kind) {
        .open => motion.openFor(&server.config, client.anim),
        .workspace => motion.workspaceFor(&server.config, client.anim),
        .none => motion.DEFAULT_OPEN,
    };
    client.animating = true;
    client.anim_kind = kind;
    scheduleAnimationFrames(server);
    events.emit(server, .{
        .name = event_names.animation_start,
        .id = client.id,
        .workspace = client.ws,
        .output = core.outputName(client.output),
        .arg = animationKindName(kind),
    });
    core.logDebug("animation: start id={d} from={d},{d} ms={d} curve={s}", .{
        client.id,
        from_x,
        from_y,
        duration_ms,
        motion.kindName(client.anim_curve),
    });
}

pub fn startOpenAnimation(client: *Client) void {
    if (!client.mapped or client.scratchpad or client.ws != client.output.active_ws) return;
    if (!animationsEnabledFor(client.server, client)) return;
    beginAnimation(
        client,
        client.server.config.animation_open_x,
        client.server.config.animation_open_y,
        .open,
        animationMsFor(client, .open),
    );
}

pub fn startWorkspaceAnimation(server: *Server, out: *Output, previous_ws: usize, ws: usize) void {
    if (server.config.reduce_motion or !server.config.animations or previous_ws == ws) return;
    const offset = server.config.animation_workspace_offset;
    const dir: i32 = if (ws > previous_ws) offset else -offset;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.output == out and cl.ws == ws and cl.mapped) {
            beginAnimation(cl, dir, 0, .workspace, animationMsFor(cl, .workspace));
        }
    }
}

pub fn tickAnimations(server: *Server, now: i64) bool {
    var active = false;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (!cl.animating) continue;
        active = true;
        const elapsed = now - cl.anim_start_ms;
        const progress = std.math.clamp(
            @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(cl.anim_ms)),
            0.0,
            1.0,
        );
        const eased = motion.evaluate(cl.anim_curve, progress);
        const remain = 1.0 - eased;
        cl.anim_off_x = @intFromFloat(@as(f64, @floatFromInt(cl.anim_from_x)) * remain);
        cl.anim_off_y = @intFromFloat(@as(f64, @floatFromInt(cl.anim_from_y)) * remain);
        c.wlr_scene_node_set_position(
            &cl.frame.node,
            cl.x + cl.anim_off_x,
            cl.y + cl.anim_off_y,
        );
        if (progress >= 1.0) {
            cl.animating = false;
            cl.anim_off_x = 0;
            cl.anim_off_y = 0;
            c.wlr_scene_node_set_position(&cl.frame.node, cl.x, cl.y);
            events.emit(server, .{
                .name = event_names.animation_done,
                .id = cl.id,
                .workspace = cl.ws,
                .output = core.outputName(cl.output),
                .arg = animationKindName(cl.anim_kind),
            });
            cl.anim_kind = .none;
            core.logDebug("animation: done id={d}", .{cl.id});
        }
    }
    return active;
}

pub fn clearAnimations(server: *Server) void {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (!cl.animating and cl.anim_off_x == 0 and cl.anim_off_y == 0) continue;
        cl.animating = false;
        cl.anim_off_x = 0;
        cl.anim_off_y = 0;
        cl.anim_kind = .none;
        c.wlr_scene_node_set_position(&cl.frame.node, cl.x, cl.y);
    }
}

fn shadowsEnabled(client: *Client) bool {
    return switch (client.shadow) {
        .on => true,
        .off => false,
        .unset => client.server.config.shadows,
    };
}

fn updateShadows(client: *Client, enabled: bool, w: i32, h: i32) void {
    const show = enabled and shadowsEnabled(client);
    const alphas = [3]f32{ 0.045, 0.055, 0.070 };
    const offsets = [3][4]i32{
        .{ -12, -9, 24, 22 },
        .{ -7, -5, 14, 14 },
        .{ -3, -2, 6, 8 },
    };
    var i: usize = 0;
    while (i < client.shadow_rects.len) : (i += 1) {
        const rect = client.shadow_rects[i] orelse continue;
        if (!show) {
            c.wlr_scene_node_set_enabled(&rect.node, false);
            continue;
        }
        const color = [4]f32{ 0, 0, 0, alphas[i] * client.opacity };
        c.wlr_scene_rect_set_color(rect, &color);
        c.wlr_scene_node_set_enabled(&rect.node, true);
        c.wlr_scene_node_set_position(&rect.node, offsets[i][0], offsets[i][1]);
        c.wlr_scene_rect_set_size(rect, @max(1, w + offsets[i][2]), @max(1, h + offsets[i][3]));
    }
}

fn applyFrame(client: *Client, x: i32, y: i32, w: i32, h: i32, border: i32, enabled_border: bool) void {
    _ = border;
    const b = if (enabled_border) borderWidth(client) else 0;
    client.x = x;
    client.y = y;
    client.w = @max(1, w);
    client.h = @max(1, h);

    c.wlr_scene_node_set_position(&client.frame.node, x + client.anim_off_x, y + client.anim_off_y);
    updateShadows(client, enabled_border, client.w, client.h);

    if (enabled_border and b > 0) {
        c.wlr_scene_node_set_enabled(&client.border_rect.node, true);
        c.wlr_scene_node_set_position(&client.border_rect.node, 0, 0);
        c.wlr_scene_rect_set_size(client.border_rect, client.w, client.h);
    } else {
        c.wlr_scene_node_set_enabled(&client.border_rect.node, false);
    }

    c.wlr_scene_node_set_position(&client.surface_tree.node, b, b);

    const cw = @max(1, client.w - b * 2);
    const ch = @max(1, client.h - b * 2);
    if (cw != client.xdg.current.width or ch != client.xdg.current.height) {
        _ = c.wlr_xdg_toplevel_set_size(client.xdg, cw, ch);
    }
    window_effects.applyClient(client, enabled_border);
}

fn initFloatRect(client: *Client, out: *Output) void {
    const area = if (out.usable.width > 100) out.usable else out.full;
    var fw: i32 = @intFromFloat(@as(f32, @floatFromInt(area.width)) * 0.55);
    var fh: i32 = @intFromFloat(@as(f32, @floatFromInt(area.height)) * 0.60);
    fw = std.math.clamp(fw, 480, 1100);
    fh = std.math.clamp(fh, 320, 760);
    client.float_w = fw;
    client.float_h = fh;
    client.float_x = area.x + @divTrunc(area.width - fw, 2);
    client.float_y = area.y + @divTrunc(area.height - fh, 2);
}

fn applyFloating(client: *Client, out: *Output) void {
    if (client.float_w <= 0 or client.float_h <= 0) initFloatRect(client, out);
    const border = borderWidth(client);

    const full = out.full;
    if (full.width > 0 and full.height > 0) {
        const max_x = full.x + full.width - client.float_w;
        const max_y = full.y + full.height - client.float_h;
        client.float_x = std.math.clamp(client.float_x, full.x, @max(full.x, max_x));
        client.float_y = std.math.clamp(client.float_y, full.y, @max(full.y, max_y));
    }

    applyFrame(client, client.float_x, client.float_y, client.float_w, client.float_h, border, true);
}

fn applyFullscreen(client: *Client, out: *Output) void {
    var full = out.full;
    if (full.width <= 0 or full.height <= 0) {
        c.wlr_output_layout_get_box(out.server.output_layout, out.wlr, &full);
    }
    applyFrame(client, full.x, full.y, full.width, full.height, 0, false);
}

fn arrangeMasterTiles(
    tiles: []const ?*Client,
    ux: i32,
    uy: i32,
    uw: i32,
    uh: i32,
    border: i32,
    gap: i32,
    ratio: f32,
    master_count: usize,
) void {
    const count = tiles.len;
    var master_n = @min(master_count, count);
    if (master_n < 1) master_n = 1;
    const stack_n = count - master_n;

    const master_w: i32 = if (stack_n == 0) uw else blk: {
        if (uw <= gap + 160) break :blk @divTrunc(uw - gap, 2);
        var w: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(uw - gap)) * ratio));
        if (w < 100) w = 100;
        if (uw - gap - w < 100) w = @divTrunc(uw - gap, 2);
        break :blk w;
    };

    const master_total = uh - gap * @as(i32, @intCast(master_n - 1));
    const master_h: i32 = @divTrunc(master_total, @as(i32, @intCast(master_n)));
    var my = uy;
    var mi: usize = 0;
    while (mi < master_n) : (mi += 1) {
        var h = master_h;
        if (mi == master_n - 1) h = uy + uh - my;
        if (h < 1) h = 1;
        applyFrame(tiles[mi].?, ux, my, master_w, h, border, true);
        my += h + gap;
    }

    if (stack_n == 0) return;
    const stack_x = ux + master_w + gap;
    const stack_w = @max(1, uw - master_w - gap);
    const stack_total = uh - gap * @as(i32, @intCast(stack_n - 1));
    const each: i32 = @divTrunc(stack_total, @as(i32, @intCast(stack_n)));
    var sy = uy;
    var i = master_n;
    while (i < count) : (i += 1) {
        const is_last = i == count - 1;
        var h = each;
        if (is_last) h = uy + uh - sy;
        if (h < 1) h = 1;
        applyFrame(tiles[i].?, stack_x, sy, stack_w, h, border, true);
        sy += h + gap;
    }
}

fn mosaicCanFit(count: usize, uw: i32, uh: i32, gap: i32, ratio: f32, min_size: i32) bool {
    var rw = uw;
    var rh = uh;
    var dir: u2 = 0;
    var i: usize = 0;
    while (i + 1 < count) : (i += 1) {
        if (rw < min_size or rh < min_size) return false;
        const horizontal = dir == 0 or dir == 2;
        const avail = if (horizontal) rw - gap else rh - gap;
        if (avail < min_size * 2) return false;
        const raw: i32 = @intFromFloat(@as(f32, @floatFromInt(avail)) * ratio);
        const slice = std.math.clamp(raw, min_size, avail - min_size);
        if (horizontal) {
            rw -= slice + gap;
        } else {
            rh -= slice + gap;
        }
        dir = @intCast((@as(u32, dir) + 1) % 4);
    }
    return true;
}

fn arrangeMosaicTiles(
    tiles: []const ?*Client,
    ux: i32,
    uy: i32,
    uw: i32,
    uh: i32,
    border: i32,
    gap: i32,
    ratio: f32,
    min_size: i32,
) void {
    if (!mosaicCanFit(tiles.len, uw, uh, gap, ratio, min_size)) {
        arrangeGridTiles(tiles, ux, uy, uw, uh, border, gap, 0);
        return;
    }
    var rx = ux;
    var ry = uy;
    var rw = uw;
    var rh = uh;
    var dir: u2 = 0;
    var i: usize = 0;
    while (i < tiles.len) : (i += 1) {
        // The last window owns what remains instead of leaving a gap.
        if (i == tiles.len - 1) {
            applyFrame(tiles[i].?, rx, ry, rw, rh, border, true);
            break;
        }
        // When a slice would leave less than a usable tile, stop spiraling
        // and divide the remaining rectangle with the grid layout.
        if (rw < min_size or rh < min_size) {
            arrangeGridTiles(tiles[i..], rx, ry, rw, rh, border, gap, 0);
            break;
        }
        const horizontal = dir == 0 or dir == 2;
        const avail = if (horizontal) rw - gap else rh - gap;
        if (avail < min_size * 2) {
            arrangeGridTiles(tiles[i..], rx, ry, rw, rh, border, gap, 0);
            break;
        }

        const raw: i32 = @intFromFloat(@as(f32, @floatFromInt(avail)) * ratio);
        const slice = std.math.clamp(raw, min_size, avail - min_size);
        if (horizontal) {
            if (dir == 0) {
                applyFrame(tiles[i].?, rx, ry, slice, rh, border, true);
                rx += slice + gap;
                rw -= slice + gap;
            } else {
                applyFrame(tiles[i].?, rx + rw - slice, ry, slice, rh, border, true);
                rw -= slice + gap;
            }
        } else {
            if (dir == 1) {
                applyFrame(tiles[i].?, rx, ry, rw, slice, border, true);
                ry += slice + gap;
                rh -= slice + gap;
            } else {
                applyFrame(tiles[i].?, rx, ry + rh - slice, rw, slice, border, true);
                rh -= slice + gap;
            }
        }
        dir = @intCast((@as(u32, dir) + 1) % 4);
    }
}

fn persistLayouts(server: *Server) void {
    if (server.save_display_state) |save| save(server);
}

pub fn applyConfigLayouts(server: *Server) void {
    var oi: usize = 0;
    while (oi < server.outputs.len) : (oi += 1) {
        const out = server.outputs[oi] orelse continue;
        var ws: usize = 0;
        while (ws < types.WS_COUNT) : (ws += 1) {
            if (!out.layout_overridden[ws]) {
                out.ws_layouts[ws] = rules.tuningFor(server, out, ws + 1).layout;
            }
        }
    }
}

fn applyHelperRects(
    tiles: []const ?*Client,
    rects: []const layout_helper.Rect,
    border: i32,
) bool {
    var order: [types.MAX_CLIENTS]usize = undefined;
    var used = [_]bool{false} ** types.MAX_CLIENTS;

    for (rects, 0..) |rect, ri| {
        var found: ?usize = null;
        for (tiles, 0..) |maybe_client, ti| {
            const client = maybe_client orelse return false;
            if (client.id == rect.id) {
                found = ti;
                break;
            }
        }
        const index = found orelse return false;
        if (used[index]) return false;
        used[index] = true;
        order[ri] = index;
    }

    for (rects, 0..) |rect, ri| {
        applyFrame(tiles[order[ri]].?, rect.x, rect.y, rect.w, rect.h, border, true);
    }
    return true;
}

fn arrangeGridTiles(
    tiles: []const ?*Client,
    ux: i32,
    uy: i32,
    uw: i32,
    uh: i32,
    border: i32,
    gap: i32,
    fixed_columns: usize,
) void {
    const count = tiles.len;
    const n: f64 = @floatFromInt(count);
    var cols: usize = if (fixed_columns > 0)
        fixed_columns
    else
        @intFromFloat(@ceil(@sqrt(n)));
    if (cols < 1) cols = 1;
    if (cols > count) cols = count;
    const rows = (count + cols - 1) / cols;

    const cell_w = @max(1, @divTrunc(uw - gap * @as(i32, @intCast(cols - 1)), @as(i32, @intCast(cols))));
    const cell_h = @max(1, @divTrunc(uh - gap * @as(i32, @intCast(rows - 1)), @as(i32, @intCast(rows))));

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const row = i / cols;
        const col = i % cols;
        const last_row = row == rows - 1;
        const last_count = count - row * cols;
        var x = ux + @as(i32, @intCast(col)) * (cell_w + gap);
        if (last_row and last_count < cols) {
            const row_w = @as(i32, @intCast(last_count)) * cell_w +
                gap * @as(i32, @intCast(last_count - 1));
            const row_x = ux + @divTrunc(uw - row_w, 2);
            x = row_x + @as(i32, @intCast(col)) * (cell_w + gap);
        }
        const y = uy + @as(i32, @intCast(row)) * (cell_h + gap);
        applyFrame(tiles[i].?, x, y, cell_w, cell_h, border, true);
    }
}

fn arrangeColumnsTiles(tiles: []const ?*Client, ux: i32, uy: i32, uw: i32, uh: i32, border: i32, gap: i32) void {
    const count = tiles.len;
    const each = @max(1, @divTrunc(uw - gap * @as(i32, @intCast(count - 1)), @as(i32, @intCast(count))));
    var x = ux;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const is_last = i == count - 1;
        const w = if (is_last) ux + uw - x else each;
        applyFrame(tiles[i].?, x, uy, @max(1, w), uh, border, true);
        x += w + gap;
    }
}

pub fn arrangeOutput(server: *Server, out: *Output) void {
    var area = out.usable;
    if (area.width < 50 or area.height < 50) area = out.full;

    var tiles: [types.MAX_CLIENTS]?*Client = undefined;
    var tile_count: usize = 0;

    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.output != out) continue;

        const visible = clientVisible(cl, out);
        c.wlr_scene_node_set_enabled(&cl.frame.node, visible);
        if (!visible) continue;

        if (cl.fullscreen) {
            applyFullscreen(cl, out);
            raiseClient(cl);
        } else if (cl.floating or cl.scratchpad) {
            applyFloating(cl, out);
        } else if (tile_count < tiles.len) {
            tiles[tile_count] = cl;
            tile_count += 1;
        }
    }

    if (tile_count > 0) {
        const cfg = &server.config;
        const tuning = rules.tuningFor(server, out, out.active_ws);
        const border = cfg.border_width;
        const outer = tuning.outer_gaps;
        const gap = tuning.gaps;
        const master_ratio = tuning.master_ratio;

        const ux = area.x + outer;
        const uy = area.y + outer;
        const uw = area.width - outer * 2;
        const uh = area.height - outer * 2;

        if (uw > 20 and uh > 20) {
            const mode = out.ws_layouts[out.active_ws - 1];
            if (tile_count == 1 and mode != .custom) {
                applyFrame(tiles[0].?, ux, uy, uw, uh, border, true);
            } else {
                switch (mode) {
                    .master => arrangeMasterTiles(tiles[0..tile_count], ux, uy, uw, uh, border, gap, master_ratio, tuning.master_count),
                    .mosaic => {
                        if (tile_count <= 8) {
                            arrangeMosaicTiles(
                                tiles[0..tile_count],
                                ux,
                                uy,
                                uw,
                                uh,
                                border,
                                gap,
                                tuning.mosaic_ratio,
                                tuning.mosaic_min_size,
                            );
                        } else {
                            arrangeMasterTiles(tiles[0..tile_count], ux, uy, uw, uh, border, gap, master_ratio, tuning.master_count);
                        }
                    },
                    .grid => arrangeGridTiles(tiles[0..tile_count], ux, uy, uw, uh, border, gap, tuning.grid_columns),
                    .columns => arrangeColumnsTiles(tiles[0..tile_count], ux, uy, uw, uh, border, gap),
                    .custom => {
                        var rects: [types.MAX_CLIENTS]layout_helper.Rect = undefined;
                        var applied = false;
                        if (layout_helper.query(
                            server,
                            out,
                            tiles[0..tile_count],
                            area,
                            border,
                            gap,
                            outer,
                            rects[0..tile_count],
                        )) |rect_count| {
                            applied = applyHelperRects(tiles[0..tile_count], rects[0..rect_count], border);
                            if (!applied) {
                                core.logInfo("layout helper returned an invalid rectangle set; using master fallback", .{});
                            }
                        }
                        if (!applied) {
                            arrangeMasterTiles(
                                tiles[0..tile_count],
                                ux,
                                uy,
                                uw,
                                uh,
                                border,
                                gap,
                                master_ratio,
                                tuning.master_count,
                            );
                        }
                    },
                }
            }
        }
    }

    if (server.focused) |fc| {
        if (fc.output == out and clientVisible(fc, out)) {
            raiseClient(fc);
        }
    }

    updateBorders(server);
}

pub fn arrangeAll(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |out| arrangeOutput(server, out);
    }
}

pub fn setProvisionalSize(client: *Client) void {
    const out = client.output;
    var area = out.usable;
    if (area.width < 50 or area.height < 50) area = out.full;
    const b = borderWidth(client);
    const outer = rules.tuningFor(client.server, out, client.ws).outer_gaps;
    const w = @max(1, area.width - outer * 2 - b * 2);
    const h = @max(1, area.height - outer * 2 - b * 2);
    _ = c.wlr_xdg_toplevel_set_size(client.xdg, w, h);
}

fn visibleClientsOnOutput(server: *Server, out: *Output, out_list: []?*Client) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (clientVisible(cl, out)) {
            if (n < out_list.len) {
                out_list[n] = cl;
                n += 1;
            }
        }
    }
    return n;
}

fn centerX(cl: *Client) i32 {
    return cl.x + @divTrunc(cl.w, 2);
}
fn centerY(cl: *Client) i32 {
    return cl.y + @divTrunc(cl.h, 2);
}

fn findDirectional(server: *Server, from: *Client, dir: Dir, same_output: bool) ?*Client {
    var list: [types.MAX_CLIENTS]?*Client = undefined;
    const n = visibleClientsOnOutput(server, from.output, &list);
    const fx = centerX(from);
    const fy = centerY(from);

    var best: ?*Client = null;
    var best_score: f64 = std.math.floatMax(f64);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const cl = list[i].?;
        if (cl == from) continue;
        if (same_output and cl.output != from.output) continue;
        const dx = centerX(cl) - fx;
        const dy = centerY(cl) - fy;

        var primary: f64 = 0;
        var secondary: f64 = 0;
        switch (dir) {
            .left => {
                if (dx >= -8) continue;
                primary = -dx;
                secondary = @abs(@as(f64, @floatFromInt(dy)));
            },
            .right => {
                if (dx <= 8) continue;
                primary = dx;
                secondary = @abs(@as(f64, @floatFromInt(dy)));
            },
            .up => {
                if (dy >= -8) continue;
                primary = -dy;
                secondary = @abs(@as(f64, @floatFromInt(dx)));
            },
            .down => {
                if (dy <= 8) continue;
                primary = dy;
                secondary = @abs(@as(f64, @floatFromInt(dx)));
            },
        }
        const score = primary + secondary * 0.45;
        if (score < best_score) {
            best_score = score;
            best = cl;
        }
    }
    return best;
}

fn firstClientOnOutput(server: *Server, out: *Output) ?*Client {
    if (out.last_focused[out.active_ws]) |cl| {
        if (clientVisible(cl, out)) return cl;
    }
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (clientVisible(cl, out)) return cl;
    }
    return null;
}

fn adjacentOutput(server: *Server, from: *Output, dir: Dir) ?*Output {
    var best: ?*Output = null;
    var best_dist: i32 = std.math.maxInt(i32);
    const fx = from.full.x + @divTrunc(from.full.width, 2);
    const fy = from.full.y + @divTrunc(from.full.height, 2);
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        if (out == from) continue;
        const ox = out.full.x + @divTrunc(out.full.width, 2);
        const oy = out.full.y + @divTrunc(out.full.height, 2);
        const dx = ox - fx;
        const dy = oy - fy;
        const dist: i32 = switch (dir) {
            .left => if (dx < -8 and @abs(dy) <= @divTrunc(from.full.height, 2) + out.full.height) -dx else continue,
            .right => if (dx > 8 and @abs(dy) <= @divTrunc(from.full.height, 2) + out.full.height) dx else continue,
            .up => if (dy < -8 and @abs(dx) <= @divTrunc(from.full.width, 2) + out.full.width) -dy else continue,
            .down => if (dy > 8 and @abs(dx) <= @divTrunc(from.full.width, 2) + out.full.width) dy else continue,
        };
        if (dist < best_dist) {
            best_dist = dist;
            best = out;
        }
    }
    return best;
}

pub fn focusDirection(server: *Server, arg: []const u8) void {
    const dir = parseDir(arg) orelse return;
    const cur = server.focused orelse {
        focusFirst(server);
        return;
    };
    if (findDirectional(server, cur, dir, true)) |target| {
        focusClient(server, target);
        return;
    }
    if (adjacentOutput(server, cur.output, dir)) |out| {
        server.focused_output = out;
        if (firstClientOnOutput(server, out)) |target| {
            focusClient(server, target);
        } else {
            focusClient(server, null);
        }
    }
}

pub fn moveDirection(server: *Server, arg: []const u8) void {
    const dir = parseDir(arg) orelse return;
    const cur = server.focused orelse return;

    if (cur.floating) {
        const step: i32 = 30;
        switch (dir) {
            .left => cur.float_x -= step,
            .right => cur.float_x += step,
            .up => cur.float_y -= step,
            .down => cur.float_y += step,
        }
        arrangeOutput(server, cur.output);
        core.markDirty(server);
        return;
    }

    if (findDirectional(server, cur, dir, true)) |target| {
        if (target == cur) return;
        const i = core.clientIndex(server, cur) orelse return;
        const j = core.clientIndex(server, target) orelse return;
        server.clients[i] = target;
        server.clients[j] = cur;
        arrangeOutput(server, cur.output);
        focusClient(server, cur);
        core.markDirty(server);
        return;
    }

    if (adjacentOutput(server, cur.output, dir)) |out| {
        const old_out = cur.output;
        if (old_out.last_focused[cur.ws] == cur) old_out.last_focused[cur.ws] = null;
        cur.output = out;
        cur.ws = out.active_ws;
        out.last_focused[cur.ws] = cur;
        server.focused_output = out;
        arrangeOutput(server, old_out);
        arrangeOutput(server, out);
        focusClient(server, cur);
        core.markDirty(server);
    }
}

pub fn focusNext(server: *Server, step: i32) void {
    if (server.focused) |focused| {
        if (focused.group_id != 0) {
            groupNext(server, step);
            return;
        }
    }
    const out = core.focusOutput(server) orelse return;
    var list: [types.MAX_CLIENTS]?*Client = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (clientVisible(cl, out)) {
            list[n] = cl;
            n += 1;
        }
    }
    if (n == 0) return;

    var cur_idx: ?usize = null;
    if (server.focused) |fc| {
        var k: usize = 0;
        while (k < n) : (k += 1) {
            if (list[k] == fc) {
                cur_idx = k;
                break;
            }
        }
    }
    var next: usize = 0;
    if (cur_idx) |ci| {
        const nn: i32 = @as(i32, @intCast(ci)) + step;
        next = @intCast(@mod(nn, @as(i32, @intCast(n))));
    }
    focusClient(server, list[next]);
}

pub fn focusFirst(server: *Server) void {
    if (core.focusOutput(server)) |out| {
        var i: usize = 0;
        while (i < server.clients.len) : (i += 1) {
            const cl = server.clients[i] orelse continue;
            if (clientVisible(cl, out)) {
                focusClient(server, cl);
                return;
            }
        }
    }
    focusClient(server, null);
}

fn pinnedOutputFor(server: *Server, ws: usize) ?*Output {
    const pins = server.config.workspace_pins[0..server.config.workspace_pin_count];
    for (pins) |pin| {
        if (pin.ws != ws) continue;
        return core.outputByName(server, pin.output_name[0..pin.output_len]);
    }
    return null;
}

pub fn switchWorkspace(server: *Server, ws: usize) void {
    const out = core.focusOutput(server) orelse return;
    switchWorkspaceOnOutput(server, out, ws);
}

pub fn switchWorkspaceOnOutput(server: *Server, requested_out: *Output, ws: usize) void {
    if (ws < 1 or ws > types.WS_COUNT) return;
    const out = pinnedOutputFor(server, ws) orelse requested_out;
    const previous_ws = out.active_ws;
    out.active_ws = ws;
    out.scratchpad_visible = false;
    server.focused_output = out;
    server.active_ws = ws;
    startWorkspaceAnimation(server, out, previous_ws, ws);
    arrangeOutput(server, out);
    if (previous_ws != ws) {
        events.emit(server, .{
            .name = event_names.workspace_change,
            .workspace = ws,
            .previous_workspace = previous_ws,
            .output = core.outputName(out),
        });
    }

    var target: ?*Client = null;
    if (out.last_focused[ws]) |cl| {
        if (cl.mapped and cl.output == out and cl.ws == ws) target = cl;
    }
    if (target == null) {
        var i: usize = 0;
        while (i < server.clients.len) : (i += 1) {
            const cl = server.clients[i] orelse continue;
            if (cl.mapped and cl.output == out and cl.ws == ws) {
                target = cl;
                break;
            }
        }
    }
    focusClient(server, target);
    core.markDirty(server);
}

pub fn moveToWorkspace(server: *Server, ws: usize) void {
    if (ws < 1 or ws > types.WS_COUNT) return;
    const cl = server.focused orelse return;
    const out = cl.output;
    const old_ws = cl.ws;
    const target_out = pinnedOutputFor(server, ws) orelse out;
    if (old_ws == ws and target_out == out) return;

    if (target_out != out) {
        if (cl.floating) {
            cl.float_x += target_out.full.x - out.full.x;
            cl.float_y += target_out.full.y - out.full.y;
        }
        cl.output = target_out;
    }
    cl.ws = ws;
    detachFromGroup(cl);
    if (cl.scratchpad) {
        cl.scratchpad = false;
        cl.floating = false;
        cl.float_w = 0;
        cl.float_h = 0;
    }
    if (out.last_focused[old_ws] == cl) out.last_focused[old_ws] = null;
    target_out.last_focused[ws] = cl;

    var next: ?*Client = null;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const other = server.clients[i] orelse continue;
        if (other != cl and other.mapped and other.output == out and other.ws == old_ws) {
            next = other;
            break;
        }
    }
    if (target_out != out and target_out.active_ws == ws) {
        focusClient(server, cl);
    } else {
        focusClient(server, next);
    }
    arrangeOutput(server, out);
    if (target_out != out) arrangeOutput(server, target_out);
    events.emit(server, .{
        .name = event_names.window_moved,
        .id = cl.id,
        .workspace = ws,
        .previous_workspace = old_ws,
        .app_id = cl.app_id[0..cl.app_id_len],
        .title = cl.title[0..cl.title_len],
        .output = core.outputName(target_out),
    });
    core.markDirty(server);
}

pub fn toggleFloat(server: *Server) void {
    const cl = server.focused orelse return;
    if (cl.scratchpad) return;
    detachFromGroup(cl);
    cl.floating = !cl.floating;
    arrangeOutput(server, cl.output);
    focusClient(server, cl);
    core.markDirty(server);
}

pub fn toggleFullscreen(server: *Server) void {
    const cl = server.focused orelse return;
    cl.fullscreen = !cl.fullscreen;
    _ = c.wlr_xdg_toplevel_set_fullscreen(cl.xdg, cl.fullscreen);
    if (cl.foreign_toplevel) |handle| {
        c.wlr_foreign_toplevel_handle_v1_set_fullscreen(handle, cl.fullscreen);
    }
    arrangeOutput(server, cl.output);
    focusClient(server, cl);
    core.markDirty(server);
}

pub fn toggleScratchpad(server: *Server) void {
    const out = core.focusOutput(server) orelse return;
    out.scratchpad_visible = !out.scratchpad_visible;
    arrangeOutput(server, out);

    if (out.scratchpad_visible) {
        var target: ?*Client = null;
        var i: usize = 0;
        while (i < server.clients.len) : (i += 1) {
            const cl = server.clients[i] orelse continue;
            if (cl.mapped and cl.scratchpad and cl.output == out) {
                target = cl;
                break;
            }
        }
        if (target) |cl| focusClient(server, cl);
    } else if (server.focused) |focused| {
        if (focused.scratchpad and focused.output == out) {
            focusClient(server, firstClientOnOutput(server, out));
        }
    }
    updateBorders(server);
    core.markDirty(server);
}

pub fn moveToScratchpad(server: *Server) void {
    const cl = server.focused orelse return;
    const out = cl.output;
    detachFromGroup(cl);
    if (cl.scratchpad) {
        cl.scratchpad = false;
        cl.ws = out.active_ws;
        cl.floating = false;
        cl.float_w = 0;
        cl.float_h = 0;
        if (out.last_focused[out.active_ws] == null) out.last_focused[out.active_ws] = cl;
    } else {
        cl.scratchpad = true;
        cl.floating = true;
        cl.ws = out.active_ws;
        out.scratchpad_visible = true;
        if (cl.float_w <= 0 or cl.float_h <= 0) initFloatRect(cl, out);
    }
    arrangeOutput(server, out);
    focusClient(server, cl);
    core.markDirty(server);
}

pub fn toggleGroup(server: *Server) void {
    const out = core.focusOutput(server) orelse return;
    if (server.focused) |focused| {
        if (focused.group_id != 0) {
            const gid = focused.group_id;
            var i: usize = 0;
            while (i < server.clients.len) : (i += 1) {
                const cl = server.clients[i] orelse continue;
                if (cl.group_id != gid) continue;
                cl.group_id = 0;
                cl.group_active = true;
            }
            arrangeOutput(server, out);
            focusClient(server, focused);
            core.markDirty(server);
            return;
        }
    }

    var members: [types.MAX_CLIENTS]?*Client = undefined;
    var count: usize = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (!cl.mapped or cl.scratchpad or cl.floating) continue;
        if (cl.output != out or cl.ws != out.active_ws) continue;
        if (count < members.len) {
            members[count] = cl;
            count += 1;
        }
    }
    if (count == 0) return;

    server.next_group_id +%= 1;
    if (server.next_group_id == 0) server.next_group_id = 1;
    const gid = server.next_group_id;
    var active: *Client = members[0].?;
    if (server.focused) |focused| {
        var k: usize = 0;
        while (k < count) : (k += 1) {
            if (members[k].? == focused) {
                active = focused;
                break;
            }
        }
    }
    i = 0;
    while (i < count) : (i += 1) {
        const cl = members[i].?;
        cl.group_id = gid;
        cl.group_active = cl == active;
    }
    arrangeOutput(server, out);
    focusClient(server, active);
    core.markDirty(server);
}

pub fn groupNext(server: *Server, step: i32) void {
    const out = core.focusOutput(server) orelse return;
    const focused = server.focused orelse return;
    if (focused.group_id == 0) return;
    const gid = focused.group_id;

    var members: [types.MAX_CLIENTS]?*Client = undefined;
    var count: usize = 0;
    var current: ?usize = null;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.group_id != gid or !cl.mapped) continue;
        if (cl == focused) current = count;
        if (count < members.len) {
            members[count] = cl;
            count += 1;
        }
    }
    if (count <= 1) return;
    const at = current orelse 0;
    const next = @mod(@as(i32, @intCast(at)) + step, @as(i32, @intCast(count)));
    const target = members[@intCast(next)].?;
    activateGroupMember(target);
    arrangeOutput(server, out);
    focusClient(server, target);
    core.markDirty(server);
}

pub fn groupAdd(server: *Server) void {
    const cl = server.focused orelse return;
    if (cl.group_id != 0 or cl.floating or cl.scratchpad) return;
    const out = cl.output;
    var gid: u32 = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const other = server.clients[i] orelse continue;
        if (other == cl or other.group_id == 0 or !other.mapped) continue;
        if (other.output != out or other.ws != out.active_ws) continue;
        gid = other.group_id;
        break;
    }
    if (gid == 0) return;
    cl.group_id = gid;
    activateGroupMember(cl);
    arrangeOutput(server, out);
    focusClient(server, cl);
    core.markDirty(server);
}

pub fn groupRemove(server: *Server) void {
    const cl = server.focused orelse return;
    if (cl.group_id == 0) return;
    detachFromGroup(cl);
    cl.group_active = true;
    arrangeOutput(server, cl.output);
    focusClient(server, cl);
    core.markDirty(server);
}

pub fn closeFocused(server: *Server) void {
    const cl = server.focused orelse return;
    effects.requestClose(server, cl);
}

pub fn cycleLayout(server: *Server) void {
    const out = core.focusOutput(server) orelse return;
    const ws = out.active_ws;
    const current = out.ws_layouts[ws - 1];
    var next = types.layout_cycle[0];
    for (types.layout_cycle, 0..) |mode, index| {
        if (mode == current) {
            next = types.layout_cycle[(index + 1) % types.layout_cycle.len];
            break;
        }
    }
    out.ws_layouts[ws - 1] = next;
    out.layout_overridden[ws - 1] = true;
    persistLayouts(server);
    arrangeOutput(server, out);
    events.emit(server, .{
        .name = event_names.layout_change,
        .workspace = ws,
        .output = core.outputName(out),
        .arg = types.layoutName(next),
    });
    core.markDirty(server);
    core.logInfo("layout: {s} workspace {d} on {s}", .{ types.layoutName(next), ws, core.outputName(out) });
}

pub fn setLayoutOnOutput(server: *Server, out: *Output, name: []const u8) bool {
    const mode = types.layoutFromName(name) orelse return false;
    const ws = out.active_ws;
    if (out.ws_layouts[ws - 1] == mode) {
        out.layout_overridden[ws - 1] = true;
        persistLayouts(server);
        arrangeOutput(server, out);
        return true;
    }
    out.ws_layouts[ws - 1] = mode;
    out.layout_overridden[ws - 1] = true;
    persistLayouts(server);
    arrangeOutput(server, out);
    events.emit(server, .{
        .name = event_names.layout_change,
        .workspace = ws,
        .output = core.outputName(out),
        .arg = types.layoutName(mode),
    });
    core.markDirty(server);
    core.logInfo("layout: {s} workspace {d} on {s}", .{ types.layoutName(mode), ws, core.outputName(out) });
    return true;
}

pub fn setLayout(server: *Server, name: []const u8) bool {
    const out = core.focusOutput(server) orelse return false;
    return setLayoutOnOutput(server, out, name);
}

pub fn toggleLayout(server: *Server) void {
    cycleLayout(server);
}

pub fn adjustRatio(server: *Server, delta: f32) void {
    const out = core.focusOutput(server) orelse return;
    const ws = out.active_ws - 1;
    const current = rules.tuningFor(server, out, ws + 1).master_ratio;
    out.runtime_ratio[ws] = std.math.clamp(current + delta, 0.15, 0.9);
    out.runtime_ratio_set[ws] = true;
    arrangeAll(server);
    core.markDirty(server);
}

pub fn keyboardResize(server: *Server, dx: i32, dy: i32) void {
    const cl = server.focused orelse return;
    if (!cl.floating or cl.fullscreen or !cl.mapped) return;
    if (dx == 0 and dy == 0) return;
    if (cl.float_w <= 0 or cl.float_h <= 0) initFloatRect(cl, cl.output);

    const border = borderWidth(cl);
    const min_w = @max(160, border * 2 + cl.xdg.current.min_width);
    const min_h = @max(120, border * 2 + cl.xdg.current.min_height);

    var w = cl.float_w + dx;
    var h = cl.float_h + dy;
    if (w < min_w) w = min_w;
    if (h < min_h) h = min_h;

    const full = cl.output.full;
    if (full.width > 0) {
        const max_w = full.x + full.width - cl.float_x;
        if (max_w >= min_w) {
            w = @min(w, max_w);
        } else {
            w = min_w;
            cl.float_x = @max(full.x, full.x + full.width - min_w);
        }
    }
    if (full.height > 0) {
        const max_h = full.y + full.height - cl.float_y;
        if (max_h >= min_h) {
            h = @min(h, max_h);
        } else {
            h = min_h;
            cl.float_y = @max(full.y, full.y + full.height - min_h);
        }
    }

    cl.float_w = w;
    cl.float_h = h;
    applyFloating(cl, cl.output);
    core.markDirty(server);
}

pub fn beginInteractive(client: *Client, mode: types.CursorMode, edges: u32) void {
    const s = client.server;
    s.grabbed = client;
    s.cursor_mode = mode;
    if (mode == .move) {
        s.grab_x = s.cursor.x - @as(f64, @floatFromInt(client.frame.node.x));
        s.grab_y = s.cursor.y - @as(f64, @floatFromInt(client.frame.node.y));
    } else {
        const g = tBase(client.xdg).geometry;
        const border = borderWidth(client);
        const bx = @as(f64, @floatFromInt(client.x + border)) +
            (if (edges & c.WLR_EDGE_RIGHT != 0) @as(f64, @floatFromInt(g.width)) else 0);
        const by = @as(f64, @floatFromInt(client.y + border)) +
            (if (edges & c.WLR_EDGE_BOTTOM != 0) @as(f64, @floatFromInt(g.height)) else 0);
        s.grab_x = s.cursor.x - bx;
        s.grab_y = s.cursor.y - by;
        s.grab_box = .{
            .x = client.x,
            .y = client.y,
            .width = client.w,
            .height = client.h,
        };
        s.resize_edges = edges;
    }
}

pub fn finishInteractive(server: *Server) void {
    const cl = server.grabbed;
    server.grabbed = null;
    server.cursor_mode = .passthrough;
    if (cl) |client| {
        arrangeOutput(server, client.output);
        core.markDirty(server);
    }
}

pub fn resetInteractive(server: *Server) void {
    server.grabbed = null;
    server.cursor_mode = .passthrough;
}

pub fn updateInteractiveMove(server: *Server) void {
    const cl = server.grabbed orelse return;
    cl.float_x = @intFromFloat(@round(server.cursor.x - server.grab_x));
    cl.float_y = @intFromFloat(@round(server.cursor.y - server.grab_y));
    c.wlr_scene_node_set_position(&cl.frame.node, cl.float_x, cl.float_y);
    cl.x = cl.float_x;
    cl.y = cl.float_y;
}

pub fn updateInteractiveResize(server: *Server) void {
    const cl = server.grabbed orelse return;
    const bx: i32 = @intFromFloat(@round(server.cursor.x - server.grab_x));
    const by: i32 = @intFromFloat(@round(server.cursor.y - server.grab_y));
    var left = server.grab_box.x;
    var right = server.grab_box.x + server.grab_box.width;
    var top = server.grab_box.y;
    var bottom = server.grab_box.y + server.grab_box.height;

    if (server.resize_edges & c.WLR_EDGE_TOP != 0) top = by;
    if (server.resize_edges & c.WLR_EDGE_BOTTOM != 0) bottom = by;
    if (server.resize_edges & c.WLR_EDGE_LEFT != 0) left = bx;
    if (server.resize_edges & c.WLR_EDGE_RIGHT != 0) right = bx;

    const min: i32 = 200;
    if (right - left < min) {
        if (server.resize_edges & c.WLR_EDGE_LEFT != 0) {
            left = right - min;
        } else {
            right = left + min;
        }
    }
    if (bottom - top < min) {
        if (server.resize_edges & c.WLR_EDGE_TOP != 0) {
            top = bottom - min;
        } else {
            bottom = top + min;
        }
    }

    cl.float_x = left;
    cl.float_y = top;
    cl.float_w = right - left;
    cl.float_h = bottom - top;
    applyFrame(cl, cl.float_x, cl.float_y, cl.float_w, cl.float_h, borderWidth(cl), true);
}
