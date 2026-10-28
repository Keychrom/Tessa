const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const rules = @import("rules.zig");

const Server = types.Server;
const Rule = types.InputRule;

fn boolOn(value: types.RuleBool) bool {
    return value == .on;
}

fn isTouchpad(handle: *c.libinput_device) bool {
    return c.libinput_device_config_tap_get_finger_count(handle) > 0;
}

fn matchesType(rule: *const Rule, device: *const c.wlr_input_device, touchpad: bool) bool {
    return switch (rule.device_type) {
        .any => true,
        .keyboard => device.type == c.WLR_INPUT_DEVICE_KEYBOARD,
        .pointer => device.type == c.WLR_INPUT_DEVICE_POINTER,
        .touchpad => device.type == c.WLR_INPUT_DEVICE_POINTER and touchpad,
        .mouse => device.type == c.WLR_INPUT_DEVICE_POINTER and !touchpad,
        .touch => device.type == c.WLR_INPUT_DEVICE_TOUCH,
        .tablet => device.type == c.WLR_INPUT_DEVICE_TABLET,
        .tablet_pad => device.type == c.WLR_INPUT_DEVICE_TABLET_PAD,
        .switch_device => device.type == c.WLR_INPUT_DEVICE_SWITCH,
    };
}

fn merge(dest: *Rule, src: *const Rule) void {
    if (src.tap != .unset) dest.tap = src.tap;
    if (src.tap_drag != .unset) dest.tap_drag = src.tap_drag;
    if (src.tap_drag_lock != .unset) dest.tap_drag_lock = src.tap_drag_lock;
    if (src.natural_scroll != .unset) dest.natural_scroll = src.natural_scroll;
    if (src.left_handed != .unset) dest.left_handed = src.left_handed;
    if (src.middle_emulation != .unset) dest.middle_emulation = src.middle_emulation;
    if (src.dwt != .unset) dest.dwt = src.dwt;
    if (src.accel_profile != .unset) dest.accel_profile = src.accel_profile;
    if (src.has_accel_speed) {
        dest.has_accel_speed = true;
        dest.accel_speed = src.accel_speed;
    }
    if (src.scroll_method != .unset) dest.scroll_method = src.scroll_method;
    if (src.has_scroll_button) {
        dest.has_scroll_button = true;
        dest.scroll_button = src.scroll_button;
    }
    if (src.click_method != .unset) dest.click_method = src.click_method;
    if (src.tap_button_map != .unset) dest.tap_button_map = src.tap_button_map;
    if (src.clickfinger_button_map != .unset) dest.clickfinger_button_map = src.clickfinger_button_map;
}

fn applyPointer(handle: *c.libinput_device, rule: *const Rule) void {
    if (rule.accel_profile == .adaptive) {
        _ = c.libinput_device_config_accel_set_profile(handle, @intCast(c.LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE));
    } else if (rule.accel_profile == .flat) {
        _ = c.libinput_device_config_accel_set_profile(handle, @intCast(c.LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT));
    }
    if (rule.has_accel_speed) {
        _ = c.libinput_device_config_accel_set_speed(handle, @floatCast(rule.accel_speed));
    }
    if (rule.natural_scroll != .unset) {
        _ = c.libinput_device_config_scroll_set_natural_scroll_enabled(
            handle,
            @as(c_int, @intFromBool(boolOn(rule.natural_scroll))),
        );
    }
    if (rule.left_handed != .unset) {
        _ = c.libinput_device_config_left_handed_set(
            handle,
            @as(c_int, @intFromBool(boolOn(rule.left_handed))),
        );
    }
    if (rule.middle_emulation != .unset) {
        _ = c.libinput_device_config_middle_emulation_set_enabled(
            handle,
            @intCast(@intFromBool(boolOn(rule.middle_emulation))),
        );
    }
    switch (rule.scroll_method) {
        .unset => {},
        .none => _ = c.libinput_device_config_scroll_set_method(handle, @intCast(c.LIBINPUT_CONFIG_SCROLL_NO_SCROLL)),
        .two_finger => _ = c.libinput_device_config_scroll_set_method(handle, @intCast(c.LIBINPUT_CONFIG_SCROLL_2FG)),
        .edge => _ = c.libinput_device_config_scroll_set_method(handle, @intCast(c.LIBINPUT_CONFIG_SCROLL_EDGE)),
        .button => _ = c.libinput_device_config_scroll_set_method(handle, @intCast(c.LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN)),
        .circular => {
            // libinput 1.32 added circular scrolling; older distributions
            // compile the option but leave it unsupported at runtime.
            if (@hasDecl(c, "LIBINPUT_CONFIG_SCROLL_CIRCULAR")) {
                _ = c.libinput_device_config_scroll_set_method(handle, @intCast(c.LIBINPUT_CONFIG_SCROLL_CIRCULAR));
            }
        },
    }
    if (rule.has_scroll_button) {
        _ = c.libinput_device_config_scroll_set_button(handle, rule.scroll_button);
    }
}

