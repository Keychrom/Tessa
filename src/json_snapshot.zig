const std = @import("std");
const types = @import("types.zig");
const core = @import("core.zig");
const modes = @import("modes.zig");

const Server = types.Server;

fn addRaw(buf: []u8, off: *usize, text: []const u8) void {
    if (off.* + text.len > buf.len) return;
    @memcpy(buf[off.* .. off.* + text.len], text);
    off.* += text.len;
}

fn add(buf: []u8, off: *usize, comptime fmt: []const u8, args: anytype) void {
    if (off.* >= buf.len) return;
    const text = std.fmt.bufPrint(buf[off.*..], fmt, args) catch return;
    off.* += text.len;
}

fn addString(buf: []u8, off: *usize, value: []const u8) void {
    const hex = "0123456789abcdef";
    addRaw(buf, off, "\"");
    for (value) |ch| {
        switch (ch) {
            '"' => addRaw(buf, off, "\\\""),
            '\\' => addRaw(buf, off, "\\\\"),
            '\n' => addRaw(buf, off, "\\n"),
            '\r' => addRaw(buf, off, "\\r"),
            '\t' => addRaw(buf, off, "\\t"),
            else => {
                if (ch < 0x20) {
                    addRaw(buf, off, "\\u00");
                    if (off.* + 2 > buf.len) return;
                    buf[off.*] = hex[ch >> 4];
                    buf[off.* + 1] = hex[ch & 0xf];
                    off.* += 2;
                } else {
                    if (off.* + 1 > buf.len) return;
                    buf[off.*] = ch;
                    off.* += 1;
                }
            },
        }
    }
    addRaw(buf, off, "\"");
}

fn addBool(buf: []u8, off: *usize, value: bool) void {
    addRaw(buf, off, if (value) "true" else "false");
}

