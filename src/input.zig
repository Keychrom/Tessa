const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const rules = @import("rules.zig");
const layout_helper = @import("layout_helper.zig");
const effect_helper = @import("effect_helper.zig");
const modes = @import("modes.zig");
const ipc = @import("ipc.zig");
const ime = @import("ime.zig");
const lock = @import("lock.zig");
const idle = @import("idle.zig");
const gestures = @import("gestures.zig");
const touch = @import("touch.zig");
const tablet = @import("tablet.zig");
const constraints = @import("constraints.zig");
const window_effects = @import("window_effects.zig");
const input_policy = @import("input_policy.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");

const Server = types.Server;
const Client = types.Client;
const Keyboard = types.Keyboard;
const Binding = types.Binding;
const TouchDevice = types.TouchDevice;

fn createCursorManager(server: *Server) ?*c.wlr_xcursor_manager {
    var theme_buf: [65:0]u8 = undefined;
    var theme: ?[*:0]const u8 = null;
    if (server.config.cursor_theme_len > 0) {
        core.copyZ(&theme_buf, server.config.cursor_theme[0..server.config.cursor_theme_len]);
        theme = @ptrCast(&theme_buf);
    }
    const size: u32 = @intCast(server.config.cursor_size);
    return c.wlr_xcursor_manager_create(theme, size);
}

fn loadCursor(manager: *c.wlr_xcursor_manager) bool {
    return c.wlr_xcursor_manager_load(manager, 1);
}

/// wlroots falls back from "default" to "left_ptr", but themes and older
/// wlroots revisions are not consistent about that alias. Pick a name that is
/// actually present so a theme cannot leave the cursor image empty.
fn defaultCursorName(manager: *c.wlr_xcursor_manager) [*:0]const u8 {
    const candidates = [_][*:0]const u8{ "default", "left_ptr", "arrow" };
    for (candidates) |name| {
        if (c.wlr_xcursor_manager_get_xcursor(manager, name, 1) != null) {
            return name;
        }
    }
    return "default";
}

fn setDefaultCursor(server: *Server) void {
    const manager = server.cursor_mgr;
    c.wlr_cursor_set_xcursor(server.cursor, manager, defaultCursorName(manager));
}

fn logCursorSelection(server: *Server, manager: *c.wlr_xcursor_manager) void {
    core.logInfo("cursor theme: {s} size {d}", .{
        if (server.config.cursor_theme_len > 0) server.config.cursor_theme[0..server.config.cursor_theme_len] else "default",
        server.config.cursor_size,
    });
    const name = defaultCursorName(manager);
    if (!std.mem.eql(u8, core.cstr(name), "default")) {
        core.logInfo("cursor: theme has no 'default' cursor; using '{s}'", .{core.cstr(name)});
    }
}

fn reloadCursor(server: *Server) void {
    const manager = createCursorManager(server) orelse {
        core.logInfo("cursor theme: failed to create manager for '{s}'", .{
            server.config.cursor_theme[0..server.config.cursor_theme_len],
        });
        return;
    };
    if (!loadCursor(manager)) {
        c.wlr_xcursor_manager_destroy(manager);
        core.logInfo("cursor theme: failed to load '{s}' size {d}, keeping previous cursor", .{
            server.config.cursor_theme[0..server.config.cursor_theme_len],
            server.config.cursor_size,
        });
        return;
    }
    c.wlr_cursor_set_xcursor(server.cursor, manager, defaultCursorName(manager));
    const old = server.cursor_mgr;
    server.cursor_mgr = manager;
    c.wlr_xcursor_manager_destroy(old);
    logCursorSelection(server, manager);
}

