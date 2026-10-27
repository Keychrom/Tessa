const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;
const Client = types.Client;
const Output = types.Output;
const WindowRule = types.WindowRule;

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

fn applyOutputRule(rule: *const types.OutputRule, tuning: *Tuning) void {
    if (rule.has_layout) tuning.layout = rule.layout;
    if (rule.has_gaps) tuning.gaps = rule.gaps;
    if (rule.has_outer_gaps) tuning.outer_gaps = rule.outer_gaps;
    if (rule.has_master_ratio) tuning.master_ratio = rule.master_ratio;
    if (rule.has_master_count) tuning.master_count = rule.master_count;
    if (rule.has_mosaic_ratio) tuning.mosaic_ratio = rule.mosaic_ratio;
    if (rule.has_mosaic_min_size) tuning.mosaic_min_size = rule.mosaic_min_size;
    if (rule.has_grid_columns) tuning.grid_columns = rule.grid_columns;
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
        if (cfg.ws_gaps_set[index]) tuning.gaps = cfg.ws_gaps[index];
        if (cfg.ws_outer_set[index]) tuning.outer_gaps = cfg.ws_outer_gaps[index];
        if (cfg.ws_ratio_set[index]) tuning.master_ratio = cfg.ws_master_ratio[index];
        if (out.runtime_ratio_set[index]) tuning.master_ratio = out.runtime_ratio[index];
        return tuning;
    }

    const name = core.outputName(out);
    var i: usize = 0;
    while (i < cfg.output_rule_count) : (i += 1) {
        const rule = &cfg.output_rules[i];
        if (rule.ws != 0) continue;
        if (!wildcardMatch(rule.output[0..rule.output_len], name)) continue;
        applyOutputRule(rule, &tuning);
    }
    if (cfg.ws_gaps_set[index]) tuning.gaps = cfg.ws_gaps[index];
    if (cfg.ws_outer_set[index]) tuning.outer_gaps = cfg.ws_outer_gaps[index];
    if (cfg.ws_ratio_set[index]) tuning.master_ratio = cfg.ws_master_ratio[index];
    if (cfg.layout_overrides[index]) tuning.layout = cfg.layout_by_ws[index];

    i = 0;
    while (i < cfg.output_rule_count) : (i += 1) {
        const rule = &cfg.output_rules[i];
        if (rule.ws == 0 or rule.ws != index + 1) continue;
        if (!wildcardMatch(rule.output[0..rule.output_len], name)) continue;
        applyOutputRule(rule, &tuning);
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

fn matches(rule: *const WindowRule, client: *Client) bool {
    if (rule.app_id_len > 0 and
        !wildcardMatch(rule.app_id[0..rule.app_id_len], client.app_id[0..client.app_id_len])) return false;
    if (rule.title_len > 0 and
        !wildcardMatch(rule.title[0..rule.title_len], client.title[0..client.title_len])) return false;
    if (rule.output_len > 0 and
        !wildcardMatch(rule.output[0..rule.output_len], core.outputName(client.output))) return false;
    return true;
}

fn apply(rule: *const WindowRule, client: *Client) void {
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
    var i: usize = 0;
    while (i < cfg.rule_count) : (i += 1) {
        const rule = &cfg.rules[i];
        if (matches(rule, client)) apply(rule, client);
    }
}

pub fn applyAll(server: *Server) void {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (client.mapped) applyToClient(client);
    }
}
