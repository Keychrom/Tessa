const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const event_names = @import("event_names.zig");
const rule_expr = @import("rule_expr.zig");

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
    cfg.animations = true;
    cfg.reduce_motion = false;
    cfg.reduce_motion_animations = .none;
    cfg.reduce_motion_fade_ms = 120;
    cfg.animation_ms = 160;
    cfg.animation_open_ms = -1;
    cfg.animation_workspace_ms = -1;
    cfg.animation_close_ms = -1;
    cfg.shadows = true;
    cfg.corner_radius = 10;
    cfg.blur = true;
    cfg.blur_radius = 6;
    cfg.blur_passes = 3;
    cfg.gestures = true;
    cfg.gesture_fingers = 3;
    cfg.gesture_workspace_threshold = 400;
    cfg.gesture_launcher_threshold = 300;
    cfg.touch = true;
    cfg.tablet = true;
    cfg.pointer_constraints = true;
    cfg.xim = true;
    copyDefault(&cfg.xim_server, &cfg.xim_server_len, "fcitx");
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
    cfg.leader_timeout = 1000;
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

fn addWorkspacePin(
    server: *Server,
    path: []const u8,
    line: u32,
    key: []const u8,
    value: []const u8,
) void {
    var it = std.mem.tokenizeAny(u8, value, " \t");
    const output_name = it.next() orelse {
        addIssue(server, path, line, "expected OUTPUT WORKSPACE for {s}", .{key});
        return;
    };
    const ws_text = it.next() orelse {
        addIssue(server, path, line, "expected OUTPUT WORKSPACE for {s}", .{key});
        return;
    };
    if (it.next() != null) {
        addIssue(server, path, line, "unexpected extra value for {s}", .{key});
        return;
    }
    if (output_name.len >= 64) {
        addIssue(server, path, line, "output name too long for {s}", .{key});
        return;
    }
    const ws = std.fmt.parseInt(usize, ws_text, 10) catch {
        addIssue(server, path, line, "invalid workspace for {s}: '{s}'", .{ key, ws_text });
        return;
    };
    if (ws < 1 or ws > types.WS_COUNT) {
        addIssue(server, path, line, "workspace out of range for {s}: '{s}'", .{ key, ws_text });
        return;
    }

    var pin: ?*types.WorkspacePin = null;
    var i: usize = 0;
    while (i < server.config.workspace_pin_count) : (i += 1) {
        if (server.config.workspace_pins[i].ws == ws) {
            pin = &server.config.workspace_pins[i];
            break;
        }
    }
    if (pin == null) {
        if (server.config.workspace_pin_count >= server.config.workspace_pins.len) {
            addIssue(server, path, line, "too many workspace pins", .{});
            return;
        }
        pin = &server.config.workspace_pins[server.config.workspace_pin_count];
        server.config.workspace_pin_count += 1;
    }
    const p = pin.?;
    core.copyString(&p.output_name, &p.output_len, output_name);
    p.ws = ws;
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
    _ = addBinding(cfg, "super+shift+s", "screenshot", "");
    _ = addBinding(cfg, "super+m", "media", "");
    _ = addBinding(cfg, "super+shift+t", "tray", "");
    _ = addBinding(cfg, "super+shift+a", "audio", "");
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

const ParsedChord = struct {
    mods: u32,
    sym: u32,
};

fn parseChord(chord: []const u8) ?ParsedChord {
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
    if (key.len == 0) return null;

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
        var lower: [64:0]u8 = undefined;
        core.copyZ(&lower, key);
        for (lower[0..@min(key.len, 63)]) |*ch| ch.* = std.ascii.toLower(ch.*);
        sym = c.xkb_keysym_from_name(&lower, 0);
    }
    if (sym == c.XKB_KEY_NoSymbol) {
        core.logInfo("config: unknown keysym '{s}'", .{key});
        return null;
    }
    return .{ .mods = mods, .sym = @intCast(sym) };
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
    const parsed = parseChord(chord) orelse {
        core.logInfo("config: invalid chord '{s}'", .{chord});
        return false;
    };
    const mods = parsed.mods;
    const sym = parsed.sym;

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

fn validThemeRole(name: []const u8) bool {
    const roles = [_][]const u8{
        "accent",
        "window.border.active",
        "window.border.inactive",
        "window.background",
        "panel.background",
        "panel.foreground",
        "wallpaper.top",
        "wallpaper.bottom",
    };
    for (roles) |role| {
        if (std.mem.eql(u8, name, role)) return true;
    }
    return false;
}

pub fn addThemeRole(cfg: *Config, value: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, value, '=') orelse {
        core.logInfo("config: theme-role needs name=color", .{});
        return false;
    };
    const name = std.mem.trim(u8, value[0..eq], " \t");
    var color = std.mem.trim(u8, value[eq + 1 ..], " \t");
    if (color.len >= 2 and
        ((color[0] == '"' and color[color.len - 1] == '"') or
            (color[0] == '\'' and color[color.len - 1] == '\'')))
    {
        color = color[1 .. color.len - 1];
    }
    if (!validThemeRole(name)) {
        core.logInfo("config: unknown theme role '{s}'", .{name});
        return false;
    }
    if (!validHexColor(color) or color.len >= 16) {
        core.logInfo("config: invalid color for theme role '{s}'", .{name});
        return false;
    }

    var index: ?usize = null;
    var i: usize = 0;
    while (i < cfg.theme_role_count) : (i += 1) {
        const role = &cfg.theme_roles[i];
        if (std.mem.eql(u8, role.name[0..role.name_len], name)) {
            index = i;
            break;
        }
    }
    if (index == null) {
        if (cfg.theme_role_count >= cfg.theme_roles.len) {
            core.logInfo("config: too many theme roles (max {d})", .{cfg.theme_roles.len});
            return false;
        }
        index = cfg.theme_role_count;
        cfg.theme_role_count += 1;
        cfg.theme_roles[index.?] = std.mem.zeroes(types.ThemeRole);
    }

    const role = &cfg.theme_roles[index.?];
    core.copyString(&role.name, &role.name_len, name);
    core.copyString(&role.color, &role.color_len, color);
    core.parseHexColor(color, &role.rgb);
    return true;
}