pub fn buildState(server: *Server, buf: []u8) usize {
    var off: usize = 0;
    add(buf, &off, "{{\"schema\":1,\"active_workspace\":{d},\"active_workspace_name\":", .{server.active_ws});
    addString(buf, &off, types.workspaceName(&server.config, server.active_ws));
    addRaw(buf, &off, ",\"workspace_names\":[");
    var wn: usize = 0;
    while (wn < types.WS_COUNT) : (wn += 1) {
        if (wn > 0) addRaw(buf, &off, ",");
        addString(buf, &off, server.config.workspace_names[wn][0..server.config.workspace_name_lens[wn]]);
    }
    addRaw(buf, &off, "],\"mode\":");
    addString(buf, &off, modes.currentName(server));
    addRaw(buf, &off, ",\"outputs\":[");
    var first = true;
    var oi: usize = 0;
    while (oi < server.outputs.len) : (oi += 1) {
        const out = server.outputs[oi] orelse continue;
        if (!first) addRaw(buf, &off, ",");
        first = false;
        addRaw(buf, &off, "{\"name\":");
        addString(buf, &off, core.outputName(out));
        add(buf, &off, ",\"workspace\":{d},\"focused\":", .{out.active_ws});
        addBool(buf, &off, server.focused_output == out);
        addRaw(buf, &off, ",\"layout\":");
        addString(buf, &off, types.layoutName(out.ws_layouts[out.active_ws - 1]));
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"occupancy\":[");

    var counts: [types.WS_COUNT]usize = [_]usize{0} ** types.WS_COUNT;
    var ci: usize = 0;
    while (ci < server.clients.len) : (ci += 1) {
        const cl = server.clients[ci] orelse continue;
        if (cl.mapped and !cl.scratchpad and cl.ws >= 1 and cl.ws <= types.WS_COUNT) counts[cl.ws - 1] += 1;
    }
    var wi: usize = 0;
    while (wi < types.WS_COUNT) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        add(buf, &off, "{{\"workspace\":{d},\"count\":{d}}}", .{ wi + 1, counts[wi] });
    }
    addRaw(buf, &off, "],\"focused\":");
    if (server.focused) |cl| {
        add(buf, &off, "{d}", .{cl.id});
    } else {
        addRaw(buf, &off, "null");
    }

    addRaw(buf, &off, ",\"statuses\":[");
    var si: usize = 0;
    while (si < server.status_count) : (si += 1) {
        const status = &server.statuses[si];
        if (si > 0) addRaw(buf, &off, ",");
        addRaw(buf, &off, "{\"id\":");
        addString(buf, &off, status.id[0..status.id_len]);
        addRaw(buf, &off, ",\"text\":");
        addString(buf, &off, status.text[0..status.text_len]);
        addRaw(buf, &off, ",\"command\":");
        addString(buf, &off, status.command[0..status.command_len]);
        addRaw(buf, &off, "}");
    }

    addRaw(buf, &off, "],\"windows\":[");
    var first_window = true;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (!cl.mapped) continue;
        if (!first_window) addRaw(buf, &off, ",");
        first_window = false;
        add(buf, &off, "{{\"id\":{d},\"workspace\":{d},\"focused\":", .{ cl.id, cl.ws });
        addBool(buf, &off, server.focused == cl);
        addRaw(buf, &off, ",\"floating\":");
        addBool(buf, &off, cl.floating);
        addRaw(buf, &off, ",\"fullscreen\":");
        addBool(buf, &off, cl.fullscreen);
        addRaw(buf, &off, ",\"urgent\":");
        addBool(buf, &off, cl.urgent);
        addRaw(buf, &off, ",\"scratchpad\":");
        addBool(buf, &off, cl.scratchpad);
        addRaw(buf, &off, ",\"visible\":");
        addBool(buf, &off, if (cl.scratchpad) cl.output.scratchpad_visible else cl.ws == cl.output.active_ws);
        addRaw(buf, &off, ",\"app_id\":");
        addString(buf, &off, cl.app_id[0..cl.app_id_len]);
        addRaw(buf, &off, ",\"title\":");
        addString(buf, &off, cl.title[0..cl.title_len]);
        addRaw(buf, &off, ",\"output\":");
        addString(buf, &off, core.outputName(cl.output));
        const bw = if (cl.fullscreen)
            0
        else if (cl.border_width >= 0)
            cl.border_width
        else
            server.config.border_width;
        const radius = if (cl.fullscreen)
            0
        else if (cl.corner_radius >= 0)
            cl.corner_radius
        else
            server.config.corner_radius;
        const blur = switch (cl.blur) {
            .on => true,
            .off => false,
            .unset => server.config.blur,
        };
        const shadow = !cl.fullscreen and switch (cl.shadow) {
            .on => true,
            .off => false,
            .unset => server.config.shadows,
        };
        add(buf, &off, ",\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d},\"opacity\":{d:.3},\"border_width\":{d},\"corner_radius\":{d},\"blur\":", .{
            cl.x,
            cl.y,
            cl.w,
            cl.h,
            cl.opacity,
            bw,
            radius,
        });
        addBool(buf, &off, blur);
        addRaw(buf, &off, ",\"shadow\":");
        addBool(buf, &off, shadow);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"layers\":[");
    var first_layer = true;
    i = 0;
    while (i < server.layers.len) : (i += 1) {
        const layer = server.layers[i] orelse continue;
        if (!layer.mapped) continue;
        if (!first_layer) addRaw(buf, &off, ",");
        first_layer = false;
        const layer_n: u32 = @intCast(layer.wlr.current.layer);
        const blur = switch (layer.blur) {
            .on => true,
            .off => false,
            .unset => server.config.blur and layer_n >= 2,
        };
        addRaw(buf, &off, "{\"namespace\":");
        addString(buf, &off, core.cstr(layer.wlr.namespace));
        addRaw(buf, &off, ",\"output\":");
        addString(buf, &off, core.outputName(layer.output));
        add(buf, &off, ",\"layer\":{d},\"opacity\":{d:.3},\"corner_radius\":{d},\"blur\":", .{
            layer_n,
            layer.opacity,
            layer.corner_radius,
        });
        addBool(buf, &off, blur);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "]}");
    return off;
}

