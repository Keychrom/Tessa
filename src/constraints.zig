const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const scene_util = @import("scene_util.zig");

const Server = types.Server;
const PointerConstraint = types.PointerConstraint;

pub fn init(server: *Server) void {
    const raw = c.wlr_pointer_constraints_v1_create(server.display);
    if (raw == null) {
        core.logInfo("failed to create pointer-constraints-v1", .{});
        return;
    }
    const mgr: *c.wlr_pointer_constraints_v1 = @ptrCast(@alignCast(raw));
    server.pointer_constraints_manager = mgr;
    server.new_pointer_constraint.notify = onNewConstraint;
    c.wl_signal_add(&mgr.events.new_constraint, &server.new_pointer_constraint);
    core.logInfo("pointer-constraints-v1 enabled", .{});
}

fn onNewConstraint(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_pointer_constraint", listener.?);
    const constraint: *c.wlr_pointer_constraint_v1 = @ptrCast(@alignCast(data.?));
    if (server.constraint_count >= server.constraints.len) return;

    const state = @as(*PointerConstraint, @ptrCast(@alignCast(c.calloc(1, @sizeOf(PointerConstraint)).?)));
    state.server = server;
    state.wlr = constraint;
    state.set_region.notify = onSetRegion;
    c.wl_signal_add(&constraint.events.set_region, &state.set_region);
    state.destroy.notify = onConstraintDestroy;
    c.wl_signal_add(&constraint.events.destroy, &state.destroy);
    server.constraints[server.constraint_count] = state;
    server.constraint_count += 1;

    core.logDebug("pointer constraint: {s} surface={*} lifetime={d}", .{
        if (constraint.type == c.WLR_POINTER_CONSTRAINT_V1_LOCKED) "locked" else "confined",
        constraint.surface,
        constraint.lifetime,
    });

    if (!server.config.pointer_constraints) return;
    if (server.seat.keyboard_state.focused_surface == constraint.surface) {
        activate(server, constraint);
    }
}

fn onSetRegion(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const state: *PointerConstraint = @fieldParentPtr("set_region", listener.?);
    const server = state.server;
    if (server.active_constraint == state.wlr) clampInside(server, state.wlr);
}

fn removeConstraint(server: *Server, state: *PointerConstraint) void {
    var i: usize = 0;
    while (i < server.constraint_count) : (i += 1) {
        if (server.constraints[i] != state) continue;
        server.constraints[i] = server.constraints[server.constraint_count - 1];
        server.constraints[server.constraint_count - 1] = null;
        server.constraint_count -= 1;
        return;
    }
}

fn onConstraintDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const state: *PointerConstraint = @fieldParentPtr("destroy", listener.?);
    const server = state.server;
    const constraint = state.wlr;

    c.wl_list_remove(&state.set_region.link);
    c.wl_list_remove(&state.destroy.link);
    removeConstraint(server, state);
    if (server.active_constraint == constraint) {
        server.active_constraint = null;
    }
    c.free(state);
}

fn warpToHint(server: *Server, constraint: *c.wlr_pointer_constraint_v1) void {
    if (!constraint.current.cursor_hint.enabled) return;
    const origin = scene_util.surfaceOrigin(server, constraint.surface) orelse return;
    const sx = constraint.current.cursor_hint.x;
    const sy = constraint.current.cursor_hint.y;
    _ = c.wlr_cursor_warp(server.cursor, null, origin.x + sx, origin.y + sy);
    c.wlr_seat_pointer_warp(server.seat, sx, sy);
}

