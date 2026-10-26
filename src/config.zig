const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const event_names = @import("event_names.zig");

const Server = types.Server;
const Config = types.Config;
const Action = types.Action;
const Binding = types.Binding;

pub fn initDefaults(cfg: *Config) void {
    _ = c.memset(@ptrCast(cfg), 0, @sizeOf(Config));

    copyDefault(&cfg.terminal, &cfg.terminal_len, "kitty");
    copyDefault(&cfg.accent, &cfg.accent_len, "#e2684f");
    copyDefault(&cfg.bg, &cfg.bg_len, "#0a0f1a");
    copyDefault(&cfg.border_inactive, &cfg.border_inactive_len, "#293347");
    core.parseHexColor(cfg.border_inactive[0..cfg.border_inactive_len], &cfg.border_inactive_rgb);
    copyDefault(&cfg.font, &cfg.font_len, "Inter");

    cfg.gaps = 10;
    cfg.outer_gaps = 16;
    cfg.border_width = 2;
    cfg.master_ratio = 0.58;
    cfg.master_count = 1;
    cfg.mosaic_ratio = 0.62;
    cfg.mosaic_min_size = 160;
    cfg.grid_columns = 0;
    cfg.layout_helper_timeout = 100;
    var wi: usize = 0;
    while (wi < types.WS_COUNT) : (wi += 1) {
        cfg.ws_gaps[wi] = cfg.gaps;
        cfg.ws_outer_gaps[wi] = cfg.outer_gaps;
        cfg.ws_master_ratio[wi] = cfg.master_ratio;
    }
    cfg.layout_mode = .master;
    for (&cfg.layout_by_ws) |*mode| mode.* = .master;
    copyDefault(&cfg.mode_names[0], &cfg.mode_name_lens[0], "default");
    cfg.mode_count = 1;
    cfg.autostart_panel = true;
    cfg.xwayland = true;
    copyDefault(&cfg.xwayland_display, &cfg.xwayland_display_len, "auto");
    cfg.repeat_rate = 25;
    cfg.repeat_delay = 600;
    core.parseHexColor(cfg.accent[0..cfg.accent_len], &cfg.accent_rgb);

    addDefaults(cfg);
}

fn copyDefault(dest: []u8, len: *usize, value: []const u8) void {
    core.copyString(dest, len, value);
}

fn addIssue(server: *Server, path: []const u8, line: u32, comptime fmt: []const u8, args: anytype) void {
    if (server.config_issue_count >= server.config_issues.len) return;
    var message_buf: [192]u8 = undefined;
    const message = std.fmt.bufPrint(&message_buf, fmt, args) catch "configuration diagnostic message too long";
    const issue = &server.config_issues[server.config_issue_count];
    issue.* = std.mem.zeroes(types.ConfigIssue);
    core.copyString(&issue.path, &issue.path_len, path);
    issue.line = line;
    core.copyString(&issue.message, &issue.message_len, message);
    issue.is_error = true;
    server.config_issue_count += 1;
    server.config_error_count += 1;
}

fn parseIntValue(
    comptime T: type,
    server: *Server,
    path: []const u8,
    line: u32,
    key: []const u8,
    value: []const u8,
) ?T {
    return std.fmt.parseInt(T, value, 10) catch {
        addIssue(server, path, line, "invalid integer for {s}: '{s}'", .{ key, value });
        return null;
    };
}

fn parseFloatValue(
    server: *Server,
    path: []const u8,
    line: u32,
    key: []const u8,
    value: []const u8,
) ?f32 {
    return std.fmt.parseFloat(f32, value) catch {
        addIssue(server, path, line, "invalid number for {s}: '{s}'", .{ key, value });
        return null;
    };
}

fn parseBoolValue(
    server: *Server,
    path: []const u8,
    line: u32,
    key: []const u8,
    value: []const u8,
) ?bool {
    if (std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "on") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.mem.eql(u8, value, "1")) return true;
    if (std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "off") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.mem.eql(u8, value, "0")) return false;
    addIssue(server, path, line, "invalid boolean for {s}: '{s}'", .{ key, value });
    return null;
}

fn validHexColor(value: []const u8) bool {
    var hex = value;
    if (hex.len > 0 and hex[0] == '#') hex = hex[1..];
    if (hex.len != 6) return false;
    for (hex[0..6]) |ch| {
        if (!std.ascii.isHex(ch)) return false;
    }
    return true;
}

