const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const ime = @import("ime.zig");
const idle = @import("idle.zig");

const Server = types.Server;
const Output = types.Output;
const LockSurface = types.LockSurface;

pub fn init(server: *Server) void {
    server.tree_lock = c.wlr_scene_tree_create(&server.scene.tree);

    const mgr_raw = c.wlr_session_lock_manager_v1_create(server.display);
    if (mgr_raw == null) return;
    const mgr: *c.wlr_session_lock_manager_v1 = @ptrCast(@alignCast(mgr_raw));
    server.session_lock_manager = mgr;
    server.new_session_lock.notify = onNewLock;
    c.wl_signal_add(&mgr.events.new_lock, &server.new_session_lock);
    core.logInfo("session-lock-v1 enabled", .{});
}

fn setDesktopEnabled(server: *Server, enabled: bool) void {
    const trees = [_]*c.wlr_scene_tree{
        server.tree_bg,
        server.tree_bottom,
        server.tree_windows,
        server.tree_floating,
        server.tree_top,
        server.tree_fullscreen,
        server.tree_effects,
        server.tree_overlay,
        server.tree_popup,
    };
    for (trees) |tree| {
        c.wlr_scene_node_set_enabled(&tree.node, enabled);
    }
}

fn blankOutputs(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        _ = c.wlr_scene_output_commit(out.scene_output, null);
    }
}

fn outputFor(server: *Server, wlr_out: *c.wlr_output) ?*Output {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        if (out.wlr == wlr_out) return out;
    }
    return null;
}

fn sceneNode(scene: *c.wlr_scene_surface) *c.wlr_scene_node {
    const buffer: *c.wlr_scene_buffer = @ptrCast(@alignCast(scene.buffer));
    return &buffer.node;
}

fn focusLockSurface(server: *Server, ls: *LockSurface) void {
    const kb_raw = c.wlr_seat_get_keyboard(server.seat);
    if (kb_raw == null) {
        c.wlr_seat_keyboard_clear_focus(server.seat);
        return;
    }
    const kb: *c.wlr_keyboard = @ptrCast(@alignCast(kb_raw));
    c.wlr_seat_keyboard_clear_focus(server.seat);
    c.wlr_seat_keyboard_notify_enter(
        server.seat,
        ls.wlr.surface,
        &kb.keycodes[0],
        kb.num_keycodes,
        &kb.modifiers,
    );
}

fn focusAtCursor(server: *Server, ls: *LockSurface) void {
    var box = c.wlr_box{ .x = 0, .y = 0, .width = 0, .height = 0 };
    core.outputBox(server, ls.output, &box);
    const x = server.cursor.x;
    const y = server.cursor.y;
    if (x < @as(f64, @floatFromInt(box.x)) or
        y < @as(f64, @floatFromInt(box.y)) or
        x >= @as(f64, @floatFromInt(box.x + box.width)) or
        y >= @as(f64, @floatFromInt(box.y + box.height))) return;
    focusLockSurface(server, ls);
    c.wlr_seat_pointer_notify_enter(
        server.seat,
        ls.wlr.surface,
        @floatCast(x - @as(f64, @floatFromInt(box.x))),
        @floatCast(y - @as(f64, @floatFromInt(box.y))),
    );
}

fn onNewLockSurface(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_lock_surface", listener.?);
    const wlr_ls: *c.wlr_session_lock_surface_v1 = @ptrCast(@alignCast(data.?));

    const out = outputFor(server, wlr_ls.output) orelse core.firstOutput(server) orelse return;
    var box = c.wlr_box{ .x = 0, .y = 0, .width = 0, .height = 0 };
    core.outputBox(server, out, &box);

    const scene_raw = c.wlr_scene_surface_create(server.tree_lock, wlr_ls.surface);
    if (scene_raw == null) return;
    const scene: *c.wlr_scene_surface = @ptrCast(@alignCast(scene_raw));
    c.wlr_scene_node_set_position(sceneNode(scene), box.x, box.y);

    const ls = @as(*LockSurface, @ptrCast(@alignCast(c.calloc(1, @sizeOf(LockSurface)).?)));
    ls.server = server;
    ls.wlr = wlr_ls;
    ls.output = out;
    ls.scene = scene;
    ls.destroy.notify = onLockSurfaceDestroy;
    c.wl_signal_add(&wlr_ls.events.destroy, &ls.destroy);

    if (server.lock_surface_count < server.lock_surfaces.len) {
        server.lock_surfaces[server.lock_surface_count] = ls;
        server.lock_surface_count += 1;
    } else {
        c.wlr_scene_node_destroy(sceneNode(scene));
        c.free(ls);
        return;
    }

    _ = c.wlr_session_lock_surface_v1_configure(
        wlr_ls,
        @intCast(@max(1, box.width)),
        @intCast(@max(1, box.height)),
    );
    if (server.seat.keyboard_state.focused_surface == null) {
        focusAtCursor(server, ls);
    }
    core.markDirty(server);
    core.logInfo("lock surface added", .{});
}

