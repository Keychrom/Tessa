const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;
const Client = types.Client;
const WindowRule = types.WindowRule;

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
