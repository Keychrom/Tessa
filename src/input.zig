const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const ipc = @import("ipc.zig");
const ime = @import("ime.zig");
const lock = @import("lock.zig");
const idle = @import("idle.zig");

const Server = types.Server;
const Client = types.Client;
const Keyboard = types.Keyboard;
const Binding = types.Binding;

pub fn init(server: *Server) void {
    server.cursor = c.wlr_cursor_create() orelse {
        core.logInfo("failed to create cursor", .{});
        return;
    };
    c.wlr_cursor_attach_output_layout(server.cursor, server.output_layout);

    server.cursor_mgr = c.wlr_xcursor_manager_create(null, 24) orelse {
        core.logInfo("failed to create xcursor manager", .{});
        return;
    };
    _ = c.wlr_xcursor_manager_load(server.cursor_mgr, 1);

    server.seat = c.wlr_seat_create(server.display, "seat0") orelse {
        core.logInfo("failed to create seat", .{});
        return;
    };

    server.new_input.notify = onNewInput;
    c.wl_signal_add(&server.backend.events.new_input, &server.new_input);

    server.cursor_motion.notify = onCursorMotion;
    c.wl_signal_add(&server.cursor.events.motion, &server.cursor_motion);
    server.cursor_motion_absolute.notify = onCursorMotionAbsolute;
    c.wl_signal_add(&server.cursor.events.motion_absolute, &server.cursor_motion_absolute);
    server.cursor_button.notify = onCursorButton;
    c.wl_signal_add(&server.cursor.events.button, &server.cursor_button);
    server.cursor_axis.notify = onCursorAxis;
    c.wl_signal_add(&server.cursor.events.axis, &server.cursor_axis);
    server.cursor_frame.notify = onCursorFrame;
    c.wl_signal_add(&server.cursor.events.frame, &server.cursor_frame);

    server.request_cursor.notify = onRequestCursor;
    c.wl_signal_add(&server.seat.events.request_set_cursor, &server.request_cursor);
    server.request_set_selection.notify = onRequestSetSelection;
    c.wl_signal_add(&server.seat.events.request_set_selection, &server.request_set_selection);

    _ = c.wlr_primary_selection_v1_device_manager_create(server.display);
    server.request_set_primary_selection.notify = onRequestSetPrimarySelection;
    c.wl_signal_add(&server.seat.events.request_set_primary_selection, &server.request_set_primary_selection);

    server.virtual_keyboard_manager = c.wlr_virtual_keyboard_manager_v1_create(server.display);
    if (server.virtual_keyboard_manager) |mgr| {
        server.new_virtual_keyboard.notify = onNewVirtualKeyboard;
        c.wl_signal_add(&mgr.events.new_virtual_keyboard, &server.new_virtual_keyboard);
    }

    const shape_mgr_raw = c.wlr_cursor_shape_manager_v1_create(server.display, 1);
    if (shape_mgr_raw != null) {
        const shape_mgr: *c.wlr_cursor_shape_manager_v1 = @ptrCast(@alignCast(shape_mgr_raw));
        server.request_set_shape.notify = onRequestSetShape;
        c.wl_signal_add(&shape_mgr.events.request_set_shape, &server.request_set_shape);
    }

    addSyntheticKeyboard(server);
    idle.init(server);
}

// Headless sessions and XWayland need a seat keymap before the first physical
// keyboard appears. This fallback keyboard provides it without generating input.
var synthetic_keyboard_impl = c.wlr_keyboard_impl{
    .name = "tessa-fallback",
    .led_update = null,
};

