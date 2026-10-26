const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;
const TextInput = types.TextInput;
const ImPopup = types.ImPopup;
const Keyboard = types.Keyboard;

pub fn init(server: *Server) void {
    server.tree_popup = c.wlr_scene_tree_create(&server.scene.tree);

    server.text_input_manager = c.wlr_text_input_manager_v3_create(server.display);
    if (server.text_input_manager) |mgr| {
        server.new_text_input.notify = onNewTextInput;
        c.wl_signal_add(&mgr.events.text_input, &server.new_text_input);
        core.logInfo("text-input-v3 enabled", .{});
    }

    server.input_method_manager = c.wlr_input_method_manager_v2_create(server.display);
    if (server.input_method_manager) |mgr| {
        server.new_input_method.notify = onNewInputMethod;
        c.wl_signal_add(&mgr.events.input_method, &server.new_input_method);
        core.logInfo("input-method-v2 enabled", .{});
    }
}

fn clientMatches(text_input: *c.wlr_text_input_v3, surface: *c.wlr_surface) bool {
    if (text_input.resource == null or surface.resource == null) return false;
    const a = c.wl_resource_get_client(text_input.resource);
    const b = c.wl_resource_get_client(surface.resource);
    return a != null and a == b;
}

fn focusedTextInput(server: *Server) ?*TextInput {
    var i: usize = 0;
    while (i < server.text_input_count) : (i += 1) {
        const ti = server.text_inputs[i] orelse continue;
        if (ti.input.focused_surface != null) return ti;
    }
    return null;
}

fn sendImState(server: *Server, ti: *TextInput) void {
    const im = server.input_method orelse return;
    const input = ti.input;

    if (input.current.surrounding.text != null) {
        c.wlr_input_method_v2_send_surrounding_text(
            im,
            input.current.surrounding.text,
            input.current.surrounding.cursor,
            input.current.surrounding.anchor,
        );
    }
    c.wlr_input_method_v2_send_text_change_cause(im, input.current.text_change_cause);
    c.wlr_input_method_v2_send_content_type(
        im,
        input.current.content_type.hint,
        input.current.content_type.purpose,
    );
    c.wlr_input_method_v2_send_done(im);
    positionPopups(server);
}

fn onTextInputEnable(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ti: *TextInput = @fieldParentPtr("enable", listener.?);
    const server = ti.server;
    core.logDebug("text input enable focused={}", .{ti.input.focused_surface != null});
    if (ti.input.focused_surface == null) return;
    const im = server.input_method orelse return;
    c.wlr_input_method_v2_send_activate(im);
    core.logDebug("ime sent activate (enable)", .{});
    sendImState(server, ti);
}

fn onTextInputCommit(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ti: *TextInput = @fieldParentPtr("commit", listener.?);
    const server = ti.server;
    if (ti.input.focused_surface == null or !ti.input.current_enabled) return;
    if (server.input_method == null) return;
    sendImState(server, ti);
}

fn onTextInputDisable(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ti: *TextInput = @fieldParentPtr("disable", listener.?);
    const server = ti.server;
    if (ti.input.focused_surface == null) return;
    if (server.input_method) |im| {
        c.wlr_input_method_v2_send_deactivate(im);
    }
    positionPopups(server);
}

fn onTextInputDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ti: *TextInput = @fieldParentPtr("destroy", listener.?);
    const server = ti.server;
    if (ti.input.current_enabled and ti.input.focused_surface != null) {
        if (server.input_method) |im| c.wlr_input_method_v2_send_deactivate(im);
    }
    c.wl_list_remove(&ti.enable.link);
    c.wl_list_remove(&ti.commit.link);
    c.wl_list_remove(&ti.disable.link);
    c.wl_list_remove(&ti.destroy.link);

    var i: usize = 0;
    while (i < server.text_inputs.len) : (i += 1) {
        if (server.text_inputs[i] == ti) {
            core.removeAt(types.TextInput, server.text_inputs[0..], &server.text_input_count, i);
            break;
        }
    }
    c.free(ti);
    positionPopups(server);
}