fn clampInside(server: *Server, constraint: *c.wlr_pointer_constraint_v1) void {
    if (constraint.type == c.WLR_POINTER_CONSTRAINT_V1_LOCKED) {
        warpToHint(server, constraint);
        return;
    }
    const origin = scene_util.surfaceOrigin(server, constraint.surface) orelse return;
    const sx = server.cursor.x - origin.x;
    const sy = server.cursor.y - origin.y;
    if (c.pixman_region32_contains_point(&constraint.region, @intFromFloat(@floor(sx)), @intFromFloat(@floor(sy)), null) != 0) {
        return;
    }

    var n: c_int = 0;
    const boxes = c.pixman_region32_rectangles(&constraint.region, &n);
    if (boxes == null or n <= 0) return;

    var best_x: f64 = sx;
    var best_y: f64 = sy;
    var best_dist = std.math.floatMax(f64);
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        const box = boxes[i];
        const x = std.math.clamp(sx, @as(f64, @floatFromInt(box.x1)), @as(f64, @floatFromInt(box.x2)));
        const y = std.math.clamp(sy, @as(f64, @floatFromInt(box.y1)), @as(f64, @floatFromInt(box.y2)));
        const dist = (x - sx) * (x - sx) + (y - sy) * (y - sy);
        if (dist < best_dist) {
            best_dist = dist;
            best_x = x;
            best_y = y;
        }
    }
    if (best_dist == std.math.floatMax(f64)) return;
    _ = c.wlr_cursor_warp(server.cursor, null, origin.x + best_x, origin.y + best_y);
    c.wlr_seat_pointer_warp(server.seat, best_x, best_y);
}

pub fn activate(server: *Server, constraint: *c.wlr_pointer_constraint_v1) void {
    if (!server.config.pointer_constraints) return;
    if (server.active_constraint == constraint) return;
    deactivate(server);
    server.active_constraint = constraint;
    clampInside(server, constraint);
    c.wlr_pointer_constraint_v1_send_activated(constraint);
    core.logDebug("pointer constraint activated: {s}", .{
        if (constraint.type == c.WLR_POINTER_CONSTRAINT_V1_LOCKED) "locked" else "confined",
    });
}

pub fn deactivate(server: *Server) void {
    const constraint = server.active_constraint orelse return;
    server.active_constraint = null;
    warpToHint(server, constraint);
    c.wlr_pointer_constraint_v1_send_deactivated(constraint);
    core.logDebug("pointer constraint deactivated", .{});
}

pub fn focusSurface(server: *Server, surface: ?*c.wlr_surface) void {
    const mgr = server.pointer_constraints_manager orelse return;
    if (!server.config.pointer_constraints) {
        deactivate(server);
        return;
    }
    const focused = surface orelse {
        deactivate(server);
        return;
    };
    const constraint = c.wlr_pointer_constraints_v1_constraint_for_surface(mgr, focused, server.seat) orelse {
        deactivate(server);
        return;
    };
    activate(server, constraint);
}

pub fn reload(server: *Server) void {
    if (!server.config.pointer_constraints) {
        deactivate(server);
        return;
    }
    focusSurface(server, server.seat.keyboard_state.focused_surface);
}

pub fn isLocked(server: *Server) bool {
    const constraint = server.active_constraint orelse return false;
    return constraint.type == c.WLR_POINTER_CONSTRAINT_V1_LOCKED;
}

pub fn clampCursor(server: *Server) void {
    const constraint = server.active_constraint orelse return;
    clampInside(server, constraint);
}

/// Returns false when no constraint is active. When true, dx/dy have been
/// adjusted (possibly to zero) and the cursor must not move beyond them.
pub fn confineMotion(server: *Server, dx: *f64, dy: *f64) bool {
    const constraint = server.active_constraint orelse return false;
    if (constraint.type == c.WLR_POINTER_CONSTRAINT_V1_LOCKED) {
        dx.* = 0;
        dy.* = 0;
        return true;
    }
    const origin = scene_util.surfaceOrigin(server, constraint.surface) orelse {
        dx.* = 0;
        dy.* = 0;
        return true;
    };
    const sx = server.cursor.x - origin.x;
    const sy = server.cursor.y - origin.y;
    var out_x: f64 = 0;
    var out_y: f64 = 0;
    if (!c.wlr_region_confine(&constraint.region, sx, sy, sx + dx.*, sy + dy.*, &out_x, &out_y)) {
        dx.* = 0;
        dy.* = 0;
        return true;
    }
    dx.* = out_x - sx;
    dy.* = out_y - sy;
    return true;
}

pub fn cleanup(server: *Server) void {
    if (server.pointer_constraints_manager != null) {
        c.wl_list_remove(&server.new_pointer_constraint.link);
    }
    var i: usize = 0;
    while (i < server.constraints.len) : (i += 1) {
        const state = server.constraints[i] orelse continue;
        c.wl_list_remove(&state.set_region.link);
        c.wl_list_remove(&state.destroy.link);
        c.free(state);
        server.constraints[i] = null;
    }
    server.constraint_count = 0;
    server.active_constraint = null;
}
