const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const effects = @import("effects.zig");
const window_effects = @import("window_effects.zig");
const json_snapshot = @import("json_snapshot.zig");
const modes = @import("modes.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");

const Server = types.Server;
const IpcClient = types.IpcClient;
const Client = types.Client;

pub fn init(server: *Server) void {
    server.ipc_fd = -1;
    server.schedule_ipc = schedule;
    server.broadcast_line = broadcastLine;

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
        cl.wants_state = false;
        cl.wants_events = false;

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

        core.logInfo("ipc: client connected", .{});
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

    // Read queued data before honoring a half-close. A one-shot CLI may send a
    // command and close immediately, which sets POLLHUP on the same wakeup.
    if ((mask & 0x10) != 0 and cl.alive) closeClient(cl);
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

fn removeStatus(server: *Server, index: usize) void {
    if (index >= server.status_count) return;
    var i = index;
    while (i + 1 < server.status_count) : (i += 1) {
        server.statuses[i] = server.statuses[i + 1];
    }
    server.status_count -= 1;
}

fn setStatus(server: *Server, id: []const u8, text: []const u8, command: []const u8) void {
    if (id.len == 0) return;

    var found: ?usize = null;
    var i: usize = 0;
    while (i < server.status_count) : (i += 1) {
        if (std.mem.eql(u8, server.statuses[i].id[0..server.statuses[i].id_len], id)) {
            found = i;
            break;
        }
    }

    if (text.len == 0) {
        if (found) |index| {
            removeStatus(server, index);
            core.markDirty(server);
        }
        return;
    }

    var index: usize = undefined;
    if (found) |existing| {
        index = existing;
    } else {
        if (server.status_count >= server.statuses.len) removeStatus(server, 0);
        index = server.status_count;
        server.status_count += 1;
    }

    const entry = &server.statuses[index];
    core.copyString(&entry.id, &entry.id_len, id);
    core.copyString(&entry.text, &entry.text_len, text);
    core.copyString(&entry.command, &entry.command_len, command);
    core.markDirty(server);
}

pub fn emitLauncher(server: *Server, query: []const u8) void {
    const output = if (core.focusOutput(server)) |out| core.outputName(out) else "";
    events.emit(server, .{
        .name = event_names.launcher,
        .arg = query,
        .output = output,
    });
}

pub fn emitPanel(server: *Server, name: []const u8, output_name: []const u8) void {
    const output = if (output_name.len > 0)
        output_name
    else if (core.focusOutput(server)) |out|
        core.outputName(out)
    else
        "";
    events.emit(server, .{
        .name = event_names.panel,
        .arg = name,
        .output = output,
    });
}

fn handleTabCommand(cl: *IpcClient, line: []const u8) bool {
    var fields: [5][]const u8 = undefined;
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= line.len and count < fields.len) : (i += 1) {
        if (i == line.len or line[i] == '\t') {
            fields[count] = line[start..i];
            count += 1;
            start = i + 1;
        }
    }
    if (count == 0) return false;
    if (std.mem.eql(u8, fields[0], "status")) {
        const id = if (count > 1) fields[1] else "";
        const text = if (count > 2) fields[2] else "";
        const command = if (count > 3) fields[3] else "";
        setStatus(cl.server, id, text, command);
        return true;
    }
    return false;
}