fn onNewTextInput(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_text_input", listener.?);
    const input: *c.wlr_text_input_v3 = @ptrCast(@alignCast(data.?));
    if (input.seat != server.seat) return;

    const ti = @as(*TextInput, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TextInput)).?)));
    ti.server = server;
    ti.input = input;

    core.logDebug("new text input", .{});

    ti.enable.notify = onTextInputEnable;
    c.wl_signal_add(&input.events.enable, &ti.enable);
    ti.commit.notify = onTextInputCommit;
    c.wl_signal_add(&input.events.commit, &ti.commit);
    ti.disable.notify = onTextInputDisable;
    c.wl_signal_add(&input.events.disable, &ti.disable);
    ti.destroy.notify = onTextInputDestroy;
    c.wl_signal_add(&input.events.destroy, &ti.destroy);

    if (server.text_input_count < server.text_inputs.len) {
        server.text_inputs[server.text_input_count] = ti;
        server.text_input_count += 1;
    } else {
        core.logInfo("too many text inputs", .{});
    }

    if (server.ime_focus_surface) |surface| {
        const matches = clientMatches(input, surface);
        core.logDebug("new text input focus match={} im={} enabled={}", .{
            matches,
            server.input_method != null,
            input.current_enabled,
        });
        if (matches) {
            c.wlr_text_input_v3_send_enter(input, surface);
            if (input.current_enabled) {
                if (server.input_method) |im| {
                    c.wlr_input_method_v2_send_activate(im);
                    sendImState(server, ti);
                }
            }
        }
    }
}

pub fn focusSurface(server: *Server, surface: ?*c.wlr_surface, ox: i32, oy: i32) void {
    core.logDebug("ime focus surface={} inputs={d} im={}", .{
        surface != null,
        server.text_input_count,
        server.input_method != null,
    });
    server.ime_focus_surface = surface;
    server.ime_focus_x = ox;
    server.ime_focus_y = oy;

    var i: usize = 0;
    while (i < server.text_input_count) : (i += 1) {
        const ti = server.text_inputs[i] orelse continue;
        const input = ti.input;

        if (input.focused_surface != null and input.focused_surface != surface) {
            c.wlr_text_input_v3_send_leave(input);
            if (input.current_enabled) {
                if (server.input_method) |im| c.wlr_input_method_v2_send_deactivate(im);
            }
        }

        if (surface) |s| {
            const matches = clientMatches(input, s);
            core.logDebug("ime input match={} focused={} enabled={}", .{
                matches,
                input.focused_surface != null,
                input.current_enabled,
            });
            if (matches) {
                if (input.focused_surface == null) {
                    c.wlr_text_input_v3_send_enter(input, s);
                    core.logDebug("ime sent enter", .{});
                }
                if (input.current_enabled) {
                    if (server.input_method) |im| {
                        c.wlr_input_method_v2_send_activate(im);
                        sendImState(server, ti);
                        core.logDebug("ime sent activate (focus)", .{});
                    }
                }
            }
        }
    }
    positionPopups(server);
}

fn onImCommit(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const server: *Server = @fieldParentPtr("im_commit", listener.?);
    const im = server.input_method orelse return;
    const ti = focusedTextInput(server) orelse return;
    const input = ti.input;
    core.logDebug("input method commit", .{});

    if (im.current.preedit.text != null) {
        c.wlr_text_input_v3_send_preedit_string(
            input,
            im.current.preedit.text,
            im.current.preedit.cursor_begin,
            im.current.preedit.cursor_end,
        );
    }
    if (im.current.commit_text != null) {
        c.wlr_text_input_v3_send_commit_string(input, im.current.commit_text);
    }
    if (im.current.delete.before_length != 0 or im.current.delete.after_length != 0) {
        c.wlr_text_input_v3_send_delete_surrounding_text(
            input,
            im.current.delete.before_length,
            im.current.delete.after_length,
        );
    }
    c.wlr_text_input_v3_send_done(input);
    positionPopups(server);
}

fn onImGrabKeyboard(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("im_grab_keyboard", listener.?);
    const grab: *c.wlr_input_method_keyboard_grab_v2 = @ptrCast(@alignCast(data.?));

    if (server.im_grab != null) {
        c.wl_list_remove(&server.im_grab_destroy.link);
    }
    server.im_grab = grab;

    const kb_raw = c.wlr_seat_get_keyboard(server.seat);
    if (kb_raw != null) {
        const kb: *c.wlr_keyboard = @ptrCast(@alignCast(kb_raw));
        c.wlr_input_method_keyboard_grab_v2_set_keyboard(grab, kb);
        c.wlr_input_method_keyboard_grab_v2_send_modifiers(grab, &kb.modifiers);
    }

    server.im_grab_destroy.notify = onImGrabDestroy;
    c.wl_signal_add(&grab.events.destroy, &server.im_grab_destroy);
    core.logInfo("input method grabbed keyboard", .{});
}