fn addDefaults(cfg: *Config) void {
    _ = addBinding(cfg, "super+return", "terminal", "");
    _ = addBinding(cfg, "super+d", "launcher", "");
    _ = addBinding(cfg, "super+v", "clipboard", "");
    _ = addBinding(cfg, "super+q", "close", "");
    _ = addBinding(cfg, "super+shift+e", "quit", "");
    _ = addBinding(cfg, "super+r", "reload", "");
    _ = addBinding(cfg, "super+t", "toggle-layout", "");
    _ = addBinding(cfg, "super+space", "toggle-float", "");
    _ = addBinding(cfg, "super+f", "toggle-fullscreen", "");
    _ = addBinding(cfg, "super+escape", "spawn", "swaylock");
    _ = addBinding(cfg, "super+tab", "focus-next", "");
    _ = addBinding(cfg, "super+shift+tab", "focus-prev", "");
    _ = addBinding(cfg, "super+h", "focus", "left");
    _ = addBinding(cfg, "super+j", "focus", "down");
    _ = addBinding(cfg, "super+k", "focus", "up");
    _ = addBinding(cfg, "super+l", "focus", "right");
    _ = addBinding(cfg, "super+shift+h", "move", "left");
    _ = addBinding(cfg, "super+shift+j", "move", "down");
    _ = addBinding(cfg, "super+shift+k", "move", "up");
    _ = addBinding(cfg, "super+shift+l", "move", "right");
    _ = addBinding(cfg, "super+ctrl+h", "ratio", "-0.03");
    _ = addBinding(cfg, "super+ctrl+l", "ratio", "+0.03");
    _ = addBinding(cfg, "super+alt+h", "resize-width", "-30");
    _ = addBinding(cfg, "super+alt+l", "resize-width", "30");
    _ = addBinding(cfg, "super+alt+k", "resize-height", "-30");
    _ = addBinding(cfg, "super+alt+j", "resize-height", "30");

    var chord: [64]u8 = undefined;
    var i: usize = 1;
    while (i <= types.WS_COUNT) : (i += 1) {
        const c1 = std.fmt.bufPrint(&chord, "super+{d}", .{i}) catch continue;
        _ = addBinding(cfg, c1, "workspace", c1[c1.len - 1 ..]);
        const c2 = std.fmt.bufPrint(&chord, "super+shift+{d}", .{i}) catch continue;
        _ = addBinding(cfg, c2, "move-to-workspace", c2[c2.len - 1 ..]);
    }
}

pub fn addBinding(cfg: *Config, chord: []const u8, action_name: []const u8, arg: []const u8) bool {
    return addBindingInMode(cfg, 0, chord, action_name, arg);
}

pub fn addBindingInMode(
    cfg: *Config,
    mode: u8,
    chord: []const u8,
    action_name: []const u8,
    arg: []const u8,
) bool {
    var mods: u32 = 0;
    var key: []const u8 = "";

    var it = std.mem.splitScalar(u8, chord, '+');
    while (it.next()) |raw| {
        const tok = std.mem.trim(u8, raw, " \t");
        if (tok.len == 0) continue;
        if (std.ascii.eqlIgnoreCase(tok, "super") or
            std.ascii.eqlIgnoreCase(tok, "logo") or
            std.ascii.eqlIgnoreCase(tok, "win"))
        {
            mods |= core.MOD_LOGO;
        } else if (std.ascii.eqlIgnoreCase(tok, "shift")) {
            mods |= core.MOD_SHIFT;
        } else if (std.ascii.eqlIgnoreCase(tok, "ctrl") or std.ascii.eqlIgnoreCase(tok, "control")) {
            mods |= core.MOD_CTRL;
        } else if (std.ascii.eqlIgnoreCase(tok, "alt")) {
            mods |= core.MOD_ALT;
        } else {
            key = tok;
        }
    }
    if (key.len == 0) return false;

    var kbuf: [64:0]u8 = undefined;
    core.copyZ(&kbuf, key);
    var sym = c.xkb_keysym_from_name(&kbuf, 0);
    if (sym == c.XKB_KEY_NoSymbol) {
        var alt: [64:0]u8 = undefined;
        core.copyZ(&alt, key);
        if (alt[0] >= 'a' and alt[0] <= 'z') alt[0] -= 32;
        sym = c.xkb_keysym_from_name(&alt, 0);
    }
    if (sym == c.XKB_KEY_NoSymbol) {
        core.logInfo("config: unknown keysym '{s}'", .{key});
        return false;
    }

    const action = parseAction(action_name);
    if (action == .none) {
        core.logInfo("config: unknown action '{s}'", .{action_name});
        return false;
    }

    var binding: Binding = .{
        .mods = mods,
        .sym = @intCast(sym),
        .mode = mode,
        .action = action,
        .num = 0,
        .ratio = 0,
        .arg = undefined,
        .arg_len = 0,
    };
    core.copyString(&binding.arg, &binding.arg_len, arg);

    switch (action) {
        .workspace, .move_to_workspace => {
            binding.num = std.fmt.parseInt(i32, arg, 10) catch {
                core.logInfo("config: invalid workspace for bind '{s}'", .{arg});
                return false;
            };
            if (binding.num < 1 or binding.num > types.WS_COUNT) {
                core.logInfo("config: bind workspace out of range: {d}", .{binding.num});
                return false;
            }
        },
        .ratio => {
            binding.ratio = std.fmt.parseFloat(f32, arg) catch {
                core.logInfo("config: invalid ratio for bind '{s}'", .{arg});
                return false;
            };
        },
        .resize_width, .resize_height => {
            binding.num = std.fmt.parseInt(i32, arg, 10) catch {
                core.logInfo("config: invalid resize delta for bind '{s}'", .{arg});
                return false;
            };
        },
        .focus, .move => {
            if (!std.mem.eql(u8, arg, "left") and !std.mem.eql(u8, arg, "right") and
                !std.mem.eql(u8, arg, "up") and !std.mem.eql(u8, arg, "down"))
            {
                core.logInfo("config: invalid direction for bind '{s}'", .{arg});
                return false;
            }
        },
        .set_layout => {
            if (types.layoutFromName(arg) == null) {
                core.logInfo("config: unknown layout for bind '{s}'", .{arg});
                return false;
            }
        },
        .enter_mode => {
            if (arg.len == 0 or arg.len >= types.MAX_MODE_NAME) {
                core.logInfo("config: invalid mode name for bind '{s}'", .{arg});
                return false;
            }
        },
        else => {},
    }

    var i: usize = 0;
    while (i < cfg.binding_count) : (i += 1) {
        if (cfg.bindings[i].mode == mode and cfg.bindings[i].mods == mods and
            cfg.bindings[i].sym == binding.sym)
        {
            cfg.bindings[i] = binding;
            return true;
        }
    }
    if (cfg.binding_count < cfg.bindings.len) {
        cfg.bindings[cfg.binding_count] = binding;
        cfg.binding_count += 1;
        return true;
    }
    core.logInfo("config: too many bindings (max {d})", .{cfg.bindings.len});
    return false;
}