fn applyTouchpad(handle: *c.libinput_device, rule: *const Rule) void {
    if (rule.tap != .unset) {
        const state: c.enum_libinput_config_tap_state = @intCast(if (boolOn(rule.tap))
            c.LIBINPUT_CONFIG_TAP_ENABLED
        else
            c.LIBINPUT_CONFIG_TAP_DISABLED);
        _ = c.libinput_device_config_tap_set_enabled(handle, state);
    }
    if (rule.tap_drag != .unset) {
        const state = @as(c.enum_libinput_config_drag_state, @intCast(if (boolOn(rule.tap_drag))
            c.LIBINPUT_CONFIG_DRAG_ENABLED
        else
            c.LIBINPUT_CONFIG_DRAG_DISABLED));
        _ = c.libinput_device_config_tap_set_drag_enabled(handle, state);
    }
    if (rule.tap_drag_lock != .unset) {
        const state = @as(c.enum_libinput_config_drag_lock_state, @intCast(if (boolOn(rule.tap_drag_lock))
            c.LIBINPUT_CONFIG_DRAG_LOCK_ENABLED_TIMEOUT
        else
            c.LIBINPUT_CONFIG_DRAG_LOCK_DISABLED));
        _ = c.libinput_device_config_tap_set_drag_lock_enabled(handle, state);
    }
    if (rule.dwt != .unset) {
        const state = @as(c.enum_libinput_config_dwt_state, @intCast(if (boolOn(rule.dwt))
            c.LIBINPUT_CONFIG_DWT_ENABLED
        else
            c.LIBINPUT_CONFIG_DWT_DISABLED));
        _ = c.libinput_device_config_dwt_set_enabled(handle, state);
    }
    if (rule.click_method != .unset) {
        const method: c.enum_libinput_config_click_method = @intCast(switch (rule.click_method) {
            .unset => c.LIBINPUT_CONFIG_CLICK_METHOD_NONE,
            .none => c.LIBINPUT_CONFIG_CLICK_METHOD_NONE,
            .button_areas => c.LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS,
            .clickfinger => c.LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER,
        });
        _ = c.libinput_device_config_click_set_method(handle, method);
    }
    if (rule.tap_button_map != .unset) {
        const map: c.enum_libinput_config_tap_button_map = @intCast(if (rule.tap_button_map == .lmr)
            c.LIBINPUT_CONFIG_TAP_MAP_LMR
        else
            c.LIBINPUT_CONFIG_TAP_MAP_LRM);
        _ = c.libinput_device_config_tap_set_button_map(handle, map);
    }
    if (rule.clickfinger_button_map != .unset) {
        const map: c.enum_libinput_config_clickfinger_button_map = @intCast(if (rule.clickfinger_button_map == .lmr)
            c.LIBINPUT_CONFIG_CLICKFINGER_MAP_LMR
        else
            c.LIBINPUT_CONFIG_CLICKFINGER_MAP_LRM);
        _ = c.libinput_device_config_click_set_clickfinger_button_map(handle, map);
    }
}

fn findState(server: *Server, device: *c.wlr_input_device) ?*types.TrackedInput {
    var i: usize = 0;
    while (i < server.tracked_inputs.len) : (i += 1) {
        const state = server.tracked_inputs[i] orelse continue;
        if (state.device == device) return state;
    }
    return null;
}