fn onImGrabDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const server: *Server = @fieldParentPtr("im_grab_destroy", listener.?);

    c.wl_list_remove(&server.im_grab_destroy.link);
    server.im_grab = null;

    const kb_raw = c.wlr_seat_get_keyboard(server.seat);
    if (kb_raw) |kb_ptr| {
        const kb: *c.wlr_keyboard = @ptrCast(@alignCast(kb_ptr));
        c.wlr_seat_set_keyboard(server.seat, kb);
        c.wlr_seat_keyboard_notify_modifiers(server.seat, &kb.modifiers);
    }
    core.logInfo("input method released keyboard", .{});
}

fn onImDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const server: *Server = @fieldParentPtr("im_destroy", listener.?);
    c.wl_list_remove(&server.im_commit.link);
    c.wl_list_remove(&server.im_grab_keyboard.link);
    c.wl_list_remove(&server.im_destroy.link);
    c.wl_list_remove(&server.im_new_popup.link);
    if (server.im_grab != null) {
        c.wl_list_remove(&server.im_grab_destroy.link);
        server.im_grab = null;
    }
    server.input_method = null;

    if (focusedTextInput(server)) |ti| {
        c.wlr_text_input_v3_send_leave(ti.input);
    }
    positionPopups(server);
    core.logInfo("input method disconnected", .{});
}

fn onNewInputMethod(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_input_method", listener.?);
    const im: *c.wlr_input_method_v2 = @ptrCast(@alignCast(data.?));
    if (im.seat != server.seat) return;
    if (server.input_method != null) {
        c.wlr_input_method_v2_send_unavailable(im);
        return;
    }
    server.input_method = im;

    server.im_commit.notify = onImCommit;
    c.wl_signal_add(&im.events.commit, &server.im_commit);
    server.im_grab_keyboard.notify = onImGrabKeyboard;
    c.wl_signal_add(&im.events.grab_keyboard, &server.im_grab_keyboard);
    server.im_destroy.notify = onImDestroy;
    c.wl_signal_add(&im.events.destroy, &server.im_destroy);
    server.im_new_popup.notify = onNewPopupSurface;
    c.wl_signal_add(&im.events.new_popup_surface, &server.im_new_popup);

    if (server.ime_focus_surface) |surface| {
        var i: usize = 0;
        while (i < server.text_input_count) : (i += 1) {
            const ti = server.text_inputs[i] orelse continue;
            if (!clientMatches(ti.input, surface)) continue;
            if (ti.input.focused_surface == null) {
                c.wlr_text_input_v3_send_enter(ti.input, surface);
            }
            if (ti.input.current_enabled) {
                c.wlr_input_method_v2_send_activate(im);
                sendImState(server, ti);
            }
        }
    }
    positionPopups(server);
    core.logInfo("input method connected", .{});
}

pub fn forwardKeyToGrab(server: *Server, kb: *Keyboard, event: *c.wlr_keyboard_key_event) bool {
    const grab = server.im_grab orelse return false;
    if (kb.virtual_keyboard) |vk| {
        if (vk.resource != null and grab.resource != null and
            c.wl_resource_get_client(vk.resource) == c.wl_resource_get_client(grab.resource))
        {
            return false;
        }
    }
    c.wlr_input_method_keyboard_grab_v2_set_keyboard(grab, kb.wlr);
    c.wlr_input_method_keyboard_grab_v2_send_key(grab, event.time_msec, event.keycode, @intCast(event.state));
    return true;
}

pub fn forwardModifiersToGrab(server: *Server, kb: *Keyboard) bool {
    const grab = server.im_grab orelse return false;
    if (kb.virtual_keyboard) |vk| {
        if (vk.resource != null and grab.resource != null and
            c.wl_resource_get_client(vk.resource) == c.wl_resource_get_client(grab.resource))
        {
            return false;
        }
    }
    c.wlr_input_method_keyboard_grab_v2_set_keyboard(grab, kb.wlr);
    c.wlr_input_method_keyboard_grab_v2_send_modifiers(grab, &kb.wlr.modifiers);
    return true;
}

fn onPopupMap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup: *ImPopup = @fieldParentPtr("map", listener.?);
    popup.mapped = true;
    positionPopups(popup.server);
}

fn onPopupUnmap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup: *ImPopup = @fieldParentPtr("unmap", listener.?);
    popup.mapped = false;
    c.wlr_scene_node_set_enabled(&popup.scene.node, false);
}