fn handleJsonRpc(cl: *IpcClient, line: []const u8) void {
    const server = cl.server;
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const parsed = std.json.parseFromSliceLeaky(
        std.json.Value,
        arena.allocator(),
        line,
        .{ .allocate = .alloc_always },
    ) catch {
        sendJsonError(cl, "", -32700, "parse error");
        return;
    };
    const obj = switch (parsed) {
        .object => |map| map,
        else => {
            sendJsonError(cl, "", -32600, "request must be an object");
            return;
        },
    };

    var id_buf: [256]u8 = undefined;
    var id_off: usize = 0;
    if (obj.get("id")) |id_value| {
        if (!serializeJsonId(&id_buf, &id_off, id_value)) {
            sendJsonError(cl, "", -32600, "id must be a string, integer, or null");
            return;
        }
    } else {
        @memcpy(id_buf[0..4], "null");
        id_off = 4;
    }
    const id_text = id_buf[0..id_off];

    const method_value = obj.get("method") orelse {
        sendJsonError(cl, id_text, -32600, "missing method");
        return;
    };
    const method = switch (method_value) {
        .string => |name| name,
        else => {
            sendJsonError(cl, id_text, -32600, "method must be a string");
            return;
        },
    };

    if (std.mem.eql(u8, method, "hello") or std.mem.eql(u8, method, "capabilities")) {
        sendJsonResult(
            cl,
            id_text,
            "{\"protocol\":\"tessa-jsonrpc\",\"version\":1,\"line_protocol\":1," ++
                "\"capabilities\":[\"state\",\"config\",\"events\",\"subscriptions\",\"request-ids\"]}",
        );
    } else if (std.mem.eql(u8, method, "ping")) {
        sendJsonResult(cl, id_text, "{\"pong\":true}");
    } else if (std.mem.eql(u8, method, "state")) {
        var result_buf: [131072]u8 = undefined;
        const len = json_snapshot.buildState(server, &result_buf);
        sendJsonResult(cl, id_text, result_buf[0..len]);
    } else if (std.mem.eql(u8, method, "config")) {
        var result_buf: [131072]u8 = undefined;
        const len = json_snapshot.buildConfig(server, &result_buf);
        sendJsonResult(cl, id_text, result_buf[0..len]);
    } else if (std.mem.eql(u8, method, "subscribe")) {
        if (id_text.len > cl.rpc_subscription.len) {
            sendJsonError(cl, id_text, -32600, "subscription id is too long");
            return;
        }
        cl.wants_events = true;
        cl.json_events = true;
        cl.rpc_subscription_len = id_text.len;
        @memcpy(cl.rpc_subscription[0..id_text.len], id_text);
        sendJsonResult(cl, id_text, "{\"subscribed\":true,\"topic\":\"events\"}");
    } else if (std.mem.eql(u8, method, "unsubscribe")) {
        cl.wants_events = false;
        cl.json_events = false;
        cl.rpc_subscription_len = 0;
        sendJsonResult(cl, id_text, "{\"subscribed\":false}");
    } else {
        sendJsonError(cl, id_text, -32601, "method not found");
    }
}