fn onLockSurfaceDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LockSurface = @fieldParentPtr("destroy", listener.?);
    const server = ls.server;

    c.wl_list_remove(&ls.destroy.link);
    c.wlr_scene_node_destroy(sceneNode(ls.scene));
    if (core.lockSurfaceIndex(server, ls)) |idx| {
        core.removeAt(types.LockSurface, server.lock_surfaces[0..], &server.lock_surface_count, idx);
    }
    c.free(ls);
}

pub fn focusForPosition(server: *Server, x: f64, y: f64) void {
    if (!server.locked) return;
    var i: usize = 0;
    while (i < server.lock_surfaces.len) : (i += 1) {
        const ls = server.lock_surfaces[i] orelse continue;
        var box = c.wlr_box{ .x = 0, .y = 0, .width = 0, .height = 0 };
        core.outputBox(server, ls.output, &box);
        if (x >= @as(f64, @floatFromInt(box.x)) and
            y >= @as(f64, @floatFromInt(box.y)) and
            x < @as(f64, @floatFromInt(box.x + box.width)) and
            y < @as(f64, @floatFromInt(box.y + box.height)))
        {
            if (server.seat.keyboard_state.focused_surface != ls.wlr.surface) {
                focusLockSurface(server, ls);
            }
            return;
        }
    }
}

fn onLockUnlock(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const server: *Server = @fieldParentPtr("lock_unlock", listener.?);
    if (server.session_lock == null) return;

    server.session_lock = null;
    server.locked = false;
    idle.updateInhibit(server);
    c.wl_list_remove(&server.new_lock_surface.link);
    c.wl_list_remove(&server.lock_unlock.link);
    c.wl_list_remove(&server.lock_destroy.link);
    // The client's unlock_and_destroy request destroys the lock resource
    // itself. Destroying it here would recurse into lock_destroy while the
    // unlock signal is still being emitted.

    setDesktopEnabled(server, true);
    if (server.lock_saved_layer) |layer| {
        server.lock_saved_layer = null;
        if (layer.mapped) {
            layout.focusLayer(server, layer);
        } else {
            layout.refreshKeyboardFocus(server);
        }
    } else {
        layout.refreshKeyboardFocus(server);
    }
    layout.arrangeAll(server);
    layout.updateBorders(server);
    core.markDirty(server);
    core.logInfo("session unlocked", .{});
}

fn onLockDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const server: *Server = @fieldParentPtr("lock_destroy", listener.?);

    c.wl_list_remove(&server.new_lock_surface.link);
    c.wl_list_remove(&server.lock_unlock.link);
    c.wl_list_remove(&server.lock_destroy.link);

    if (server.session_lock != null) {
        server.session_lock = null;
        if (server.locked) {
            core.logInfo("session lock client disappeared while locked; terminating", .{});
            c.wl_display_terminate(server.display);
        }
    }
}

fn onNewLock(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_session_lock", listener.?);
    const lock: *c.wlr_session_lock_v1 = @ptrCast(@alignCast(data.?));

    if (server.session_lock != null) {
        c.wlr_session_lock_v1_destroy(lock);
        return;
    }

    server.session_lock = lock;
    server.locked = true;
    idle.updateInhibit(server);
    server.lock_saved_layer = server.focused_layer;
    server.focused_layer = null;

    ime.focusSurface(server, null, 0, 0);
    c.wlr_seat_keyboard_clear_focus(server.seat);
    c.wlr_seat_pointer_clear_focus(server.seat);
    setDesktopEnabled(server, false);
    blankOutputs(server);

    server.new_lock_surface.notify = onNewLockSurface;
    c.wl_signal_add(&lock.events.new_surface, &server.new_lock_surface);
    server.lock_unlock.notify = onLockUnlock;
    c.wl_signal_add(&lock.events.unlock, &server.lock_unlock);
    server.lock_destroy.notify = onLockDestroy;
    c.wl_signal_add(&lock.events.destroy, &server.lock_destroy);

    c.wlr_session_lock_v1_send_locked(lock);
    core.logInfo("session locked", .{});
}