pub fn init(server: *Server) void {
    server.cursor = c.wlr_cursor_create() orelse {
        core.logInfo("failed to create cursor", .{});
        return;
    };
    c.wlr_cursor_attach_output_layout(server.cursor, server.output_layout);

    server.cursor_mgr = createCursorManager(server) orelse {
        core.logInfo("failed to create xcursor manager", .{});
        return;
    };
    if (!loadCursor(server.cursor_mgr)) {
        if (server.config.cursor_theme_len > 0) {
            core.logInfo("cursor theme: failed to load '{s}', falling back to default", .{
                server.config.cursor_theme[0..server.config.cursor_theme_len],
            });
            c.wlr_xcursor_manager_destroy(server.cursor_mgr);
            const size: u32 = @intCast(server.config.cursor_size);
            server.cursor_mgr = c.wlr_xcursor_manager_create(null, size) orelse {
                core.logInfo("failed to create fallback xcursor manager", .{});
                return;
            };
            if (!loadCursor(server.cursor_mgr)) {
                core.logInfo("failed to load fallback cursor theme; install an Xcursor theme", .{});
            }
        } else {
            core.logInfo("failed to load default cursor theme; install an Xcursor theme", .{});
        }
    }
    // Layer surfaces such as the wallpaper do not request a cursor shape, so
    // without an initial default the pointer stays invisible until a client
    // asks for one.
    setDefaultCursor(server);
    logCursorSelection(server, server.cursor_mgr);

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

    server.virtual_pointer_manager = c.wlr_virtual_pointer_manager_v1_create(server.display);
    if (server.virtual_pointer_manager) |mgr| {
        server.new_virtual_pointer.notify = onNewVirtualPointer;
        c.wl_signal_add(&mgr.events.new_virtual_pointer, &server.new_virtual_pointer);
        core.logInfo("virtual-pointer-v1 enabled", .{});
    }

    const rel_raw = c.wlr_relative_pointer_manager_v1_create(server.display);
    if (rel_raw != null) {
        server.relative_pointer_manager = @ptrCast(@alignCast(rel_raw));
    }

    const shape_mgr_raw = c.wlr_cursor_shape_manager_v1_create(server.display, 1);
    if (shape_mgr_raw != null) {
        const shape_mgr: *c.wlr_cursor_shape_manager_v1 = @ptrCast(@alignCast(shape_mgr_raw));
        server.cursor_shape_manager = shape_mgr;
        server.request_set_shape.notify = onRequestSetShape;
        c.wl_signal_add(&shape_mgr.events.request_set_shape, &server.request_set_shape);
    }

    server.reload_runtime = reloadRuntime;
    addSyntheticKeyboard(server);
    gestures.init(server);
    touch.init(server);
    tablet.init(server);
    constraints.init(server);
    idle.init(server);
    modes.init(server);
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
    if (server.touch_device_count > 0) caps |= c.WL_SEAT_CAPABILITY_TOUCH;
    c.wlr_seat_set_capabilities(server.seat, caps);
}

fn onTouchDeviceDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const state: *TouchDevice = @fieldParentPtr("destroy", listener.?);
    const server = state.server;
    c.wl_list_remove(&state.destroy.link);
    var i: usize = 0;
    while (i < server.touch_device_count) : (i += 1) {
        if (server.touch_devices[i] != state) continue;
        server.touch_devices[i] = server.touch_devices[server.touch_device_count - 1];
        server.touch_devices[server.touch_device_count - 1] = null;
        server.touch_device_count -= 1;
        break;
    }
    c.free(state);
    updateCapabilities(server);
}

fn onTrackedInputDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const state: *types.TrackedInput = @fieldParentPtr("destroy", listener.?);
    const server = state.server;
    var i: usize = 0;
    while (i < server.tracked_inputs.len) : (i += 1) {
        if (server.tracked_inputs[i] == state) {
            if (server.tracked_input_count > 0) server.tracked_input_count -= 1;
            if (i != server.tracked_input_count) {
                server.tracked_inputs[i] = server.tracked_inputs[server.tracked_input_count];
            }
            server.tracked_inputs[server.tracked_input_count] = null;
            break;
        }
    }
    c.free(state);
}

fn trackInput(server: *Server, device: *c.wlr_input_device) void {
    if (server.tracked_input_count >= server.tracked_inputs.len) return;
    const state = @as(*types.TrackedInput, @ptrCast(@alignCast(c.calloc(1, @sizeOf(types.TrackedInput)).?)));
    state.server = server;
    state.device = device;
    state.destroy.notify = onTrackedInputDestroy;
    c.wl_signal_add(&device.events.destroy, &state.destroy);
    server.tracked_inputs[server.tracked_input_count] = state;
    server.tracked_input_count += 1;
}

pub fn cleanupTrackedInputs(server: *Server) void {
    var i: usize = 0;
    while (i < server.tracked_inputs.len) : (i += 1) {
        const state = server.tracked_inputs[i] orelse continue;
        c.wl_list_remove(&state.destroy.link);
        c.free(state);
        server.tracked_inputs[i] = null;
    }
    server.tracked_input_count = 0;
}

fn addTouchDevice(server: *Server, device: *c.wlr_input_device) bool {
    if (!server.config.touch) return false;
    if (server.touch_device_count >= server.touch_devices.len) return false;
    c.wlr_cursor_attach_input_device(server.cursor, device);
    const state = @as(*TouchDevice, @ptrCast(@alignCast(c.calloc(1, @sizeOf(TouchDevice)).?)));
    state.server = server;
    state.device = device;
    state.destroy.notify = onTouchDeviceDestroy;
    c.wl_signal_add(&device.events.destroy, &state.destroy);
    server.touch_devices[server.touch_device_count] = state;
    server.touch_device_count += 1;
    core.logInfo("touch device added: {s}", .{core.cstr(device.name)});
    return true;
}

