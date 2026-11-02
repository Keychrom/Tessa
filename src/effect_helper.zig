const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const window_effects = @import("window_effects.zig");
const motion = @import("motion.zig");

const Server = types.Server;
const Client = types.Client;
const MAX_REQUEST = types.LAYOUT_HELPER_BUFFER;
const FAIL_BACKOFF_MS = 1000;
const PROTOCOL_VERSION: u8 = 2;

fn hashBytes(data: []const u8) u64 {
    var h: u64 = 1469598103934665603;
    for (data) |ch| {
        h ^= ch;
        h *%= 1099511628211;
    }
    return h;
}

fn append(buf: []u8, off: *usize, comptime fmt: []const u8, args: anytype) bool {
    if (off.* >= buf.len) return false;
    const text = std.fmt.bufPrint(buf[off.*..], fmt, args) catch return false;
    off.* += text.len;
    return true;
}

fn appendEscaped(buf: []u8, off: *usize, text: []const u8) bool {
    for (text) |ch| {
        if (ch == '\\' or ch == '\t' or ch == '\n' or ch == '\r') {
            if (off.* + 2 > buf.len) return false;
            buf[off.*] = '\\';
            off.* += 1;
            buf[off.*] = switch (ch) {
                '\\' => '\\',
                '\t' => 't',
                '\n' => 'n',
                '\r' => 'r',
                else => unreachable,
            };
            off.* += 1;
        } else {
            if (off.* + 1 > buf.len) return false;
            buf[off.*] = ch;
            off.* += 1;
        }
    }
    return true;
}

fn hasEndLine(data: []const u8) bool {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (std.mem.eql(u8, line, "END")) return true;
    }
    return false;
}

fn disarmTimer(h: *types.EffectHookState) void {
    if (h.timer) |timer| _ = c.wl_event_source_timer_update(timer, 0);
}

fn clearHooks(server: *Server) bool {
    var changed = false;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (client.hook_active) {
            client.hook_active = false;
            changed = true;
        }
        if (client.hook_anim_active) {
            client.hook_anim_active = false;
            changed = true;
        }
    }
    return changed;
}

fn stop(server: *Server, clear: bool) void {
    const h = &server.effect_helper;
    if (h.source) |source| {
        _ = c.wl_event_source_remove(source);
        h.source = null;
    }
    if (h.timer) |timer| {
        _ = c.wl_event_source_timer_update(timer, 0);
        _ = c.wl_event_source_remove(timer);
        h.timer = null;
    }
    if (h.fd >= 0) {
        _ = c.close(h.fd);
        h.fd = -1;
    }
    if (h.pid > 0) {
        _ = c.kill(-h.pid, c.SIGTERM);
        _ = c.kill(h.pid, c.SIGTERM);
        h.pid = 0;
    }
    h.waiting = false;
    h.pending = false;
    h.hello_sent = false;
    h.version = 0;
    h.version_logged = false;
    h.request_sig = 0;
    h.request_count = 0;
    h.read_len = 0;
    if (clear) h.cache_sig = 0;
}

fn fail(server: *Server, reason: []const u8) void {
    const h = &server.effect_helper;
    const hash = h.hash;
    stop(server, true);
    h.hash = hash;
    h.fail_until = core.timeNowMs() + FAIL_BACKOFF_MS;
    const changed = clearHooks(server);
    if (changed) {
        window_effects.applyAll(server);
        layout.arrangeAll(server);
        layout.updateBorders(server);
        core.markDirty(server);
    }
    core.logInfo("effect helper failed: {s}; using rule visuals", .{reason});
}