fn buildKeymap(server: *Server) ?*c.xkb_keymap {
    const cfg = &server.config;
    var names = std.mem.zeroes(c.xkb_rule_names);
    var rules_buf: [65:0]u8 = undefined;
    var model_buf: [65:0]u8 = undefined;
    var layout_buf: [65:0]u8 = undefined;
    var variant_buf: [65:0]u8 = undefined;
    var options_buf: [129:0]u8 = undefined;

    if (cfg.kb_rules_len > 0) {
        core.copyZ(&rules_buf, cfg.kb_rules[0..cfg.kb_rules_len]);
        names.rules = @ptrCast(&rules_buf);
    }
    if (cfg.kb_model_len > 0) {
        core.copyZ(&model_buf, cfg.kb_model[0..cfg.kb_model_len]);
        names.model = @ptrCast(&model_buf);
    }
    if (cfg.kb_layout_len > 0) {
        core.copyZ(&layout_buf, cfg.kb_layout[0..cfg.kb_layout_len]);
        names.layout = @ptrCast(&layout_buf);
    }
    if (cfg.kb_variant_len > 0) {
        core.copyZ(&variant_buf, cfg.kb_variant[0..cfg.kb_variant_len]);
        names.variant = @ptrCast(&variant_buf);
    }
    if (cfg.kb_options_len > 0) {
        core.copyZ(&options_buf, cfg.kb_options[0..cfg.kb_options_len]);
        names.options = @ptrCast(&options_buf);
    }

    const ctx = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse return null;
    defer c.xkb_context_unref(ctx);
    return c.xkb_keymap_new_from_names(ctx, &names, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
}

fn applyKeymap(server: *Server, wlr_kb: *c.wlr_keyboard) bool {
    const keymap = buildKeymap(server) orelse {
        core.logInfo("failed to compile keymap", .{});
        return false;
    };
    defer c.xkb_keymap_unref(keymap);
    if (!c.wlr_keyboard_set_keymap(wlr_kb, keymap)) {
        core.logInfo("failed to set keymap", .{});
        return false;
    }
    c.wlr_keyboard_set_repeat_info(wlr_kb, server.config.repeat_rate, server.config.repeat_delay);
    return true;
}

fn addSyntheticKeyboard(server: *Server) void {
    const wlr_kb = @as(*c.wlr_keyboard, @ptrCast(@alignCast(c.calloc(1, @sizeOf(c.wlr_keyboard)).?)));
    c.wlr_keyboard_init(wlr_kb, &synthetic_keyboard_impl, "tessa-fallback");
    wlr_kb.data = null;

    if (!applyKeymap(server, wlr_kb)) {
        c.wlr_keyboard_finish(wlr_kb);
        c.free(wlr_kb);
        return;
    }

    attachKeyboard(server, wlr_kb, &wlr_kb.base, null);
    core.logInfo("fallback keyboard ready", .{});
}

fn updateCapabilities(server: *Server) void {
    var caps: u32 = c.WL_SEAT_CAPABILITY_POINTER;
    if (server.keyboard_count > 0) caps |= c.WL_SEAT_CAPABILITY_KEYBOARD;
    c.wlr_seat_set_capabilities(server.seat, caps);
}

fn onNewInput(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_input", listener.?);
    const device: *c.wlr_input_device = @ptrCast(@alignCast(data.?));

    if (device.type == c.WLR_INPUT_DEVICE_KEYBOARD) {
        addKeyboard(server, device);
    } else if (device.type == c.WLR_INPUT_DEVICE_POINTER) {
        c.wlr_cursor_attach_input_device(server.cursor, device);
    }
    updateCapabilities(server);
}

fn addKeyboard(server: *Server, device: *c.wlr_input_device) void {
    const wlr_kb_raw = c.wlr_keyboard_from_input_device(device);
    const wlr_kb: *c.wlr_keyboard = @ptrCast(@alignCast(wlr_kb_raw));

    if (!applyKeymap(server, wlr_kb)) return;

    attachKeyboard(server, wlr_kb, device, null);
    core.logInfo("keyboard added: {s}", .{core.cstr(device.name)});
}

fn attachKeyboard(server: *Server, wlr_kb: *c.wlr_keyboard, device: *c.wlr_input_device, virtual: ?*c.wlr_virtual_keyboard_v1) void {
    const kb = @as(*Keyboard, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Keyboard)).?)));
    kb.server = server;
    kb.wlr = wlr_kb;
    kb.device = device;
    kb.virtual_keyboard = virtual;

    kb.modifiers.notify = onKeyboardModifiers;
    c.wl_signal_add(&wlr_kb.events.modifiers, &kb.modifiers);
    kb.key.notify = onKeyboardKey;
    c.wl_signal_add(&wlr_kb.events.key, &kb.key);
    kb.keymap.notify = onKeyboardKeymap;
    c.wl_signal_add(&wlr_kb.events.keymap, &kb.keymap);
    kb.destroy.notify = onKeyboardDestroy;
    c.wl_signal_add(&device.events.destroy, &kb.destroy);

    if (server.keyboard_count < server.keyboards.len) {
        server.keyboards[server.keyboard_count] = kb;
        server.keyboard_count += 1;
    } else {
        core.logInfo("too many keyboards", .{});
    }

    c.wlr_seat_set_keyboard(server.seat, wlr_kb);
    updateCapabilities(server);
    layout.refreshKeyboardFocus(server);
}