fn onNewInput(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_input", listener.?);
    const device: *c.wlr_input_device = @ptrCast(@alignCast(data.?));

    trackInput(server, device);
    if (device.type == c.WLR_INPUT_DEVICE_KEYBOARD) {
        addKeyboard(server, device);
    } else if (device.type == c.WLR_INPUT_DEVICE_POINTER) {
        c.wlr_cursor_attach_input_device(server.cursor, device);
    } else if (device.type == c.WLR_INPUT_DEVICE_TOUCH) {
        _ = addTouchDevice(server, device);
    } else if (device.type == c.WLR_INPUT_DEVICE_TABLET) {
        if (tablet.addTablet(server, device)) {
            c.wlr_cursor_attach_input_device(server.cursor, device);
        }
    } else if (device.type == c.WLR_INPUT_DEVICE_TABLET_PAD) {
        _ = tablet.addPad(server, device);
    }
    input_policy.apply(server, device);
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

fn onNewVirtualPointer(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_virtual_pointer", listener.?);
    const event: *c.wlr_virtual_pointer_v1_new_pointer_event = @ptrCast(@alignCast(data.?));
    const pointer: *c.wlr_virtual_pointer_v1 = @ptrCast(@alignCast(event.new_pointer));
    c.wlr_cursor_attach_input_device(server.cursor, &pointer.pointer.base);
    core.logInfo("virtual pointer added", .{});
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

pub fn reloadRuntime(server: *Server) void {
    const cfg = @import("config.zig");
    const previous = server.config;
    cfg.load(server);
    if (server.config_error_count > 0) {
        server.config = previous;
        core.logInfo("config reload rejected: {d} error(s); keeping previous configuration", .{server.config_error_count});
        core.markDirty(server);
        return;
    }
    modes.sync(server);
    reloadKeymaps(server);
    reloadCursor(server);
    input_policy.applyAll(server);
    layout_helper.reload(server);
    effect_helper.reload(server);
    rules.applyAll(server);
    rules.applyOutputThemes(server);
    rules.applyOutputPolicies(server);
    constraints.reload(server);
    window_effects.reload(server);
    rules.clearRuntimeRatios(server);
    layout.clearAnimations(server);
    layout.applyConfigLayouts(server);
    layout.arrangeAll(server);
    layout.ensureVisibleFocus(server);
    events.emit(server, .{ .name = event_names.config_reload });
    core.markDirty(server);
    core.logInfo("config reloaded", .{});
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
        .toggle_scratchpad => layout.toggleScratchpad(server),
        .move_to_scratchpad => layout.moveToScratchpad(server),
        .toggle_special => layout.toggleSpecial(server, b.arg[0..b.arg_len]),
        .move_to_special => layout.moveToSpecial(server, b.arg[0..b.arg_len]),
        .toggle_group => layout.toggleGroup(server),
        .group_next => layout.groupNext(server, 1),
        .group_prev => layout.groupNext(server, -1),
        .group_add => layout.groupAdd(server),
        .group_remove => layout.groupRemove(server),
        .focus_next => layout.focusNext(server, 1),
        .focus_prev => layout.focusNext(server, -1),
        .launcher => ipc.emitLauncher(server, ""),
        .clipboard => ipc.emitPanel(server, "clipboard", ""),
        .screenshot => ipc.emitPanel(server, "screenshot", ""),
        .media => ipc.emitPanel(server, "media", ""),
        .tray => ipc.emitPanel(server, "tray", ""),
        .audio => ipc.emitPanel(server, "audio", ""),
        .reload => reloadRuntime(server),
        .ratio => layout.adjustRatio(server, b.ratio),
        .toggle_layout => layout.toggleLayout(server),
        .set_layout => {
            if (!layout.setLayout(server, b.arg[0..b.arg_len])) {
                core.logInfo("layout: unknown layout '{s}'", .{b.arg[0..b.arg_len]});
            }
        },
        .resize_width => layout.keyboardResize(server, b.num, 0),
        .resize_height => layout.keyboardResize(server, 0, b.num),
        .enter_mode => {
            if (!modes.set(server, b.arg[0..b.arg_len])) {
                core.logInfo("mode: unknown mode '{s}'", .{b.arg[0..b.arg_len]});
            }
        },
    }
}

fn tryBindings(
    server: *Server,
    syms: [*c]const c.xkb_keysym_t,
    count: c_int,
    mods: u32,
    mode: u8,
) bool {
    if (count <= 0) return false;
    var bi: usize = 0;
    while (bi < server.config.binding_count) : (bi += 1) {
        const b = &server.config.bindings[bi];
        if (b.mode != mode or b.mods != mods) continue;
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

fn leaderModeActive(server: *Server) bool {
    return std.mem.eql(u8, modes.currentName(server), "leader");
}

fn isLeaderKey(server: *Server, syms: [*c]const c.xkb_keysym_t, count: c_int, mods: u32) bool {
    if (!server.config.leader_set or mods != server.config.leader_mods or count <= 0) return false;
    var i: c_int = 0;
    while (i < count) : (i += 1) {
        if (@as(u32, @intCast(syms[@intCast(i)])) == server.config.leader_sym) return true;
    }
    return false;
}

fn tryModeBindings(server: *Server, syms: [*c]const c.xkb_keysym_t, count: c_int, mods: u32) bool {
    const was_leader = leaderModeActive(server);
    const mode_before = server.active_mode;
    if (!tryBindings(server, syms, count, mods, server.active_mode)) return false;
    if (was_leader and server.active_mode == mode_before) {
        modes.setDefault(server);
    }
    return true;
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

    if (pressed and server.focused_layer == null) {
        var syms: [*c]const c.xkb_keysym_t = null;
        const n = c.xkb_state_key_get_syms(@ptrCast(@alignCast(kb.wlr.xkb_state)), keycode, &syms);

        if (isLeaderKey(server, syms, n, bind_mods)) {
            if (leaderModeActive(server)) {
                modes.setDefault(server);
                return;
            }
            if (server.active_mode == 0 and modes.setLeader(server)) return;
        }

        if (server.active_mode != 0) {
            if (tryModeBindings(server, syms, n, bind_mods)) return;
            if (kb.wlr.keymap != null) {
                var base: [*c]const c.xkb_keysym_t = null;
                const bn = c.xkb_keymap_key_get_syms_by_level(@ptrCast(@alignCast(kb.wlr.keymap)), keycode, 0, 0, &base);
                if (bn > 0 and tryModeBindings(server, base, bn, bind_mods)) return;
            }
        }

        if ((bind_mods & core.MOD_LOGO) != 0) {
            if (tryBindings(server, syms, n, bind_mods, 0)) return;
            if (kb.wlr.keymap != null) {
                var base: [*c]const c.xkb_keysym_t = null;
                const bn = c.xkb_keymap_key_get_syms_by_level(@ptrCast(@alignCast(kb.wlr.keymap)), keycode, 0, 0, &base);
                if (bn > 0 and tryBindings(server, base, bn, bind_mods, 0)) return;
            }
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
        // A client can leave its cursor surface unset (or clear it while
        // leaving) before the pointer enters a layer surface such as the panel.
        // Restore the compositor's cursor when entering a layer surface so the
        // panel and desktop never inherit an invisible cursor.
        if (server.seat.pointer_state.focused_surface != surf and
            c.wlr_layer_surface_v1_try_from_wlr_surface(surf) != null)
        {
            core.logDebug("cursor: restored default on layer focus", .{});
            setDefaultCursor(server);
        }
        c.wlr_seat_pointer_notify_enter(server.seat, surf, sx, sy);
        c.wlr_seat_pointer_notify_motion(server.seat, time_msec, sx, sy);
    } else {
        c.wlr_seat_pointer_clear_focus(server.seat);
        setDefaultCursor(server);
    }
}

fn onCursorMotion(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion", listener.?);
    const event: *c.wlr_pointer_motion_event = @ptrCast(@alignCast(data.?));
    const pointer: *c.wlr_pointer = @ptrCast(@alignCast(event.pointer));
    idle.notifyActivity(server);
    if (server.relative_pointer_manager) |mgr| {
        c.wlr_relative_pointer_manager_v1_send_relative_motion(
            mgr,
            server.seat,
            @as(u64, event.time_msec) * 1000,
            event.delta_x,
            event.delta_y,
            event.unaccel_dx,
            event.unaccel_dy,
        );
    }
    var dx = event.delta_x;
    var dy = event.delta_y;
    if (server.cursor_mode == .passthrough) {
        _ = constraints.confineMotion(server, &dx, &dy);
    }
    c.wlr_cursor_move(server.cursor, &pointer.base, dx, dy);
    processMotion(server, event.time_msec);
}

fn onCursorMotionAbsolute(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("cursor_motion_absolute", listener.?);
    const event: *c.wlr_pointer_motion_absolute_event = @ptrCast(@alignCast(data.?));
    const pointer: *c.wlr_pointer = @ptrCast(@alignCast(event.pointer));
    idle.notifyActivity(server);
    if (server.cursor_mode == .passthrough and constraints.isLocked(server)) {
        processMotion(server, event.time_msec);
        return;
    }
    c.wlr_cursor_warp_absolute(server.cursor, &pointer.base, event.x, event.y);
    if (server.cursor_mode == .passthrough) constraints.clampCursor(server);
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
        layout.finishInteractive(server);
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
    } else if (core.outputAt(server, server.cursor.x, server.cursor.y)) |out| {
        if (server.focused_output != out) {
            server.focused_output = out;
            server.active_ws = out.active_ws;
            layout.focusFirst(server);
            core.markDirty(server);
        }
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
