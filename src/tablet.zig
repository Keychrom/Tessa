const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const scene_util = @import("scene_util.zig");

const Server = types.Server;
const Tablet = types.Tablet;
const TabletTool = types.TabletTool;
const TabletPad = types.TabletPad;

fn tabletFrom(raw: [*c]c.wlr_tablet) *c.wlr_tablet {
    return @ptrCast(@alignCast(raw));
}

fn toolFrom(raw: [*c]c.wlr_tablet_tool) *c.wlr_tablet_tool {
    return @ptrCast(@alignCast(raw));
}

pub fn init(server: *Server) void {
    const raw = c.wlr_tablet_v2_create(server.display);
    if (raw == null) {
        core.logInfo("failed to create tablet-v2 manager", .{});
        return;
    }
    const mgr: *c.wlr_tablet_manager_v2 = @ptrCast(@alignCast(raw));
    server.tablet_manager = mgr;
    core.logInfo("tablet-v2 enabled", .{});
}

fn addToolState(tablet: *Tablet, tool: *c.wlr_tablet_tool) ?*TabletTool {
    const server = tablet.server;
    if (tool.data) |data| return @ptrCast(@alignCast(data));
    if (server.tablet_tool_count >= server.tablet_tools.len) return null;
    const mgr = server.tablet_manager orelse return null;
    const v2_raw = c.wlr_tablet_tool_create(mgr, server.seat, tool);
    if (v2_raw == null) return null;
    const v2: *c.wlr_tablet_v2_tablet_tool = @ptrCast(@alignCast(v2_raw));

    const state = @as(*TabletTool, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TabletTool)).?)));
    state.server = server;
    state.tablet = tablet;
    state.wlr = tool;
    state.v2 = v2;
    state.destroy.notify = onToolDestroy;
    c.wl_signal_add(&tool.events.destroy, &state.destroy);
    state.set_cursor.notify = onToolSetCursor;
    c.wl_signal_add(&v2.events.set_cursor, &state.set_cursor);
    tool.data = state;
    server.tablet_tools[server.tablet_tool_count] = state;
    server.tablet_tool_count += 1;
    core.logDebug("tablet tool added: type={d}", .{tool.type});
    return state;
}

fn onToolDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const state: *TabletTool = @fieldParentPtr("destroy", listener.?);
    const server = state.server;

    c.wl_list_remove(&state.destroy.link);
    c.wl_list_remove(&state.set_cursor.link);
    state.wlr.data = null;
    var i: usize = 0;
    while (i < server.tablet_tool_count) : (i += 1) {
        if (server.tablet_tools[i] != state) continue;
        server.tablet_tools[i] = server.tablet_tools[server.tablet_tool_count - 1];
        server.tablet_tools[server.tablet_tool_count - 1] = null;
        server.tablet_tool_count -= 1;
        break;
    }
    c.free(state);
}

fn onToolSetCursor(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const state: *TabletTool = @fieldParentPtr("set_cursor", listener.?);
    const event: *c.wlr_tablet_v2_event_cursor = @ptrCast(@alignCast(data.?));
    c.wlr_cursor_set_surface(state.server.cursor, event.surface, event.hotspot_x, event.hotspot_y);
}

fn destroyTablet(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const tablet: *Tablet = @fieldParentPtr("destroy", listener.?);
    const server = tablet.server;

    c.wl_list_remove(&tablet.axis.link);
    c.wl_list_remove(&tablet.proximity.link);
    c.wl_list_remove(&tablet.tip.link);
    c.wl_list_remove(&tablet.button.link);
    c.wl_list_remove(&tablet.destroy.link);

    var i: usize = 0;
    while (i < server.tablet_tool_count) : (i += 1) {
        const tool = server.tablet_tools[i] orelse continue;
        if (tool.tablet == tablet) tool.tablet = null;
    }
    i = 0;
    while (i < server.tablet_count) : (i += 1) {
        if (server.tablets[i] != tablet) continue;
        server.tablets[i] = server.tablets[server.tablet_count - 1];
        server.tablets[server.tablet_count - 1] = null;
        server.tablet_count -= 1;
        break;
    }
    c.free(tablet);
}