fn applyThemeRoles(cfg: *Config) void {
    var i: usize = 0;
    while (i < cfg.theme_role_count) : (i += 1) {
        const role = &cfg.theme_roles[i];
        const name = role.name[0..role.name_len];
        const color = role.color[0..role.color_len];
        if (std.mem.eql(u8, name, "accent")) {
            core.copyString(&cfg.accent, &cfg.accent_len, color);
        } else if (std.mem.eql(u8, name, "window.border.active")) {
            core.copyString(&cfg.border_active, &cfg.border_active_len, color);
        } else if (std.mem.eql(u8, name, "window.border.inactive")) {
            core.copyString(&cfg.border_inactive, &cfg.border_inactive_len, color);
        } else if (std.mem.eql(u8, name, "window.background")) {
            core.copyString(&cfg.bg, &cfg.bg_len, color);
        }
    }
}

pub fn addEventRule(cfg: *Config, value: []const u8) bool {
    if (cfg.event_rule_count >= cfg.event_rules.len) {
        core.logInfo("config: too many event rules (max {d})", .{cfg.event_rules.len});
        return false;
    }

    var rule = types.EventRule{};
    var clauses = std.mem.splitScalar(u8, value, ';');
    while (clauses.next()) |raw| {
        const clause = std.mem.trim(u8, raw, " \t");
        if (clause.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, clause, '=') orelse {
            if (rule.event_len > 0 or !event_names.isKnown(clause)) {
                core.logInfo("config: invalid event-rule clause '{s}'", .{clause});
                return false;
            }
            core.copyString(&rule.event, &rule.event_len, clause);
            continue;
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
            core.logInfo("config: invalid event-rule clause '{s}'", .{clause});
            return false;
        }

        if (std.ascii.eqlIgnoreCase(key, "event")) {
            if (!event_names.isKnown(val)) {
                core.logInfo("config: unknown event-rule event '{s}'", .{val});
                return false;
            }
            core.copyString(&rule.event, &rule.event_len, val);
        } else if (std.ascii.eqlIgnoreCase(key, "match") or
            std.ascii.eqlIgnoreCase(key, "expr"))
        {
            if (val.len >= types.MAX_COMMAND or !rule_expr.validate(val)) {
                core.logInfo("config: invalid event-rule expression '{s}'", .{val});
                return false;
            }
            core.copyString(&rule.expr, &rule.expr_len, val);
        } else if (std.ascii.eqlIgnoreCase(key, "run") or
            std.ascii.eqlIgnoreCase(key, "command") or
            std.ascii.eqlIgnoreCase(key, "action"))
        {
            if (val.len >= types.MAX_COMMAND) {
                core.logInfo("config: event-rule command too long", .{});
                return false;
            }
            core.copyString(&rule.command, &rule.command_len, val);
        } else {
            core.logInfo("config: unknown event-rule key '{s}'", .{key});
            return false;
        }
    }

    if (rule.event_len == 0 or rule.command_len == 0) {
        core.logInfo("config: event-rule needs an event and a run command", .{});
        return false;
    }
    cfg.event_rules[cfg.event_rule_count] = rule;
    cfg.event_rule_count += 1;
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
        } else if (std.ascii.eqlIgnoreCase(key, "match") or
            std.ascii.eqlIgnoreCase(key, "expr"))
        {
            if (!rule_expr.validate(val)) {
                core.logInfo("config: invalid window-rule expression '{s}'", .{val});
                return false;
            }
            core.copyString(&rule.expr, &rule.expr_len, val);
        } else if (std.ascii.eqlIgnoreCase(key, "border-active") or
            std.ascii.eqlIgnoreCase(key, "border_active"))
        {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid rule border-active color '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.border_active_rgb);
            rule.has_border_active = true;
        } else if (std.ascii.eqlIgnoreCase(key, "border-inactive") or
            std.ascii.eqlIgnoreCase(key, "border_inactive"))
        {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid rule border-inactive color '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.border_inactive_rgb);
            rule.has_border_inactive = true;
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

fn clampTuning(tuning: *types.LayoutTuning) void {
    if (tuning.has_gaps and tuning.gaps < 0) tuning.gaps = 0;
    if (tuning.has_outer_gaps and tuning.outer_gaps < 0) tuning.outer_gaps = 0;
    if (tuning.has_master_ratio) tuning.master_ratio = std.math.clamp(tuning.master_ratio, 0.15, 0.9);
    if (tuning.has_master_count) tuning.master_count = std.math.clamp(tuning.master_count, 1, 8);
    if (tuning.has_mosaic_ratio) tuning.mosaic_ratio = std.math.clamp(tuning.mosaic_ratio, 0.25, 0.85);
    if (tuning.has_mosaic_min_size) tuning.mosaic_min_size = std.math.clamp(tuning.mosaic_min_size, 80, 600);
    if (tuning.has_grid_columns and tuning.grid_columns > 8) tuning.grid_columns = 8;
}

fn parseTuningClause(tuning: *types.LayoutTuning, key: []const u8, val: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(key, "layout")) {
        tuning.layout = types.layoutFromName(val) orelse {
            core.logInfo("config: unknown layout '{s}'", .{val});
            return false;
        };
        tuning.has_layout = true;
    } else if (std.ascii.eqlIgnoreCase(key, "gaps")) {
        tuning.gaps = std.fmt.parseInt(i32, val, 10) catch {
            core.logInfo("config: invalid gaps '{s}'", .{val});
            return false;
        };
        tuning.has_gaps = true;
    } else if (std.ascii.eqlIgnoreCase(key, "outer-gaps") or
        std.ascii.eqlIgnoreCase(key, "outer_gaps"))
    {
        tuning.outer_gaps = std.fmt.parseInt(i32, val, 10) catch {
            core.logInfo("config: invalid outer-gaps '{s}'", .{val});
            return false;
        };
        tuning.has_outer_gaps = true;
    } else if (std.ascii.eqlIgnoreCase(key, "master-ratio") or
        std.ascii.eqlIgnoreCase(key, "master_ratio"))
    {
        tuning.master_ratio = std.fmt.parseFloat(f32, val) catch {
            core.logInfo("config: invalid master-ratio '{s}'", .{val});
            return false;
        };
        tuning.has_master_ratio = true;
    } else if (std.ascii.eqlIgnoreCase(key, "master-count") or
        std.ascii.eqlIgnoreCase(key, "master_count"))
    {
        tuning.master_count = std.fmt.parseInt(usize, val, 10) catch {
            core.logInfo("config: invalid master-count '{s}'", .{val});
            return false;
        };
        tuning.has_master_count = true;
    } else if (std.ascii.eqlIgnoreCase(key, "mosaic-ratio") or
        std.ascii.eqlIgnoreCase(key, "mosaic_ratio"))
    {
        tuning.mosaic_ratio = std.fmt.parseFloat(f32, val) catch {
            core.logInfo("config: invalid mosaic-ratio '{s}'", .{val});
            return false;
        };
        tuning.has_mosaic_ratio = true;
    } else if (std.ascii.eqlIgnoreCase(key, "mosaic-min-size") or
        std.ascii.eqlIgnoreCase(key, "mosaic_min_size"))
    {
        tuning.mosaic_min_size = std.fmt.parseInt(i32, val, 10) catch {
            core.logInfo("config: invalid mosaic-min-size '{s}'", .{val});
            return false;
        };
        tuning.has_mosaic_min_size = true;
    } else if (std.ascii.eqlIgnoreCase(key, "grid-columns") or
        std.ascii.eqlIgnoreCase(key, "grid_columns"))
    {
        tuning.grid_columns = std.fmt.parseInt(usize, val, 10) catch {
            core.logInfo("config: invalid grid-columns '{s}'", .{val});
            return false;
        };
        tuning.has_grid_columns = true;
    } else {
        core.logInfo("config: unknown tuning key '{s}'", .{key});
        return false;
    }
    return true;
}