fn start(server: *Server, command: []const u8, hash: u64) bool {
    stop(server, true);

    var fds: [2]c_int = undefined;
    if (c.socketpair(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0, &fds[0]) != 0) {
        core.logInfo("effect helper: socketpair failed", .{});
        return false;
    }

    const timeout_us: i64 = @as(i64, server.config.effect_helper_timeout) * 1000;
    var send_timeout = c.timeval{
        .tv_sec = @intCast(@divTrunc(timeout_us, 1_000_000)),
        .tv_usec = @intCast(@mod(timeout_us, 1_000_000)),
    };
    _ = c.setsockopt(
        fds[0],
        c.SOL_SOCKET,
        c.SO_SNDTIMEO,
        &send_timeout,
        @sizeOf(c.timeval),
    );

    var cmd_buf: [2048:0]u8 = undefined;
    const command_z = std.mem.printSentinel(&cmd_buf, "{s}", .{command}, 0) catch {
        _ = c.close(fds[0]);
        _ = c.close(fds[1]);
        core.logInfo("effect helper: command too long", .{});
        return false;
    };

    const pid = c.fork();
    if (pid < 0) {
        _ = c.close(fds[0]);
        _ = c.close(fds[1]);
        core.logInfo("effect helper: fork failed", .{});
        return false;
    }
    if (pid == 0) {
        _ = c.close(fds[0]);
        _ = c.dup2(fds[1], 0);
        _ = c.dup2(fds[1], 1);
        if (fds[1] > 2) _ = c.close(fds[1]);
        core.resetChildSignals();
        _ = c.setsid();
        _ = c.execl("/bin/sh", "/bin/sh", "-c", command_z.ptr, @as(?[*:0]const u8, null));
        c._exit(127);
    }

    _ = c.close(fds[1]);
    const h = &server.effect_helper;
    h.fd = fds[0];
    h.pid = pid;
    h.hash = hash;
    h.fail_until = 0;
    h.waiting = false;
    h.pending = false;
    h.hello_sent = false;
    h.version = 0;
    h.version_logged = false;
    h.request_sig = 0;
    h.request_count = 0;
    h.cache_sig = 0;
    h.read_len = 0;

    const loop = c.wl_display_get_event_loop(server.display);
    const source = c.wl_event_loop_add_fd(loop, h.fd, @intCast(c.WL_EVENT_READABLE), onRead, server);
    if (source == null) {
        core.logInfo("effect helper: event source failed", .{});
        _ = c.close(h.fd);
        h.fd = -1;
        _ = c.kill(-pid, c.SIGTERM);
        _ = c.kill(pid, c.SIGTERM);
        h.pid = 0;
        return false;
    }
    h.source = source;

    const timer = c.wl_event_loop_add_timer(loop, onTimeout, server);
    if (timer == null) {
        _ = c.wl_event_source_remove(source);
        h.source = null;
        _ = c.close(h.fd);
        h.fd = -1;
        _ = c.kill(-pid, c.SIGTERM);
        _ = c.kill(pid, c.SIGTERM);
        h.pid = 0;
        core.logInfo("effect helper: timer failed", .{});
        return false;
    }
    h.timer = timer;
    core.logInfo("effect helper started (pid {d})", .{pid});
    return true;
}

fn ensureStarted(server: *Server, command: []const u8, hash: u64) bool {
    const h = &server.effect_helper;
    if (h.fd >= 0) {
        if (h.hash == hash) return true;
        stop(server, true);
    }
    const now = core.timeNowMs();
    if (h.hash == hash and now < h.fail_until) return false;
    if (!start(server, command, hash)) {
        h.hash = hash;
        h.fail_until = now + FAIL_BACKOFF_MS;
        return false;
    }
    return true;
}

pub fn deinit(server: *Server) void {
    stop(server, true);
}

pub fn reload(server: *Server) void {
    const command = server.config.effect_helper[0..server.config.effect_helper_len];
    const hash = if (command.len > 0) hashBytes(command) else 0;
    const h = &server.effect_helper;
    if (command.len == 0) {
        if (h.fd >= 0) core.logInfo("effect helper stopped", .{});
        stop(server, true);
        if (clearHooks(server)) {
            window_effects.applyAll(server);
            layout.arrangeAll(server);
            layout.updateBorders(server);
            core.markDirty(server);
        }
        return;
    }
    if (h.fd >= 0 and h.hash != hash) {
        core.logInfo("effect helper command changed; restarting", .{});
        stop(server, true);
        if (clearHooks(server)) {
            window_effects.applyAll(server);
            layout.arrangeAll(server);
            layout.updateBorders(server);
            core.markDirty(server);
        }
    }
    refresh(server);
}

fn modeToken(mode: types.RuleBool) []const u8 {
    return switch (mode) {
        .on => "on",
        .off => "off",
        .unset => "unset",
    };
}

fn tintHex(buf: *[9]u8, tint: [4]f32) []const u8 {
    const hex = "0123456789abcdef";
    buf[0] = '#';
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const value: u8 = @intFromFloat(@round(std.math.clamp(tint[i], 0.0, 1.0) * 255.0));
        buf[1 + i * 2] = hex[value >> 4];
        buf[2 + i * 2] = hex[value & 0x0f];
    }
    return buf[0..9];
}