pub fn addTablet(server: *Server, device: *c.wlr_input_device) bool {
    if (!server.config.tablet) return false;
    const mgr = server.tablet_manager orelse return false;
    if (server.tablet_count >= server.tablets.len) return false;
    const wlr_raw = c.wlr_tablet_from_input_device(device);
    const wlr: *c.wlr_tablet = @ptrCast(@alignCast(wlr_raw));
    const v2_raw = c.wlr_tablet_create(mgr, server.seat, device);
    if (v2_raw == null) return false;
    const v2: *c.wlr_tablet_v2_tablet = @ptrCast(@alignCast(v2_raw));

    const tablet = @as(*Tablet, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Tablet)).?)));
    tablet.server = server;
    tablet.device = device;
    tablet.wlr = wlr;
    tablet.v2 = v2;
    tablet.axis.notify = onTabletAxis;
    c.wl_signal_add(&wlr.events.axis, &tablet.axis);
    tablet.proximity.notify = onTabletProximity;
    c.wl_signal_add(&wlr.events.proximity, &tablet.proximity);
    tablet.tip.notify = onTabletTip;
    c.wl_signal_add(&wlr.events.tip, &tablet.tip);
    tablet.button.notify = onTabletButton;
    c.wl_signal_add(&wlr.events.button, &tablet.button);
    tablet.destroy.notify = destroyTablet;
    c.wl_signal_add(&device.events.destroy, &tablet.destroy);
    server.tablets[server.tablet_count] = tablet;
    server.tablet_count += 1;
    core.logInfo("tablet added: {s}", .{core.cstr(device.name)});
    return true;
}

fn getTool(tablet: *Tablet, tool: *c.wlr_tablet_tool) ?*TabletTool {
    return addToolState(tablet, tool);
}

fn updateCursor(server: *Server, tablet: *c.wlr_tablet, x: f64, y: f64) void {
    c.wlr_cursor_warp_absolute(server.cursor, &tablet.base, x, y);
}

fn pointerMotion(server: *Server, time_msec: u32) void {
    var sx: f64 = 0;
    var sy: f64 = 0;
    if (scene_util.surfaceAt(server, server.cursor.x, server.cursor.y, &sx, &sy)) |surface| {
        c.wlr_seat_pointer_notify_enter(server.seat, surface, sx, sy);
        c.wlr_seat_pointer_notify_motion(server.seat, time_msec, sx, sy);
    } else {
        c.wlr_seat_pointer_clear_focus(server.seat);
    }
}

fn focusAt(server: *Server, time_msec: u32) bool {
    _ = time_msec;
    if (scene_util.clientAt(server, server.cursor.x, server.cursor.y)) |cl| {
        layout.focusClient(server, cl);
        return true;
    }
    var sx: f64 = 0;
    var sy: f64 = 0;
    if (scene_util.surfaceAt(server, server.cursor.x, server.cursor.y, &sx, &sy)) |surface| {
        if (scene_util.layerForSurface(server, surface)) |layer| {
            if (layer.wlr.current.keyboard_interactive != 0) {
                layout.focusLayer(server, layer);
                return true;
            }
        }
    }
    return false;
}

fn clearProximity(tool: *TabletTool) void {
    if (tool.surface != null) {
        c.wlr_tablet_v2_tablet_tool_notify_proximity_out(tool.v2);
        tool.surface = null;
    }
}

