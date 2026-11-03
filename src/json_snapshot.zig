const std = @import("std");
const types = @import("types.zig");
const core = @import("core.zig");
const modes = @import("modes.zig");
const scrolling = @import("scrolling.zig");
const api = @import("api.zig");
const extension_manager = @import("extension_manager.zig");

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
    add(buf, &off, "{{\"schema\":{d},\"tessa\":\"{s}\",\"line_protocol\":{d},\"extension_api\":{d},\"layout_api\":{d},\"effect_api\":{d},\"active_workspace\":{d},\"active_workspace_name\":", .{
        api.state_schema,
        api.tessa_version,
        api.line_protocol,
        api.extension_api,
        api.layout_api,
        api.effect_api,
        server.active_ws,
    });
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
        if (out.ws_layouts[out.active_ws - 1] == .scrolling) {
            const sw = &out.scroll_ws[out.active_ws - 1];
            add(buf, &off, ",\"view_offset\":{d},\"content_width\":{d},\"viewport_width\":{d},\"focus_column\":{d},\"columns\":[", .{
                @as(i32, @intFromFloat(@round(sw.view_offset))),
                sw.content_width,
                sw.viewport_width,
                sw.focus_index,
            });
            var ci: usize = 0;
            var first_column = true;
            while (ci < sw.count) : (ci += 1) {
                const id = sw.columns[ci];
                if (id == 0 or @as(usize, id) > server.scroll_columns.len) continue;
                const column = &server.scroll_columns[id - 1];
                if (!column.used) continue;
                if (!first_column) addRaw(buf, &off, ",");
                first_column = false;
                add(buf, &off, "{{\"index\":{d},\"x\":{d},\"width\":{d},\"focused\":", .{
                    ci,
                    scrolling.columnX(out, ci) orelse 0,
                    column.width_px,
                });
                addBool(buf, &off, ci == sw.focus_index);
                addRaw(buf, &off, ",\"maximized\":");
                addBool(buf, &off, column.maximized);
                addRaw(buf, &off, ",\"tabbed\":");
                addBool(buf, &off, column.tabbed);
                add(buf, &off, ",\"windows\":{d}}}", .{column.count});
            }
            addRaw(buf, &off, "]");
        }
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "],\"occupancy\":[");

    var counts: [types.WS_COUNT]usize = @splat(0);
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
        addRaw(buf, &off, ",\"icon\":");
        addString(buf, &off, status.icon[0..status.icon_len]);
        add(buf, &off, ",\"priority\":{d}", .{status.priority});
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
        addBool(buf, &off, (cl.group_id == 0 or cl.group_active) and
            (if (cl.scratchpad) cl.output.scratchpad_visible else cl.ws == cl.output.active_ws));
        add(buf, &off, ",\"group\":{d},\"group_active\":", .{cl.group_id});
        addBool(buf, &off, cl.group_active);
        addRaw(buf, &off, ",\"app_id\":");
        addString(buf, &off, cl.app_id[0..cl.app_id_len]);
        addRaw(buf, &off, ",\"title\":");
        addString(buf, &off, cl.title[0..cl.title_len]);
        addRaw(buf, &off, ",\"output\":");
        addString(buf, &off, core.outputName(cl.output));
        const hook_bw = types.effectiveClientBorderWidth(cl);
        const bw = if (cl.fullscreen)
            0
        else if (hook_bw >= 0)
            hook_bw
        else
            server.config.border_width;
        const hook_radius = types.effectiveClientRadius(cl);
        const radius = if (cl.fullscreen)
            0
        else if (hook_radius >= 0)
            hook_radius
        else
            server.config.corner_radius;
        const blur = switch (types.effectiveClientBlur(cl)) {
            .on => true,
            .off => false,
            .unset => server.config.blur,
        };
        const shadow = !cl.fullscreen and switch (types.effectiveClientShadow(cl)) {
            .on => true,
            .off => false,
            .unset => server.config.shadows,
        };
        add(buf, &off, ",\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d},\"opacity\":{d:.3},\"border_width\":{d},\"corner_radius\":{d},\"blur\":", .{
            cl.x,
            cl.y,
            cl.w,
            cl.h,
            types.effectiveClientOpacity(cl),
            bw,
            radius,
        });
        addBool(buf, &off, blur);
        addRaw(buf, &off, ",\"shadow\":");
        addBool(buf, &off, shadow);
        const tint = types.effectiveClientTint(cl);
        add(buf, &off, ",\"tint\":[{d:.3},{d:.3},{d:.3},{d:.3}]", .{ tint[0], tint[1], tint[2], tint[3] });
        const anim = types.effectiveClientAnim(cl);
        add(buf, &off, ",\"animation\":{{\"open_ms\":{d},\"workspace_ms\":{d},\"close_ms\":{d},\"open_curve\":", .{
            anim.open_ms,
            anim.workspace_ms,
            anim.close_ms,
        });
        addString(buf, &off, anim.open_curve[0..anim.open_curve_len]);
        addRaw(buf, &off, ",\"workspace_curve\":");
        addString(buf, &off, anim.workspace_curve[0..anim.workspace_curve_len]);
        addRaw(buf, &off, ",\"close_curve\":");
        addString(buf, &off, anim.close_curve[0..anim.close_curve_len]);
        addRaw(buf, &off, "}");
        const tearing = switch (cl.tearing) {
            .on => true,
            .off => false,
            .unset => server.config.tearing != .off,
        };
        addRaw(buf, &off, ",\"tearing\":");
        addBool(buf, &off, tearing);
        addRaw(buf, &off, ",\"on_screen\":");
        addBool(buf, &off, cl.on_screen);
        add(buf, &off, ",\"column\":{d},\"tile\":{d}", .{ cl.scroll_column, scrolling.tileIndex(cl) });
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
    addRaw(buf, &off, "],\"extensions\":");
    if (off < buf.len) {
        const written = buildExtensionsArray(server, buf[off..]);
        off += written;
    }
    addRaw(buf, &off, "}");
    return off;
}

