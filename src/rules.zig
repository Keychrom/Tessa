const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const rule_expr = @import("rule_expr.zig");

const Server = types.Server;
const Client = types.Client;
const Output = types.Output;
const WindowRule = types.WindowRule;
const LayerSurface = types.LayerSurface;

pub const Tuning = struct {
    layout: types.LayoutMode,
    gaps: i32,
    outer_gaps: i32,
    master_ratio: f32,
    master_count: usize,
    mosaic_ratio: f32,
    mosaic_min_size: i32,
    grid_columns: usize,
};

pub fn wildcardMatch(pattern: []const u8, text: []const u8) bool {
    if (pattern.len == 0) return true;

    var p: usize = 0;
    var t: usize = 0;
    var star: ?usize = null;
    var star_text: usize = 0;

    while (t < text.len) {
        if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star = p;
            star_text = t;
            p += 1;
        } else if (star) |s| {
            star_text += 1;
            t = star_text;
            p = s + 1;
        } else {
            return false;
        }
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

fn applyProfileTuning(profile: *const types.Profile, tuning: *Tuning) void {
    const p = &profile.tuning;
    if (p.has_layout) tuning.layout = p.layout;
    if (p.has_gaps) tuning.gaps = p.gaps;
    if (p.has_outer_gaps) tuning.outer_gaps = p.outer_gaps;
    if (p.has_master_ratio) tuning.master_ratio = p.master_ratio;
    if (p.has_master_count) tuning.master_count = p.master_count;
    if (p.has_mosaic_ratio) tuning.mosaic_ratio = p.mosaic_ratio;
    if (p.has_mosaic_min_size) tuning.mosaic_min_size = p.mosaic_min_size;
    if (p.has_grid_columns) tuning.grid_columns = p.grid_columns;
}

fn applyOutputRule(cfg: *const types.Config, rule: *const types.OutputRule, tuning: *Tuning) void {
    if (rule.profile_len > 0) {
        var pi: usize = 0;
        while (pi < cfg.profile_count) : (pi += 1) {
            const profile = &cfg.profiles[pi];
            if (std.mem.eql(u8, profile.name[0..profile.name_len], rule.profile[0..rule.profile_len])) {
                applyProfileTuning(profile, tuning);
                break;
            }
        }
    }
    if (rule.has_layout) tuning.layout = rule.layout;
    if (rule.has_gaps) tuning.gaps = rule.gaps;
    if (rule.has_outer_gaps) tuning.outer_gaps = rule.outer_gaps;
    if (rule.has_master_ratio) tuning.master_ratio = rule.master_ratio;
    if (rule.has_master_count) tuning.master_count = rule.master_count;
    if (rule.has_mosaic_ratio) tuning.mosaic_ratio = rule.mosaic_ratio;
    if (rule.has_mosaic_min_size) tuning.mosaic_min_size = rule.mosaic_min_size;
    if (rule.has_grid_columns) tuning.grid_columns = rule.grid_columns;
}

fn applyWorkspaceOverrides(cfg: *const types.Config, index: usize, tuning: *Tuning) void {
    if (cfg.ws_gaps_set[index]) tuning.gaps = cfg.ws_gaps[index];
    if (cfg.ws_outer_set[index]) tuning.outer_gaps = cfg.ws_outer_gaps[index];
    if (cfg.ws_ratio_set[index]) tuning.master_ratio = cfg.ws_master_ratio[index];
    if (cfg.ws_master_count_set[index]) tuning.master_count = cfg.ws_master_count[index];
    if (cfg.ws_mosaic_ratio_set[index]) tuning.mosaic_ratio = cfg.ws_mosaic_ratio[index];
    if (cfg.ws_mosaic_min_size_set[index]) tuning.mosaic_min_size = cfg.ws_mosaic_min_size[index];
    if (cfg.ws_grid_columns_set[index]) tuning.grid_columns = cfg.ws_grid_columns[index];
    if (cfg.layout_overrides[index]) tuning.layout = cfg.layout_by_ws[index];
}

pub fn tuningFor(server: *Server, out: *Output, ws: usize) Tuning {
    const cfg = &server.config;
    const index = @min(@max(ws, 1), types.WS_COUNT) - 1;
    var tuning = Tuning{
        .layout = if (cfg.layout_overrides[index]) cfg.layout_by_ws[index] else cfg.layout_mode,
        .gaps = cfg.gaps,
        .outer_gaps = cfg.outer_gaps,
        .master_ratio = cfg.master_ratio,
        .master_count = cfg.master_count,
        .mosaic_ratio = cfg.mosaic_ratio,
        .mosaic_min_size = cfg.mosaic_min_size,
        .grid_columns = cfg.grid_columns,
    };
    if (cfg.output_rule_count == 0) {
        applyWorkspaceOverrides(cfg, index, &tuning);
        if (out.runtime_ratio_set[index]) tuning.master_ratio = out.runtime_ratio[index];
        return tuning;
    }

    const name = core.outputName(out);
    var i: usize = 0;
    while (i < cfg.output_rule_count) : (i += 1) {
        const rule = &cfg.output_rules[i];
        if (rule.ws != 0) continue;
        if (!wildcardMatch(rule.output[0..rule.output_len], name)) continue;
        applyOutputRule(cfg, rule, &tuning);
    }
    applyWorkspaceOverrides(cfg, index, &tuning);

    i = 0;
    while (i < cfg.output_rule_count) : (i += 1) {
        const rule = &cfg.output_rules[i];
        if (rule.ws == 0 or rule.ws != index + 1) continue;
        if (!wildcardMatch(rule.output[0..rule.output_len], name)) continue;
        applyOutputRule(cfg, rule, &tuning);
    }
    if (out.runtime_ratio_set[index]) tuning.master_ratio = out.runtime_ratio[index];
    return tuning;
}

pub fn seedOutputLayouts(server: *Server, out: *Output) void {
    var ws: usize = 1;
    while (ws <= types.WS_COUNT) : (ws += 1) {
        out.ws_layouts[ws - 1] = tuningFor(server, out, ws).layout;
    }
}

pub fn clearRuntimeRatios(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        var ws: usize = 0;
        while (ws < types.WS_COUNT) : (ws += 1) {
            out.runtime_ratio_set[ws] = false;
            out.runtime_ratio[ws] = 0;
        }
    }
}

