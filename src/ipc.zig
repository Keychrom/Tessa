const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");

const Server = types.Server;
const IpcClient = types.IpcClient;
const Client = types.Client;

pub fn init(server: *Server) void {
    server.ipc_fd = -1;
    server.schedule_ipc = schedule;

    var path_buf: [256]u8 = undefined;
    var path: []const u8 = "";
    if (c.getenv("TESSA_IPC")) |p| {
        path = core.cstr(p);
    } else if (c.getenv("XDG_RUNTIME_DIR")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/tessa.sock", .{core.cstr(p)}) catch "";
    } else {
        path = std.fmt.bufPrint(&path_buf, "/tmp/tessa-{d}.sock", .{c.getuid()}) catch "";
    }
    if (path.len == 0 or path.len >= 100) {
        core.logInfo("ipc: invalid socket path", .{});
        return;
    }
    core.copyZ(&server.ipc_path, path);
    _ = c.setenv("TESSA_IPC", &server.ipc_path, 1);

    const fd = c.socket(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_NONBLOCK | c.SOCK_CLOEXEC, 0);
    if (fd < 0) {
        core.logInfo("ipc: socket() failed", .{});
        return;
    }

    _ = c.unlink(&server.ipc_path);

    var addr: c.sockaddr_un = std.mem.zeroes(c.sockaddr_un);
    addr.sun_family = c.AF_UNIX;
    @memcpy(addr.sun_path[0..path.len], path);
    addr.sun_path[path.len] = 0;

    const bind_addr: c.__CONST_SOCKADDR_ARG = .{ .__sockaddr_un__ = @ptrCast(&addr) };
    if (c.bind(fd, bind_addr, @intCast(@sizeOf(c.sockaddr_un))) < 0) {
        core.logInfo("ipc: bind({s}) failed", .{path});
        _ = c.close(fd);
        return;
    }
    if (c.listen(fd, 8) < 0) {
        core.logInfo("ipc: listen() failed", .{});
        _ = c.close(fd);
        _ = c.unlink(&server.ipc_path);
        return;
    }
    _ = c.chmod(&server.ipc_path, 0o600);

    server.ipc_fd = fd;
    const loop = c.wl_display_get_event_loop(server.display);
    server.ipc_source = c.wl_event_loop_add_fd(
        loop,
        fd,
        @intCast(c.WL_EVENT_READABLE),
        onAccept,
        server,
    );
    core.logInfo("ipc: listening on {s}", .{path});
}

pub fn deinit(server: *Server) void {
    var i: usize = 0;
    while (i < server.ipcs.len) : (i += 1) {
        if (server.ipcs[i]) |cl| {
            closeClient(cl);
        }
    }
    if (server.ipc_idle) |src| {
        _ = c.wl_event_source_remove(src);
        server.ipc_idle = null;
    }
    if (server.ipc_source) |src| {
        _ = c.wl_event_source_remove(src);
        server.ipc_source = null;
    }
    if (server.ipc_fd >= 0) {
        _ = c.close(server.ipc_fd);
        server.ipc_fd = -1;
        _ = c.unlink(&server.ipc_path);
    }
}

pub fn schedule(server: *Server) void {
    if (server.ipc_idle != null) return;
    const loop = c.wl_display_get_event_loop(server.display);
    server.ipc_idle = c.wl_event_loop_add_idle(loop, onIdle, server);
}

fn onIdle(data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @ptrCast(@alignCast(data.?));
    server.ipc_idle = null;
    if (server.ipc_dirty) {
        broadcastState(server);
    }
}

fn onAccept(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = mask;
    const server: *Server = @ptrCast(@alignCast(data.?));
    while (true) {
        const empty_addr: c.__SOCKADDR_ARG = .{ .__sockaddr__ = null };
        const cfd = c.accept4(fd, empty_addr, null, c.SOCK_NONBLOCK | c.SOCK_CLOEXEC);
        if (cfd < 0) break;

        const cl = @as(*IpcClient, @ptrCast(@alignCast(c.calloc(1, @sizeOf(IpcClient)).?)));
        cl.server = server;
        cl.fd = cfd;
        cl.len = 0;
        cl.alive = true;

        if (server.ipc_count >= server.ipcs.len) {
            const msg = "ERR busy\n";
            _ = c.send(cfd, msg, msg.len, c.MSG_NOSIGNAL);
            _ = c.close(cfd);
            c.free(cl);
            continue;
        }

        const loop = c.wl_display_get_event_loop(server.display);
        cl.source = c.wl_event_loop_add_fd(loop, cfd, @intCast(c.WL_EVENT_READABLE), onRead, cl);
        server.ipcs[server.ipc_count] = cl;
        server.ipc_count += 1;

        sendState(server, cl);
        core.logInfo("ipc: panel connected", .{});
    }
    return 0;
}

