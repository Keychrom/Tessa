const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const ipc = @import("ipc.zig");

const Server = types.Server;

pub fn init(server: *Server) void {
    const mgr = c.wlr_pointer_gestures_v1_create(server.display) orelse {
        core.logInfo("failed to create pointer-gestures-v1", .{});
        return;
    };
    server.pointer_gestures = mgr;

    server.gesture_swipe_begin.notify = onSwipeBegin;
    c.wl_signal_add(&server.cursor.events.swipe_begin, &server.gesture_swipe_begin);
    server.gesture_swipe_update.notify = onSwipeUpdate;
    c.wl_signal_add(&server.cursor.events.swipe_update, &server.gesture_swipe_update);
    server.gesture_swipe_end.notify = onSwipeEnd;
    c.wl_signal_add(&server.cursor.events.swipe_end, &server.gesture_swipe_end);

    server.gesture_pinch_begin.notify = onPinchBegin;
    c.wl_signal_add(&server.cursor.events.pinch_begin, &server.gesture_pinch_begin);
    server.gesture_pinch_update.notify = onPinchUpdate;
    c.wl_signal_add(&server.cursor.events.pinch_update, &server.gesture_pinch_update);
    server.gesture_pinch_end.notify = onPinchEnd;
    c.wl_signal_add(&server.cursor.events.pinch_end, &server.gesture_pinch_end);

    server.gesture_hold_begin.notify = onHoldBegin;
    c.wl_signal_add(&server.cursor.events.hold_begin, &server.gesture_hold_begin);
    server.gesture_hold_end.notify = onHoldEnd;
    c.wl_signal_add(&server.cursor.events.hold_end, &server.gesture_hold_end);

    core.logInfo("pointer-gestures-v1 enabled", .{});
    if (server.config.gestures) {
        core.logInfo("gestures: {d}-finger swipe, workspace threshold {d}, launcher threshold {d}", .{
            server.config.gesture_fingers,
            server.config.gesture_workspace_threshold,
            server.config.gesture_launcher_threshold,
        });
    }
}

fn shellSwipe(server: *Server, fingers: u32) bool {
    return server.config.gestures and
        !server.locked and
        server.focused_layer == null and
        fingers == @as(u32, @intCast(server.config.gesture_fingers));
}

fn onSwipeBegin(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("gesture_swipe_begin", listener.?);
    const event: *c.wlr_pointer_swipe_begin_event = @ptrCast(@alignCast(data.?));
    server.gesture_active = true;
    server.gesture_fingers = event.fingers;
    server.gesture_dx = 0;
    server.gesture_dy = 0;
    server.gesture_handled = false;
    server.gesture_forward = !shellSwipe(server, event.fingers);
    if (server.gesture_forward) {
        if (server.pointer_gestures) |mgr| {
            c.wlr_pointer_gestures_v1_send_swipe_begin(mgr, server.seat, event.time_msec, event.fingers);
        }
    }
}

fn onSwipeUpdate(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("gesture_swipe_update", listener.?);
    const event: *c.wlr_pointer_swipe_update_event = @ptrCast(@alignCast(data.?));

    if (server.gesture_forward) {
        if (server.pointer_gestures) |mgr| {
            c.wlr_pointer_gestures_v1_send_swipe_update(mgr, server.seat, event.time_msec, event.dx, event.dy);
        }
        return;
    }
    if (!server.gesture_active or server.gesture_handled) return;

    server.gesture_dx += event.dx;
    server.gesture_dy += event.dy;
    const dx = server.gesture_dx;
    const dy = server.gesture_dy;
    const horizontal = @abs(dx) > @abs(dy) * 1.25;
    const vertical = @abs(dy) > @abs(dx) * 1.25;

    if (horizontal and @abs(dx) >= @as(f64, @floatFromInt(server.config.gesture_workspace_threshold))) {
        const out = core.focusOutput(server) orelse return;
        const next: i32 = if (dx < 0)
            @as(i32, @intCast(out.active_ws)) + 1
        else
            @as(i32, @intCast(out.active_ws)) - 1;
        const clamped = std.math.clamp(next, 1, @as(i32, types.WS_COUNT));
        server.gesture_handled = true;
        if (@as(usize, @intCast(clamped)) != out.active_ws) {
            core.logDebug("gesture: workspace {d} -> {d}", .{ out.active_ws, clamped });
            layout.switchWorkspaceOnOutput(server, out, @intCast(clamped));
        }
        return;
    }

    if (vertical and dy < 0 and -dy >= @as(f64, @floatFromInt(server.config.gesture_launcher_threshold))) {
        server.gesture_handled = true;
        core.logDebug("gesture: launcher swipe", .{});
        ipc.emitLauncher(server, "");
    }
}