fn color4(rgb: [3]f32) [4]f32 {
    return .{ rgb[0], rgb[1], rgb[2], 1.0 };
}

pub fn applyOutputTheme(server: *Server, out: *Output) void {
    const cfg = &server.config;

    out.theme_accent = null;
    out.theme_border_active = null;
    out.theme_border_inactive = null;
    out.theme_bg = .{ 0.025, 0.04, 0.075, 1.0 };
    if (cfg.bg_len > 0) {
        var rgb: [3]f32 = .{ out.theme_bg[0], out.theme_bg[1], out.theme_bg[2] };
        core.parseHexColor(cfg.bg[0..cfg.bg_len], &rgb);
        out.theme_bg = color4(rgb);
    }

    const name = core.outputName(out);
    var i: usize = 0;
    while (i < cfg.output_rule_count) : (i += 1) {
        const rule = &cfg.output_rules[i];
        if (rule.ws != 0) continue;
        if (!wildcardMatch(rule.output[0..rule.output_len], name)) continue;
        if (rule.has_accent) out.theme_accent = color4(rule.accent_rgb);
        if (rule.has_bg) out.theme_bg = color4(rule.bg_rgb);
        if (rule.has_border_active) out.theme_border_active = color4(rule.border_active_rgb);
        if (rule.has_border_inactive) out.theme_border_inactive = color4(rule.border_inactive_rgb);
    }
}

pub fn applyOutputThemes(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        applyOutputTheme(server, out);
        core.updateBackground(out);
    }
}

fn matches(rule: *const WindowRule, client: *Client) bool {
    if (rule.app_id_len > 0 and
        !wildcardMatch(rule.app_id[0..rule.app_id_len], client.app_id[0..client.app_id_len])) return false;
    if (rule.title_len > 0 and
        !wildcardMatch(rule.title[0..rule.title_len], client.title[0..client.title_len])) return false;
    if (rule.output_len > 0 and
        !wildcardMatch(rule.output[0..rule.output_len], core.outputName(client.output))) return false;
    if (rule.expr_len > 0) {
        const value = rule_expr.evaluate(rule.expr[0..rule.expr_len], .{
            .app_id = client.app_id[0..client.app_id_len],
            .title = client.title[0..client.title_len],
            .output = core.outputName(client.output),
        }) orelse return false;
        if (!value) return false;
    }
    return true;
}

fn resetDecorations(client: *Client) void {
    client.border_active_override = null;
    client.border_inactive_override = null;
    client.opacity = 1.0;
    client.corner_radius = -1;
    client.blur = .unset;
    client.shadow = .unset;
    client.border_width = -1;
    client.anim = .{};
}

fn mergeCurve(dest: *[types.MAX_CURVE_NAME]u8, dest_len: *usize, src: []const u8) void {
    if (src.len == 0) return;
    core.copyString(dest, dest_len, src);
}

fn mergeAnimation(dest: *types.AnimationOverride, src: *const types.AnimationOverride) void {
    if (src.enabled != .unset) dest.enabled = src.enabled;
    if (src.animation_ms >= 0) dest.animation_ms = src.animation_ms;
    if (src.open_ms >= 0) dest.open_ms = src.open_ms;
    if (src.workspace_ms >= 0) dest.workspace_ms = src.workspace_ms;
    if (src.close_ms >= 0) dest.close_ms = src.close_ms;
    mergeCurve(&dest.curve, &dest.curve_len, src.curve[0..src.curve_len]);
    mergeCurve(&dest.open_curve, &dest.open_curve_len, src.open_curve[0..src.open_curve_len]);
    mergeCurve(&dest.workspace_curve, &dest.workspace_curve_len, src.workspace_curve[0..src.workspace_curve_len]);
    mergeCurve(&dest.close_curve, &dest.close_curve_len, src.close_curve[0..src.close_curve_len]);
}