fn closeClient(cl: *IpcClient) void {
    if (!cl.alive) return;
    cl.alive = false;
    const server = cl.server;

    if (cl.source) |src| {
        _ = c.wl_event_source_remove(src);
        cl.source = null;
    }
    _ = c.close(cl.fd);

    var i: usize = 0;
    while (i < server.ipcs.len) : (i += 1) {
        if (server.ipcs[i] == cl) {
            core.removeAt(types.IpcClient, server.ipcs[0..], &server.ipc_count, i);
            break;
        }
    }
    c.free(cl);
}

fn onRead(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    const cl: *IpcClient = @ptrCast(@alignCast(data.?));
    if (!cl.alive) return 0;
    if ((mask & 0x10) != 0) {
        closeClient(cl);
        return 0;
    }

    if (cl.len >= cl.buf.len) {
        closeClient(cl);
        return 0;
    }
    const n = c.read(fd, cl.buf[cl.len..].ptr, cl.buf.len - cl.len);
    if (n <= 0) {
        closeClient(cl);
        return 0;
    }
    cl.len += @intCast(n);

    while (cl.alive) {
        const slice = cl.buf[0..cl.len];
        const nl = std.mem.indexOfScalar(u8, slice, '\n') orelse break;
        const line = std.mem.trim(u8, slice[0..nl], " \t\r");
        if (line.len > 0) handleCommand(cl, line);
        if (!cl.alive) return 0;
        const remain = cl.len - (nl + 1);
        if (remain > 0) std.mem.copyForwards(u8, cl.buf[0..remain], cl.buf[nl + 1 .. cl.len]);
        cl.len = remain;
    }
    return 0;
}

fn tokens(line: []const u8, out: *[8][]const u8) usize {
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, line, " \t");
    while (it.next()) |tok| {
        if (n < out.len) {
            out[n] = tok;
            n += 1;
        }
    }
    return n;
}

fn findClient(server: *Server, id: u64) ?*Client {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        if (server.clients[i]) |cl| {
            if (cl.id == id) return cl;
        }
    }
    return null;
}

fn handleCommand(cl: *IpcClient, line: []const u8) void {
    const server = cl.server;
    var toks: [8][]const u8 = undefined;
    const n = tokens(line, &toks);
    if (n == 0) return;

    var start: usize = 0;
    if (std.mem.eql(u8, toks[0], "CMD")) start = 1;
    if (start >= n) return;
    const cmd = toks[start];

    if (std.mem.eql(u8, cmd, "state")) {
        sendState(server, cl);
    } else if (std.mem.eql(u8, cmd, "workspace")) {
        if (start + 1 < n) {
            const ws = std.fmt.parseInt(usize, toks[start + 1], 10) catch return;
            layout.switchWorkspace(server, ws);
            broadcastState(server);
        }
    } else if (std.mem.eql(u8, cmd, "focus")) {
        if (start + 1 < n) {
            const id = std.fmt.parseInt(u64, toks[start + 1], 10) catch return;
            if (findClient(server, id)) |target| {
                layout.focusClient(server, target);
                broadcastState(server);
            }
        }
    } else if (std.mem.eql(u8, cmd, "close")) {
        if (start + 1 < n) {
            const id = std.fmt.parseInt(u64, toks[start + 1], 10) catch return;
            if (findClient(server, id)) |target| c.wlr_xdg_toplevel_send_close(target.xdg);
        }
    } else if (std.mem.eql(u8, cmd, "float")) {
        if (start + 1 < n) {
            const id = std.fmt.parseInt(u64, toks[start + 1], 10) catch return;
            if (findClient(server, id)) |target| {
                target.floating = !target.floating;
                target.float_w = 0;
                target.float_h = 0;
                layout.focusClient(server, target);
                layout.arrangeAll(server);
                broadcastState(server);
            }
        }
    } else if (std.mem.eql(u8, cmd, "spawn")) {
        const prefix_len = findWordOffset(line, "spawn");
        if (prefix_len < line.len) {
            core.spawn(std.mem.trimStart(u8, line[prefix_len..], " \t"));
        }
    } else if (std.mem.eql(u8, cmd, "layout")) {
        layout.toggleLayout(server);
        broadcastState(server);
    } else if (std.mem.eql(u8, cmd, "launcher")) {
        const off = findWordOffset(line, "launcher");
        const arg = std.mem.trim(u8, line[off..], " \t");
        if (arg.len > 0) {
            broadcastEventArg(server, "launcher", arg);
        } else {
            broadcastEvent(server, "launcher");
        }
    } else if (std.mem.eql(u8, cmd, "quit")) {
        c.wl_display_terminate(server.display);
    }
}