fn setProximity(tool: *TabletTool, surface: ?*c.wlr_surface) void {
    if (tool.surface == surface) return;
    if (tool.surface != null) {
        c.wlr_tablet_v2_tablet_tool_notify_proximity_out(tool.v2);
        tool.surface = null;
    }
    const next = surface orelse return;
    const tablet = tool.tablet orelse return;
    if (!c.wlr_surface_accepts_tablet_v2(next, tablet.v2)) return;
    c.wlr_tablet_v2_tablet_tool_notify_proximity_in(tool.v2, tablet.v2, next);
    tool.surface = next;
}

fn surfaceAccepts(tool: *TabletTool, surface: *c.wlr_surface) bool {
    const tablet = tool.tablet orelse return false;
    return c.wlr_surface_accepts_tablet_v2(surface, tablet.v2);
}

fn currentToolSurface(tool: *TabletTool) ?struct { surface: *c.wlr_surface, sx: f64, sy: f64 } {
    const server = tool.server;
    var sx: f64 = 0;
    var sy: f64 = 0;
    if (tool.surface != null and (tool.tablet_down or tool.buttons > 0)) {
        const surface = tool.surface.?;
        const origin = scene_util.surfaceOrigin(server, surface) orelse return null;
        return .{
            .surface = surface,
            .sx = server.cursor.x - origin.x,
            .sy = server.cursor.y - origin.y,
        };
    }
    const surface = scene_util.surfaceAt(server, server.cursor.x, server.cursor.y, &sx, &sy) orelse return null;
    if (!surfaceAccepts(tool, surface)) return null;
    return .{ .surface = surface, .sx = sx, .sy = sy };
}

fn onTabletProximity(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const tablet: *Tablet = @fieldParentPtr("proximity", listener.?);
    const event: *c.wlr_tablet_tool_proximity_event = @ptrCast(@alignCast(data.?));
    if (!tablet.server.config.tablet) return;
    const tool = getTool(tablet, toolFrom(event.tool)) orelse return;
    updateCursor(tablet.server, tabletFrom(event.tablet), event.x, event.y);

    if (event.state == c.WLR_TABLET_TOOL_PROXIMITY_OUT) {
        clearProximity(tool);
        return;
    }
    var sx: f64 = 0;
    var sy: f64 = 0;
    const surface = scene_util.surfaceAt(tablet.server, tablet.server.cursor.x, tablet.server.cursor.y, &sx, &sy);
    if (surface != null and surfaceAccepts(tool, surface.?)) {
        setProximity(tool, surface);
    } else {
        clearProximity(tool);
        pointerMotion(tablet.server, event.time_msec);
    }
}

fn onTabletAxis(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const tablet: *Tablet = @fieldParentPtr("axis", listener.?);
    const event: *c.wlr_tablet_tool_axis_event = @ptrCast(@alignCast(data.?));
    const server = tablet.server;
    if (!server.config.tablet) return;
    const tool = getTool(tablet, toolFrom(event.tool)) orelse return;

    const has_x = (event.updated_axes & c.WLR_TABLET_TOOL_AXIS_X) != 0;
    const has_y = (event.updated_axes & c.WLR_TABLET_TOOL_AXIS_Y) != 0;
    if (has_x or has_y) {
        const x = if (has_x) event.x else std.math.nan(f64);
        const y = if (has_y) event.y else std.math.nan(f64);
        c.wlr_cursor_warp_absolute(server.cursor, &tabletFrom(event.tablet).base, x, y);
    }

    const local = currentToolSurface(tool);
    if (local != null) {
        if (!tool.tablet_down and tool.buttons == 0) {
            setProximity(tool, local.?.surface);
        }
    } else {
        clearProximity(tool);
        pointerMotion(server, event.time_msec);
    }

    if (local) |pos| {
        c.wlr_tablet_v2_tablet_tool_notify_motion(tool.v2, pos.sx, pos.sy);
    }
    if ((event.updated_axes & c.WLR_TABLET_TOOL_AXIS_PRESSURE) != 0) {
        c.wlr_tablet_v2_tablet_tool_notify_pressure(tool.v2, event.pressure);
    }
    if ((event.updated_axes & c.WLR_TABLET_TOOL_AXIS_DISTANCE) != 0) {
        c.wlr_tablet_v2_tablet_tool_notify_distance(tool.v2, event.distance);
    }
    if ((event.updated_axes & (c.WLR_TABLET_TOOL_AXIS_TILT_X | c.WLR_TABLET_TOOL_AXIS_TILT_Y)) != 0) {
        c.wlr_tablet_v2_tablet_tool_notify_tilt(tool.v2, event.tilt_x, event.tilt_y);
    }
    if ((event.updated_axes & c.WLR_TABLET_TOOL_AXIS_ROTATION) != 0) {
        c.wlr_tablet_v2_tablet_tool_notify_rotation(tool.v2, event.rotation);
    }
    if ((event.updated_axes & c.WLR_TABLET_TOOL_AXIS_SLIDER) != 0) {
        c.wlr_tablet_v2_tablet_tool_notify_slider(tool.v2, event.slider);
    }
    if ((event.updated_axes & c.WLR_TABLET_TOOL_AXIS_WHEEL) != 0) {
        c.wlr_tablet_v2_tablet_tool_notify_wheel(tool.v2, event.wheel_delta, 0);
    }
}