fn onNewVirtualKeyboard(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_virtual_keyboard", listener.?);
    const vk: *c.wlr_virtual_keyboard_v1 = @ptrCast(@alignCast(data.?));
    attachKeyboard(server, &vk.keyboard, &vk.keyboard.base, vk);
    core.logInfo("virtual keyboard added", .{});
}

pub fn reloadKeymaps(server: *Server) void {
    var i: usize = 0;
    while (i < server.keyboards.len) : (i += 1) {
        const kb = server.keyboards[i] orelse continue;
        if (kb.virtual_keyboard != null) continue;
        _ = applyKeymap(server, kb.wlr);
    }
    layout.refreshKeyboardFocus(server);
    core.logInfo("keymaps reloaded", .{});
}

fn onKeyboardModifiers(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const kb: *Keyboard = @fieldParentPtr("modifiers", listener.?);
    idle.notifyActivity(kb.server);
    if (kb.server.locked) {
        if (kb.virtual_keyboard != null) return;
        c.wlr_seat_set_keyboard(kb.server.seat, kb.wlr);
        c.wlr_seat_keyboard_notify_modifiers(kb.server.seat, &kb.wlr.modifiers);
        return;
    }
    if (ime.forwardModifiersToGrab(kb.server, kb)) return;
    c.wlr_seat_set_keyboard(kb.server.seat, kb.wlr);
    c.wlr_seat_keyboard_notify_modifiers(kb.server.seat, &kb.wlr.modifiers);
}

fn onKeyboardKeymap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const kb: *Keyboard = @fieldParentPtr("keymap", listener.?);
    const server = kb.server;
    c.wlr_seat_set_keyboard(server.seat, kb.wlr);
    layout.refreshKeyboardFocus(server);
    if (server.seat.keyboard_state.focused_surface != null) {
        c.wlr_seat_keyboard_notify_modifiers(server.seat, &kb.wlr.modifiers);
    }
    core.logDebug("keyboard keymap updated{s}", .{if (kb.virtual_keyboard != null) " (virtual)" else ""});
}

fn onKeyboardDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const kb: *Keyboard = @fieldParentPtr("destroy", listener.?);
    const server = kb.server;

    c.wl_list_remove(&kb.modifiers.link);
    c.wl_list_remove(&kb.key.link);
    c.wl_list_remove(&kb.keymap.link);
    c.wl_list_remove(&kb.destroy.link);

    if (server.keyboard_count > 0) {
        var i: usize = 0;
        while (i < server.keyboards.len) : (i += 1) {
            if (server.keyboards[i] == kb) {
                server.keyboards[i] = server.keyboards[server.keyboard_count - 1];
                server.keyboards[server.keyboard_count - 1] = null;
                server.keyboard_count -= 1;
                break;
            }
        }
    }

    c.free(kb);
    updateCapabilities(server);

    if (server.keyboard_count > 0) {
        var i: usize = 0;
        while (i < server.keyboards.len) : (i += 1) {
            if (server.keyboards[i]) |next| {
                c.wlr_seat_set_keyboard(server.seat, next.wlr);
                if (server.seat.keyboard_state.focused_surface != null) {
                    c.wlr_seat_keyboard_notify_modifiers(server.seat, &next.wlr.modifiers);
                }
                break;
            }
        }
    } else {
        c.wlr_seat_set_keyboard(server.seat, null);
    }
    layout.refreshKeyboardFocus(server);
}