fn buildRequest(server: *Server, buf: []u8, ids: []u64) ?usize {
    var off: usize = 0;
    if (!append(buf, &off, "HELLO\t{d}\n", .{PROTOCOL_VERSION})) return null;
    if (!append(buf, &off, "EFFECT\t{d}\n", .{PROTOCOL_VERSION})) return null;
    var count: usize = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (!client.mapped) continue;
        if (count >= ids.len) return null;
        ids[count] = client.id;
        count += 1;

        const focused: u8 = if (server.focused == client and server.focused_layer == null) 1 else 0;
        const visible: u8 = if (types.clientVisible(client, client.output)) 1 else 0;
        if (!append(buf, &off, "WINDOW\t{d}\t", .{client.id})) return null;
        if (!appendEscaped(buf, &off, client.app_id[0..client.app_id_len])) return null;
        if (!append(buf, &off, "\t", .{})) return null;
        if (!appendEscaped(buf, &off, client.title[0..client.title_len])) return null;
        if (!append(buf, &off, "\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}\t", .{
            core.outputName(client.output),
            client.ws,
            focused,
            @as(u8, if (client.urgent) 1 else 0),
            @as(u8, if (client.fullscreen) 1 else 0),
            @as(u8, if (client.floating) 1 else 0),
        })) return null;
        if (!append(buf, &off, "{d}\t{d:.3}\t{d}\t{s}\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}", .{
            visible,
            client.opacity,
            client.corner_radius,
            modeToken(client.blur),
            modeToken(client.shadow),
            client.border_width,
            client.x,
            client.y,
            client.w,
            client.h,
        })) return null;
        if (server.effect_helper.version >= 2) {
            const tint = types.effectiveClientTint(client);
            var tint_buf: [9]u8 = undefined;
            if (!append(buf, &off, "\t{s}", .{tintHex(&tint_buf, tint)})) return null;
        }
        if (!append(buf, &off, "\n", .{})) return null;
    }
    if (!append(buf, &off, "END\n", .{})) return null;
    return off;
}

fn sendAll(server: *Server, data: []const u8) bool {
    var sent: usize = 0;
    while (sent < data.len) {
        const n = c.send(server.effect_helper.fd, data[sent..].ptr, data.len - sent, c.MSG_NOSIGNAL);
        if (n <= 0) return false;
        sent += @intCast(n);
    }
    return true;
}

const Override = struct {
    id: u64,
    has_opacity: bool = false,
    opacity: f32 = 1.0,
    has_radius: bool = false,
    radius: i32 = -1,
    has_blur: bool = false,
    blur: types.RuleBool = .unset,
    has_shadow: bool = false,
    shadow: types.RuleBool = .unset,
    has_border_width: bool = false,
    border_width: i32 = -1,
    has_tint: bool = false,
    tint: [4]f32 = .{ 0, 0, 0, 0 },
    has_anim: bool = false,
    anim: types.AnimationOverride = .{},

    fn hasVisual(self: *const Override) bool {
        return self.has_opacity or self.has_radius or self.has_blur or
            self.has_shadow or self.has_border_width or self.has_tint;
    }
};

fn parseTint(text: []const u8, out: *[4]f32) bool {
    if (std.ascii.eqlIgnoreCase(text, "none")) {
        out.* = .{ 0, 0, 0, 0 };
        return true;
    }
    var hex = text;
    if (hex.len > 0 and hex[0] == '#') hex = hex[1..];
    if (hex.len != 6 and hex.len != 8) return false;
    var rgba: [4]f32 = .{ 0, 0, 0, 1 };
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (i == 3 and hex.len == 6) break;
        const component = std.fmt.parseInt(u8, hex[i * 2 .. i * 2 + 2], 16) catch return false;
        rgba[i] = @as(f32, @floatFromInt(component)) / 255.0;
    }
    out.* = rgba;
    return true;
}

fn parseV1Override(fields: anytype) ?Override {
    const id = std.fmt.parseInt(u64, fields.next() orelse "", 10) catch return null;
    const opacity = std.fmt.parseFloat(f64, fields.next() orelse "") catch return null;
    const radius = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch return null;
    const blur = parseMode(fields.next() orelse "") orelse return null;
    const shadow = parseMode(fields.next() orelse "") orelse return null;
    const border_width = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch return null;
    if (opacity < 0 or opacity > 1 or radius < 0 or radius > 64 or
        border_width < 0 or border_width > 16)
    {
        return null;
    }
    return .{
        .id = id,
        .has_opacity = true,
        .opacity = @floatCast(opacity),
        .has_radius = true,
        .radius = radius,
        .has_blur = true,
        .blur = blur,
        .has_shadow = true,
        .shadow = shadow,
        .has_border_width = true,
        .border_width = border_width,
    };
}

