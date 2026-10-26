const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");

const Server = types.Server;
const Client = types.Client;
const Output = types.Output;

pub const MAX_HELPER_WINDOWS = 64;
const MAX_REQUEST = 64 * 1024;
const MAX_RESPONSE = 64 * 1024;
const FAIL_BACKOFF_MS = 1000;

pub const Rect = struct {
    id: u64,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

fn hashCommand(cmd: []const u8) u64 {
    var h: u64 = 1469598103934665603;
    for (cmd) |ch| {
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

pub fn deinit(server: *Server) void {
    if (server.layout_helper_fd >= 0) {
        _ = c.close(server.layout_helper_fd);
        server.layout_helper_fd = -1;
    }
    if (server.layout_helper_pid > 0) {
        _ = c.kill(-server.layout_helper_pid, c.SIGTERM);
        _ = c.kill(server.layout_helper_pid, c.SIGTERM);
        server.layout_helper_pid = 0;
    }
    server.layout_helper_hash = 0;
    server.layout_helper_fail_until = 0;
}

fn stop(server: *Server) void {
    if (server.layout_helper_fd >= 0) {
        _ = c.close(server.layout_helper_fd);
        server.layout_helper_fd = -1;
    }
    if (server.layout_helper_pid > 0) {
        _ = c.kill(-server.layout_helper_pid, c.SIGTERM);
        _ = c.kill(server.layout_helper_pid, c.SIGTERM);
        server.layout_helper_pid = 0;
    }
}

fn fail(server: *Server, hash: u64, reason: []const u8) void {
    stop(server);
    server.layout_helper_hash = hash;
    server.layout_helper_fail_until = core.timeNowMs() + FAIL_BACKOFF_MS;
    core.logInfo("layout helper failed: {s}; using built-in fallback", .{reason});
}

fn start(server: *Server, command: []const u8, hash: u64) bool {
    stop(server);

    var fds: [2]c_int = undefined;
    if (c.socketpair(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0, &fds[0]) != 0) {
        core.logInfo("layout helper: socketpair failed", .{});
        return false;
    }

    const timeout_us: i64 = @as(i64, server.config.layout_helper_timeout) * 1000;
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
        core.logInfo("layout helper: command too long", .{});
        return false;
    };

    const pid = c.fork();
    if (pid < 0) {
        _ = c.close(fds[0]);
        _ = c.close(fds[1]);
        core.logInfo("layout helper: fork failed", .{});
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
    server.layout_helper_fd = fds[0];
    server.layout_helper_pid = pid;
    server.layout_helper_hash = hash;
    server.layout_helper_fail_until = 0;
    core.logInfo("layout helper started (pid {d})", .{pid});
    return true;
}

pub fn reload(server: *Server) void {
    const command = server.config.layout_helper[0..server.config.layout_helper_len];
    if (command.len == 0) {
        if (server.layout_helper_fd >= 0) core.logInfo("layout helper stopped", .{});
        stop(server);
        server.layout_helper_hash = 0;
        server.layout_helper_fail_until = 0;
        return;
    }
    const hash = hashCommand(command);
    if (server.layout_helper_fd >= 0 and server.layout_helper_hash != hash) {
        core.logInfo("layout helper command changed; restarting", .{});
        stop(server);
    }
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
    if (command.len == 0 or tiles.len > MAX_HELPER_WINDOWS or rects.len < tiles.len) return null;

    const hash = hashCommand(command);
    const now = core.timeNowMs();
    if (server.layout_helper_fd < 0) {
        if (server.layout_helper_hash == hash and now < server.layout_helper_fail_until) return null;
        if (!start(server, command, hash)) {
            server.layout_helper_hash = hash;
            server.layout_helper_fail_until = now + FAIL_BACKOFF_MS;
            return null;
        }
    } else if (server.layout_helper_hash != hash) {
        stop(server);
        if (!start(server, command, hash)) {
            server.layout_helper_hash = hash;
            server.layout_helper_fail_until = now + FAIL_BACKOFF_MS;
            return null;
        }
    }

    var request_buf: [MAX_REQUEST]u8 = undefined;
    var off: usize = 0;
    if (!append(&request_buf, &off, "LAYOUT\t1\n", .{})) return null;
    if (!append(&request_buf, &off, "OUTPUT\t{s}\n", .{core.outputName(out)})) return null;
    if (!append(&request_buf, &off, "AREA\t{d}\t{d}\t{d}\t{d}\n", .{
        area.x,
        area.y,
        area.width,
        area.height,
    })) return null;
    if (!append(&request_buf, &off, "OUTER_GAP\t{d}\n", .{outer_gaps})) return null;
    if (!append(&request_buf, &off, "GAP\t{d}\n", .{gap})) return null;
    if (!append(&request_buf, &off, "BORDER\t{d}\n", .{border})) return null;
    if (!append(&request_buf, &off, "SCALE\t{d:.3}\n", .{out.wlr.scale})) return null;
    if (!append(&request_buf, &off, "TRANSFORM\t{d}\n", .{out.wlr.transform})) return null;
    if (!append(&request_buf, &off, "COUNT\t{d}\n", .{tiles.len})) return null;

    for (tiles) |maybe_client| {
        const client = maybe_client orelse return null;
        if (!append(&request_buf, &off, "WINDOW\t{d}\t", .{client.id})) return null;
        if (!appendEscaped(&request_buf, &off, client.app_id[0..client.app_id_len])) return null;
        if (!append(&request_buf, &off, "\t", .{})) return null;
        if (!appendEscaped(&request_buf, &off, client.title[0..client.title_len])) return null;
        if (!append(&request_buf, &off, "\n", .{})) return null;
    }
    if (!append(&request_buf, &off, "END\n", .{})) return null;

    var sent: usize = 0;
    while (sent < off) {
        const n = c.send(server.layout_helper_fd, request_buf[sent..].ptr, off - sent, c.MSG_NOSIGNAL);
        if (n <= 0) {
            fail(server, hash, "write failed");
            return null;
        }
        sent += @intCast(n);
    }

    const timeout_ms = server.config.layout_helper_timeout;
    const started = core.timeNowMs();
    var response_buf: [MAX_RESPONSE]u8 = undefined;
    var response_len: usize = 0;
    while (true) {
        const elapsed = core.timeNowMs() - started;
        if (elapsed >= timeout_ms) {
            fail(server, hash, "response timed out");
            return null;
        }
        var pfd = [_]c.pollfd{.{
            .fd = server.layout_helper_fd,
            .events = c.POLLIN,
            .revents = 0,
        }};
        const pr = c.poll(&pfd, 1, @intCast(timeout_ms - elapsed));
        if (pr <= 0) {
            fail(server, hash, "response timed out");
            return null;
        }
        const n = c.read(server.layout_helper_fd, response_buf[response_len..].ptr, response_buf.len - response_len);
        if (n <= 0) {
            fail(server, hash, "helper closed the connection");
            return null;
        }
        response_len += @intCast(n);
        if (hasEndLine(response_buf[0..response_len])) break;
        if (response_len >= response_buf.len) {
            fail(server, hash, "response is too large");
            return null;
        }
    }

    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, response_buf[0..response_len], '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        var fields = std.mem.tokenizeScalar(u8, line, '\t');
        const tag = fields.next() orelse continue;
        if (std.mem.eql(u8, tag, "END")) break;
        if (std.mem.eql(u8, tag, "ERR")) {
            fail(server, hash, "helper returned an error");
            return null;
        }
        if (!std.mem.eql(u8, tag, "RECT")) continue;
        const id = std.fmt.parseInt(u64, fields.next() orelse "", 10) catch {
            fail(server, hash, "invalid rectangle id");
            return null;
        };
        const x = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch {
            fail(server, hash, "invalid rectangle x");
            return null;
        };
        const y = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch {
            fail(server, hash, "invalid rectangle y");
            return null;
        };
        const w = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch {
            fail(server, hash, "invalid rectangle width");
            return null;
        };
        const h = std.fmt.parseInt(i32, fields.next() orelse "", 10) catch {
            fail(server, hash, "invalid rectangle height");
            return null;
        };
        if (w <= 0 or h <= 0 or count >= rects.len) {
            fail(server, hash, "invalid rectangle size");
            return null;
        }
        rects[count] = .{ .id = id, .x = x, .y = y, .w = w, .h = h };
        count += 1;
    }

    if (count != tiles.len) {
        fail(server, hash, "rectangle count mismatch");
        return null;
    }
    return count;
}
