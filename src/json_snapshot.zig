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
    add(buf, &off, "{{\"schema\":1,\"active_workspace\":{d},\"mode\":", .{server.active_ws});
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
        if (cl.mapped and cl.ws >= 1 and cl.ws <= types.WS_COUNT) counts[cl.ws - 1] += 1;
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
        addRaw(buf, &off, ",\"app_id\":");
        addString(buf, &off, cl.app_id[0..cl.app_id_len]);
        addRaw(buf, &off, ",\"title\":");
        addString(buf, &off, cl.title[0..cl.title_len]);
        addRaw(buf, &off, ",\"output\":");
        addString(buf, &off, core.outputName(cl.output));
        add(buf, &off, ",\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d}}}", .{ cl.x, cl.y, cl.w, cl.h });
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

    addRaw(buf, &off, "],\"panel\":");
    addBool(buf, &off, cfg.autostart_panel);
    addRaw(buf, &off, ",\"xwayland\":");
    addBool(buf, &off, cfg.xwayland);
    addRaw(buf, &off, ",\"xwayland_display\":");
    addString(buf, &off, cfg.xwayland_display[0..cfg.xwayland_display_len]);
    addRaw(buf, &off, ",\"animations\":");
    addBool(buf, &off, cfg.animations);
    add(buf, &off, ",\"animation_ms\":{d},\"reduce_motion\":", .{cfg.animation_ms});
    addBool(buf, &off, cfg.reduce_motion);
    addRaw(buf, &off, ",\"shadows\":");
    addBool(buf, &off, cfg.shadows);
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
    addRaw(buf, &off, ",\"font\":");
    addString(buf, &off, cfg.font[0..cfg.font_len]);
    addRaw(buf, &off, ",\"accent\":");
    addString(buf, &off, cfg.accent[0..cfg.accent_len]);
    addRaw(buf, &off, ",\"bg\":");
    addString(buf, &off, cfg.bg[0..cfg.bg_len]);
    addRaw(buf, &off, ",\"output_config\":");
    addString(buf, &off, cfg.output_config[0..cfg.output_config_len]);
    add(buf, &off, ",\"binding_count\":{d},\"hook_count\":{d},\"rule_count\":{d}", .{
        cfg.binding_count,
        cfg.hook_count,
        cfg.rule_count,
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