fn captureSnapshot(handle: *c.libinput_device) types.InputPolicySnapshot {
    return .{
        .accel_profile = @intCast(c.libinput_device_config_accel_get_profile(handle)),
        .accel_speed = c.libinput_device_config_accel_get_speed(handle),
        .natural_scroll = c.libinput_device_config_scroll_get_natural_scroll_enabled(handle),
        .left_handed = c.libinput_device_config_left_handed_get(handle),
        .middle_emulation = @intCast(c.libinput_device_config_middle_emulation_get_enabled(handle)),
        .scroll_method = @intCast(c.libinput_device_config_scroll_get_method(handle)),
        .scroll_button = c.libinput_device_config_scroll_get_button(handle),
        .tap_enabled = @intCast(c.libinput_device_config_tap_get_enabled(handle)),
        .drag_enabled = @intCast(c.libinput_device_config_tap_get_drag_enabled(handle)),
        .drag_lock_enabled = @intCast(c.libinput_device_config_tap_get_drag_lock_enabled(handle)),
        .tap_button_map = @intCast(c.libinput_device_config_tap_get_button_map(handle)),
        .click_method = @intCast(c.libinput_device_config_click_get_method(handle)),
        .clickfinger_button_map = @intCast(c.libinput_device_config_click_get_clickfinger_button_map(handle)),
        .dwt_enabled = @intCast(c.libinput_device_config_dwt_get_enabled(handle)),
    };
}

fn restoreSnapshot(handle: *c.libinput_device, snapshot: *const types.InputPolicySnapshot) void {
    _ = c.libinput_device_config_accel_set_profile(handle, @intCast(snapshot.accel_profile));
    _ = c.libinput_device_config_accel_set_speed(handle, snapshot.accel_speed);
    _ = c.libinput_device_config_scroll_set_natural_scroll_enabled(handle, snapshot.natural_scroll);
    _ = c.libinput_device_config_left_handed_set(handle, snapshot.left_handed);
    _ = c.libinput_device_config_middle_emulation_set_enabled(handle, snapshot.middle_emulation);
    _ = c.libinput_device_config_scroll_set_method(handle, @intCast(snapshot.scroll_method));
    _ = c.libinput_device_config_scroll_set_button(handle, snapshot.scroll_button);
    _ = c.libinput_device_config_tap_set_enabled(handle, @intCast(snapshot.tap_enabled));
    _ = c.libinput_device_config_tap_set_drag_enabled(handle, @intCast(snapshot.drag_enabled));
    _ = c.libinput_device_config_tap_set_drag_lock_enabled(handle, @intCast(snapshot.drag_lock_enabled));
    _ = c.libinput_device_config_tap_set_button_map(handle, @intCast(snapshot.tap_button_map));
    _ = c.libinput_device_config_click_set_method(handle, @intCast(snapshot.click_method));
    _ = c.libinput_device_config_click_set_clickfinger_button_map(
        handle,
        @intCast(snapshot.clickfinger_button_map),
    );
    _ = c.libinput_device_config_dwt_set_enabled(handle, @intCast(snapshot.dwt_enabled));
}

fn applyDevice(server: *Server, device: *c.wlr_input_device) void {
    if (!c.wlr_input_device_is_libinput(device)) return;
    const handle = c.wlr_libinput_get_device_handle(device) orelse return;
    const touchpad = isTouchpad(handle);
    const name = core.cstr(device.name);

    if (findState(server, device)) |state| {
        if (state.has_policy_snapshot) {
            restoreSnapshot(handle, &state.policy_snapshot);
        } else {
            state.policy_snapshot = captureSnapshot(handle);
            state.has_policy_snapshot = true;
        }
    }

    var effective = Rule{};
    var matched = false;
    var i: usize = 0;
    while (i < server.config.input_rule_count) : (i += 1) {
        const rule = &server.config.input_rules[i];
        if (!matchesType(rule, device, touchpad)) continue;
        if (rule.name_len > 0 and !rules.wildcardMatch(rule.name[0..rule.name_len], name)) continue;
        merge(&effective, rule);
        matched = true;
    }
    if (!matched) return;

    if (device.type == c.WLR_INPUT_DEVICE_POINTER) {
        applyPointer(handle, &effective);
        if (touchpad) applyTouchpad(handle, &effective);
    }
    core.logDebug("input policy applied to {s}", .{name});
}

pub fn applyAll(server: *Server) void {
    var i: usize = 0;
    while (i < server.tracked_inputs.len) : (i += 1) {
        const state = server.tracked_inputs[i] orelse continue;
        applyDevice(server, state.device);
    }
}

pub fn apply(server: *Server, device: *c.wlr_input_device) void {
    applyDevice(server, device);
}