fn parseV2Override(server: *Server, fields: anytype) ?Override {
    var result = Override{ .id = std.fmt.parseInt(u64, fields.next() orelse "", 10) catch return null };
    while (fields.next()) |token| {
        const eq = std.mem.indexOfScalar(u8, token, '=') orelse return null;
        const key = token[0..eq];
        const value = token[eq + 1 ..];
        if (value.len == 0) return null;
        if (std.mem.eql(u8, key, "opacity")) {
            result.opacity = @floatCast(std.fmt.parseFloat(f64, value) catch return null);
            result.has_opacity = true;
        } else if (std.mem.eql(u8, key, "radius")) {
            result.radius = std.fmt.parseInt(i32, value, 10) catch return null;
            result.has_radius = true;
        } else if (std.mem.eql(u8, key, "blur")) {
            result.blur = parseMode(value) orelse return null;
            result.has_blur = true;
        } else if (std.mem.eql(u8, key, "shadow")) {
            result.shadow = parseMode(value) orelse return null;
            result.has_shadow = true;
        } else if (std.mem.eql(u8, key, "border-width") or std.mem.eql(u8, key, "border_width")) {
            result.border_width = std.fmt.parseInt(i32, value, 10) catch return null;
            result.has_border_width = true;
        } else if (std.mem.eql(u8, key, "tint")) {
            if (!parseTint(value, &result.tint)) return null;
            result.has_tint = true;
        } else if (std.mem.eql(u8, key, "animation-ms")) {
            result.anim.animation_ms = std.fmt.parseInt(i32, value, 10) catch return null;
            result.has_anim = true;
        } else if (std.mem.eql(u8, key, "open-ms")) {
            result.anim.open_ms = std.fmt.parseInt(i32, value, 10) catch return null;
            result.has_anim = true;
        } else if (std.mem.eql(u8, key, "workspace-ms")) {
            result.anim.workspace_ms = std.fmt.parseInt(i32, value, 10) catch return null;
            result.has_anim = true;
        } else if (std.mem.eql(u8, key, "close-ms")) {
            result.anim.close_ms = std.fmt.parseInt(i32, value, 10) catch return null;
            result.has_anim = true;
        } else if (std.mem.eql(u8, key, "curve")) {
            if (value.len > result.anim.curve.len) return null;
            std.mem.copyForwards(u8, &result.anim.curve, value);
            result.anim.curve_len = value.len;
            result.has_anim = true;
        } else if (std.mem.eql(u8, key, "open-curve")) {
            if (value.len > result.anim.open_curve.len) return null;
            std.mem.copyForwards(u8, &result.anim.open_curve, value);
            result.anim.open_curve_len = value.len;
            result.has_anim = true;
        } else if (std.mem.eql(u8, key, "workspace-curve")) {
            if (value.len > result.anim.workspace_curve.len) return null;
            std.mem.copyForwards(u8, &result.anim.workspace_curve, value);
            result.anim.workspace_curve_len = value.len;
            result.has_anim = true;
        } else if (std.mem.eql(u8, key, "close-curve")) {
            if (value.len > result.anim.close_curve.len) return null;
            std.mem.copyForwards(u8, &result.anim.close_curve, value);
            result.anim.close_curve_len = value.len;
            result.has_anim = true;
        } else {
            return null;
        }
    }

    if ((result.has_opacity and (result.opacity < 0 or result.opacity > 1)) or
        (result.has_radius and (result.radius < 0 or result.radius > 64)) or
        (result.has_border_width and (result.border_width < 0 or result.border_width > 16)) or
        (result.has_anim and
            (result.anim.animation_ms < -1 or result.anim.animation_ms > 1000 or
                result.anim.open_ms < -1 or result.anim.open_ms > 1000 or
                result.anim.workspace_ms < -1 or result.anim.workspace_ms > 1000 or
                result.anim.close_ms < -1 or result.anim.close_ms > 1000)))
    {
        return null;
    }
    if (result.anim.curve_len > 0 and !motion.isKnown(&server.config, result.anim.curve[0..result.anim.curve_len])) return null;
    if (result.anim.open_curve_len > 0 and !motion.isKnown(&server.config, result.anim.open_curve[0..result.anim.open_curve_len])) return null;
    if (result.anim.workspace_curve_len > 0 and !motion.isKnown(&server.config, result.anim.workspace_curve[0..result.anim.workspace_curve_len])) return null;
    if (result.anim.close_curve_len > 0 and !motion.isKnown(&server.config, result.anim.close_curve[0..result.anim.close_curve_len])) return null;
    return result;
}