fn applyVisual(rule: *const WindowRule, client: *Client) void {
    if (rule.has_border_active) {
        client.border_active_override = .{
            rule.border_active_rgb[0],
            rule.border_active_rgb[1],
            rule.border_active_rgb[2],
            1.0,
        };
    }
    if (rule.has_border_inactive) {
        client.border_inactive_override = .{
            rule.border_inactive_rgb[0],
            rule.border_inactive_rgb[1],
            rule.border_inactive_rgb[2],
            1.0,
        };
    }
    if (rule.has_opacity) client.opacity = rule.opacity;
    if (rule.has_corner_radius) client.corner_radius = rule.corner_radius;
    if (rule.blur != .unset) client.blur = rule.blur;
    if (rule.shadow != .unset) client.shadow = rule.shadow;
    if (rule.has_border_width) client.border_width = rule.border_width;
    mergeAnimation(&client.anim, &rule.anim);
}

fn apply(rule: *const WindowRule, client: *Client) void {
    applyVisual(rule, client);
    if (rule.floating != .unset) {
        client.floating = rule.floating == .on;
    }
    if ((rule.has_size or rule.has_position) and rule.floating != .off) {
        client.floating = true;
    }
    if (client.floating and rule.has_size) {
        client.float_w = @max(1, rule.width);
        client.float_h = @max(1, rule.height);
    }
    if (client.floating and rule.has_position) {
        client.float_x = rule.x;
        client.float_y = rule.y;
    }

    if (rule.fullscreen != .unset) {
        const on = rule.fullscreen == .on;
        client.fullscreen = on;
        _ = c.wlr_xdg_toplevel_set_fullscreen(client.xdg, on);
        if (client.foreign_toplevel) |handle| {
            c.wlr_foreign_toplevel_handle_v1_set_fullscreen(handle, on);
        }
    }

    if (rule.workspace >= 1 and rule.workspace <= types.WS_COUNT and
        client.ws != rule.workspace)
    {
        const out = client.output;
        if (out.last_focused[client.ws] == client) out.last_focused[client.ws] = null;
        client.ws = rule.workspace;
        out.last_focused[client.ws] = client;
    }
}

pub fn applyToClient(client: *Client) void {
    const cfg = &client.server.config;
    resetDecorations(client);
    var i: usize = 0;
    while (i < cfg.rule_count) : (i += 1) {
        const rule = &cfg.rules[i];
        if (matches(rule, client)) apply(rule, client);
    }
}

/// Re-evaluate only decorative fields. Structural rules (floating, workspace,
/// size, fullscreen) stay at their map/reload values so a title update cannot
/// move or resize a window behind the user's back. Returns true when a visual
/// field changed and the layout should be re-applied.
pub fn applyVisualToClient(client: *Client) bool {
    const cfg = &client.server.config;
    const old_opacity = client.opacity;
    const old_radius = client.corner_radius;
    const old_blur = client.blur;
    const old_shadow = client.shadow;
    const old_border_width = client.border_width;
    const old_active = client.border_active_override;
    const old_inactive = client.border_inactive_override;
    resetDecorations(client);
    var i: usize = 0;
    while (i < cfg.rule_count) : (i += 1) {
        const rule = &cfg.rules[i];
        if (matches(rule, client)) applyVisual(rule, client);
    }
    return old_opacity != client.opacity or
        old_radius != client.corner_radius or
        old_blur != client.blur or
        old_shadow != client.shadow or
        old_border_width != client.border_width or
        !std.meta.eql(old_active, client.border_active_override) or
        !std.meta.eql(old_inactive, client.border_inactive_override);
}

fn layerMatches(rule: *const types.LayerRule, layer: *LayerSurface) bool {
    if (rule.namespace_len > 0 and
        !wildcardMatch(
            rule.namespace[0..rule.namespace_len],
            core.cstr(layer.wlr.namespace),
        )) return false;
    if (rule.output_len > 0 and
        !wildcardMatch(
            rule.output[0..rule.output_len],
            core.outputName(layer.output),
        )) return false;
    if (rule.layer >= 0 and rule.layer != @as(i32, @intCast(layer.wlr.current.layer))) return false;
    return true;
}

pub fn applyLayerVisuals(server: *Server, layer: *LayerSurface) void {
    const cfg = &server.config;
    layer.opacity = 1.0;
    layer.corner_radius = 0;
    layer.blur = .unset;
    var i: usize = 0;
    while (i < cfg.layer_rule_count) : (i += 1) {
        const rule = &cfg.layer_rules[i];
        if (!layerMatches(rule, layer)) continue;
        if (rule.has_opacity) layer.opacity = rule.opacity;
        if (rule.has_corner_radius) layer.corner_radius = rule.corner_radius;
        if (rule.blur != .unset) layer.blur = rule.blur;
    }
}

pub fn applyAllLayers(server: *Server) void {
    var i: usize = 0;
    while (i < server.layers.len) : (i += 1) {
        const layer = server.layers[i] orelse continue;
        applyLayerVisuals(server, layer);
    }
}

pub fn applyAll(server: *Server) void {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (client.mapped) applyToClient(client);
    }
}
