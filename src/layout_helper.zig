const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;
const Client = types.Client;
const Output = types.Output;

pub const Rect = types.LayoutRect;
pub const MAX_HELPER_WINDOWS = types.MAX_LAYOUT_RECTS;
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

fn notify(server: *Server) void {
    if (server.layout_refresh) |refresh| refresh(server);
}

fn disarmTimer(h: *types.LayoutHelperState) void {
    if (h.timer) |timer| _ = c.wl_event_source_timer_update(timer, 0);
}

fn stop(out: *Output, clear_cache: bool) void {
    const h = &out.helper;
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
    h.hello_sent = false;
    h.version = 0;
    h.version_logged = false;
    h.request_sig = 0;
    h.request_count = 0;
    h.read_len = 0;
    if (clear_cache) {
        h.cache_sig = 0;
        h.cache_count = 0;
    }
}

fn failState(out: *Output, reason: []const u8) void {
    const h = &out.helper;
    const hash = h.hash;
    stop(out, true);
    h.hash = hash;
    h.fail_until = core.timeNowMs() + FAIL_BACKOFF_MS;
    core.logInfo("layout helper for {s} failed: {s}; using built-in fallback", .{
        core.outputName(out),
        reason,
    });
}

fn failAndNotify(out: *Output, reason: []const u8) void {
    failState(out, reason);
    notify(out.server);
}

fn start(out: *Output, command: []const u8, hash: u64) bool {
    stop(out, true);

    var fds: [2]c_int = undefined;
    if (c.socketpair(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0, &fds[0]) != 0) {
        core.logInfo("layout helper for {s}: socketpair failed", .{core.outputName(out)});
        return false;
    }

    const timeout_us: i64 = @as(i64, out.server.config.layout_helper_timeout) * 1000;
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
    const command_z = std.fmt.bufPrintZ(&cmd_buf, "{s}", .{command}) catch {
        _ = c.close(fds[0]);
        _ = c.close(fds[1]);
        core.logInfo("layout helper for {s}: command too long", .{core.outputName(out)});
        return false;
    };

    const pid = c.fork();
    if (pid < 0) {
        _ = c.close(fds[0]);
        _ = c.close(fds[1]);
        core.logInfo("layout helper for {s}: fork failed", .{core.outputName(out)});
        return false;
    }
    if (pid == 0) {
        _ = c.close(fds[0]);
        _ = c.dup2(fds[1], 0);
        _ = c.dup2(fds[1], 1);
        if (fds[1] > 2) _ = c.close(fds[1]);
        _ = c.signal(c.SIGCHLD, c.SIG_DFL);
        _ = c.signal(c.SIGINT, c.SIG_DFL);
        _ = c.signal(c.SIGTERM, c.SIG_DFL);
        _ = c.signal(c.SIGPIPE, c.SIG_DFL);
        _ = c.setsid();
        _ = c.execl("/bin/sh", "/bin/sh", "-c", command_z.ptr, @as(?[*:0]const u8, null));
        c._exit(127);
    }

    _ = c.close(fds[1]);
    const h = &out.helper;
    h.fd = fds[0];
    h.pid = pid;
    h.hash = hash;
    h.fail_until = 0;
    h.waiting = false;
    h.hello_sent = false;
    h.version = 0;
    h.version_logged = false;
    h.request_sig = 0;
    h.request_count = 0;
    h.cache_sig = 0;
    h.cache_count = 0;
    h.read_len = 0;

    const loop = c.wl_display_get_event_loop(out.server.display);
    const source = c.wl_event_loop_add_fd(
        loop,
        h.fd,
        @intCast(c.WL_EVENT_READABLE),
        onRead,
        out,
    );
    if (source == null) {
        core.logInfo("layout helper for {s}: event source failed", .{core.outputName(out)});
        _ = c.close(h.fd);
        h.fd = -1;
        _ = c.kill(-pid, c.SIGTERM);
        _ = c.kill(pid, c.SIGTERM);
        h.pid = 0;
        return false;
    }
    h.source = source;

    const timer = c.wl_event_loop_add_timer(loop, onTimeout, out);
    if (timer == null) {
        _ = c.wl_event_source_remove(source);
        h.source = null;
        _ = c.close(h.fd);
        h.fd = -1;
        _ = c.kill(-pid, c.SIGTERM);
        _ = c.kill(pid, c.SIGTERM);
        h.pid = 0;
        core.logInfo("layout helper for {s}: timer failed", .{core.outputName(out)});
        return false;
    }
    h.timer = timer;
    core.logInfo("layout helper started for {s} (pid {d})", .{ core.outputName(out), pid });
    return true;
}