fn onTabletTip(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const tablet: *Tablet = @fieldParentPtr("tip", listener.?);
    const event: *c.wlr_tablet_tool_tip_event = @ptrCast(@alignCast(data.?));
    const server = tablet.server;
    if (!server.config.tablet) return;
    const tool = getTool(tablet, toolFrom(event.tool)) orelse return;
    updateCursor(server, tabletFrom(event.tablet), event.x, event.y);

    if (event.state == c.WLR_TABLET_TOOL_TIP_UP) {
        if (tool.pointer_down) {
            _ = c.wlr_seat_pointer_notify_button(server.seat, event.time_msec, 0x110, c.WL_POINTER_BUTTON_STATE_RELEASED);
            c.wlr_seat_pointer_notify_frame(server.seat);
            tool.pointer_down = false;
        } else if (tool.tablet_down) {
            c.wlr_tablet_v2_tablet_tool_notify_up(tool.v2);
            tool.tablet_down = false;
        }
        return;
    }

    var sx: f64 = 0;
    var sy: f64 = 0;
    const surface = scene_util.surfaceAt(server, server.cursor.x, server.cursor.y, &sx, &sy);
    _ = focusAt(server, event.time_msec);
    if (surface != null and surfaceAccepts(tool, surface.?)) {
        setProximity(tool, surface);
        c.wlr_tablet_v2_tablet_tool_notify_down(tool.v2);
        c.wlr_tablet_tool_v2_start_implicit_grab(tool.v2);
        tool.tablet_down = true;
    } else {
        pointerMotion(server, event.time_msec);
        _ = c.wlr_seat_pointer_notify_button(server.seat, event.time_msec, 0x110, c.WL_POINTER_BUTTON_STATE_PRESSED);
        c.wlr_seat_pointer_notify_frame(server.seat);
        tool.pointer_down = true;
    }
}