fn validProfileName(name: []const u8) bool {
    if (name.len == 0 or name.len >= 32) return false;
    for (name) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '-' and ch != '.') return false;
    }
    return true;
}

pub fn findProfile(cfg: *Config, name: []const u8) ?*types.Profile {
    var i: usize = 0;
    while (i < cfg.profile_count) : (i += 1) {
        const profile = &cfg.profiles[i];
        if (std.mem.eql(u8, profile.name[0..profile.name_len], name)) return profile;
    }
    return null;
}

pub fn addProfile(cfg: *Config, value: []const u8) bool {
    if (cfg.profile_count >= cfg.profiles.len) {
        core.logInfo("config: too many profiles (max {d})", .{cfg.profiles.len});
        return false;
    }

    var profile = types.Profile{};
    var clauses = std.mem.splitScalar(u8, value, ';');
    while (clauses.next()) |raw| {
        const clause = std.mem.trim(u8, raw, " \t");
        if (clause.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, clause, '=') orelse {
            if (profile.name_len == 0 and validProfileName(clause)) {
                core.copyString(&profile.name, &profile.name_len, clause);
                continue;
            }
            core.logInfo("config: profile clause needs '=': '{s}'", .{clause});
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
            core.logInfo("config: invalid profile clause '{s}'", .{clause});
            return false;
        }
        if (std.ascii.eqlIgnoreCase(key, "name") or
            std.ascii.eqlIgnoreCase(key, "profile"))
        {
            if (!validProfileName(val) or findProfile(cfg, val) != null) {
                core.logInfo("config: invalid or duplicate profile name '{s}'", .{val});
                return false;
            }
            core.copyString(&profile.name, &profile.name_len, val);
        } else if (!parseTuningClause(&profile.tuning, key, val)) {
            return false;
        }
    }

    if (profile.name_len == 0) {
        core.logInfo("config: profile needs name=<name>", .{});
        return false;
    }
    clampTuning(&profile.tuning);
    cfg.profiles[cfg.profile_count] = profile;
    cfg.profile_count += 1;
    return true;
}