fn applyResponse(server: *Server, data: []const u8) bool {
    const h = &server.effect_helper;
    var overrides: [types.MAX_CLIENTS]Override = undefined;
    var override_count: usize = 0;
    var matched: [types.MAX_CLIENTS]bool = @splat(false);
    var saw_end = false;
    var response_version: u8 = if (h.version == 0) 1 else h.version;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        var fields = std.mem.tokenizeScalar(u8, line, '\t');
        const tag = fields.next() orelse continue;
        if (std.mem.eql(u8, tag, "END")) {
            saw_end = true;
            break;
        }
        if (std.mem.eql(u8, tag, "VERSION")) {
            const value = fields.next() orelse "1";
            const version = std.fmt.parseInt(u8, value, 10) catch 1;
            response_version = @max(1, @min(version, PROTOCOL_VERSION));
            h.version = response_version;
            if (!h.version_logged) {
                core.logInfo("effect helper: protocol {d}", .{response_version});
                h.version_logged = true;
            }
            continue;
        }
        if (std.mem.eql(u8, tag, "ERR")) {
            fail(server, "helper returned an error");
            return false;
        }
        if (!std.mem.eql(u8, tag, "WINDOW")) continue;
        if (override_count >= overrides.len) {
            fail(server, "too many window overrides");
            return false;
        }
        const parsed = if (response_version >= 2)
            parseV2Override(server, &fields)
        else
            parseV1Override(&fields);
        const override = parsed orelse {
            fail(server, "invalid window override");
            return false;
        };

        var index: ?usize = null;
        var i: usize = 0;
        while (i < h.request_count) : (i += 1) {
            if (h.request_ids[i] == override.id) {
                index = i;
                break;
            }
        }
        const idx = index orelse {
            fail(server, "response contained an unknown window id");
            return false;
        };
        if (matched[idx]) {
            fail(server, "duplicate window in response");
            return false;
        }
        matched[idx] = true;
        overrides[override_count] = override;
        override_count += 1;
    }

    if (!saw_end) {
        fail(server, "response ended without END");
        return false;
    }

    h.waiting = false;
    h.read_len = 0;
    h.cache_sig = h.request_sig;
    disarmTimer(h);

    var changed = false;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (client.hook_active) {
            client.hook_active = false;
            changed = true;
        }
        if (client.hook_anim_active) {
            client.hook_anim_active = false;
            changed = true;
        }
    }
    for (overrides[0..override_count]) |override| {
        if (findClient(server, override.id)) |client| {
            // Start from the rule values so partial v2 replies leave omitted
            // fields untouched.
            client.hook_opacity = client.opacity;
            client.hook_corner_radius = client.corner_radius;
            client.hook_blur = client.blur;
            client.hook_shadow = client.shadow;
            client.hook_border_width = client.border_width;
            client.hook_tint_rgba = client.tint_rgba;
            client.hook_anim = client.anim;
            if (override.hasVisual()) {
                client.hook_active = true;
                if (override.has_opacity) client.hook_opacity = override.opacity;
                if (override.has_radius) client.hook_corner_radius = override.radius;
                if (override.has_blur) client.hook_blur = override.blur;
                if (override.has_shadow) client.hook_shadow = override.shadow;
                if (override.has_border_width) client.hook_border_width = override.border_width;
                if (override.has_tint) client.hook_tint_rgba = override.tint;
            }
            if (override.has_anim) {
                client.hook_anim_active = true;
                if (override.anim.animation_ms >= 0) client.hook_anim.animation_ms = override.anim.animation_ms;
                if (override.anim.open_ms >= 0) client.hook_anim.open_ms = override.anim.open_ms;
                if (override.anim.workspace_ms >= 0) client.hook_anim.workspace_ms = override.anim.workspace_ms;
                if (override.anim.close_ms >= 0) client.hook_anim.close_ms = override.anim.close_ms;
                if (override.anim.curve_len > 0) {
                    @memcpy(client.hook_anim.curve[0..override.anim.curve_len], override.anim.curve[0..override.anim.curve_len]);
                    client.hook_anim.curve_len = override.anim.curve_len;
                }
                if (override.anim.open_curve_len > 0) {
                    @memcpy(client.hook_anim.open_curve[0..override.anim.open_curve_len], override.anim.open_curve[0..override.anim.open_curve_len]);
                    client.hook_anim.open_curve_len = override.anim.open_curve_len;
                }
                if (override.anim.workspace_curve_len > 0) {
                    @memcpy(client.hook_anim.workspace_curve[0..override.anim.workspace_curve_len], override.anim.workspace_curve[0..override.anim.workspace_curve_len]);
                    client.hook_anim.workspace_curve_len = override.anim.workspace_curve_len;
                }
                if (override.anim.close_curve_len > 0) {
                    @memcpy(client.hook_anim.close_curve[0..override.anim.close_curve_len], override.anim.close_curve[0..override.anim.close_curve_len]);
                    client.hook_anim.close_curve_len = override.anim.close_curve_len;
                }
            }
            changed = true;
        }
    }

    if (changed) {
        window_effects.applyAll(server);
        layout.arrangeAll(server);
        layout.updateBorders(server);
        core.markDirty(server);
    }
    core.logDebug("effect helper: applied response", .{});
    if (h.pending) {
        h.pending = false;
        refresh(server);
    }
    return true;
}