pub fn addHook(cfg: *Config, event: []const u8, command: []const u8) bool {
    if (command.len == 0) return false;
    if (!event_names.isKnown(event)) {
        core.logInfo("config: unknown hook event '{s}'", .{event});
        return false;
    }
    if (cfg.hook_count >= cfg.hooks.len) {
        core.logInfo("config: too many hooks (max {d})", .{cfg.hooks.len});
        return false;
    }

    var hook = &cfg.hooks[cfg.hook_count];
    core.copyString(&hook.event, &hook.event_len, event);
    core.copyString(&hook.command, &hook.command_len, command);
    cfg.hook_count += 1;
    return true;
}

fn parseRuleBool(value: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "on") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.mem.eql(u8, value, "1")) return true;
    if (std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "off") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.mem.eql(u8, value, "0")) return false;
    return null;
}

pub fn addRule(cfg: *Config, value: []const u8) bool {
    if (cfg.rule_count >= cfg.rules.len) {
        core.logInfo("config: too many window rules (max {d})", .{cfg.rules.len});
        return false;
    }

    var rule = types.WindowRule{};
    var clauses = std.mem.splitScalar(u8, value, ';');
    var clauses_seen: usize = 0;
    while (clauses.next()) |raw| {
        const clause = std.mem.trim(u8, raw, " \t");
        if (clause.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, clause, '=') orelse {
            core.logInfo("config: window-rule clause needs '=': '{s}'", .{clause});
            return false;
        };
        const key = std.mem.trim(u8, clause[0..eq], " \t");
        var val = std.mem.trim(u8, clause[eq + 1 ..], " \t");
        if (val.len >= 2 and
            ((val[0] == '"' and val[val.len - 1] == '"') or
                (val[0] == '\'' and val[val.len - 1] == '\'')))
        {
            val = val[1 .. val.len - 1];
        }
        if (key.len == 0 or val.len == 0) {
            core.logInfo("config: invalid window-rule clause '{s}'", .{clause});
            return false;
        }
        clauses_seen += 1;

        if (std.ascii.eqlIgnoreCase(key, "app-id") or
            std.ascii.eqlIgnoreCase(key, "app_id") or
            std.ascii.eqlIgnoreCase(key, "class"))
        {
            core.copyString(&rule.app_id, &rule.app_id_len, val);
        } else if (std.ascii.eqlIgnoreCase(key, "title")) {
            core.copyString(&rule.title, &rule.title_len, val);
        } else if (std.ascii.eqlIgnoreCase(key, "output") or
            std.ascii.eqlIgnoreCase(key, "monitor"))
        {
            core.copyString(&rule.output, &rule.output_len, val);
        } else if (std.ascii.eqlIgnoreCase(key, "workspace") or
            std.ascii.eqlIgnoreCase(key, "ws"))
        {
            const ws = std.fmt.parseInt(usize, val, 10) catch {
                core.logInfo("config: invalid rule workspace '{s}'", .{val});
                return false;
            };
            if (ws < 1 or ws > types.WS_COUNT) {
                core.logInfo("config: rule workspace out of range: {d}", .{ws});
                return false;
            }
            rule.workspace = ws;
        } else if (std.ascii.eqlIgnoreCase(key, "float") or
            std.ascii.eqlIgnoreCase(key, "floating"))
        {
            const on = parseRuleBool(val) orelse {
                core.logInfo("config: invalid rule float value '{s}'", .{val});
                return false;
            };
            rule.floating = if (on) .on else .off;
        } else if (std.ascii.eqlIgnoreCase(key, "tile")) {
            const on = parseRuleBool(val) orelse {
                core.logInfo("config: invalid rule tile value '{s}'", .{val});
                return false;
            };
            rule.floating = if (on) .off else .on;
        } else if (std.ascii.eqlIgnoreCase(key, "fullscreen")) {
            const on = parseRuleBool(val) orelse {
                core.logInfo("config: invalid rule fullscreen value '{s}'", .{val});
                return false;
            };
            rule.fullscreen = if (on) .on else .off;
        } else if (std.ascii.eqlIgnoreCase(key, "size")) {
            const sep = std.mem.indexOfAny(u8, val, "xX") orelse {
                core.logInfo("config: rule size needs WxH: '{s}'", .{val});
                return false;
            };
            const w = std.fmt.parseInt(i32, std.mem.trim(u8, val[0..sep], " \t"), 10) catch 0;
            const h = std.fmt.parseInt(i32, std.mem.trim(u8, val[sep + 1 ..], " \t"), 10) catch 0;
            if (w <= 0 or h <= 0) {
                core.logInfo("config: invalid rule size '{s}'", .{val});
                return false;
            }
            rule.has_size = true;
            rule.width = w;
            rule.height = h;
        } else if (std.ascii.eqlIgnoreCase(key, "width")) {
            const w = std.fmt.parseInt(i32, val, 10) catch 0;
            if (w <= 0) {
                core.logInfo("config: invalid rule width '{s}'", .{val});
                return false;
            }
            rule.has_size = true;
            rule.width = w;
            if (rule.height <= 0) rule.height = 1;
        } else if (std.ascii.eqlIgnoreCase(key, "height")) {
            const h = std.fmt.parseInt(i32, val, 10) catch 0;
            if (h <= 0) {
                core.logInfo("config: invalid rule height '{s}'", .{val});
                return false;
            }
            rule.has_size = true;
            rule.height = h;
            if (rule.width <= 0) rule.width = 1;
        } else if (std.ascii.eqlIgnoreCase(key, "position") or
            std.ascii.eqlIgnoreCase(key, "pos"))
        {
            const sep = std.mem.indexOfScalar(u8, val, ',') orelse {
                core.logInfo("config: rule position needs X,Y: '{s}'", .{val});
                return false;
            };
            const x = std.fmt.parseInt(i32, std.mem.trim(u8, val[0..sep], " \t"), 10) catch {
                core.logInfo("config: invalid rule position '{s}'", .{val});
                return false;
            };
            const y = std.fmt.parseInt(i32, std.mem.trim(u8, val[sep + 1 ..], " \t"), 10) catch {
                core.logInfo("config: invalid rule position '{s}'", .{val});
                return false;
            };
            rule.has_position = true;
            rule.x = x;
            rule.y = y;
        } else {
            core.logInfo("config: unknown window-rule key '{s}'", .{key});
            return false;
        }
    }

    if (clauses_seen == 0) return false;
    core.copyString(&rule.raw, &rule.raw_len, value);
    cfg.rules[cfg.rule_count] = rule;
    cfg.rule_count += 1;
    return true;
}