pub fn addWorkspaceRule(cfg: *Config, value: []const u8) bool {
    if (cfg.workspace_rule_count >= cfg.workspace_rules.len) {
        core.logInfo("config: too many workspace rules (max {d})", .{cfg.workspace_rules.len});
        return false;
    }

    var rule = types.WorkspaceRule{};
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
            rule.ws = @intCast(n);
        } else if (std.ascii.eqlIgnoreCase(key, "profile")) {
            if (!validProfileName(val)) {
                core.logInfo("config: invalid workspace-rule profile '{s}'", .{val});
                return false;
            }
            core.copyString(&rule.profile, &rule.profile_len, val);
        } else if (!parseTuningClause(&rule.tuning, key, val)) {
            return false;
        }
    }

    if (rule.ws == 0) {
        core.logInfo("config: workspace-rule needs ws=<1..9>", .{});
        return false;
    }
    clampTuning(&rule.tuning);
    cfg.workspace_rules[cfg.workspace_rule_count] = rule;
    cfg.workspace_rule_count += 1;
    return true;
}

fn applyTuningToWorkspace(cfg: *Config, tuning: *const types.LayoutTuning, idx: usize) void {
    if (tuning.has_layout) {
        cfg.layout_by_ws[idx] = tuning.layout;
        cfg.layout_overrides[idx] = true;
    }
    if (tuning.has_gaps) {
        cfg.ws_gaps[idx] = tuning.gaps;
        cfg.ws_gaps_set[idx] = true;
    }
    if (tuning.has_outer_gaps) {
        cfg.ws_outer_gaps[idx] = tuning.outer_gaps;
        cfg.ws_outer_set[idx] = true;
    }
    if (tuning.has_master_ratio) {
        cfg.ws_master_ratio[idx] = tuning.master_ratio;
        cfg.ws_ratio_set[idx] = true;
    }
    if (tuning.has_master_count) {
        cfg.ws_master_count[idx] = tuning.master_count;
        cfg.ws_master_count_set[idx] = true;
    }
    if (tuning.has_mosaic_ratio) {
        cfg.ws_mosaic_ratio[idx] = tuning.mosaic_ratio;
        cfg.ws_mosaic_ratio_set[idx] = true;
    }
    if (tuning.has_mosaic_min_size) {
        cfg.ws_mosaic_min_size[idx] = tuning.mosaic_min_size;
        cfg.ws_mosaic_min_size_set[idx] = true;
    }
    if (tuning.has_grid_columns) {
        cfg.ws_grid_columns[idx] = tuning.grid_columns;
        cfg.ws_grid_columns_set[idx] = true;
    }
}

fn resolveProfileReferences(server: *Server) void {
    const cfg = &server.config;
    var i: usize = 0;
    while (i < cfg.workspace_rule_count) : (i += 1) {
        const rule = &cfg.workspace_rules[i];
        if (rule.profile_len > 0) {
            if (findProfile(&server.config, rule.profile[0..rule.profile_len])) |profile| {
                applyTuningToWorkspace(&server.config, &profile.tuning, rule.ws - 1);
            } else {
                addIssue(server, "<config>", 0, "workspace-rule references unknown profile '{s}'", .{
                    rule.profile[0..rule.profile_len],
                });
            }
        }
        applyTuningToWorkspace(&server.config, &rule.tuning, rule.ws - 1);
    }

    i = 0;
    while (i < cfg.output_rule_count) : (i += 1) {
        const rule = &cfg.output_rules[i];
        if (rule.profile_len > 0 and
            findProfile(&server.config, rule.profile[0..rule.profile_len]) == null)
        {
            addIssue(server, "<config>", 0, "output-rule references unknown profile '{s}'", .{
                rule.profile[0..rule.profile_len],
            });
        }
    }
}