fn onPopupCommit(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup: *ImPopup = @fieldParentPtr("commit", listener.?);
    positionPopups(popup.server);
}

fn onPopupDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const popup: *ImPopup = @fieldParentPtr("destroy", listener.?);
    const server = popup.server;
    c.wl_list_remove(&popup.map.link);
    c.wl_list_remove(&popup.unmap.link);
    c.wl_list_remove(&popup.commit.link);
    c.wl_list_remove(&popup.destroy.link);
    c.wlr_scene_node_destroy(&popup.scene.node);
    if (core.popupIndex(server, popup)) |idx| {
        core.removeAt(types.ImPopup, server.im_popups[0..], &server.im_popup_count, idx);
    }
    c.free(popup);
}

fn onNewPopupSurface(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("im_new_popup", listener.?);
    const popup_surface: *c.wlr_input_popup_surface_v2 = @ptrCast(@alignCast(data.?));
    core.logDebug("im popup surface created", .{});

    const popup = @as(*ImPopup, @ptrCast(@alignCast(c.calloc(1, @sizeOf(ImPopup)).?)));
    popup.server = server;
    popup.popup = popup_surface;
    popup.mapped = false;
    const surface: *c.wlr_surface = @ptrCast(@alignCast(popup_surface.surface));
    const tree_raw = c.wlr_scene_subsurface_tree_create(server.tree_popup, surface) orelse {
        c.free(popup);
        return;
    };
    const tree: *c.wlr_scene_tree = @ptrCast(@alignCast(tree_raw));
    popup.scene = tree;
    c.wlr_scene_node_set_enabled(&tree.node, false);

    popup.map.notify = onPopupMap;
    c.wl_signal_add(&surface.events.map, &popup.map);
    popup.unmap.notify = onPopupUnmap;
    c.wl_signal_add(&surface.events.unmap, &popup.unmap);
    popup.commit.notify = onPopupCommit;
    c.wl_signal_add(&surface.events.commit, &popup.commit);
    popup.destroy.notify = onPopupDestroy;
    c.wl_signal_add(&popup_surface.events.destroy, &popup.destroy);

    if (server.im_popup_count < server.im_popups.len) {
        server.im_popups[server.im_popup_count] = popup;
        server.im_popup_count += 1;
    } else {
        c.wlr_scene_node_destroy(&tree.node);
        c.free(popup);
        return;
    }
    positionPopups(server);
}

fn positionPopups(server: *Server) void {
    const ti = focusedTextInput(server);
    var cursor = c.wlr_box{ .x = 0, .y = 0, .width = 0, .height = 0 };
    if (ti) |t| {
        const rect = t.input.current.cursor_rectangle;
        if (rect.width > 0 or rect.height > 0) cursor = rect;
    }

    var i: usize = 0;
    while (i < server.im_popup_count) : (i += 1) {
        const popup = server.im_popups[i] orelse continue;
        if (!popup.mapped or ti == null) {
            c.wlr_scene_node_set_enabled(&popup.scene.node, false);
            continue;
        }
        const surf = popup.popup.surface;
        if (surf == null) continue;
        const pw: i32 = @intCast(surf.*.current.width);
        const ph: i32 = @intCast(surf.*.current.height);

        var x = server.ime_focus_x + cursor.x;
        var y = server.ime_focus_y + cursor.y + cursor.height + 4;
        if (core.firstOutput(server)) |out| {
            const right = out.full.x + out.full.width;
            const bottom = out.full.y + out.full.height;
            if (x + pw > right) x = right - pw;
            if (x < out.full.x) x = out.full.x;
            if (y + ph > bottom) y = server.ime_focus_y + cursor.y - ph - 4;
            if (y < out.full.y) y = out.full.y;
        }
        c.wlr_scene_node_set_position(&popup.scene.node, x, y);
        c.wlr_scene_node_set_enabled(&popup.scene.node, true);
        core.logDebug("im popup pos {d},{d} size {d}x{d} cursor {d},{d}", .{ x, y, pw, ph, cursor.x, cursor.y });

        var box = c.wlr_box{
            .x = server.ime_focus_x + cursor.x - x,
            .y = server.ime_focus_y + cursor.y - y,
            .width = cursor.width,
            .height = cursor.height,
        };
        c.wlr_input_popup_surface_v2_send_text_input_rectangle(popup.popup, &box);
    }
}