fn onTabletButton(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const tablet: *Tablet = @fieldParentPtr("button", listener.?);
    const event: *c.wlr_tablet_tool_button_event = @ptrCast(@alignCast(data.?));
    const server = tablet.server;
    if (!server.config.tablet) return;
    const tool = getTool(tablet, toolFrom(event.tool)) orelse return;

    if (event.state == c.WLR_BUTTON_PRESSED) _ = focusAt(server, event.time_msec);
    const accepts = if (tool.surface) |surface| surfaceAccepts(tool, surface) else false;
    if (accepts) {
        c.wlr_tablet_v2_tablet_tool_notify_button(
            tool.v2,
            event.button,
            @intCast(event.state),
        );
        if (event.state == c.WLR_BUTTON_PRESSED) {
            tool.buttons += 1;
            c.wlr_tablet_tool_v2_start_implicit_grab(tool.v2);
        } else if (tool.buttons > 0) {
            tool.buttons -= 1;
        }
        return;
    }

    pointerMotion(server, event.time_msec);
    if (event.state == c.WLR_BUTTON_PRESSED) {
        _ = c.wlr_seat_pointer_notify_button(server.seat, event.time_msec, 0x111, c.WL_POINTER_BUTTON_STATE_PRESSED);
        tool.pointer_buttons += 1;
    } else if (tool.pointer_buttons > 0) {
        _ = c.wlr_seat_pointer_notify_button(server.seat, event.time_msec, 0x111, c.WL_POINTER_BUTTON_STATE_RELEASED);
        tool.pointer_buttons -= 1;
    }
    c.wlr_seat_pointer_notify_frame(server.seat);
}

pub fn addPad(server: *Server, device: *c.wlr_input_device) bool {
    if (!server.config.tablet) return false;
    const mgr = server.tablet_manager orelse return false;
    if (server.tablet_pad_count >= server.tablet_pads.len) return false;
    const wlr_raw = c.wlr_tablet_pad_from_input_device(device);
    const wlr: *c.wlr_tablet_pad = @ptrCast(@alignCast(wlr_raw));
    const v2_raw = c.wlr_tablet_pad_create(mgr, server.seat, device);
    if (v2_raw == null) return false;
    const v2: *c.wlr_tablet_v2_tablet_pad = @ptrCast(@alignCast(v2_raw));

    const pad = @as(*TabletPad, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TabletPad)).?)));
    pad.server = server;
    pad.device = device;
    pad.wlr = wlr;
    pad.v2 = v2;
    pad.attach.notify = onPadAttach;
    c.wl_signal_add(&wlr.events.attach_tablet, &pad.attach);
    pad.button.notify = onPadButton;
    c.wl_signal_add(&wlr.events.button, &pad.button);
    pad.ring.notify = onPadRing;
    c.wl_signal_add(&wlr.events.ring, &pad.ring);
    pad.strip.notify = onPadStrip;
    c.wl_signal_add(&wlr.events.strip, &pad.strip);
    pad.destroy.notify = destroyPad;
    c.wl_signal_add(&device.events.destroy, &pad.destroy);
    server.tablet_pads[server.tablet_pad_count] = pad;
    server.tablet_pad_count += 1;
    core.logInfo("tablet pad added: {s}", .{core.cstr(device.name)});
    return false;
}

fn onPadAttach(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const pad: *TabletPad = @fieldParentPtr("attach", listener.?);
    const tool_raw: [*c]c.wlr_tablet_tool = @ptrCast(@alignCast(data.?));
    const tool = toolFrom(tool_raw);
    const state = tool.data orelse return;
    const tt: *TabletTool = @ptrCast(@alignCast(state));
    if (tt.tablet) |tablet| pad.tablet_v2 = tablet.v2;
}

fn padTabletV2(pad: *TabletPad) ?*c.wlr_tablet_v2_tablet {
    if (pad.tablet_v2) |tablet| return tablet;
    const server = pad.server;
    var i: usize = 0;
    while (i < server.tablet_count) : (i += 1) {
        const tablet = server.tablets[i] orelse continue;
        pad.tablet_v2 = tablet.v2;
        return tablet.v2;
    }
    return null;
}

fn padReady(pad: *TabletPad) bool {
    const server = pad.server;
    const surface = server.seat.keyboard_state.focused_surface orelse
        server.seat.pointer_state.focused_surface orelse return false;
    const tablet_v2 = padTabletV2(pad) orelse return false;
    if (pad.enter_surface == surface) return true;
    if (pad.enter_surface) |old| _ = c.wlr_tablet_v2_tablet_pad_notify_leave(pad.v2, old);
    _ = c.wlr_tablet_v2_tablet_pad_notify_enter(pad.v2, tablet_v2, surface);
    pad.enter_surface = surface;
    return true;
}