fn onSwipeEnd(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("gesture_swipe_end", listener.?);
    const event: *c.wlr_pointer_swipe_end_event = @ptrCast(@alignCast(data.?));
    if (server.gesture_forward) {
        if (server.pointer_gestures) |mgr| {
            c.wlr_pointer_gestures_v1_send_swipe_end(mgr, server.seat, event.time_msec, event.cancelled);
        }
    }
    server.gesture_active = false;
    server.gesture_handled = false;
    server.gesture_forward = false;
    server.gesture_dx = 0;
    server.gesture_dy = 0;
}

fn onPinchBegin(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("gesture_pinch_begin", listener.?);
    const event: *c.wlr_pointer_pinch_begin_event = @ptrCast(@alignCast(data.?));
    if (server.pointer_gestures) |mgr| {
        c.wlr_pointer_gestures_v1_send_pinch_begin(mgr, server.seat, event.time_msec, event.fingers);
    }
}

fn onPinchUpdate(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("gesture_pinch_update", listener.?);
    const event: *c.wlr_pointer_pinch_update_event = @ptrCast(@alignCast(data.?));
    if (server.pointer_gestures) |mgr| {
        c.wlr_pointer_gestures_v1_send_pinch_update(
            mgr,
            server.seat,
            event.time_msec,
            event.dx,
            event.dy,
            event.scale,
            event.rotation,
        );
    }
}

fn onPinchEnd(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("gesture_pinch_end", listener.?);
    const event: *c.wlr_pointer_pinch_end_event = @ptrCast(@alignCast(data.?));
    if (server.pointer_gestures) |mgr| {
        c.wlr_pointer_gestures_v1_send_pinch_end(mgr, server.seat, event.time_msec, event.cancelled);
    }
}

fn onHoldBegin(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("gesture_hold_begin", listener.?);
    const event: *c.wlr_pointer_hold_begin_event = @ptrCast(@alignCast(data.?));
    if (server.pointer_gestures) |mgr| {
        c.wlr_pointer_gestures_v1_send_hold_begin(mgr, server.seat, event.time_msec, event.fingers);
    }
}

fn onHoldEnd(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("gesture_hold_end", listener.?);
    const event: *c.wlr_pointer_hold_end_event = @ptrCast(@alignCast(data.?));
    if (server.pointer_gestures) |mgr| {
        c.wlr_pointer_gestures_v1_send_hold_end(mgr, server.seat, event.time_msec, event.cancelled);
    }
}

pub fn cleanup(server: *Server) void {
    if (server.pointer_gestures == null) return;
    c.wl_list_remove(&server.gesture_swipe_begin.link);
    c.wl_list_remove(&server.gesture_swipe_update.link);
    c.wl_list_remove(&server.gesture_swipe_end.link);
    c.wl_list_remove(&server.gesture_pinch_begin.link);
    c.wl_list_remove(&server.gesture_pinch_update.link);
    c.wl_list_remove(&server.gesture_pinch_end.link);
    c.wl_list_remove(&server.gesture_hold_begin.link);
    c.wl_list_remove(&server.gesture_hold_end.link);
}