fn findClient(server: *Server, id: u64) ?*Client {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (client.id == id) return client;
    }
    return null;
}

fn parseMode(text: []const u8) ?types.RuleBool {
    if (std.mem.eql(u8, text, "on")) return .on;
    if (std.mem.eql(u8, text, "off")) return .off;
    if (std.mem.eql(u8, text, "unset")) return .unset;
    return null;
}

fn onRead(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = fd;
    _ = mask;
    const server: *Server = @ptrCast(@alignCast(data.?));
    const h = &server.effect_helper;
    if (h.fd < 0) return 0;
    if (h.read_len >= h.read_buf.len) {
        fail(server, "response is too large");
        return 0;
    }
    const n = c.read(h.fd, h.read_buf[h.read_len..].ptr, h.read_buf.len - h.read_len);
    if (n <= 0) {
        if (n == 0) {
            fail(server, "helper closed the connection");
        } else {
            fail(server, "read failed");
        }
        return 0;
    }
    h.read_len += @intCast(n);
    if (hasEndLine(h.read_buf[0..h.read_len])) {
        _ = applyResponse(server, h.read_buf[0..h.read_len]);
    }
    return 0;
}

fn onTimeout(data: ?*anyopaque) callconv(.c) c_int {
    const server: *Server = @ptrCast(@alignCast(data.?));
    if (server.effect_helper.waiting) {
        fail(server, "response timed out");
    }
    return 0;
}

/// Send the current window state to the helper when it changed. The helper is
/// long-lived and receives one coalesced request per visible state change.
pub fn refresh(server: *Server) void {
    const command = server.config.effect_helper[0..server.config.effect_helper_len];
    if (command.len == 0) return;
    const h = &server.effect_helper;
    if (!ensureStarted(server, command, hashBytes(command))) return;

    var request_buf: [MAX_REQUEST]u8 = undefined;
    var ids: [types.MAX_CLIENTS]u64 = undefined;
    const request_len = buildRequest(server, request_buf[0..], ids[0..]) orelse {
        core.logInfo("effect helper: request is too large", .{});
        return;
    };
    const sig = hashBytes(request_buf[0..request_len]);
    if (h.cache_sig == sig) return;
    if (h.waiting) {
        h.pending = true;
        return;
    }

    if (!h.hello_sent) {
        h.hello_sent = true;
    }
    if (!sendAll(server, request_buf[0..request_len])) {
        fail(server, "write failed");
        return;
    }
    h.waiting = true;
    h.request_sig = sig;
    h.request_count = countRequestWindows(server);
    @memcpy(h.request_ids[0..h.request_count], ids[0..h.request_count]);
    h.read_len = 0;
    if (h.timer) |timer| _ = c.wl_event_source_timer_update(timer, server.config.effect_helper_timeout);
    core.logDebug("effect helper: request sent (count={d}, sig={x})", .{ h.request_count, sig });
}

fn countRequestWindows(server: *Server) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (client.mapped) count += 1;
    }
    return count;
}