pub fn addOutputRule(cfg: *Config, value: []const u8) bool {
    if (cfg.output_rule_count >= cfg.output_rules.len) {
        core.logInfo("config: too many output rules (max {d})", .{cfg.output_rules.len});
        return false;
    }

    var rule = types.OutputRule{};
    var clauses_seen: usize = 0;
    var clauses = std.mem.splitScalar(u8, value, ';');
    while (clauses.next()) |raw| {
        const clause = std.mem.trim(u8, raw, " \t");
        if (clause.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, clause, '=') orelse {
            core.logInfo("config: output-rule clause needs '=': '{s}'", .{clause});
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
            core.logInfo("config: invalid output-rule clause '{s}'", .{clause});
            return false;
        }
        clauses_seen += 1;

        if (std.ascii.eqlIgnoreCase(key, "output") or
            std.ascii.eqlIgnoreCase(key, "monitor"))
        {
            if (val.len >= rule.output.len) {
                core.logInfo("config: output-rule output name too long", .{});
                return false;
            }
            core.copyString(&rule.output, &rule.output_len, val);
        } else if (std.ascii.eqlIgnoreCase(key, "profile")) {
            if (!validProfileName(val)) {
                core.logInfo("config: invalid output-rule profile '{s}'", .{val});
                return false;
            }
            core.copyString(&rule.profile, &rule.profile_len, val);
        } else if (std.ascii.eqlIgnoreCase(key, "ws") or
            std.ascii.eqlIgnoreCase(key, "workspace"))
        {
            const n = std.fmt.parseInt(usize, val, 10) catch {
                core.logInfo("config: invalid output-rule workspace '{s}'", .{val});
                return false;
            };
            if (n < 1 or n > types.WS_COUNT) {
                core.logInfo("config: output-rule workspace out of range: {d}", .{n});
                return false;
            }
            rule.ws = @intCast(n);
        } else if (std.ascii.eqlIgnoreCase(key, "gaps")) {
            rule.gaps = std.fmt.parseInt(i32, val, 10) catch {
                core.logInfo("config: invalid output-rule gaps '{s}'", .{val});
                return false;
            };
            if (rule.gaps < 0) {
                core.logInfo("config: output-rule gaps must be >= 0", .{});
                return false;
            }
            rule.has_gaps = true;
        } else if (std.ascii.eqlIgnoreCase(key, "outer-gaps") or
            std.ascii.eqlIgnoreCase(key, "outer_gaps"))
        {
            rule.outer_gaps = std.fmt.parseInt(i32, val, 10) catch {
                core.logInfo("config: invalid output-rule outer-gaps '{s}'", .{val});
                return false;
            };
            if (rule.outer_gaps < 0) {
                core.logInfo("config: output-rule outer-gaps must be >= 0", .{});
                return false;
            }
            rule.has_outer_gaps = true;
        } else if (std.ascii.eqlIgnoreCase(key, "master-ratio") or
            std.ascii.eqlIgnoreCase(key, "master_ratio"))
        {
            rule.master_ratio = std.fmt.parseFloat(f32, val) catch {
                core.logInfo("config: invalid output-rule master-ratio '{s}'", .{val});
                return false;
            };
            rule.has_master_ratio = true;
        } else if (std.ascii.eqlIgnoreCase(key, "master-count") or
            std.ascii.eqlIgnoreCase(key, "master_count"))
        {
            const n = std.fmt.parseInt(usize, val, 10) catch {
                core.logInfo("config: invalid output-rule master-count '{s}'", .{val});
                return false;
            };
            if (n < 1 or n > 8) {
                core.logInfo("config: output-rule master-count out of range: {d}", .{n});
                return false;
            }
            rule.master_count = n;
            rule.has_master_count = true;
        } else if (std.ascii.eqlIgnoreCase(key, "mosaic-ratio") or
            std.ascii.eqlIgnoreCase(key, "mosaic_ratio"))
        {
            rule.mosaic_ratio = std.fmt.parseFloat(f32, val) catch {
                core.logInfo("config: invalid output-rule mosaic-ratio '{s}'", .{val});
                return false;
            };
            rule.has_mosaic_ratio = true;
        } else if (std.ascii.eqlIgnoreCase(key, "mosaic-min-size") or
            std.ascii.eqlIgnoreCase(key, "mosaic_min_size"))
        {
            rule.mosaic_min_size = std.fmt.parseInt(i32, val, 10) catch {
                core.logInfo("config: invalid output-rule mosaic-min-size '{s}'", .{val});
                return false;
            };
            rule.has_mosaic_min_size = true;
        } else if (std.ascii.eqlIgnoreCase(key, "grid-columns") or
            std.ascii.eqlIgnoreCase(key, "grid_columns"))
        {
            const n = std.fmt.parseInt(usize, val, 10) catch {
                core.logInfo("config: invalid output-rule grid-columns '{s}'", .{val});
                return false;
            };
            if (n > 8) {
                core.logInfo("config: output-rule grid-columns out of range: {d}", .{n});
                return false;
            }
            rule.grid_columns = n;
            rule.has_grid_columns = true;
        } else if (std.ascii.eqlIgnoreCase(key, "accent")) {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid output-rule accent '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.accent_rgb);
            rule.has_accent = true;
        } else if (std.ascii.eqlIgnoreCase(key, "bg")) {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid output-rule bg '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.bg_rgb);
            rule.has_bg = true;
        } else if (std.ascii.eqlIgnoreCase(key, "border-active") or
            std.ascii.eqlIgnoreCase(key, "border_active"))
        {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid output-rule border-active '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.border_active_rgb);
            rule.has_border_active = true;
        } else if (std.ascii.eqlIgnoreCase(key, "border-inactive") or
            std.ascii.eqlIgnoreCase(key, "border_inactive"))
        {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid output-rule border-inactive '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.border_inactive_rgb);
            rule.has_border_inactive = true;
        } else if (std.ascii.eqlIgnoreCase(key, "panel-bg") or
            std.ascii.eqlIgnoreCase(key, "panel_bg"))
        {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid output-rule panel-bg '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.panel_bg_rgb);
            rule.has_panel_bg = true;
        } else if (std.ascii.eqlIgnoreCase(key, "panel-fg") or
            std.ascii.eqlIgnoreCase(key, "panel_fg"))
        {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid output-rule panel-fg '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.panel_fg_rgb);
            rule.has_panel_fg = true;
        } else if (std.ascii.eqlIgnoreCase(key, "bg-top") or
            std.ascii.eqlIgnoreCase(key, "bg_top"))
        {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid output-rule bg-top '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.bg_top_rgb);
            rule.has_bg_top = true;
        } else if (std.ascii.eqlIgnoreCase(key, "bg-bottom") or
            std.ascii.eqlIgnoreCase(key, "bg_bottom"))
        {
            if (!validHexColor(val)) {
                core.logInfo("config: invalid output-rule bg-bottom '{s}'", .{val});
                return false;
            }
            core.parseHexColor(val, &rule.bg_bottom_rgb);
            rule.has_bg_bottom = true;
        } else if (std.ascii.eqlIgnoreCase(key, "bar-height") or
            std.ascii.eqlIgnoreCase(key, "bar_height"))
        {
            const n = std.fmt.parseInt(i32, val, 10) catch {
                core.logInfo("config: invalid output-rule bar-height '{s}'", .{val});
                return false;
            };
            if (n < 0 or n > 200) {
                core.logInfo("config: output-rule bar-height out of range: {d}", .{n});
                return false;
            }
            rule.bar_height = n;
            rule.has_bar_height = true;
        } else if (std.ascii.eqlIgnoreCase(key, "bar-top-margin") or
            std.ascii.eqlIgnoreCase(key, "bar_top_margin"))
        {
            const n = std.fmt.parseInt(i32, val, 10) catch {
                core.logInfo("config: invalid output-rule bar-top-margin '{s}'", .{val});
                return false;
            };
            if (n < 0 or n > 128) {
                core.logInfo("config: output-rule bar-top-margin out of range: {d}", .{n});
                return false;
            }
            rule.bar_top_margin = n;
            rule.has_bar_top_margin = true;
        } else if (std.ascii.eqlIgnoreCase(key, "bar-side-margin") or
            std.ascii.eqlIgnoreCase(key, "bar_side_margin"))
        {
            const n = std.fmt.parseInt(i32, val, 10) catch {
                core.logInfo("config: invalid output-rule bar-side-margin '{s}'", .{val});
                return false;
            };
            if (n < 0 or n > 256) {
                core.logInfo("config: output-rule bar-side-margin out of range: {d}", .{n});
                return false;
            }
            rule.bar_side_margin = n;
            rule.has_bar_side_margin = true;
        } else if (std.ascii.eqlIgnoreCase(key, "layout")) {
            rule.layout = types.layoutFromName(val) orelse {
                core.logInfo("config: unknown output-rule layout '{s}'", .{val});
                return false;
            };
            rule.has_layout = true;
        } else {
            core.logInfo("config: unknown output-rule key '{s}'", .{key});
            return false;
        }
    }

    if (clauses_seen == 0 or rule.output_len == 0) {
        core.logInfo("config: output-rule needs output=<name>", .{});
        return false;
    }
    core.copyString(&rule.raw, &rule.raw_len, value);
    cfg.output_rules[cfg.output_rule_count] = rule;
    cfg.output_rule_count += 1;
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
    if (std.ascii.eqlIgnoreCase(name, "screenshot")) return .screenshot;
    if (std.ascii.eqlIgnoreCase(name, "media")) return .media;
    if (std.ascii.eqlIgnoreCase(name, "tray")) return .tray;
    if (std.ascii.eqlIgnoreCase(name, "audio") or std.ascii.eqlIgnoreCase(name, "volume")) return .audio;
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
        } else if (std.mem.eql(u8, key, "workspace_pin") or std.mem.eql(u8, key, "workspace-pin")) {
            addWorkspacePin(server, path, line_no, key, value);
        } else if (std.mem.eql(u8, key, "panel") or std.mem.eql(u8, key, "autostart_panel")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.autostart_panel = v;
        } else if (std.mem.eql(u8, key, "animations")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.animations = v;
        } else if (std.mem.eql(u8, key, "reduce_motion")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.reduce_motion = v;
        } else if (std.mem.eql(u8, key, "animation_ms")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.animation_ms = v;
        } else if (std.mem.eql(u8, key, "animation_open_ms") or
            std.mem.eql(u8, key, "animation-open-ms"))
        {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.animation_open_ms = v;
        } else if (std.mem.eql(u8, key, "animation_workspace_ms") or
            std.mem.eql(u8, key, "animation-workspace-ms"))
        {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.animation_workspace_ms = v;
        } else if (std.mem.eql(u8, key, "animation_close_ms") or
            std.mem.eql(u8, key, "animation-close-ms"))
        {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.animation_close_ms = v;
        } else if (std.mem.eql(u8, key, "reduce_motion_animations") or
            std.mem.eql(u8, key, "reduce-motion-animations"))
        {
            if (std.ascii.eqlIgnoreCase(value, "none") or
                std.ascii.eqlIgnoreCase(value, "off") or
                std.ascii.eqlIgnoreCase(value, "disabled"))
            {
                server.config.reduce_motion_animations = .none;
            } else if (std.ascii.eqlIgnoreCase(value, "fade")) {
                server.config.reduce_motion_animations = .fade;
            } else {
                addIssue(server, path, line_no, "invalid {s}: '{s}' (expected none or fade)", .{ key, value });
            }
        } else if (std.mem.eql(u8, key, "reduce_motion_fade_ms") or
            std.mem.eql(u8, key, "reduce-motion-fade-ms"))
        {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.reduce_motion_fade_ms = v;
        } else if (std.mem.eql(u8, key, "shadows")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.shadows = v;
        } else if (std.mem.eql(u8, key, "corner_radius")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.corner_radius = v;
        } else if (std.mem.eql(u8, key, "blur")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.blur = v;
        } else if (std.mem.eql(u8, key, "blur_radius")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.blur_radius = v;
        } else if (std.mem.eql(u8, key, "blur_passes")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.blur_passes = v;
        } else if (std.mem.eql(u8, key, "gestures")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.gestures = v;
        } else if (std.mem.eql(u8, key, "gesture_fingers")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.gesture_fingers = v;
        } else if (std.mem.eql(u8, key, "gesture_workspace_threshold")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.gesture_workspace_threshold = v;
        } else if (std.mem.eql(u8, key, "gesture_launcher_threshold")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| server.config.gesture_launcher_threshold = v;
        } else if (std.mem.eql(u8, key, "touch")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.touch = v;
        } else if (std.mem.eql(u8, key, "tablet")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.tablet = v;
        } else if (std.mem.eql(u8, key, "pointer_constraints")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.pointer_constraints = v;
        } else if (std.mem.eql(u8, key, "xim")) {
            if (parseBoolValue(server, path, line_no, key, value)) |v| server.config.xim = v;
        } else if (std.mem.eql(u8, key, "xim_server")) {
            core.copyString(&server.config.xim_server, &server.config.xim_server_len, value);
        } else if (std.mem.eql(u8, key, "xim_start")) {
            core.copyString(&server.config.xim_start, &server.config.xim_start_len, value);
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
        } else if (std.mem.eql(u8, key, "leader")) {
            if (parseChord(value)) |parsed| {
                server.config.leader_mods = parsed.mods;
                server.config.leader_sym = parsed.sym;
                server.config.leader_set = true;
                if (ensureMode(&server.config, "leader") == null) {
                    addIssue(server, path, line_no, "cannot create leader mode (too many modes)", .{});
                }
            } else {
                addIssue(server, path, line_no, "invalid leader chord: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "leader_timeout") or std.mem.eql(u8, key, "leader-timeout")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| {
                if (v < 0 or v > 60000) {
                    addIssue(server, path, line_no, "{s} out of range (0-60000): {d}", .{ key, v });
                } else {
                    server.config.leader_timeout = v;
                }
            }
        } else if (std.mem.eql(u8, key, "mode_timeout") or std.mem.eql(u8, key, "mode-timeout")) {
            if (parseIntValue(i32, server, path, line_no, key, value)) |v| {
                if (v < 0 or v > 60000) {
                    addIssue(server, path, line_no, "{s} out of range (0-60000): {d}", .{ key, v });
                } else {
                    server.config.mode_timeouts[current_mode.*] = v;
                }
            }
        } else if (std.mem.eql(u8, key, "profile")) {
            if (!addProfile(&server.config, value)) {
                addIssue(server, path, line_no, "invalid profile: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "theme-role") or std.mem.eql(u8, key, "theme_role")) {
            if (!addThemeRole(&server.config, value)) {
                addIssue(server, path, line_no, "invalid theme-role: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "window-rule") or std.mem.eql(u8, key, "window_rule")) {
            if (!addRule(&server.config, value)) {
                addIssue(server, path, line_no, "invalid window-rule: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "workspace-rule") or std.mem.eql(u8, key, "workspace_rule")) {
            if (!addWorkspaceRule(&server.config, value)) {
                addIssue(server, path, line_no, "invalid workspace-rule: '{s}'", .{value});
            }
        } else if (std.mem.eql(u8, key, "output-rule") or std.mem.eql(u8, key, "output_rule")) {
            if (!addOutputRule(&server.config, value)) {
                addIssue(server, path, line_no, "invalid output-rule: '{s}'", .{value});
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
        } else if (std.mem.eql(u8, key, "event-rule") or std.mem.eql(u8, key, "event_rule")) {
            if (!addEventRule(&server.config, value)) {
                addIssue(server, path, line_no, "invalid event-rule: '{s}'", .{value});
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
            std.mem.eql(u8, key, "bg_top") or
            std.mem.eql(u8, key, "bg_bottom") or
            std.mem.eql(u8, key, "wallpaper_art") or
            std.mem.eql(u8, key, "bar_height") or
            std.mem.eql(u8, key, "bar_top_margin") or
            std.mem.eql(u8, key, "bar_side_margin") or
            std.mem.eql(u8, key, "power_lock") or
            std.mem.eql(u8, key, "power_suspend") or
            std.mem.eql(u8, key, "power_reboot") or
            std.mem.eql(u8, key, "power_off") or
            std.mem.eql(u8, key, "screenshot_dir") or
            std.mem.eql(u8, key, "volume_status") or
            std.mem.eql(u8, key, "volume_up") or
            std.mem.eql(u8, key, "volume_down") or
            std.mem.eql(u8, key, "volume_mute"))
        {
            // The panel parses these keys; the compositor only validates the file.
        } else {
            addIssue(server, path, line_no, "unknown key '{s}'", .{key});
        }
    }
}

pub fn resolvePath(path_buf: *[512]u8) []const u8 {
    if (c.getenv("TESSA_CONFIG")) |p| return core.cstr(p);
    if (c.getenv("XDG_CONFIG_HOME")) |p| {
        return std.fmt.bufPrint(path_buf, "{s}/tessa/config", .{core.cstr(p)}) catch "";
    }
    if (c.getenv("HOME")) |p| {
        return std.fmt.bufPrint(path_buf, "{s}/.config/tessa/config", .{core.cstr(p)}) catch "";
    }
    return "";
}

pub fn load(server: *Server) void {
    server.config_issue_count = 0;
    server.config_error_count = 0;
    initDefaults(&server.config);

    var path_buf: [512]u8 = undefined;
    const path = resolvePath(&path_buf);

    var parse_mode: usize = 0;
    if (path.len > 0) loadPath(server, path, 0, &parse_mode, "", 0);
    resolveProfileReferences(server);

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
    if (server.config.animation_ms < 0) server.config.animation_ms = 0;
    if (server.config.animation_ms > 1000) server.config.animation_ms = 1000;
    if (server.config.animation_open_ms < -1) server.config.animation_open_ms = -1;
    if (server.config.animation_open_ms > 1000) server.config.animation_open_ms = 1000;
    if (server.config.animation_workspace_ms < -1) server.config.animation_workspace_ms = -1;
    if (server.config.animation_workspace_ms > 1000) server.config.animation_workspace_ms = 1000;
    if (server.config.animation_close_ms < -1) server.config.animation_close_ms = -1;
    if (server.config.animation_close_ms > 1000) server.config.animation_close_ms = 1000;
    if (server.config.reduce_motion_fade_ms < 0) server.config.reduce_motion_fade_ms = 0;
    if (server.config.reduce_motion_fade_ms > 1000) server.config.reduce_motion_fade_ms = 1000;
    if (server.config.corner_radius < 0) server.config.corner_radius = 0;
    if (server.config.corner_radius > 64) server.config.corner_radius = 64;
    if (server.config.blur_radius < 1) server.config.blur_radius = 1;
    if (server.config.blur_radius > 32) server.config.blur_radius = 32;
    if (server.config.blur_passes < 1) server.config.blur_passes = 1;
    if (server.config.blur_passes > 5) server.config.blur_passes = 5;
    if (server.config.gesture_fingers < 2) server.config.gesture_fingers = 2;
    if (server.config.gesture_fingers > 5) server.config.gesture_fingers = 5;
    if (server.config.gesture_workspace_threshold < 20) server.config.gesture_workspace_threshold = 20;
    if (server.config.gesture_workspace_threshold > 1000) server.config.gesture_workspace_threshold = 1000;
    if (server.config.gesture_launcher_threshold < 20) server.config.gesture_launcher_threshold = 20;
    if (server.config.gesture_launcher_threshold > 1000) server.config.gesture_launcher_threshold = 1000;
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
        if (server.config.ws_master_count[wi] < 1) server.config.ws_master_count[wi] = 1;
        if (server.config.ws_master_count[wi] > 8) server.config.ws_master_count[wi] = 8;
        if (server.config.ws_mosaic_ratio[wi] < 0.25) server.config.ws_mosaic_ratio[wi] = 0.25;
        if (server.config.ws_mosaic_ratio[wi] > 0.85) server.config.ws_mosaic_ratio[wi] = 0.85;
        if (server.config.ws_mosaic_min_size[wi] < 80) server.config.ws_mosaic_min_size[wi] = 80;
        if (server.config.ws_mosaic_min_size[wi] > 600) server.config.ws_mosaic_min_size[wi] = 600;
        if (server.config.ws_grid_columns[wi] > 8) server.config.ws_grid_columns[wi] = 8;
        if (!server.config.layout_overrides[wi]) {
            server.config.layout_by_ws[wi] = server.config.layout_mode;
        }
    }
    var ri: usize = 0;
    while (ri < server.config.output_rule_count) : (ri += 1) {
        const rule = &server.config.output_rules[ri];
        if (rule.has_master_ratio) {
            rule.master_ratio = std.math.clamp(rule.master_ratio, 0.15, 0.9);
        }
        if (rule.has_mosaic_ratio) {
            rule.mosaic_ratio = std.math.clamp(rule.mosaic_ratio, 0.25, 0.85);
        }
        if (rule.has_mosaic_min_size) {
            rule.mosaic_min_size = std.math.clamp(rule.mosaic_min_size, 80, 600);
        }
    }
    applyThemeRoles(&server.config);
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
    ri = 0;
    while (ri < server.config.output_rule_count) : (ri += 1) {
        if (server.config.output_rules[ri].has_layout and
            server.config.output_rules[ri].layout == .custom) wants_custom = true;
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

    core.logInfo("config: {s} (terminal={s}, bindings={d}, hooks={d}, rules={d}, output_rules={d})", .{
        if (path.len > 0) path else "defaults",
        server.config.terminal[0..server.config.terminal_len],
        server.config.binding_count,
        server.config.hook_count,
        server.config.rule_count,
        server.config.output_rule_count,
    });
}