fn handleCommand(cl: *IpcClient, line: []const u8) void {
    const server = cl.server;
    if (line.len > 0 and line[0] == '{') {
        handleJsonRpc(cl, line);
        return;
    }
    if (std.mem.startsWith(u8, line, "CMD\t")) {
        if (handleTabCommand(cl, line[4..])) return;
        core.logInfo("ipc: unknown tab command", .{});
        return;
    }

    var toks: [8][]const u8 = undefined;
    const n = tokens(line, &toks);
    if (n == 0) return;

    var start: usize = 0;
    if (std.mem.eql(u8, toks[0], "CMD")) start = 1;
    if (start >= n) return;
    const cmd = toks[start];

    if (std.mem.eql(u8, cmd, "state")) {
        sendState(server, cl);
    } else if (std.mem.eql(u8, cmd, "state-json")) {
        sendStateJson(server, cl);
    } else if (std.mem.eql(u8, cmd, "subscribe")) {
        var want_snapshot = false;
        var i = start + 1;
        while (i < n) : (i += 1) {
            if (std.mem.eql(u8, toks[i], "events")) {
                cl.wants_events = true;
            } else if (std.mem.eql(u8, toks[i], "state")) {
                cl.wants_state = true;
                want_snapshot = true;
            } else if (std.mem.eql(u8, toks[i], "all")) {
                cl.wants_state = true;
                cl.wants_events = true;
                want_snapshot = true;
            }
        }
        core.logDebug("ipc: subscription state={} events={}", .{ cl.wants_state, cl.wants_events });
        if (want_snapshot) sendState(server, cl);
    } else if (std.mem.eql(u8, cmd, "status")) {
        const off = findWordOffset(line, "status");
        const rest = std.mem.trimStart(u8, line[off..], " \t");
        if (rest.len > 0) {
            const sp = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
            const id = rest[0..sp];
            const text = std.mem.trim(u8, rest[sp..], " \t");
            setStatus(server, id, text, "");
        }
    } else if (std.mem.eql(u8, cmd, "workspace")) {
        if (start + 1 < n) {
            const ws = std.fmt.parseInt(usize, toks[start + 1], 10) catch return;
            if (start + 2 < n) {
                if (core.outputByName(server, toks[start + 2])) |out| {
                    layout.switchWorkspaceOnOutput(server, out, ws);
                }
            } else {
                layout.switchWorkspace(server, ws);
            }
            broadcastState(server);
        }
    } else if (std.mem.eql(u8, cmd, "move-workspace")) {
        if (start + 1 < n) {
            const ws = std.fmt.parseInt(usize, toks[start + 1], 10) catch return;
            layout.moveToWorkspace(server, ws);
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
            if (findClient(server, id)) |target| effects.requestClose(server, target);
        }
    } else if (std.mem.eql(u8, cmd, "urgent")) {
        if (start + 1 < n) {
            const id = std.fmt.parseInt(u64, toks[start + 1], 10) catch return;
            if (findClient(server, id)) |target| {
                var on = true;
                if (start + 2 < n) {
                    const value = toks[start + 2];
                    on = !(std.ascii.eqlIgnoreCase(value, "off") or
                        std.ascii.eqlIgnoreCase(value, "false") or
                        std.mem.eql(u8, value, "0"));
                }
                target.urgent = on;
                layout.arrangeAll(server);
                broadcastState(server);
            }
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
        const off = findWordOffset(line, "layout");
        const rest = std.mem.trim(u8, line[off..], " \t");
        var lit = std.mem.tokenizeAny(u8, rest, " \t");
        if (lit.next()) |name| {
            if (lit.next()) |output_name| {
                if (core.outputByName(server, output_name)) |out| {
                    _ = layout.setLayoutOnOutput(server, out, name);
                }
            } else {
                _ = layout.setLayout(server, name);
            }
        } else {
            layout.toggleLayout(server);
        }
        broadcastState(server);
    } else if (std.mem.eql(u8, cmd, "resize")) {
        if (start + 2 < n) {
            const dx = std.fmt.parseInt(i32, toks[start + 1], 10) catch return;
            const dy = std.fmt.parseInt(i32, toks[start + 2], 10) catch return;
            layout.keyboardResize(server, dx, dy);
            broadcastState(server);
        }
    } else if (std.mem.eql(u8, cmd, "mode")) {
        if (start + 1 < n) {
            if (!modes.set(server, toks[start + 1])) {
                core.logInfo("mode: unknown mode '{s}'", .{toks[start + 1]});
            }
        } else {
            modes.setDefault(server);
        }
        broadcastState(server);
    } else if (std.mem.eql(u8, cmd, "config")) {
        sendConfig(server, cl);
    } else if (std.mem.eql(u8, cmd, "config-json")) {
        sendConfigJson(server, cl);
    } else if (std.mem.eql(u8, cmd, "reload")) {
        if (server.reload_runtime) |reload| reload(server);
        broadcastState(server);
    } else if (std.mem.eql(u8, cmd, "launcher")) {
        const off = findWordOffset(line, "launcher");
        const arg = std.mem.trim(u8, line[off..], " \t");
        emitLauncher(server, arg);
    } else if (std.mem.eql(u8, cmd, "panel")) {
        if (start + 1 < n) {
            const name = toks[start + 1];
            if (start + 2 < n) {
                if (core.outputByName(server, toks[start + 2])) |target| {
                    emitPanel(server, name, core.outputName(target));
                }
            } else {
                emitPanel(server, name, "");
            }
        }
    } else if (std.mem.eql(u8, cmd, "notification-action")) {
        const off = findWordOffset(line, "notification-action");
        const rest = std.mem.trimStart(u8, line[off..], " \t");
        const sp = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
        const id_s = std.mem.trim(u8, rest[0..sp], " \t");
        const key = std.mem.trim(u8, rest[sp..], " \t");
        if (id_s.len > 0 and key.len > 0) {
            const id = std.fmt.parseInt(u32, id_s, 10) catch 0;
            if (id > 0) {
                var key_buf: [512]u8 = undefined;
                const escaped = escape(&key_buf, key);
                var out_buf: [640]u8 = undefined;
                const out = std.fmt.bufPrint(
                    &out_buf,
                    "EVENT\tnotification-action\tid={d}\taction={s}\n",
                    .{ id, escaped },
                ) catch return;
                broadcastLine(server, out);
            }
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
    append(buf, &off, "MODE {s}\n", .{modes.currentName(server)});
    var oi: usize = 0;
    while (oi < server.outputs.len) : (oi += 1) {
        const out = server.outputs[oi] orelse continue;
        append(buf, &off, "OUT {s} {d} {d} {s}\n", .{
            core.outputName(out),
            out.active_ws,
            @as(u8, if (server.focused_output == out) 1 else 0),
            types.layoutName(out.ws_layouts[out.active_ws - 1]),
        });
    }

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

    var si: usize = 0;
    while (si < server.status_count) : (si += 1) {
        const st = &server.statuses[si];
        var id_buf: [types.MAX_STATUS_ID * 2 + 1]u8 = undefined;
        var text_buf: [types.MAX_STATUS_TEXT * 2 + 1]u8 = undefined;
        var cmd_buf: [types.MAX_STATUS_COMMAND * 2 + 1]u8 = undefined;
        const id = escape(&id_buf, st.id[0..st.id_len]);
        const text = escape(&text_buf, st.text[0..st.text_len]);
        const command = escape(&cmd_buf, st.command[0..st.command_len]);
        append(buf, &off, "STATUS\t{s}\t{s}\t{s}\n", .{ id, text, command });
    }

    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (!cl.mapped) continue;

        var app_buf: [512]u8 = undefined;
        var title_buf: [1024]u8 = undefined;
        const app = escape(&app_buf, cl.app_id[0..cl.app_id_len]);
        const title = escape(&title_buf, cl.title[0..cl.title_len]);

        append(buf, &off, "WIN\t{d}\t{d}\t{d}\t{d}\t{d}\t{s}\t{s}\t{s}\t{d}\t{d}\t{d}\t{d}\n", .{
            cl.id,
            cl.ws,
            @as(u8, if (server.focused == cl) 1 else 0),
            @as(u8, if (cl.floating) 1 else 0),
            @as(u8, if (cl.fullscreen) 1 else 0),
            app,
            title,
            core.outputName(cl.output),
            cl.x,
            cl.y,
            cl.w,
            cl.h,
        });
        if (off > buf.len - 2048) break;
    }

    i = 0;
    while (i < server.layers.len) : (i += 1) {
        const layer = server.layers[i] orelse continue;
        if (!layer.mapped) continue;
        const layer_n: u32 = @intCast(layer.wlr.current.layer);
        const blur = switch (layer.blur) {
            .on => true,
            .off => false,
            .unset => server.config.blur and layer_n >= 2,
        };
        var ns_buf: [512]u8 = undefined;
        const ns = escape(&ns_buf, core.cstr(layer.wlr.namespace));
        append(buf, &off, "LAYER\t{s}\t{s}\t{d}\t{d:.3}\t{d}\t{d}\n", .{
            ns,
            core.outputName(layer.output),
            layer_n,
            layer.opacity,
            layer.corner_radius,
            @as(u8, if (blur) 1 else 0),
        });
        if (off > buf.len - 1024) break;
    }

    append(buf, &off, "END\n", .{});
    return off;
}

fn sendConfig(server: *Server, cl: *IpcClient) void {
    var buf: [65536]u8 = undefined;
    var off: usize = 0;
    const cfg = &server.config;
    append(&buf, &off, "CONFIG\n", .{});
    append(&buf, &off, "terminal {s}\n", .{cfg.terminal[0..cfg.terminal_len]});
    append(&buf, &off, "gaps {d}\n", .{cfg.gaps});
    append(&buf, &off, "outer_gaps {d}\n", .{cfg.outer_gaps});
    append(&buf, &off, "border_width {d}\n", .{cfg.border_width});
    append(&buf, &off, "border_active {s}\n", .{cfg.border_active[0..cfg.border_active_len]});
    append(&buf, &off, "border_inactive {s}\n", .{cfg.border_inactive[0..cfg.border_inactive_len]});
    append(&buf, &off, "master_ratio {d:.3}\n", .{cfg.master_ratio});
    append(&buf, &off, "master_count {d}\n", .{cfg.master_count});
    append(&buf, &off, "mosaic_ratio {d:.3}\n", .{cfg.mosaic_ratio});
    append(&buf, &off, "mosaic_min_size {d}\n", .{cfg.mosaic_min_size});
    append(&buf, &off, "grid_columns {d}\n", .{cfg.grid_columns});
    append(&buf, &off, "layout_helper {s}\n", .{cfg.layout_helper[0..cfg.layout_helper_len]});
    append(&buf, &off, "layout_helper_timeout {d}\n", .{cfg.layout_helper_timeout});
    append(&buf, &off, "layout {s}\n", .{types.layoutName(cfg.layout_mode)});
    var ws: usize = 0;
    while (ws < types.WS_COUNT) : (ws += 1) {
        append(&buf, &off, "layout_ws {d} {s}\n", .{ ws + 1, types.layoutName(cfg.layout_by_ws[ws]) });
        append(&buf, &off, "workspace_tuning {d} {d} {d} {d:.3}\n", .{
            ws + 1,
            cfg.ws_gaps[ws],
            cfg.ws_outer_gaps[ws],
            cfg.ws_master_ratio[ws],
        });
    }
    var pi: usize = 0;
    while (pi < cfg.workspace_pin_count) : (pi += 1) {
        const pin = &cfg.workspace_pins[pi];
        append(&buf, &off, "workspace_pin {s} {d}\n", .{ pin.output_name[0..pin.output_len], pin.ws });
    }
    append(&buf, &off, "active_mode {s}\n", .{modes.currentName(server)});
    var mi: usize = 0;
    while (mi < cfg.mode_count) : (mi += 1) {
        append(&buf, &off, "mode {s}\n", .{cfg.mode_names[mi][0..cfg.mode_name_lens[mi]]});
    }
    append(&buf, &off, "panel {d}\n", .{@as(u8, if (cfg.autostart_panel) 1 else 0)});
    append(&buf, &off, "xwayland {d}\n", .{@as(u8, if (cfg.xwayland) 1 else 0)});
    append(&buf, &off, "xwayland_display {s}\n", .{cfg.xwayland_display[0..cfg.xwayland_display_len]});
    append(&buf, &off, "animations {d}\n", .{@as(u8, if (cfg.animations) 1 else 0)});
    append(&buf, &off, "animation_ms {d}\n", .{cfg.animation_ms});
    append(&buf, &off, "animation_open_ms {d}\n", .{
        if (cfg.animation_open_ms >= 0) cfg.animation_open_ms else cfg.animation_ms,
    });
    append(&buf, &off, "animation_workspace_ms {d}\n", .{
        if (cfg.animation_workspace_ms >= 0) cfg.animation_workspace_ms else cfg.animation_ms,
    });
    append(&buf, &off, "animation_close_ms {d}\n", .{
        if (cfg.animation_close_ms >= 0) cfg.animation_close_ms else cfg.animation_ms,
    });
    append(&buf, &off, "animation_curve {s}\n", .{cfg.animation_curve[0..cfg.animation_curve_len]});
    append(&buf, &off, "animation_open_curve {s}\n", .{cfg.animation_open_curve[0..cfg.animation_open_curve_len]});
    append(&buf, &off, "animation_workspace_curve {s}\n", .{cfg.animation_workspace_curve[0..cfg.animation_workspace_curve_len]});
    append(&buf, &off, "animation_close_curve {s}\n", .{cfg.animation_close_curve[0..cfg.animation_close_curve_len]});
    append(&buf, &off, "animation_open_x {d}\n", .{cfg.animation_open_x});
    append(&buf, &off, "animation_open_y {d}\n", .{cfg.animation_open_y});
    append(&buf, &off, "animation_workspace_offset {d}\n", .{cfg.animation_workspace_offset});
    append(&buf, &off, "animation_close_scale {d:.3}\n", .{cfg.animation_close_scale});
    append(&buf, &off, "animation_close_fade {d}\n", .{@as(u8, if (cfg.animation_close_fade) 1 else 0)});
    append(&buf, &off, "curve_count {d}\n", .{cfg.curve_count});
    var ci: usize = 0;
    while (ci < cfg.curve_count) : (ci += 1) {
        const curve = &cfg.curves[ci];
        switch (curve.curve.kind) {
            .bezier => append(&buf, &off, "bezier {s} {d:.3} {d:.3} {d:.3} {d:.3}\n", .{
                curve.name[0..curve.name_len],
                curve.curve.points[0],
                curve.curve.points[1],
                curve.curve.points[2],
                curve.curve.points[3],
            }),
            .spring => append(&buf, &off, "spring {s} {d:.3} {d:.3}\n", .{
                curve.name[0..curve.name_len],
                curve.curve.damping,
                curve.curve.frequency,
            }),
        }
    }
    append(&buf, &off, "reduce_motion {d}\n", .{@as(u8, if (cfg.reduce_motion) 1 else 0)});
    append(&buf, &off, "reduce_motion_animations {s}\n", .{switch (cfg.reduce_motion_animations) {
        .none => "none",
        .fade => "fade",
    }});
    append(&buf, &off, "reduce_motion_fade_ms {d}\n", .{cfg.reduce_motion_fade_ms});
    append(&buf, &off, "theme_role_count {d}\n", .{cfg.theme_role_count});
    var tri: usize = 0;
    while (tri < cfg.theme_role_count) : (tri += 1) {
        const role = &cfg.theme_roles[tri];
        append(&buf, &off, "theme_role {s} {s}\n", .{
            role.name[0..role.name_len],
            role.color[0..role.color_len],
        });
    }
    append(&buf, &off, "shadows {d}\n", .{@as(u8, if (cfg.shadows) 1 else 0)});
    append(&buf, &off, "scenefx {d}\n", .{@as(u8, if (window_effects.available()) 1 else 0)});
    append(&buf, &off, "corner_radius {d}\n", .{cfg.corner_radius});
    append(&buf, &off, "blur {d}\n", .{@as(u8, if (cfg.blur) 1 else 0)});
    append(&buf, &off, "blur_radius {d}\n", .{cfg.blur_radius});
    append(&buf, &off, "blur_passes {d}\n", .{cfg.blur_passes});
    append(&buf, &off, "gestures {d}\n", .{@as(u8, if (cfg.gestures) 1 else 0)});
    append(&buf, &off, "gesture_fingers {d}\n", .{cfg.gesture_fingers});
    append(&buf, &off, "gesture_workspace_threshold {d}\n", .{cfg.gesture_workspace_threshold});
    append(&buf, &off, "gesture_launcher_threshold {d}\n", .{cfg.gesture_launcher_threshold});
    append(&buf, &off, "touch {d}\n", .{@as(u8, if (cfg.touch) 1 else 0)});
    append(&buf, &off, "tablet {d}\n", .{@as(u8, if (cfg.tablet) 1 else 0)});
    append(&buf, &off, "pointer_constraints {d}\n", .{@as(u8, if (cfg.pointer_constraints) 1 else 0)});
    append(&buf, &off, "xim {d}\n", .{@as(u8, if (cfg.xim) 1 else 0)});
    append(&buf, &off, "xim_server {s}\n", .{cfg.xim_server[0..cfg.xim_server_len]});
    append(&buf, &off, "xim_start {s}\n", .{cfg.xim_start[0..cfg.xim_start_len]});
    append(&buf, &off, "kb_layout {s}\n", .{cfg.kb_layout[0..cfg.kb_layout_len]});
    append(&buf, &off, "kb_variant {s}\n", .{cfg.kb_variant[0..cfg.kb_variant_len]});
    append(&buf, &off, "kb_options {s}\n", .{cfg.kb_options[0..cfg.kb_options_len]});
    append(&buf, &off, "kb_model {s}\n", .{cfg.kb_model[0..cfg.kb_model_len]});
    append(&buf, &off, "kb_rules {s}\n", .{cfg.kb_rules[0..cfg.kb_rules_len]});
    append(&buf, &off, "repeat_rate {d}\n", .{cfg.repeat_rate});
    append(&buf, &off, "repeat_delay {d}\n", .{cfg.repeat_delay});
    append(&buf, &off, "font {s}\n", .{cfg.font[0..cfg.font_len]});
    append(&buf, &off, "accent {s}\n", .{cfg.accent[0..cfg.accent_len]});
    append(&buf, &off, "bg {s}\n", .{cfg.bg[0..cfg.bg_len]});
    append(&buf, &off, "output_config {s}\n", .{cfg.output_config[0..cfg.output_config_len]});
    append(&buf, &off, "binding_count {d}\n", .{cfg.binding_count});
    append(&buf, &off, "hook_count {d}\n", .{cfg.hook_count});
    append(&buf, &off, "event_rule_count {d}\n", .{cfg.event_rule_count});
    append(&buf, &off, "profile_count {d}\n", .{cfg.profile_count});
    append(&buf, &off, "workspace_rule_count {d}\n", .{cfg.workspace_rule_count});
    append(&buf, &off, "rule_count {d}\n", .{cfg.rule_count});
    append(&buf, &off, "output_rule_count {d}\n", .{cfg.output_rule_count});
    var hi: usize = 0;
    while (hi < cfg.hook_count) : (hi += 1) {
        const hook = &cfg.hooks[hi];
        var command_buf: [types.MAX_COMMAND * 2 + 1]u8 = undefined;
        const command = escape(&command_buf, hook.command[0..hook.command_len]);
        append(&buf, &off, "hook {s} {s}\n", .{ hook.event[0..hook.event_len], command });
    }
    var eri: usize = 0;
    while (eri < cfg.event_rule_count) : (eri += 1) {
        const rule = &cfg.event_rules[eri];
        var expr_buf: [types.MAX_COMMAND * 2 + 1]u8 = undefined;
        var command_buf: [types.MAX_COMMAND * 2 + 1]u8 = undefined;
        const expr_text = escape(&expr_buf, rule.expr[0..rule.expr_len]);
        const command_text = escape(&command_buf, rule.command[0..rule.command_len]);
        append(&buf, &off, "event_rule {s} {s} {s}\n", .{
            rule.event[0..rule.event_len],
            expr_text,
            command_text,
        });
    }
    var profi: usize = 0;
    while (profi < cfg.profile_count) : (profi += 1) {
        const profile = &cfg.profiles[profi];
        append(&buf, &off, "profile {s} {s} {d} {d} {d:.3} {d} {d:.3} {d} {d}\n", .{
            profile.name[0..profile.name_len],
            types.layoutName(profile.tuning.layout),
            profile.tuning.gaps,
            profile.tuning.outer_gaps,
            profile.tuning.master_ratio,
            profile.tuning.master_count,
            profile.tuning.mosaic_ratio,
            profile.tuning.mosaic_min_size,
            profile.tuning.grid_columns,
        });
    }
    var i: usize = 0;
    while (i < cfg.rule_count) : (i += 1) {
        const rule = &cfg.rules[i];
        var raw_buf: [types.MAX_COMMAND * 2 + 1]u8 = undefined;
        const raw = escape(&raw_buf, rule.raw[0..rule.raw_len]);
        append(&buf, &off, "rule {s}\n", .{raw});
    }
    i = 0;
    while (i < cfg.output_rule_count) : (i += 1) {
        const rule = &cfg.output_rules[i];
        var raw_buf: [types.MAX_COMMAND * 2 + 1]u8 = undefined;
        const raw = escape(&raw_buf, rule.raw[0..rule.raw_len]);
        append(&buf, &off, "output_rule {s}\n", .{raw});
    }
    i = 0;
    while (i < cfg.layer_rule_count) : (i += 1) {
        const rule = &cfg.layer_rules[i];
        var raw_buf: [types.MAX_COMMAND * 2 + 1]u8 = undefined;
        const raw = escape(&raw_buf, rule.raw[0..rule.raw_len]);
        append(&buf, &off, "layer_rule {s}\n", .{raw});
    }
    i = 0;
    while (i < server.config_issue_count) : (i += 1) {
        const issue = &server.config_issues[i];
        append(&buf, &off, "diagnostic {s} {s}:{d}: {s}\n", .{
            if (issue.is_error) "error" else "warning",
            issue.path[0..issue.path_len],
            issue.line,
            issue.message[0..issue.message_len],
        });
    }
    append(&buf, &off, "END\n", .{});
    sendRaw(cl, buf[0..off]);
}

pub fn broadcastState(server: *Server) void {
    server.ipc_dirty = false;
    if (server.ipc_count == 0) return;

    var buf: [65536]u8 = undefined;
    const len = buildState(server, &buf);
    var i: usize = 0;
    while (i < server.ipcs.len) : (i += 1) {
        const cl = server.ipcs[i] orelse continue;
        if (!cl.wants_state) continue;
        sendRaw(cl, buf[0..len]);
    }
}

fn sendState(server: *Server, cl: *IpcClient) void {
    var buf: [65536]u8 = undefined;
    const len = buildState(server, &buf);
    sendRaw(cl, buf[0..len]);
}

fn sendStateJson(server: *Server, cl: *IpcClient) void {
    var buf: [131072]u8 = undefined;
    const len = json_snapshot.buildState(server, &buf);
    sendRaw(cl, "STATE_JSON\n");
    sendRaw(cl, buf[0..len]);
    sendRaw(cl, "\nEND\n");
}

fn sendConfigJson(server: *Server, cl: *IpcClient) void {
    var buf: [131072]u8 = undefined;
    const len = json_snapshot.buildConfig(server, &buf);
    sendRaw(cl, "CONFIG_JSON\n");
    sendRaw(cl, buf[0..len]);
    sendRaw(cl, "\nEND\n");
}

fn sendRaw(cl: *IpcClient, data: []const u8) void {
    if (!cl.alive) return;
    var sent: usize = 0;
    while (sent < data.len) {
        const n = c.send(cl.fd, data.ptr + sent, data.len - sent, c.MSG_NOSIGNAL);
        if (n <= 0) {
            closeClient(cl);
            return;
        }
        sent += @intCast(n);
    }
}

fn appendJsonString(buf: []u8, off: *usize, value: []const u8) bool {
    const hex = "0123456789abcdef";
    if (off.* + 1 > buf.len) return false;
    buf[off.*] = '"';
    off.* += 1;
    for (value) |ch| {
        switch (ch) {
            '"' => {
                if (off.* + 2 > buf.len) return false;
                buf[off.*] = '\\';
                buf[off.* + 1] = '"';
                off.* += 2;
            },
            '\\' => {
                if (off.* + 2 > buf.len) return false;
                buf[off.*] = '\\';
                buf[off.* + 1] = '\\';
                off.* += 2;
            },
            '\n' => {
                if (off.* + 2 > buf.len) return false;
                buf[off.*] = '\\';
                buf[off.* + 1] = 'n';
                off.* += 2;
            },
            '\r' => {
                if (off.* + 2 > buf.len) return false;
                buf[off.*] = '\\';
                buf[off.* + 1] = 'r';
                off.* += 2;
            },
            '\t' => {
                if (off.* + 2 > buf.len) return false;
                buf[off.*] = '\\';
                buf[off.* + 1] = 't';
                off.* += 2;
            },
            else => {
                if (ch < 0x20) {
                    if (off.* + 6 > buf.len) return false;
                    buf[off.*] = '\\';
                    buf[off.* + 1] = 'u';
                    buf[off.* + 2] = '0';
                    buf[off.* + 3] = '0';
                    buf[off.* + 4] = hex[ch >> 4];
                    buf[off.* + 5] = hex[ch & 0xf];
                    off.* += 6;
                } else {
                    if (off.* + 1 > buf.len) return false;
                    buf[off.*] = ch;
                    off.* += 1;
                }
            },
        }
    }
    if (off.* + 1 > buf.len) return false;
    buf[off.*] = '"';
    off.* += 1;
    return true;
}

fn serializeJsonId(buf: []u8, off: *usize, value: std.json.Value) bool {
    switch (value) {
        .integer => |v| {
            const text = std.fmt.bufPrint(buf[off.*..], "{d}", .{v}) catch return false;
            off.* += text.len;
            return true;
        },
        .string => |v| return appendJsonString(buf, off, v),
        .null => {
            if (off.* + 4 > buf.len) return false;
            @memcpy(buf[off.* .. off.* + 4], "null");
            off.* += 4;
            return true;
        },
        else => return false,
    }
}

fn sendJsonError(cl: *IpcClient, id_text: []const u8, code: i32, message: []const u8) void {
    var buf: [512]u8 = undefined;
    var off: usize = 0;
    const h = "{\"jsonrpc\":\"2.0\",\"id\":";
    @memcpy(buf[off .. off + h.len], h);
    off += h.len;
    const id = if (id_text.len > 0) id_text else "null";
    @memcpy(buf[off .. off + id.len], id);
    off += id.len;
    const mid = ",\"error\":{\"code\":";
    @memcpy(buf[off .. off + mid.len], mid);
    off += mid.len;
    const ctext = std.fmt.bufPrint(buf[off..], "{d}", .{code}) catch return;
    off += ctext.len;
    const mid2 = ",\"message\":";
    @memcpy(buf[off .. off + mid2.len], mid2);
    off += mid2.len;
    if (!appendJsonString(&buf, &off, message)) return;
    const tail = "}}\n";
    @memcpy(buf[off .. off + tail.len], tail);
    off += tail.len;
    sendRaw(cl, buf[0..off]);
}

fn sendJsonResult(cl: *IpcClient, id_text: []const u8, result: []const u8) void {
    sendRaw(cl, "{\"jsonrpc\":\"2.0\",\"id\":");
    sendRaw(cl, id_text);
    sendRaw(cl, ",\"result\":");
    sendRaw(cl, result);
    sendRaw(cl, "}\n");
}

fn decodeEventValue(dest: []u8, src: []const u8) []const u8 {
    var out: usize = 0;
    var i: usize = 0;
    while (i < src.len and out < dest.len) {
        if (src[i] == '\\' and i + 1 < src.len) {
            const ch = switch (src[i + 1]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                else => src[i + 1],
            };
            dest[out] = ch;
            out += 1;
            i += 2;
        } else {
            dest[out] = src[i];
            out += 1;
            i += 1;
        }
    }
    return dest[0..out];
}

fn sendJsonEvent(cl: *IpcClient, line: []const u8) void {
    var fields: [16][]const u8 = undefined;
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, line, '\t');
    while (it.next()) |field| {
        if (count < fields.len) {
            fields[count] = field;
            count += 1;
        }
    }
    if (count < 2 or !std.mem.eql(u8, fields[0], "EVENT")) return;

    var buf: [8192]u8 = undefined;
    var off: usize = 0;
    const prefix = "{\"jsonrpc\":\"2.0\",\"method\":\"event\",\"params\":{\"name\":";
    @memcpy(buf[off .. off + prefix.len], prefix);
    off += prefix.len;
    var decoded: [1024]u8 = undefined;
    if (!appendJsonString(&buf, &off, decodeEventValue(&decoded, fields[1]))) return;

    var fi: usize = 2;
    while (fi < count) : (fi += 1) {
        const field = fields[fi];
        const eq = std.mem.indexOfScalar(u8, field, '=') orelse continue;
        const key = field[0..eq];
        const value = field[eq + 1 ..];
        if (off + key.len + 4 > buf.len) return;
        buf[off] = ',';
        off += 1;
        if (!appendJsonString(&buf, &off, key)) return;
        buf[off] = ':';
        off += 1;

        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "previous") or
            std.mem.eql(u8, key, "ws") or std.mem.eql(u8, key, "previous-ws"))
        {
            if (off + value.len > buf.len) return;
            @memcpy(buf[off .. off + value.len], value);
            off += value.len;
        } else if (!appendJsonString(&buf, &off, decodeEventValue(&decoded, value))) {
            return;
        }
    }

    if (cl.rpc_subscription_len > 0) {
        const sub_prefix = ",\"subscription\":";
        if (off + sub_prefix.len + cl.rpc_subscription_len > buf.len) return;
        @memcpy(buf[off .. off + sub_prefix.len], sub_prefix);
        off += sub_prefix.len;
        @memcpy(buf[off .. off + cl.rpc_subscription_len], cl.rpc_subscription[0..cl.rpc_subscription_len]);
        off += cl.rpc_subscription_len;
    }
    if (off + 3 > buf.len) return;
    @memcpy(buf[off .. off + 3], "}}\n");
    off += 3;
    sendRaw(cl, buf[0..off]);
}

pub fn broadcastLine(server: *Server, line: []const u8) void {
    var i: usize = 0;
    while (i < server.ipcs.len) : (i += 1) {
        const cl = server.ipcs[i] orelse continue;
        if (!cl.wants_events) continue;
        core.logDebug("ipc: event to client fd={d}", .{cl.fd});
        if (cl.json_events) {
            sendJsonEvent(cl, line);
        } else {
            sendRaw(cl, line);
        }
    }
}