pub fn buildConfig(server: *Server, buf: []u8) usize {
    var off: usize = 0;
    const cfg = &server.config;

    add(buf, &off, "{{\"schema\":1,\"errors\":{d},\"terminal\":", .{server.config_error_count});
    addString(buf, &off, cfg.terminal[0..cfg.terminal_len]);
    add(buf, &off, ",\"gaps\":{d},\"outer_gaps\":{d},\"border_width\":{d}", .{ cfg.gaps, cfg.outer_gaps, cfg.border_width });
    addRaw(buf, &off, ",\"border_active\":");
    addString(buf, &off, cfg.border_active[0..cfg.border_active_len]);
    addRaw(buf, &off, ",\"border_inactive\":");
    addString(buf, &off, cfg.border_inactive[0..cfg.border_inactive_len]);
    add(buf, &off, ",\"master_ratio\":{d:.3},\"master_count\":{d}", .{ cfg.master_ratio, cfg.master_count });
    add(buf, &off, ",\"mosaic_ratio\":{d:.3},\"mosaic_min_size\":{d},\"grid_columns\":{d}", .{ cfg.mosaic_ratio, cfg.mosaic_min_size, cfg.grid_columns });
    addRaw(buf, &off, ",\"layout_helper\":");
    addString(buf, &off, cfg.layout_helper[0..cfg.layout_helper_len]);
    add(buf, &off, ",\"layout_helper_timeout\":{d},\"layout\":", .{cfg.layout_helper_timeout});
    addString(buf, &off, types.layoutName(cfg.layout_mode));
    addRaw(buf, &off, ",\"layouts\":[");
    var wi: usize = 0;
    while (wi < types.WS_COUNT) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        addString(buf, &off, types.layoutName(cfg.layout_by_ws[wi]));
    }
    addRaw(buf, &off, "],\"modes\":[");
    wi = 0;
    while (wi < cfg.mode_count) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        addString(buf, &off, cfg.mode_names[wi][0..cfg.mode_name_lens[wi]]);
    }
    addRaw(buf, &off, "],\"workspace_tuning\":[");
    wi = 0;
    while (wi < types.WS_COUNT) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        add(buf, &off, "{{\"workspace\":{d},\"gaps\":{d},\"outer_gaps\":{d},\"master_ratio\":{d:.3}}}", .{
            wi + 1,
            cfg.ws_gaps[wi],
            cfg.ws_outer_gaps[wi],
            cfg.ws_master_ratio[wi],
        });
    }

    addRaw(buf, &off, "],\"workspace_pins\":[");
    wi = 0;
    while (wi < cfg.workspace_pin_count) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        const pin = &cfg.workspace_pins[wi];
        addRaw(buf, &off, "{\"output\":");
        addString(buf, &off, pin.output_name[0..pin.output_len]);
        add(buf, &off, ",\"workspace\":{d}}}", .{pin.ws});
    }

    addRaw(buf, &off, "],\"workspace_names\":[");
    wi = 0;
    while (wi < types.WS_COUNT) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        addString(buf, &off, cfg.workspace_names[wi][0..cfg.workspace_name_lens[wi]]);
    }

    addRaw(buf, &off, "],\"panel\":");
    addBool(buf, &off, cfg.autostart_panel);
    addRaw(buf, &off, ",\"xwayland\":");
    addBool(buf, &off, cfg.xwayland);
    addRaw(buf, &off, ",\"xwayland_display\":");
    addString(buf, &off, cfg.xwayland_display[0..cfg.xwayland_display_len]);
    addRaw(buf, &off, ",\"animations\":");
    addBool(buf, &off, cfg.animations);
    add(buf, &off, ",\"animation_ms\":{d},\"animation_open_ms\":{d},\"animation_workspace_ms\":{d},\"animation_close_ms\":{d},\"animation_open_x\":{d},\"animation_open_y\":{d},\"animation_workspace_offset\":{d},\"animation_close_scale\":{d:.3},\"animation_close_fade\":", .{
        cfg.animation_ms,
        if (cfg.animation_open_ms >= 0) cfg.animation_open_ms else cfg.animation_ms,
        if (cfg.animation_workspace_ms >= 0) cfg.animation_workspace_ms else cfg.animation_ms,
        if (cfg.animation_close_ms >= 0) cfg.animation_close_ms else cfg.animation_ms,
        cfg.animation_open_x,
        cfg.animation_open_y,
        cfg.animation_workspace_offset,
        cfg.animation_close_scale,
    });
    addBool(buf, &off, cfg.animation_close_fade);
    addRaw(buf, &off, ",\"animation_curve\":");
    addString(buf, &off, cfg.animation_curve[0..cfg.animation_curve_len]);
    addRaw(buf, &off, ",\"animation_open_curve\":");
    addString(buf, &off, cfg.animation_open_curve[0..cfg.animation_open_curve_len]);
    addRaw(buf, &off, ",\"animation_workspace_curve\":");
    addString(buf, &off, cfg.animation_workspace_curve[0..cfg.animation_workspace_curve_len]);
    addRaw(buf, &off, ",\"animation_close_curve\":");
    addString(buf, &off, cfg.animation_close_curve[0..cfg.animation_close_curve_len]);
    addRaw(buf, &off, ",\"curves\":[");
    var ci: usize = 0;
    while (ci < cfg.curve_count) : (ci += 1) {
        if (ci > 0) addRaw(buf, &off, ",");
        const curve = &cfg.curves[ci];
        addRaw(buf, &off, "{\"name\":");
        addString(buf, &off, curve.name[0..curve.name_len]);
        addRaw(buf, &off, ",\"kind\":");
        addString(buf, &off, switch (curve.curve.kind) {
            .bezier => "bezier",
            .spring => "spring",
        });
        switch (curve.curve.kind) {
            .bezier => add(buf, &off, ",\"points\":[{d:.3},{d:.3},{d:.3},{d:.3}]}}", .{
                curve.curve.points[0],
                curve.curve.points[1],
                curve.curve.points[2],
                curve.curve.points[3],
            }),
            .spring => add(buf, &off, ",\"damping\":{d:.3},\"frequency\":{d:.3}}}", .{
                curve.curve.damping,
                curve.curve.frequency,
            }),
        }
    }
    addRaw(buf, &off, "],\"reduce_motion\":");
    addBool(buf, &off, cfg.reduce_motion);
    addRaw(buf, &off, ",\"reduce_motion_animations\":");
    addString(buf, &off, switch (cfg.reduce_motion_animations) {
        .none => "none",
        .fade => "fade",
    });
    add(buf, &off, ",\"reduce_motion_fade_ms\":{d}", .{cfg.reduce_motion_fade_ms});
    addRaw(buf, &off, ",\"shadows\":");
    addBool(buf, &off, cfg.shadows);
    addRaw(buf, &off, ",\"scenefx\":");
    addBool(buf, &off, @import("build_options").scenefx);
    add(buf, &off, ",\"corner_radius\":{d},\"blur\":", .{cfg.corner_radius});
    addBool(buf, &off, cfg.blur);
    add(buf, &off, ",\"blur_radius\":{d},\"blur_passes\":{d}", .{ cfg.blur_radius, cfg.blur_passes });
    addRaw(buf, &off, ",\"gestures\":");
    addBool(buf, &off, cfg.gestures);
    add(buf, &off, ",\"gesture_fingers\":{d},\"gesture_workspace_threshold\":{d},\"gesture_launcher_threshold\":{d}", .{
        cfg.gesture_fingers,
        cfg.gesture_workspace_threshold,
        cfg.gesture_launcher_threshold,
    });
    addRaw(buf, &off, ",\"touch\":");
    addBool(buf, &off, cfg.touch);
    addRaw(buf, &off, ",\"tablet\":");
    addBool(buf, &off, cfg.tablet);
    addRaw(buf, &off, ",\"pointer_constraints\":");
    addBool(buf, &off, cfg.pointer_constraints);
    addRaw(buf, &off, ",\"xim\":");
    addBool(buf, &off, cfg.xim);
    addRaw(buf, &off, ",\"xim_server\":");
    addString(buf, &off, cfg.xim_server[0..cfg.xim_server_len]);
    addRaw(buf, &off, ",\"xim_start\":");
    addString(buf, &off, cfg.xim_start[0..cfg.xim_start_len]);
    addRaw(buf, &off, ",\"kb_layout\":");
    addString(buf, &off, cfg.kb_layout[0..cfg.kb_layout_len]);
    addRaw(buf, &off, ",\"kb_variant\":");
    addString(buf, &off, cfg.kb_variant[0..cfg.kb_variant_len]);
    addRaw(buf, &off, ",\"kb_options\":");
    addString(buf, &off, cfg.kb_options[0..cfg.kb_options_len]);
    addRaw(buf, &off, ",\"kb_model\":");
    addString(buf, &off, cfg.kb_model[0..cfg.kb_model_len]);
    addRaw(buf, &off, ",\"kb_rules\":");
    addString(buf, &off, cfg.kb_rules[0..cfg.kb_rules_len]);
    add(buf, &off, ",\"repeat_rate\":{d},\"repeat_delay\":{d}", .{ cfg.repeat_rate, cfg.repeat_delay });
    addRaw(buf, &off, ",\"cursor_theme\":");
    addString(buf, &off, cfg.cursor_theme[0..cfg.cursor_theme_len]);
    add(buf, &off, ",\"cursor_size\":{d}", .{cfg.cursor_size});
    addRaw(buf, &off, ",\"font\":");
    addString(buf, &off, cfg.font[0..cfg.font_len]);
    addRaw(buf, &off, ",\"accent\":");
    addString(buf, &off, cfg.accent[0..cfg.accent_len]);
    addRaw(buf, &off, ",\"bg\":");
    addString(buf, &off, cfg.bg[0..cfg.bg_len]);
    addRaw(buf, &off, ",\"output_config\":");
    addString(buf, &off, cfg.output_config[0..cfg.output_config_len]);
    add(buf, &off, ",\"binding_count\":{d},\"hook_count\":{d},\"event_rule_count\":{d},\"profile_count\":{d},\"workspace_rule_count\":{d},\"rule_count\":{d},\"output_rule_count\":{d},\"layer_rule_count\":{d},\"input_rule_count\":{d}", .{
        cfg.binding_count,
        cfg.hook_count,
        cfg.event_rule_count,
        cfg.profile_count,
        cfg.workspace_rule_count,
        cfg.rule_count,
        cfg.output_rule_count,
        cfg.layer_rule_count,
        cfg.input_rule_count,
    });

    addRaw(buf, &off, ",\"rules\":[");
    var i: usize = 0;
    while (i < cfg.rule_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const rule = &cfg.rules[i];
        addRaw(buf, &off, "{\"raw\":");
        addString(buf, &off, rule.raw[0..rule.raw_len]);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"output_rules\":[");
    i = 0;
    while (i < cfg.output_rule_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const rule = &cfg.output_rules[i];
        addRaw(buf, &off, "{\"raw\":");
        addString(buf, &off, rule.raw[0..rule.raw_len]);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"layer_rules\":[");
    i = 0;
    while (i < cfg.layer_rule_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const rule = &cfg.layer_rules[i];
        addRaw(buf, &off, "{\"raw\":");
        addString(buf, &off, rule.raw[0..rule.raw_len]);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"input_rules\":[");
    i = 0;
    while (i < cfg.input_rule_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const rule = &cfg.input_rules[i];
        addRaw(buf, &off, "{\"raw\":");
        addString(buf, &off, rule.raw[0..rule.raw_len]);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"hooks\":[");
    i = 0;
    while (i < cfg.hook_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const hook = &cfg.hooks[i];
        addRaw(buf, &off, "{\"event\":");
        addString(buf, &off, hook.event[0..hook.event_len]);
        addRaw(buf, &off, ",\"command\":");
        addString(buf, &off, hook.command[0..hook.command_len]);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"event_rules\":[");
    i = 0;
    while (i < cfg.event_rule_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const rule = &cfg.event_rules[i];
        addRaw(buf, &off, "{\"event\":");
        addString(buf, &off, rule.event[0..rule.event_len]);
        addRaw(buf, &off, ",\"match\":");
        addString(buf, &off, rule.expr[0..rule.expr_len]);
        addRaw(buf, &off, ",\"run\":");
        addString(buf, &off, rule.command[0..rule.command_len]);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"profiles\":[");
    i = 0;
    while (i < cfg.profile_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const profile = &cfg.profiles[i];
        addRaw(buf, &off, "{\"name\":");
        addString(buf, &off, profile.name[0..profile.name_len]);
        addRaw(buf, &off, ",\"layout\":");
        addString(buf, &off, types.layoutName(profile.tuning.layout));
        add(buf, &off, ",\"gaps\":{d},\"outer_gaps\":{d},\"master_ratio\":{d:.3},\"master_count\":{d},\"grid_columns\":{d}}}", .{
            profile.tuning.gaps,
            profile.tuning.outer_gaps,
            profile.tuning.master_ratio,
            profile.tuning.master_count,
            profile.tuning.grid_columns,
        });
    }
    addRaw(buf, &off, "],\"theme_roles\":[");
    i = 0;
    while (i < cfg.theme_role_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const role = &cfg.theme_roles[i];
        addRaw(buf, &off, "{\"name\":");
        addString(buf, &off, role.name[0..role.name_len]);
        addRaw(buf, &off, ",\"color\":");
        addString(buf, &off, role.color[0..role.color_len]);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"diagnostics\":[");
    i = 0;
    while (i < server.config_issue_count) : (i += 1) {
        const issue = &server.config_issues[i];
        if (i > 0) addRaw(buf, &off, ",");
        addRaw(buf, &off, "{\"severity\":");
        addString(buf, &off, if (issue.is_error) "error" else "warning");
        addRaw(buf, &off, ",\"path\":");
        addString(buf, &off, issue.path[0..issue.path_len]);
        add(buf, &off, ",\"line\":{d},\"message\":", .{issue.line});
        addString(buf, &off, issue.message[0..issue.message_len]);
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "]}");
    return off;
}
