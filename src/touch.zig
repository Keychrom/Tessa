const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const lock = @import("lock.zig");
const scene_util = @import("scene_util.zig");

const Server = types.Server;

pub fn init(server: *Server) void {
    server.cursor_touch_down.notify = onTouchDown;
    c.wl_signal_add(&server.cursor.events.touch_down, &server.cursor_touch_down);
    server.cursor_touch_up.notify = onTouchUp;
    c.wl_signal_add(&server.cursor.events.touch_up, &server.cursor_touch_up);
    server.cursor_touch_motion.notify = onTouchMotion;
    c.wl_signal_add(&server.cursor.events.touch_motion, &server.cursor_touch_motion);
    server.cursor_touch_cancel.notify = onTouchCancel;
    c.wl_signal_add(&server.cursor.events.touch_cancel, &server.cursor_touch_cancel);
    server.cursor_touch_frame.notify = onTouchFrame;
    c.wl_signal_add(&server.cursor.events.touch_frame, &server.cursor_touch_frame);
}

fn touchDevice(touch: [*c]c.wlr_touch) *c.wlr_touch {
    return @ptrCast(@alignCast(touch));
}

fn layoutCoords(server: *Server, event: *c.wlr_touch_down_event) struct { x: f64, y: f64 } {
    var lx: f64 = 0;
    var ly: f64 = 0;
    c.wlr_cursor_absolute_to_layout_coords(server.cursor, &touchDevice(event.touch).base, event.x, event.y, &lx, &ly);
    return .{ .x = lx, .y = ly };
}

fn focusAt(server: *Server, surface: *c.wlr_surface, lx: f64, ly: f64) void {
    if (server.locked) {
        lock.focusForPosition(server, lx, ly);
        return;
    }
    if (scene_util.clientAt(server, lx, ly)) |cl| {
        if (server.focused != cl) layout.focusClient(server, cl);
        return;
    }
    if (scene_util.layerForSurface(server, surface)) |layer| {
        if (server.focused_layer != layer and layer.wlr.current.keyboard_interactive != 0) {
            layout.focusLayer(server, layer);
        }
    }
}

fn onTouchDown(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_touch_down", listener.?);
    const event: *c.wlr_touch_down_event = @ptrCast(@alignCast(data.?));

    var sx: f64 = 0;
    var sy: f64 = 0;
    const pos = layoutCoords(server, event);
    const surface = scene_util.surfaceAt(server, pos.x, pos.y, &sx, &sy) orelse return;
    focusAt(server, surface, pos.x, pos.y);
    _ = c.wlr_seat_touch_notify_down(server.seat, surface, event.time_msec, event.touch_id, sx, sy);
    core.logDebug("touch: down id={d} at {d:.0},{d:.0}", .{ event.touch_id, pos.x, pos.y });
}

fn onTouchUp(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_touch_up", listener.?);
    const event: *c.wlr_touch_up_event = @ptrCast(@alignCast(data.?));
    if (c.wlr_seat_touch_get_point(server.seat, event.touch_id) == null) return;
    _ = c.wlr_seat_touch_notify_up(server.seat, event.time_msec, event.touch_id);
}

fn onTouchMotion(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_touch_motion", listener.?);
    const event: *c.wlr_touch_motion_event = @ptrCast(@alignCast(data.?));
    const point_raw = c.wlr_seat_touch_get_point(server.seat, event.touch_id) orelse return;
    const point: *c.wlr_touch_point = @ptrCast(@alignCast(point_raw));
    const surface = point.surface orelse return;

    var lx: f64 = 0;
    var ly: f64 = 0;
    c.wlr_cursor_absolute_to_layout_coords(server.cursor, &touchDevice(event.touch).base, event.x, event.y, &lx, &ly);
    const origin = scene_util.surfaceOrigin(server, surface) orelse return;
    c.wlr_seat_touch_notify_motion(server.seat, event.time_msec, event.touch_id, lx - origin.x, ly - origin.y);
}

fn onTouchCancel(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_touch_cancel", listener.?);
    const event: *c.wlr_touch_cancel_event = @ptrCast(@alignCast(data.?));
    const point_raw = c.wlr_seat_touch_get_point(server.seat, event.touch_id) orelse return;
    const point: *c.wlr_touch_point = @ptrCast(@alignCast(point_raw));
    const client = point.focus_client orelse return;
    _ = c.wlr_seat_touch_notify_cancel(server.seat, client);
}

fn onTouchFrame(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const server: *Server = @fieldParentPtr("cursor_touch_frame", listener.?);
    c.wlr_seat_touch_notify_frame(server.seat);
}

pub fn cleanup(server: *Server) void {
    c.wl_list_remove(&server.cursor_touch_down.link);
    c.wl_list_remove(&server.cursor_touch_up.link);
    c.wl_list_remove(&server.cursor_touch_motion.link);
    c.wl_list_remove(&server.cursor_touch_cancel.link);
    c.wl_list_remove(&server.cursor_touch_frame.link);
}