pub fn buildExtensionsArray(server: *Server, buf: []u8) usize {
    var off: usize = 0;
    addRaw(buf, &off, "[");
    var i: usize = 0;
    while (i < server.extension_count) : (i += 1) {
        if (i > 0) addRaw(buf, &off, ",");
        const ext = &server.extensions[i];
        addRaw(buf, &off, "{\"id\":");
        addString(buf, &off, ext.manifest.id[0..ext.manifest.id_len]);
        addRaw(buf, &off, ",\"state\":");
        addString(buf, &off, extension_manager.stateName(ext.state));
        add(buf, &off, ",\"api\":{d},\"pid\":{d},\"ready\":", .{ ext.manifest.api, ext.pid });
        addBool(buf, &off, ext.ready);
        add(buf, &off, ",\"restarts\":{d},\"enabled\":", .{ext.restarts});
        addBool(buf, &off, ext.manifest.enabled);
        var perm_buf: [128]u8 = undefined;
        addRaw(buf, &off, ",\"permissions\":");
        addString(buf, &off, extension_manager.permissionsText(&perm_buf, ext.manifest.permissions));
        addRaw(buf, &off, ",\"requires\":[");
        var j: usize = 0;
        while (j < ext.manifest.require_count) : (j += 1) {
            if (j > 0) addRaw(buf, &off, ",");
            addString(buf, &off, ext.manifest.requires[j][0..ext.manifest.require_lens[j]]);
        }
        addRaw(buf, &off, "],\"after\":[");
        j = 0;
        while (j < ext.manifest.after_count) : (j += 1) {
            if (j > 0) addRaw(buf, &off, ",");
            addString(buf, &off, ext.manifest.after[j][0..ext.manifest.after_lens[j]]);
        }
        addRaw(buf, &off, "],\"last_error\":");
        addString(buf, &off, ext.last_error[0..ext.last_error_len]);
        add(buf, &off, ",\"failures\":{d},\"next_restart_ms\":{d}", .{
            ext.failures,
            if (ext.restart_at_ms > core.timeNowMs()) ext.restart_at_ms - core.timeNowMs() else 0,
        });
        addRaw(buf, &off, "}");
    }
    addRaw(buf, &off, "]");
    return off;
}

fn addPanelModules(buf: []u8, off: *usize, modules: u16) void {
    addRaw(buf, off, "[");
    const items = [_]struct { bit: u16, name: []const u8 }{
        .{ .bit = types.PANEL_MODULE_BACKGROUND, .name = "background" },
        .{ .bit = types.PANEL_MODULE_BAR, .name = "bar" },
        .{ .bit = types.PANEL_MODULE_LAUNCHER, .name = "launcher" },
        .{ .bit = types.PANEL_MODULE_POPOVERS, .name = "popovers" },
        .{ .bit = types.PANEL_MODULE_NOTIFICATIONS, .name = "notifications" },
        .{ .bit = types.PANEL_MODULE_TOASTS, .name = "toasts" },
        .{ .bit = types.PANEL_MODULE_TRAY, .name = "tray" },
        .{ .bit = types.PANEL_MODULE_MEDIA, .name = "media" },
        .{ .bit = types.PANEL_MODULE_AUDIO, .name = "audio" },
    };
    var first = true;
    for (items) |item| {
        if (modules & item.bit == 0) continue;
        if (!first) addRaw(buf, off, ",");
        first = false;
        addString(buf, off, item.name);
    }
    addRaw(buf, off, "]");
}