pub fn addWorkspaceRule(cfg: *Config, value: []const u8) bool {
    var ws: ?usize = null;
    var gaps: ?i32 = null;
    var outer_gaps: ?i32 = null;
    var master_ratio: ?f32 = null;
    var layout_mode: ?types.LayoutMode = null;

    var clauses = std.mem.splitScalar(u8, value, ';');
    while (clauses.next()) |raw| {
        const clause = std.mem.trim(u8, raw, " \t");
        if (clause.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, clause, '=') orelse {
            core.logInfo("config: workspace-rule clause needs '=': '{s}'", .{clause});
            return false;
        };
        const key = std.mem.trim(u8, clause[0..eq], " \t");
        var val = std.mem.trim(u8, clause[eq + 1 ..], " \t");
        if (val.len >= 2 and
            ((val[0] == '"' and val[val.len - 1] == '"') or
                (val[0] == '\'' and val[val.len - 1] == '\'')))
        {
            val = val[1 .. val.len - 1];
        }
        if (key.len == 0 or val.len == 0) {
            core.logInfo("config: invalid workspace-rule clause '{s}'", .{clause});
            return false;
        }

        if (std.ascii.eqlIgnoreCase(key, "ws") or
            std.ascii.eqlIgnoreCase(key, "workspace"))
        {
            const n = std.fmt.parseInt(usize, val, 10) catch {
                core.logInfo("config: invalid workspace-rule workspace '{s}'", .{val});
                return false;
            };
            if (n < 1 or n > types.WS_COUNT) {
                core.logInfo("config: workspace-rule workspace out of range: {d}", .{n});
                return false;
            }
            ws = n - 1;
        } else if (std.ascii.eqlIgnoreCase(key, "gaps")) {
            gaps = std.fmt.parseInt(i32, val, 10) catch {
                core.logInfo("config: invalid workspace-rule gaps '{s}'", .{val});
                return false;
            };
        } else if (std.ascii.eqlIgnoreCase(key, "outer-gaps") or
            std.ascii.eqlIgnoreCase(key, "outer_gaps"))
        {
            outer_gaps = std.fmt.parseInt(i32, val, 10) catch {
                core.logInfo("config: invalid workspace-rule outer-gaps '{s}'", .{val});
                return false;
            };
        } else if (std.ascii.eqlIgnoreCase(key, "master-ratio") or
            std.ascii.eqlIgnoreCase(key, "master_ratio"))
        {
            master_ratio = std.fmt.parseFloat(f32, val) catch {
                core.logInfo("config: invalid workspace-rule master-ratio '{s}'", .{val});
                return false;
            };
        } else if (std.ascii.eqlIgnoreCase(key, "layout")) {
            layout_mode = types.layoutFromName(val) orelse {
                core.logInfo("config: unknown workspace-rule layout '{s}'", .{val});
                return false;
            };
        } else {
            core.logInfo("config: unknown workspace-rule key '{s}'", .{key});
            return false;
        }
    }

    const idx = ws orelse {
        core.logInfo("config: workspace-rule needs ws=<1..9>", .{});
        return false;
    };
    if (gaps) |v| {
        cfg.ws_gaps[idx] = v;
        cfg.ws_gaps_set[idx] = true;
    }
    if (outer_gaps) |v| {
        cfg.ws_outer_gaps[idx] = v;
        cfg.ws_outer_set[idx] = true;
    }
    if (master_ratio) |v| {
        cfg.ws_master_ratio[idx] = v;
        cfg.ws_ratio_set[idx] = true;
    }
    if (layout_mode) |v| {
        cfg.layout_by_ws[idx] = v;
        cfg.layout_overrides[idx] = true;
    }
    return true;
}