fn executeBinding(server: *Server, b: *Binding) void {
    switch (b.action) {
        .none => {},
        .spawn => core.spawn(b.arg[0..b.arg_len]),
        .terminal => core.spawn(server.config.terminal[0..server.config.terminal_len]),
        .close => layout.closeFocused(server),
        .quit => c.wl_display_terminate(server.display),
        .workspace => {
            if (b.num >= 1 and b.num <= types.WS_COUNT) {
                layout.switchWorkspace(server, @intCast(b.num));
            }
        },
        .move_to_workspace => {
            if (b.num >= 1 and b.num <= types.WS_COUNT) {
                layout.moveToWorkspace(server, @intCast(b.num));
            }
        },
        .focus => layout.focusDirection(server, b.arg[0..b.arg_len]),
        .move => layout.moveDirection(server, b.arg[0..b.arg_len]),
        .toggle_float => layout.toggleFloat(server),
        .toggle_fullscreen => layout.toggleFullscreen(server),
        .focus_next => layout.focusNext(server, 1),
        .focus_prev => layout.focusNext(server, -1),
        .launcher => ipc.broadcastEvent(server, "launcher"),
        .reload => {
            const cfg = @import("config.zig");
            cfg.load(server);
            reloadKeymaps(server);
            layout.arrangeAll(server);
            core.markDirty(server);
            core.logInfo("config reloaded", .{});
        },
        .ratio => layout.adjustRatio(server, b.ratio),
        .toggle_layout => layout.toggleLayout(server),
    }
}

fn tryBindings(server: *Server, syms: [*c]const c.xkb_keysym_t, count: c_int, mods: u32) bool {
    if (count <= 0) return false;
    var bi: usize = 0;
    while (bi < server.config.binding_count) : (bi += 1) {
        const b = &server.config.bindings[bi];
        if (b.mods != mods) continue;
        var i: c_int = 0;
        while (i < count) : (i += 1) {
            if (@as(u32, @intCast(syms[@intCast(i)])) == b.sym) {
                executeBinding(server, b);
                return true;
            }
        }
    }
    return false;
}

fn onKeyboardKey(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const kb: *Keyboard = @fieldParentPtr("key", listener.?);
    const server = kb.server;
    const event: *c.wlr_keyboard_key_event = @ptrCast(@alignCast(data.?));
    idle.notifyActivity(server);

    if (server.locked) {
        if (kb.virtual_keyboard != null) return;
        c.wlr_seat_set_keyboard(server.seat, kb.wlr);
        c.wlr_seat_keyboard_notify_key(server.seat, event.time_msec, event.keycode, event.state);
        return;
    }

    if (ime.forwardKeyToGrab(server, kb, event)) return;
    if (event.state == c.WL_KEYBOARD_KEY_STATE_PRESSED and server.focused_layer != null) {
        const focused = server.seat.keyboard_state.focused_surface;
        const layer_surface: *c.wlr_surface = @ptrCast(@alignCast(server.focused_layer.?.wlr.surface));
        core.logDebug("key to layer: {d} focus_ok={} vk={}", .{
            event.keycode,
            focused == layer_surface,
            kb.virtual_keyboard != null,
        });
    }

    const keycode: c.xkb_keycode_t = event.keycode + 8;
    const pressed = event.state == c.WL_KEYBOARD_KEY_STATE_PRESSED;
    const mods = c.wlr_keyboard_get_modifiers(kb.wlr);
    const bind_mods = mods & (core.MOD_SHIFT | core.MOD_CTRL | core.MOD_ALT | core.MOD_LOGO);

    if (pressed and server.focused_layer == null and (bind_mods & core.MOD_LOGO) != 0) {
        var syms: [*c]const c.xkb_keysym_t = null;
        const n = c.xkb_state_key_get_syms(@ptrCast(@alignCast(kb.wlr.xkb_state)), keycode, &syms);
        if (tryBindings(server, syms, n, bind_mods)) return;

        if (kb.wlr.keymap != null) {
            var base: [*c]const c.xkb_keysym_t = null;
            const bn = c.xkb_keymap_key_get_syms_by_level(@ptrCast(@alignCast(kb.wlr.keymap)), keycode, 0, 0, &base);
            if (bn > 0 and tryBindings(server, base, bn, bind_mods)) return;
        }
    }

    c.wlr_seat_set_keyboard(server.seat, kb.wlr);
    c.wlr_seat_keyboard_notify_key(server.seat, event.time_msec, event.keycode, event.state);
}