fn onPadButton(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const pad: *TabletPad = @fieldParentPtr("button", listener.?);
    const event: *c.wlr_tablet_pad_button_event = @ptrCast(@alignCast(data.?));
    if (!padReady(pad)) return;
    _ = c.wlr_tablet_v2_tablet_pad_notify_mode(pad.v2, event.group, event.mode, event.time_msec);
    c.wlr_tablet_v2_tablet_pad_notify_button(pad.v2, event.button, event.time_msec, @intCast(event.state));
}

fn onPadRing(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const pad: *TabletPad = @fieldParentPtr("ring", listener.?);
    const event: *c.wlr_tablet_pad_ring_event = @ptrCast(@alignCast(data.?));
    if (!padReady(pad)) return;
    c.wlr_tablet_v2_tablet_pad_notify_ring(
        pad.v2,
        event.ring,
        event.position,
        event.source == c.WLR_TABLET_PAD_RING_SOURCE_FINGER,
        event.time_msec,
    );
}

fn onPadStrip(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const pad: *TabletPad = @fieldParentPtr("strip", listener.?);
    const event: *c.wlr_tablet_pad_strip_event = @ptrCast(@alignCast(data.?));
    if (!padReady(pad)) return;
    c.wlr_tablet_v2_tablet_pad_notify_strip(
        pad.v2,
        event.strip,
        event.position,
        event.source == c.WLR_TABLET_PAD_STRIP_SOURCE_FINGER,
        event.time_msec,
    );
}

fn destroyPad(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const pad: *TabletPad = @fieldParentPtr("destroy", listener.?);
    const server = pad.server;
    c.wl_list_remove(&pad.attach.link);
    c.wl_list_remove(&pad.button.link);
    c.wl_list_remove(&pad.ring.link);
    c.wl_list_remove(&pad.strip.link);
    c.wl_list_remove(&pad.destroy.link);
    var i: usize = 0;
    while (i < server.tablet_pad_count) : (i += 1) {
        if (server.tablet_pads[i] != pad) continue;
        server.tablet_pads[i] = server.tablet_pads[server.tablet_pad_count - 1];
        server.tablet_pads[server.tablet_pad_count - 1] = null;
        server.tablet_pad_count -= 1;
        break;
    }
    c.free(pad);
}

pub fn cleanup(server: *Server) void {
    var i: usize = 0;
    while (i < server.tablet_tool_count) : (i += 1) {
        const tool = server.tablet_tools[i] orelse continue;
        c.wl_list_remove(&tool.destroy.link);
        c.wl_list_remove(&tool.set_cursor.link);
        c.free(tool);
        server.tablet_tools[i] = null;
    }
    server.tablet_tool_count = 0;
    i = 0;
    while (i < server.tablet_count) : (i += 1) {
        const tablet = server.tablets[i] orelse continue;
        c.wl_list_remove(&tablet.axis.link);
        c.wl_list_remove(&tablet.proximity.link);
        c.wl_list_remove(&tablet.tip.link);
        c.wl_list_remove(&tablet.button.link);
        c.wl_list_remove(&tablet.destroy.link);
        c.free(tablet);
        server.tablets[i] = null;
    }
    server.tablet_count = 0;
    i = 0;
    while (i < server.tablet_pad_count) : (i += 1) {
        const pad = server.tablet_pads[i] orelse continue;
        c.wl_list_remove(&pad.attach.link);
        c.wl_list_remove(&pad.button.link);
        c.wl_list_remove(&pad.ring.link);
        c.wl_list_remove(&pad.strip.link);
        c.wl_list_remove(&pad.destroy.link);
        c.free(pad);
        server.tablet_pads[i] = null;
    }
    server.tablet_pad_count = 0;
}