fn parseAction(name: []const u8) Action {
    if (std.ascii.eqlIgnoreCase(name, "spawn") or std.ascii.eqlIgnoreCase(name, "exec")) return .spawn;
    if (std.ascii.eqlIgnoreCase(name, "terminal")) return .terminal;
    if (std.ascii.eqlIgnoreCase(name, "close")) return .close;
    if (std.ascii.eqlIgnoreCase(name, "quit")) return .quit;
    if (std.ascii.eqlIgnoreCase(name, "workspace")) return .workspace;
    if (std.ascii.eqlIgnoreCase(name, "move-to-workspace")) return .move_to_workspace;
    if (std.ascii.eqlIgnoreCase(name, "focus")) return .focus;
    if (std.ascii.eqlIgnoreCase(name, "move")) return .move;
    if (std.ascii.eqlIgnoreCase(name, "toggle-float")) return .toggle_float;
    if (std.ascii.eqlIgnoreCase(name, "toggle-fullscreen")) return .toggle_fullscreen;
    if (std.ascii.eqlIgnoreCase(name, "focus-next")) return .focus_next;
    if (std.ascii.eqlIgnoreCase(name, "focus-prev")) return .focus_prev;
    if (std.ascii.eqlIgnoreCase(name, "launcher")) return .launcher;
    if (std.ascii.eqlIgnoreCase(name, "clipboard") or std.ascii.eqlIgnoreCase(name, "clipboard-history")) return .clipboard;
    if (std.ascii.eqlIgnoreCase(name, "reload")) return .reload;
    if (std.ascii.eqlIgnoreCase(name, "ratio")) return .ratio;
    if (std.ascii.eqlIgnoreCase(name, "toggle-layout")) return .toggle_layout;
    if (std.ascii.eqlIgnoreCase(name, "set-layout")) return .set_layout;
    if (std.ascii.eqlIgnoreCase(name, "resize-width")) return .resize_width;
    if (std.ascii.eqlIgnoreCase(name, "resize-height")) return .resize_height;
    if (std.ascii.eqlIgnoreCase(name, "enter-mode") or std.ascii.eqlIgnoreCase(name, "mode")) return .enter_mode;
    return .none;
}

pub fn findMode(cfg: *const Config, name: []const u8) ?u8 {
    var i: usize = 0;
    while (i < cfg.mode_count) : (i += 1) {
        if (std.mem.eql(u8, cfg.mode_names[i][0..cfg.mode_name_lens[i]], name)) {
            return @intCast(i);
        }
    }
    return null;
}

fn validModeName(name: []const u8) bool {
    if (name.len == 0 or name.len >= types.MAX_MODE_NAME) return false;
    for (name) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '-') return false;
    }
    return true;
}

fn ensureMode(cfg: *Config, name: []const u8) ?u8 {
    if (findMode(cfg, name)) |existing| return existing;
    if (!validModeName(name)) return null;
    if (cfg.mode_count >= cfg.mode_names.len) return null;
    const index = cfg.mode_count;
    cfg.mode_count += 1;
    core.copyString(&cfg.mode_names[index], &cfg.mode_name_lens[index], name);
    return @intCast(index);
}