fn sceneSurfaceAt(server: *Server, lx: f64, ly: f64, sx: *f64, sy: *f64) ?*c.wlr_surface {
    const node_raw = c.wlr_scene_node_at(&server.scene.tree.node, lx, ly, sx, sy) orelse return null;
    const node: *c.wlr_scene_node = @ptrCast(@alignCast(node_raw));
    if (node.type != c.WLR_SCENE_NODE_BUFFER) return null;
    const buf = c.wlr_scene_buffer_from_node(node);
    const scene_surface_raw = c.wlr_scene_surface_try_from_buffer(buf) orelse return null;
    const scene_surface: *c.wlr_scene_surface = @ptrCast(@alignCast(scene_surface_raw));
    const surf: *c.wlr_surface = @ptrCast(@alignCast(scene_surface.surface));
    return surf;
}

fn nodeClientAt(server: *Server, lx: f64, ly: f64) ?*Client {
    var sx: f64 = 0;
    var sy: f64 = 0;
    const node = c.wlr_scene_node_at(&server.scene.tree.node, lx, ly, &sx, &sy) orelse return null;
    var cur: ?*c.wlr_scene_node = node;
    while (cur) |n| {
        if (n.data) |d| {
            return @ptrCast(@alignCast(d));
        }
        if (n.parent) |p| {
            const ptree: *c.wlr_scene_tree = @ptrCast(@alignCast(p));
            cur = &ptree.node;
        } else {
            cur = null;
        }
    }
    return null;
}

fn processMotion(server: *Server, time_msec: u32) void {
    if (server.locked) {
        lock.focusForPosition(server, server.cursor.x, server.cursor.y);
    }
    if (server.cursor_mode == .move) {
        layout.updateInteractiveMove(server);
        return;
    }
    if (server.cursor_mode == .resize) {
        layout.updateInteractiveResize(server);
        return;
    }

    var sx: f64 = 0;
    var sy: f64 = 0;
    const surface = sceneSurfaceAt(server, server.cursor.x, server.cursor.y, &sx, &sy);
    if (surface) |surf| {
        c.wlr_seat_pointer_notify_enter(server.seat, surf, sx, sy);
        c.wlr_seat_pointer_notify_motion(server.seat, time_msec, sx, sy);
    } else {
        c.wlr_seat_pointer_clear_focus(server.seat);
        c.wlr_cursor_set_xcursor(server.cursor, server.cursor_mgr, "default");
    }
}

fn onCursorMotion(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion", listener.?);
    const event: *c.wlr_pointer_motion_event = @ptrCast(@alignCast(data.?));
    const pointer: *c.wlr_pointer = @ptrCast(@alignCast(event.pointer));
    idle.notifyActivity(server);
    c.wlr_cursor_move(server.cursor, &pointer.base, event.delta_x, event.delta_y);
    processMotion(server, event.time_msec);
}

fn onCursorMotionAbsolute(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion_absolute", listener.?);
    const event: *c.wlr_pointer_motion_absolute_event = @ptrCast(@alignCast(data.?));
    const pointer: *c.wlr_pointer = @ptrCast(@alignCast(event.pointer));
    idle.notifyActivity(server);
    c.wlr_cursor_warp_absolute(server.cursor, &pointer.base, event.x, event.y);
    processMotion(server, event.time_msec);
}