fn ensureStarted(out: *Output, command: []const u8, hash: u64) bool {
    const h = &out.helper;
    if (h.fd >= 0) {
        if (h.hash == hash) return true;
        stop(out, true);
    }
    const now = core.timeNowMs();
    if (h.hash == hash and now < h.fail_until) return false;
    if (!start(out, command, hash)) {
        h.hash = hash;
        h.fail_until = now + FAIL_BACKOFF_MS;
        return false;
    }
    return true;
}

pub fn deinit(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        stop(out, true);
    }
}

pub fn initOutput(out: *Output) void {
    out.helper = .{};
}

pub fn destroyOutput(out: *Output) void {
    stop(out, true);
}

pub fn reload(server: *Server) void {
    const command = server.config.layout_helper[0..server.config.layout_helper_len];
    const hash = if (command.len > 0) hashBytes(command) else 0;
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        if (command.len == 0) {
            if (out.helper.fd >= 0) core.logInfo("layout helper stopped for {s}", .{core.outputName(out)});
            stop(out, true);
        } else if (out.helper.fd >= 0 and out.helper.hash != hash) {
            core.logInfo("layout helper command changed; restarting for {s}", .{core.outputName(out)});
            stop(out, true);
        }
    }
}

/// Tell running helpers that focus or urgency changed. The next arrange sends
/// a fresh request but keeps the current rectangles until the response arrives.
pub fn focusChanged(server: *Server) void {
    var active = false;
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        if (out.helper.fd >= 0) {
            active = true;
            break;
        }
    }
    if (active) notify(server);
}

fn sendAll(out: *Output, data: []const u8) bool {
    var sent: usize = 0;
    while (sent < data.len) {
        const n = c.send(out.helper.fd, data[sent..].ptr, data.len - sent, c.MSG_NOSIGNAL);
        if (n <= 0) return false;
        sent += @intCast(n);
    }
    return true;
}

fn sendRequest(out: *Output, request: []const u8, sig: u64, ids: []const u64) bool {
    const h = &out.helper;
    if (!h.hello_sent) {
        if (!sendAll(out, "HELLO\t2\n")) return false;
        h.hello_sent = true;
    }
    if (!sendAll(out, request)) return false;
    h.waiting = true;
    h.request_sig = sig;
    h.request_count = ids.len;
    var i: usize = 0;
    while (i < ids.len) : (i += 1) h.request_ids[i] = ids[i];
    h.read_len = 0;
    if (h.timer) |timer| _ = c.wl_event_source_timer_update(timer, out.server.config.layout_helper_timeout);
    core.logDebug("layout helper: request sent to {s} (count={d}, sig={x})", .{
        core.outputName(out),
        ids.len,
        sig,
    });
    return true;
}