fn findWordOffset(line: []const u8, word: []const u8) usize {
    if (std.mem.indexOf(u8, line, word)) |idx| {
        const after = idx + word.len;
        if (after < line.len and (line[after] == ' ' or line[after] == '\t')) return after;
    }
    return line.len;
}

fn append(buf: []u8, off: *usize, comptime fmt: []const u8, args: anytype) void {
    if (off.* >= buf.len) return;
    const s = std.fmt.bufPrint(buf[off.*..], fmt, args) catch return;
    off.* += s.len;
}

fn escape(dest: []u8, src: []const u8) []const u8 {
    var j: usize = 0;
    for (src) |ch| {
        if (j + 2 >= dest.len) break;
        switch (ch) {
            '\\' => {
                dest[j] = '\\';
                dest[j + 1] = '\\';
                j += 2;
            },
            '\n' => {
                dest[j] = '\\';
                dest[j + 1] = 'n';
                j += 2;
            },
            '\r' => {
                dest[j] = '\\';
                dest[j + 1] = 'r';
                j += 2;
            },
            '\t' => {
                dest[j] = '\\';
                dest[j + 1] = 't';
                j += 2;
            },
            else => {
                dest[j] = ch;
                j += 1;
            },
        }
    }
    return dest[0..j];
}

fn buildState(server: *Server, buf: []u8) usize {
    var off: usize = 0;
    append(buf, &off, "STATE\n", .{});
    append(buf, &off, "ACTIVE {d}\n", .{server.active_ws});

    var ws: usize = 1;
    while (ws <= types.WS_COUNT) : (ws += 1) {
        var count: usize = 0;
        var i: usize = 0;
        while (i < server.clients.len) : (i += 1) {
            const cl = server.clients[i] orelse continue;
            if (cl.mapped and cl.ws == ws) count += 1;
        }
        append(buf, &off, "OCC {d} {d}\n", .{ ws, count });
    }

    const focused_id: u64 = if (server.focused) |f| f.id else 0;
    append(buf, &off, "FOCUSED {d}\n", .{focused_id});

    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (!cl.mapped) continue;

        var app_buf: [512]u8 = undefined;
        var title_buf: [1024]u8 = undefined;
        const app = escape(&app_buf, cl.app_id[0..cl.app_id_len]);
        const title = escape(&title_buf, cl.title[0..cl.title_len]);

        append(buf, &off, "WIN\t{d}\t{d}\t{d}\t{d}\t{d}\t{s}\t{s}\n", .{
            cl.id,
            cl.ws,
            @as(u8, if (server.focused == cl) 1 else 0),
            @as(u8, if (cl.floating) 1 else 0),
            @as(u8, if (cl.fullscreen) 1 else 0),
            app,
            title,
        });
        if (off > buf.len - 2048) break;
    }

    append(buf, &off, "END\n", .{});
    return off;
}

pub fn broadcastState(server: *Server) void {
    server.ipc_dirty = false;
    if (server.ipc_count == 0) return;

    var buf: [65536]u8 = undefined;
    const len = buildState(server, &buf);
    var i: usize = 0;
    while (i < server.ipcs.len) : (i += 1) {
        const cl = server.ipcs[i] orelse continue;
        sendRaw(cl, buf[0..len]);
    }
}

fn sendState(server: *Server, cl: *IpcClient) void {
    var buf: [65536]u8 = undefined;
    const len = buildState(server, &buf);
    sendRaw(cl, buf[0..len]);
}

fn sendRaw(cl: *IpcClient, data: []const u8) void {
    if (!cl.alive) return;
    const n = c.send(cl.fd, data.ptr, data.len, c.MSG_NOSIGNAL);
    if (n < 0) {
        closeClient(cl);
    }
}

pub fn broadcastEvent(server: *Server, name: []const u8) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "EVENT {s}\n", .{name}) catch return;
    var i: usize = 0;
    while (i < server.ipcs.len) : (i += 1) {
        const cl = server.ipcs[i] orelse continue;
        sendRaw(cl, msg);
    }
}

pub fn broadcastEventArg(server: *Server, name: []const u8, arg: []const u8) void {
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "EVENT {s} {s}\n", .{ name, arg }) catch return;
    var i: usize = 0;
    while (i < server.ipcs.len) : (i += 1) {
        const cl = server.ipcs[i] orelse continue;
        sendRaw(cl, msg);
    }
}