fn onCursorButton(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_button", listener.?);
    const event: *c.wlr_pointer_button_event = @ptrCast(@alignCast(data.?));
    idle.notifyActivity(server);

    if (event.state == c.WL_POINTER_BUTTON_STATE_RELEASED) {
        const swallowed = server.cursor_mode != .passthrough and server.grab_swallowed;
        if (!swallowed) {
            _ = c.wlr_seat_pointer_notify_button(server.seat, event.time_msec, event.button, event.state);
        }
        layout.resetInteractive(server);
        server.grab_swallowed = false;
        return;
    }

    if (server.locked) {
        _ = c.wlr_seat_pointer_notify_button(server.seat, event.time_msec, event.button, event.state);
        return;
    }

    const client = nodeClientAt(server, server.cursor.x, server.cursor.y);
    var mods: u32 = 0;
    if (c.wlr_seat_get_keyboard(server.seat)) |kb_raw| {
        const kb: *c.wlr_keyboard = @ptrCast(@alignCast(kb_raw));
        mods = c.wlr_keyboard_get_modifiers(kb);
    }
    const super = (mods & core.MOD_LOGO) != 0;

    if (super and client != null and client.?.floating) {
        if (event.button == 0x110) {
            layout.beginInteractive(client.?, .move, 0);
            server.grab_swallowed = true;
            return;
        }
        if (event.button == 0x111) {
            const cl = client.?;
            var edges: u32 = 0;
            const relx = server.cursor.x - @as(f64, @floatFromInt(cl.x));
            const rely = server.cursor.y - @as(f64, @floatFromInt(cl.y));
            if (relx < @as(f64, @floatFromInt(cl.w)) / 3.0) {
                edges |= c.WLR_EDGE_LEFT;
            } else if (relx > @as(f64, @floatFromInt(cl.w)) * 2.0 / 3.0) {
                edges |= c.WLR_EDGE_RIGHT;
            }
            if (rely < @as(f64, @floatFromInt(cl.h)) / 3.0) {
                edges |= c.WLR_EDGE_TOP;
            } else if (rely > @as(f64, @floatFromInt(cl.h)) * 2.0 / 3.0) {
                edges |= c.WLR_EDGE_BOTTOM;
            }
            layout.beginInteractive(cl, .resize, edges);
            server.grab_swallowed = true;
            return;
        }
    }

    _ = c.wlr_seat_pointer_notify_button(server.seat, event.time_msec, event.button, event.state);
    if (client) |cl| {
        layout.focusClient(server, cl);
    }
}

fn onCursorAxis(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_axis", listener.?);
    const event: *c.wlr_pointer_axis_event = @ptrCast(@alignCast(data.?));
    idle.notifyActivity(server);
    c.wlr_seat_pointer_notify_axis(
        server.seat,
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
        event.relative_direction,
    );
}

fn onCursorFrame(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const server: *Server = @fieldParentPtr("cursor_frame", listener.?);
    c.wlr_seat_pointer_notify_frame(server.seat);
}

fn onRequestCursor(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_cursor", listener.?);
    const event: *c.wlr_seat_pointer_request_set_cursor_event = @ptrCast(@alignCast(data.?));
    const focused_client = server.seat.pointer_state.focused_client;
    if (focused_client == event.seat_client) {
        c.wlr_cursor_set_surface(server.cursor, @ptrCast(@alignCast(event.surface)), event.hotspot_x, event.hotspot_y);
    }
}

fn onRequestSetShape(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_set_shape", listener.?);
    const event: *c.wlr_cursor_shape_manager_v1_request_set_shape_event = @ptrCast(@alignCast(data.?));
    if (server.seat.pointer_state.focused_client != event.seat_client) return;
    const name = c.wlr_cursor_shape_v1_name(event.shape);
    c.wlr_cursor_set_xcursor(server.cursor, server.cursor_mgr, name);
}

fn onRequestSetSelection(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_set_selection", listener.?);
    const event: *c.wlr_seat_request_set_selection_event = @ptrCast(@alignCast(data.?));
    c.wlr_seat_set_selection(server.seat, event.source, event.serial);
}

fn onRequestSetPrimarySelection(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("request_set_primary_selection", listener.?);
    const event: *c.wlr_seat_request_set_primary_selection_event = @ptrCast(@alignCast(data.?));
    c.wlr_seat_set_primary_selection(server.seat, event.source, event.serial);
}