fn buildRequest(
    server: *Server,
    out: *Output,
    tiles: []const ?*Client,
    area: c.wlr_box,
    border: i32,
    gap: i32,
    outer_gaps: i32,
    buf: []u8,
) ?usize {
    var off: usize = 0;
    if (!append(buf, &off, "LAYOUT\t{d}\n", .{PROTOCOL_VERSION})) return null;
    if (!append(buf, &off, "OUTPUT\t{s}\n", .{core.outputName(out)})) return null;
    if (!append(buf, &off, "AREA\t{d}\t{d}\t{d}\t{d}\n", .{
        area.x,
        area.y,
        area.width,
        area.height,
    })) return null;
    if (!append(buf, &off, "OUTER_GAP\t{d}\n", .{outer_gaps})) return null;
    if (!append(buf, &off, "GAP\t{d}\n", .{gap})) return null;
    if (!append(buf, &off, "BORDER\t{d}\n", .{border})) return null;
    if (!append(buf, &off, "SCALE\t{d:.3}\n", .{out.wlr.scale})) return null;
    if (!append(buf, &off, "TRANSFORM\t{d}\n", .{out.wlr.transform})) return null;
    if (!append(buf, &off, "COUNT\t{d}\n", .{tiles.len})) return null;

    for (tiles) |maybe_client| {
        const client = maybe_client orelse return null;
        if (!append(buf, &off, "WINDOW\t{d}\t", .{client.id})) return null;
        if (!appendEscaped(buf, &off, client.app_id[0..client.app_id_len])) return null;
        if (!append(buf, &off, "\t", .{})) return null;
        if (!appendEscaped(buf, &off, client.title[0..client.title_len])) return null;
        if (out.helper.version >= 2) {
            const focused: u8 = if (server.focused == client and server.focused_layer == null) 1 else 0;
            if (!append(buf, &off, "\t{d}\t{d}\n", .{ focused, @as(u8, if (client.urgent) 1 else 0) })) return null;
        } else {
            if (!append(buf, &off, "\n", .{})) return null;
        }
    }
    if (!append(buf, &off, "END\n", .{})) return null;
    return off;
}

fn noteVersion(out: *Output, version: u8) void {
    const h = &out.helper;
    const negotiated: u8 = if (version >= 2) 2 else 1;
    if (!h.version_logged or h.version != negotiated) {
        core.logInfo("layout helper {s}: negotiated protocol {d}", .{
            core.outputName(out),
            negotiated,
        });
        h.version_logged = true;
    }
    h.version = negotiated;
}

fn parseResponse(out: *Output, data: []const u8) bool {
    const h = &out.helper;
    var rects: [MAX_HELPER_WINDOWS]Rect = undefined;
    var count: usize = 0;
    var seen_version: ?u8 = null;
    var saw_end = false;

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
            seen_version = std.fmt.parseInt(u8, fields.next() orelse "", 10) catch {
                failAndNotify(out, "invalid version line");
                return false;
            };
            continue;
        }
        if (std.mem.eql(u8, tag, "ERR")) {
            failAndNotify(out, "helper returned an error");
            return false;
        }
        if (!std.mem.eql(u8, tag, "RECT")) continue;
        if (count >= rects.len) {
            failAndNotify(out, "too many rectangles");
            return false;
        }
        const id = std.fmt.parseInt(u64, fields.next() orelse "", 10) catch {
            failAndNotify(out, "invalid rectangle id");
            return false;
        };
        const x = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch {
            failAndNotify(out, "invalid rectangle x");
            return false;
        };
        const y = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch {
            failAndNotify(out, "invalid rectangle y");
            return false;
        };
        const w = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch {
            failAndNotify(out, "invalid rectangle width");
            return false;
        };
        const rect_h = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch {
            failAndNotify(out, "invalid rectangle height");
            return false;
        };
        if (w <= 0 or rect_h <= 0) {
            failAndNotify(out, "invalid rectangle size");
            return false;
        }
        rects[count] = .{ .id = id, .x = x, .y = y, .w = w, .h = rect_h };
        count += 1;
    }

    if (!saw_end) {
        failAndNotify(out, "response ended without END");
        return false;
    }
    if (count != h.request_count) {
        failAndNotify(out, "rectangle count mismatch");
        return false;
    }

    var matched = [_]bool{false} ** MAX_HELPER_WINDOWS;
    for (rects[0..count]) |rect| {
        var found = false;
        var i: usize = 0;
        while (i < h.request_count) : (i += 1) {
            if (!matched[i] and h.request_ids[i] == rect.id) {
                matched[i] = true;
                found = true;
                break;
            }
        }
        if (!found) {
            failAndNotify(out, "response contained an unknown window id");
            return false;
        }
    }

    if (seen_version) |version| {
        noteVersion(out, version);
    } else if (h.version == 0) {
        noteVersion(out, 1);
    }
    @memcpy(h.rects[0..count], rects[0..count]);
    h.cache_count = count;
    h.cache_sig = h.request_sig;
    h.waiting = false;
    h.read_len = 0;
    disarmTimer(h);
    core.logDebug("layout helper: response from {s} (count={d})", .{
        core.outputName(out),
        count,
    });
    notify(out.server);
    return true;
}