fn resolveInclude(dest: []u8, base: []const u8, value: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(value)) {
        return std.fmt.bufPrint(dest, "{s}", .{value}) catch "";
    }
    const dir = std.fs.path.dirname(base) orelse ".";
    return std.fmt.bufPrint(dest, "{s}/{s}", .{ dir, value }) catch "";
}

fn loadPath(
    server: *Server,
    path: []const u8,
    depth: usize,
    current_mode: *usize,
    origin_path: []const u8,
    origin_line: u32,
) void {
    const source_path = if (origin_path.len > 0) origin_path else path;
    const source_line = if (origin_path.len > 0) origin_line else 0;

    if (depth > 8) {
        addIssue(server, source_path, source_line, "include depth limit reached for '{s}'", .{path});
        return;
    }
    if (path.len >= 512) {
        addIssue(server, source_path, source_line, "config path too long: '{s}'", .{path});
        return;
    }

    var zpath: [512:0]u8 = undefined;
    core.copyZ(&zpath, path);
    const file = c.fopen(&zpath, "r") orelse {
        if (depth == 0) {
            core.logInfo("config: {s} not found; using defaults", .{path});
        } else {
            addIssue(server, source_path, source_line, "included config not found: '{s}'", .{path});
        }
        return;
    };
    defer _ = c.fclose(file);

    var line_buf: [1024]u8 = undefined;
    var line_no: u32 = 0;
    while (c.fgets(&line_buf, @intCast(line_buf.len), file)) |_| {
        line_no += 1;
        const raw = std.mem.span(@as([*:0]const u8, @ptrCast(&line_buf)));
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse {
            addIssue(server, path, line_no, "expected key = value: '{s}'", .{trimmed});
            continue;
        };
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        const value = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        if (key.len == 0) {
            addIssue(server, path, line_no, "empty key", .{});
            continue;
        }

        if (std.mem.eql(u8, key, "include")) {
            var include_buf: [512]u8 = undefined;
            const include_path = resolveInclude(&include_buf, path, value);
            if (include_path.len == 0) {
                addIssue(server, path, line_no, "invalid include '{s}'", .{value});
            } else {
                const parent_mode = current_mode.*;
                loadPath(server, include_path, depth + 1, current_mode, path, line_no);
                current_mode.* = parent_mode;
            }
        } else if (std.mem.eql(u8, key, "terminal")) {
            core.copyString(&server.config.terminal, &server.config.terminal_len, value);
        } else if (std.mem.eql(u8, key, "gaps")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.gaps = v;
        } else if (std.mem.eql(u8, key, "outer_gaps")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.outer_gaps = v;
        } else if (std.mem.eql(u8, key, "border_width")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.border_width = v;
        } else if (std.mem.eql(u8, key, "master_ratio")) {
            if (parseFloatValue(server, path, line_no, key, value)) |v| server.config.master_ratio = v;
        } else if (std.mem.eql(u8, key, "master_count")) {
            if (parseIntValue(usize, server, path, line_no, key, value)) |v| server.config.master_count = v;
        } else if (std.mem.eql(u8, key, "mosaic_ratio")) {
            if (parseFloatValue(server, path, line_no, key, value)) |v| server.config.mosaic_ratio = v;
        } else if (std.mem.eql(u8, key, "mosaic_min_size")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.mosaic_min_size = v;
        } else if (std.mem.eql(u8, key, "grid_columns")) {
            if (parseIntValue(usize, server, path, line_no, key, value)) |v| server.config.grid_columns = v;
        } else if (std.mem.eql(u8, key, "layout_helper")) {
            core.copyString(&server.config.layout_helper, &server.config.layout_helper_len, value);
        } else if (std.mem.eql(u8, key, "layout_helper_timeout")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.layout_helper_timeout = v;
        } else if (std.mem.eql(u8, key, "layout")) {
            if (types.layoutFromName(value)) |mode| {
                server.config.layout_mode = mode;
            } else {
                addIssue(server, path, line_no, "unknown layout '{s}'", .{value});
            }
        } else if (std.mem.startsWith(u8, key, "layout_") and key.len == 8 and
            key[7] >= '1' and key[7] <= '9')
        {
            const ws: usize = key[7] - '1';
            if (types.layoutFromName(value)) |mode| {
                server.config.layout_by_ws[ws] = mode;
                server.config.layout_overrides[ws] = true;
            } else {
                addIssue(server, path, line_no, "unknown layout '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "panel") or std.mem.eql(u8, key, "autostart_panel")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.autostart_panel = v;
        } else if (std.mem.eql(u8, key, "xwayland")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.xwayland = v;
        } else if (std.mem.eql(u8, key, "xwayland_display")) {
            core.copyString(&server.config.xwayland_display, &server.config.xwayland_display_len, value);
        } else if (std.mem.eql(u8, key, "kb_layout") or std.mem.eql(u8, key, "keyboard_layout")) {
            core.copyString(&server.config.kb_layout, &server.config.kb_layout_len, value);
        } else if (std.mem.eql(u8, key, "kb_variant") or std.mem.eql(u8, key, "keyboard_variant")) {
            core.copyString(&server.config.kb_variant, &server.config.kb_variant_len, value);
        } else if (std.mem.eql(u8, key, "kb_options") or std.mem.eql(u8, key, "keyboard_options")) {
            core.copyString(&server.config.kb_options, &server.config.kb_options_len, value);
        } else if (std.mem.eql(u8, key, "kb_model") or std.mem.eql(u8, key, "keyboard_model")) {
            core.copyString(&server.config.kb_model, &server.config.kb_model_len, value);
        } else if (std.mem.eql(u8, key, "kb_rules") or std.mem.eql(u8, key, "keyboard_rules")) {
            core.copyString(&server.config.kb_rules, &server.config.kb_rules_len, value);
        } else if (std.mem.eql(u8, key, "repeat_rate")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.repeat_rate = v;
        } else if (std.mem.eql(u8, key, "repeat_delay")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.repeat_delay = v;
        } else if (std.mem.eql(u8, key, "accent")) {
            if (validHexColor(value)) {
                core.copyString(&server.config.accent, &server.config.accent_len, value);
            } else {
                addIssue(server, path, line_no, "invalid color for accent: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "bg")) {
            if (validHexColor(value)) {
                core.copyString(&server.config.bg, &server.config.bg_len, value);
            } else {
                addIssue(server, path, line_no, "invalid color for bg: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "border_active") or std.mem.eql(u8, key, "active_border")) {
            if (value.len == 0 or validHexColor(value)) {
                core.copyString(&server.config.border_active, &server.config.border_active_len, value);
            } else {
                addIssue(server, path, line_no, "invalid color for {s}: '{s}'", .{ key, value });
            }
        } else if (std.mem.eql(u8, key, "border_inactive") or std.mem.eql(u8, key, "inactive_border")) {
            if (value.len == 0 or validHexColor(value)) {
                core.copyString(&server.config.border_inactive, &server.config.border_inactive_len, value);
            } else {
                addIssue(server, path, line_no, "invalid color for {s}: '{s}'", .{ key, value });
            }
        } else if (std.mem.eql(u8, key, "mode")) {
            if (ensureMode(&server.config, value)) |mode_index| {
                current_mode.* = mode_index;
            } else {
                addIssue(server, path, line_no, "invalid mode name '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "window-rule") or std.mem.eql(u8, key, "window_rule")) {
            if (!addRule(&server.config, value)) {
                addIssue(server, path, line_no, "invalid window-rule: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "workspace-rule") or std.mem.eql(u8, key, "workspace_rule")) {
            if (!addWorkspaceRule(&server.config, value)) {
                addIssue(server, path, line_no, "invalid workspace-rule: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "font")) {
            core.copyString(&server.config.font, &server.config.font_len, value);
        } else if (std.mem.eql(u8, key, "output_config")) {
            core.copyString(&server.config.output_config, &server.config.output_config_len, value);
        } else if (std.mem.eql(u8, key, "bind")) {
            if (std.mem.indexOfAny(u8, value, " \t")) |sp| {
                const chord = value[0..sp];
                const rest = std.mem.trimStart(u8, value[sp..], " \t");
                const rest_sp = std.mem.indexOfAny(u8, rest, " \t");
                const action_name = if (rest_sp) |p| rest[0..p] else rest;
                const arg = if (rest_sp) |p| std.mem.trimStart(u8, rest[p..], " \t") else "";
                if (!addBindingInMode(&server.config, @intCast(current_mode.*), chord, action_name, arg)) {
                    addIssue(server, path, line_no, "invalid bind: '{s}'", .{value});
                }
            } else {
                addIssue(server, path, line_no, "bind needs a chord and action: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "hook") or std.mem.eql(u8, key, "startup")) {
            if (std.mem.eql(u8, key, "startup")) {
                if (!addHook(&server.config, event_names.startup, value)) {
                    addIssue(server, path, line_no, "invalid startup command", .{});
                }
            } else if (std.mem.indexOfAny(u8, value, " \t")) |sp| {
                const event = value[0..sp];
                const command = std.mem.trimStart(u8, value[sp..], " \t");
                if (!addHook(&server.config, event, command)) {
                    addIssue(server, path, line_no, "invalid hook '{s}'", .{event});
                }
            } else {
                addIssue(server, path, line_no, "hook needs an event and a command", .{});
            }
        } else if (std.mem.eql(u8, key, "launcher_entry") or
            std.mem.eql(u8, key, "panel_bg") or
            std.mem.eql(u8, key, "panel_fg") or
            std.mem.eql(u8, key, "bar_height") or
            std.mem.eql(u8, key, "bar_top_margin") or
            std.mem.eql(u8, key, "bar_side_margin") or
            std.mem.eql(u8, key, "power_lock") or
            std.mem.eql(u8, key, "power_suspend") or
            std.mem.eql(u8, key, "power_reboot") or
            std.mem.eql(u8, key, "power_off"))
        {
            // The panel parses these keys; the compositor only validates the file.
        } else {
            addIssue(server, path, line_no, "unknown key '{s}'", .{key});
        }
    }
}

pub fn load(server: *Server) void {
    server.config_issue_count = 0;
    server.config_error_count = 0;
    initDefaults(&server.config);

    var path_buf: [512]u8 = undefined;
    var path: []const u8 = "";
    if (c.getenv("TESSA_CONFIG")) |p| {
        path = core.cstr(p);
    } else if (c.getenv("XDG_CONFIG_HOME")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/tessa/config", .{core.cstr(p)}) catch "";
    } else if (c.getenv("HOME")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/.config/tessa/config", .{core.cstr(p)}) catch "";
    }

    var parse_mode: usize = 0;
    if (path.len > 0) loadPath(server, path, 0, &parse_mode, "", 0);

    if (server.config.gaps < 0) server.config.gaps = 0;
    if (server.config.outer_gaps < 0) server.config.outer_gaps = 0;
    if (server.config.border_width < 0) server.config.border_width = 0;
    if (server.config.border_width > 16) server.config.border_width = 16;
    if (server.config.master_ratio < 0.15) server.config.master_ratio = 0.15;
    if (server.config.master_ratio > 0.9) server.config.master_ratio = 0.9;
    if (server.config.master_count < 1) server.config.master_count = 1;
    if (server.config.master_count > 8) server.config.master_count = 8;
    if (server.config.mosaic_ratio < 0.25) server.config.mosaic_ratio = 0.25;
    if (server.config.mosaic_ratio > 0.85) server.config.mosaic_ratio = 0.85;
    if (server.config.mosaic_min_size < 80) server.config.mosaic_min_size = 80;
    if (server.config.mosaic_min_size > 600) server.config.mosaic_min_size = 600;
    if (server.config.grid_columns > 8) server.config.grid_columns = 8;
    if (server.config.layout_helper_timeout < 10) server.config.layout_helper_timeout = 10;
    if (server.config.layout_helper_timeout > 1000) server.config.layout_helper_timeout = 1000;
    if (server.config.repeat_rate < 1) server.config.repeat_rate = 25;
    if (server.config.repeat_rate > 2000) server.config.repeat_rate = 2000;
    if (server.config.repeat_delay < 1) server.config.repeat_delay = 600;
    var wi: usize = 0;
    while (wi < types.WS_COUNT) : (wi += 1) {
        if (!server.config.ws_gaps_set[wi]) server.config.ws_gaps[wi] = server.config.gaps;
        if (!server.config.ws_outer_set[wi]) server.config.ws_outer_gaps[wi] = server.config.outer_gaps;
        if (!server.config.ws_ratio_set[wi]) server.config.ws_master_ratio[wi] = server.config.master_ratio;
        if (server.config.ws_gaps[wi] < 0) server.config.ws_gaps[wi] = 0;
        if (server.config.ws_outer_gaps[wi] < 0) server.config.ws_outer_gaps[wi] = 0;
        if (server.config.ws_master_ratio[wi] < 0.15) server.config.ws_master_ratio[wi] = 0.15;
        if (server.config.ws_master_ratio[wi] > 0.9) server.config.ws_master_ratio[wi] = 0.9;
        if (!server.config.layout_overrides[wi]) {
            server.config.layout_by_ws[wi] = server.config.layout_mode;
        }
    }
    core.parseHexColor(server.config.accent[0..server.config.accent_len], &server.config.accent_rgb);
    if (server.config.border_active_len > 0) {
        core.parseHexColor(server.config.border_active[0..server.config.border_active_len], &server.config.border_active_rgb);
    }
    if (server.config.border_inactive_len > 0) {
        core.parseHexColor(server.config.border_inactive[0..server.config.border_inactive_len], &server.config.border_inactive_rgb);
    }

    var wants_custom = server.config.layout_mode == .custom;
    var si: usize = 0;
    while (si < types.WS_COUNT) : (si += 1) {
        if (server.config.layout_by_ws[si] == .custom) wants_custom = true;
    }
    if (wants_custom and server.config.layout_helper_len == 0) {
        core.logInfo("config: custom layout selected without layout_helper; using master fallback", .{});
    }

    if (server.config_issue_count > 0) {
        core.logInfo("config: {d} error(s) while loading", .{server.config_issue_count});
        var ei: usize = 0;
        while (ei < server.config_issue_count) : (ei += 1) {
            const issue = &server.config_issues[ei];
            core.logInfo("config: {s}:{d}: {s}", .{
                issue.path[0..issue.path_len],
                issue.line,
                issue.message[0..issue.message_len],
            });
        }
    }

    core.logInfo("config: {s} (terminal={s}, bindings={d}, hooks={d}, rules={d})", .{
        if (path.len > 0) path else "defaults",
        server.config.terminal[0..server.config.terminal_len],
        server.config.binding_count,
        server.config.hook_count,
        server.config.rule_count,
    });
}