fn addColumnWidth(buf: []u8, off: *usize, width: types.ColumnWidth) void {
    add(buf, off, "{{\"kind\":\"{s}\",\"value\":{d:.3}}}", .{
        @tagName(width.kind),
        width.value,
    });
}

pub fn buildConfig(server: *Server, buf: []u8) usize {
    var off: usize = 0;
    const cfg = &server.config;

    add(buf, &off, "{{\"schema\":{d},\"tessa\":\"{s}\",\"line_protocol\":{d},\"extension_api\":{d},\"layout_api\":{d},\"effect_api\":{d},\"errors\":{d},\"terminal\":", .{
        api.config_schema,
        api.tessa_version,
        api.line_protocol,
        api.extension_api,
        api.layout_api,
        api.effect_api,
        server.config_error_count,
    });
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
    add(buf, &off, ",\"layout_helper_timeout\":{d}", .{cfg.layout_helper_timeout});
    addRaw(buf, &off, ",\"effect_helper\":");
    addString(buf, &off, cfg.effect_helper[0..cfg.effect_helper_len]);
    add(buf, &off, ",\"effect_helper_timeout\":{d},\"frame_time_budget\":{d}", .{ cfg.effect_helper_timeout, cfg.frame_time_budget });
    add(buf, &off, ",\"direct_scanout\":{d},\"tearing\":", .{@as(u8, if (cfg.direct_scanout) 1 else 0)});
    addString(buf, &off, @tagName(cfg.tearing));
    add(buf, &off, ",\"explicit_sync\":{d}", .{@as(u8, if (cfg.explicit_sync) 1 else 0)});
    addRaw(buf, &off, ",\"layout\":");
    addString(buf, &off, types.layoutName(cfg.layout_mode));
    addRaw(buf, &off, ",\"layouts\":[");
    var wi: usize = 0;
    while (wi < types.WS_COUNT) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        addString(buf, &off, types.layoutName(cfg.layout_by_ws[wi]));
    }
    addRaw(buf, &off, "],\"layout_cycle\":[");
    wi = 0;
    while (wi < cfg.layout_cycle_len) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        addString(buf, &off, types.layoutName(cfg.layout_cycle[wi]));
    }
    addRaw(buf, &off, "],\"default_column_width\":");
    addColumnWidth(buf, &off, cfg.default_column_width);
    addRaw(buf, &off, ",\"column_width_presets\":[");
    wi = 0;
    while (wi < cfg.column_width_preset_count) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        addColumnWidth(buf, &off, cfg.column_width_presets[wi]);
    }
    addRaw(buf, &off, "],\"center_focused_column\":");
    addString(buf, &off, @tagName(cfg.center_focused_column));
    add(buf, &off, ",\"animation_view_ms\":{d},\"animation_view_curve\":", .{cfg.animation_view_ms});
    addString(buf, &off, cfg.animation_view_curve[0..cfg.animation_view_curve_len]);
    addRaw(buf, &off, ",\"panel_modules\":");
    addPanelModules(buf, &off, cfg.panel_modules);
    add(buf, &off, ",\"extension_ready_timeout\":{d}", .{cfg.extension_ready_timeout});
    addRaw(buf, &off, ",\"extensions\":[");
    wi = 0;
    while (wi < cfg.extension_count) : (wi += 1) {
        if (wi > 0) addRaw(buf, &off, ",");
        const ext = &cfg.extensions[wi];
        addRaw(buf, &off, "{\"id\":");
        addString(buf, &off, ext.id[0..ext.id_len]);
        addRaw(buf, &off, ",\"command\":");
        addString(buf, &off, ext.command[0..ext.command_len]);
        add(buf, &off, ",\"api\":{d},\"enabled\":", .{ext.api});
        addBool(buf, &off, ext.enabled);
        var perm_buf: [128]u8 = undefined;
        addRaw(buf, &off, ",\"permissions\":");
        addString(buf, &off, extension_manager.permissionsText(&perm_buf, ext.permissions));
        addRaw(buf, &off, ",\"requires\":[");
        var di: usize = 0;
        while (di < ext.require_count) : (di += 1) {
            if (di > 0) addRaw(buf, &off, ",");
            addString(buf, &off, ext.requires[di][0..ext.require_lens[di]]);
        }
        addRaw(buf, &off, "],\"after\":[");
        di = 0;
        while (di < ext.after_count) : (di += 1) {
            if (di > 0) addRaw(buf, &off, ",");
            addString(buf, &off, ext.after[di][0..ext.after_lens[di]]);
        }
        addRaw(buf, &off, "]}");
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