fn onRead(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = fd;
    _ = mask;
    const out: *Output = @ptrCast(@alignCast(data.?));
    const h = &out.helper;
    if (h.fd < 0) return 0;
    if (h.read_len >= h.read_buf.len) {
        failAndNotify(out, "response is too large");
        return 0;
    }
    const n = c.read(h.fd, h.read_buf[h.read_len..].ptr, h.read_buf.len - h.read_len);
    if (n <= 0) {
        if (n == 0) {
            failAndNotify(out, "helper closed the connection");
        } else {
            failAndNotify(out, "read failed");
        }
        return 0;
    }
    h.read_len += @intCast(n);
    if (hasEndLine(h.read_buf[0..h.read_len])) {
        _ = parseResponse(out, h.read_buf[0..h.read_len]);
    }
    return 0;
}

fn onTimeout(data: ?*anyopaque) callconv(.c) c_int {
    const out: *Output = @ptrCast(@alignCast(data.?));
    if (out.helper.waiting) {
        failAndNotify(out, "response timed out");
    }
    return 0;
}

fn cachedRects(h: *const types.LayoutHelperState, rects: []Rect) usize {
    @memcpy(rects[0..h.cache_count], h.rects[0..h.cache_count]);
    return h.cache_count;
}

pub fn query(
    server: *Server,
    out: *Output,
    tiles: []const ?*Client,
    area: c.wlr_box,
    border: i32,
    gap: i32,
    outer_gaps: i32,
    rects: []Rect,
) ?usize {
    const command = server.config.layout_helper[0..server.config.layout_helper_len];
    if (command.len == 0 or tiles.len == 0 or tiles.len > MAX_HELPER_WINDOWS or rects.len < tiles.len) return null;

    const hash = hashBytes(command);
    if (!ensureStarted(out, command, hash)) return null;
    const h = &out.helper;

    var request_buf: [MAX_REQUEST]u8 = undefined;
    const request_len = buildRequest(server, out, tiles, area, border, gap, outer_gaps, request_buf[0..]) orelse {
        core.logInfo("layout helper: request is too large for {s}", .{core.outputName(out)});
        return null;
    };
    const sig = hashBytes(request_buf[0..request_len]);

    const have_cache = h.cache_count == tiles.len and h.cache_count > 0;
    if (have_cache and h.cache_sig == sig) return cachedRects(h, rects);

    if (h.waiting) {
        return if (have_cache) cachedRects(h, rects) else null;
    }

    var ids: [MAX_HELPER_WINDOWS]u64 = undefined;
    for (tiles, 0..) |maybe_client, i| {
        const client = maybe_client orelse return null;
        ids[i] = client.id;
    }
    if (!sendRequest(out, request_buf[0..request_len], sig, ids[0..tiles.len])) {
        failState(out, "write failed");
        return null;
    }
    return if (have_cache) cachedRects(h, rects) else null;
}
