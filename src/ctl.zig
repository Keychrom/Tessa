const std = @import("std");

const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/un.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
});

const MAX_SOCKET_PATH = 100;

fn usage() void {
    writeAll(1, "usage: tessa-ctl <command>\n" ++
        "\n" ++
        "  state [--json]                print one state snapshot\n" ++
        "  config [--json]               print the effective configuration\n" ++
        "  config-check                  check config diagnostics; exit 1 on errors\n" ++
        "  config-check <file>           validate a candidate config file\n" ++
        "  config-diff <file>            preview effective changes from a candidate\n" ++
        "  config-edit [file]            edit, validate, diff, and apply config\n" ++
        "  perf [--json] [--reset]       print frame-time statistics\n" ++
        "  events [topic]                stream extension events (default: all)\n" ++
        "  rpc <json>                    send one JSON-RPC request and print the reply\n" ++
        "  dispatch <compositor command> send a raw command, adding CMD\n" ++
        "  workspace <1-9|name> [output] switch workspace\n" ++
        "  special <name>                toggle a named special workspace\n" ++
        "  move-to-special <name>        move the focused window to a special workspace\n" ++
        "  spawn <command...>            start a command\n" ++
        "  launcher [query...]           open the launcher\n" ++
        "  panel <calendar|power|clipboard|screenshot|media|tray|audio> [out]\n" ++
        "                                open a panel popover\n" ++
        "  notify-action <id> <key>      invoke a notification action\n" ++
        "  layout [name] [output]       cycle or set a workspace layout\n" ++
        "  mode [name]                  switch input mode (default: default)\n" ++
        "  resize <dx> <dy>              resize the focused floating window\n" ++
        "  status <id> <text>            set a bar status entry\n" ++
        "  status <id> --clear           remove a bar status entry\n" ++
        "  status <id> <text> --exec <command...>\n" ++
        "                                set a clickable bar status\n" ++
        "  quit                          stop the compositor\n" ++
        "\n" ++
        "The socket is $TESSA_IPC, or $XDG_RUNTIME_DIR/tessa.sock.\n");
}

fn writeAll(fd: c_int, data: []const u8) void {
    var sent: usize = 0;
    while (sent < data.len) {
        const n = c.write(fd, data.ptr + sent, data.len - sent);
        if (n <= 0) return;
        sent += @intCast(n);
    }
}

fn writeLine(data: []const u8) void {
    writeAll(1, data);
    writeAll(1, "\n");
}

fn socketPath(buf: []u8) ![]const u8 {
    var path: []const u8 = "";
    if (c.getenv("TESSA_IPC")) |p| {
        path = std.mem.span(p);
    } else if (c.getenv("XDG_RUNTIME_DIR")) |p| {
        path = std.fmt.bufPrint(buf, "{s}/tessa.sock", .{std.mem.span(p)}) catch return error.PathTooLong;
    }
    if (path.len == 0) return error.NoSocket;
    if (path.len >= MAX_SOCKET_PATH or path.len >= buf.len) return error.PathTooLong;
    return path;
}

fn connectSocket() !c_int {
    var path_buf: [256]u8 = undefined;
    const path = try socketPath(&path_buf);

    const fd = c.socket(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0);
    if (fd < 0) return error.SocketFailed;

    var addr: c.sockaddr_un = std.mem.zeroes(c.sockaddr_un);
    addr.sun_family = c.AF_UNIX;
    @memcpy(addr.sun_path[0..path.len], path);
    addr.sun_path[path.len] = 0;

    const sockaddr: c.__CONST_SOCKADDR_ARG = .{ .__sockaddr_un__ = @ptrCast(&addr) };
    if (c.connect(fd, sockaddr, @intCast(@sizeOf(c.sockaddr_un))) < 0) {
        _ = c.close(fd);
        return error.ConnectFailed;
    }
    return fd;
}

fn sendAll(fd: c_int, data: []const u8) !void {
    var sent: usize = 0;
    while (sent < data.len) {
        const n = c.send(fd, data.ptr + sent, data.len - sent, c.MSG_NOSIGNAL);
        if (n <= 0) return error.SendFailed;
        sent += @intCast(n);
    }
}

const LineReader = struct {
    fd: c_int,
    buf: [262144]u8 = undefined,
    start: usize = 0,
    end: usize = 0,

    fn fill(self: *LineReader) !bool {
        if (self.start > 0) {
            const remain = self.end - self.start;
            if (remain > 0) std.mem.copyForwards(u8, self.buf[0..remain], self.buf[self.start..self.end]);
            self.start = 0;
            self.end = remain;
        }
        if (self.end >= self.buf.len) return error.LineTooLong;
        const n = c.read(self.fd, self.buf[self.end..].ptr, self.buf.len - self.end);
        if (n <= 0) return false;
        self.end += @intCast(n);
        return true;
    }

    fn next(self: *LineReader, out: []u8) !?[]const u8 {
        while (true) {
            const slice = self.buf[self.start..self.end];
            if (std.mem.indexOfScalar(u8, slice, '\n')) |nl| {
                const line = slice[0..nl];
                if (line.len > out.len) return error.LineTooLong;
                @memcpy(out[0..line.len], line);
                self.start += nl + 1;
                return out[0..line.len];
            }
            if (!(try self.fill())) {
                if (self.start >= self.end) return null;
                const line = self.buf[self.start..self.end];
                if (line.len > out.len) return error.LineTooLong;
                @memcpy(out[0..line.len], line);
                self.start = self.end;
                return out[0..line.len];
            }
        }
    }
};

fn printState() !void {
    const fd = try connectSocket();
    defer _ = c.close(fd);
    try sendAll(fd, "CMD state\n");
    var reader = LineReader{ .fd = fd };
    var line_buf: [65536]u8 = undefined;
    var in_state = false;
    while (try reader.next(&line_buf)) |line| {
        if (std.mem.eql(u8, line, "STATE")) in_state = true;
        if (in_state) writeLine(line);
        if (in_state and std.mem.eql(u8, line, "END")) return;
    }
    return error.Closed;
}

fn eventMatches(line: []const u8, filter: []const u8) bool {
    if (filter.len == 0) return true;
    if (!std.mem.startsWith(u8, line, "EVENT")) return false;
    var i: usize = 5;
    if (i < line.len and line[i] == '\t') i += 1;
    const start = i;
    while (i < line.len and line[i] != '\t' and line[i] != ' ') : (i += 1) {}
    return std.mem.eql(u8, line[start..i], filter);
}

fn printJson(command: []const u8, header: []const u8) !void {
    const fd = try connectSocket();
    defer _ = c.close(fd);
    try sendAll(fd, command);
    var reader = LineReader{ .fd = fd };
    var line_buf: [262144]u8 = undefined;
    var in_json = false;
    while (try reader.next(&line_buf)) |line| {
        if (std.mem.eql(u8, line, header)) {
            in_json = true;
            continue;
        }
        if (!in_json) continue;
        if (std.mem.eql(u8, line, "END")) return;
        writeLine(line);
    }
    return error.Closed;
}

fn printConfigCheck() !void {
    const fd = try connectSocket();
    defer _ = c.close(fd);
    try sendAll(fd, "CMD config\n");
    var reader = LineReader{ .fd = fd };
    var line_buf: [65536]u8 = undefined;
    var in_config = false;
    var diagnostics: usize = 0;
    var errors: usize = 0;
    while (try reader.next(&line_buf)) |line| {
        if (std.mem.eql(u8, line, "CONFIG")) in_config = true;
        if (in_config and std.mem.startsWith(u8, line, "diagnostic ")) {
            diagnostics += 1;
            if (std.mem.startsWith(u8, line, "diagnostic error ")) errors += 1;
            writeLine(line);
        }
        if (in_config and std.mem.eql(u8, line, "END")) {
            if (diagnostics == 0) writeLine("config: ok");
            if (errors > 0) return error.ConfigInvalid;
            return;
        }
    }
    return error.Closed;
}

fn printConfig() !void {
    const fd = try connectSocket();
    defer _ = c.close(fd);
    try sendAll(fd, "CMD config\n");
    var reader = LineReader{ .fd = fd };
    var line_buf: [65536]u8 = undefined;
    var in_config = false;
    while (try reader.next(&line_buf)) |line| {
        if (std.mem.eql(u8, line, "CONFIG")) in_config = true;
        if (in_config) writeLine(line);
        if (in_config and std.mem.eql(u8, line, "END")) return;
    }
    return error.Closed;
}

fn printEvents(filter: []const u8) !void {
    const nl = [_]u8{10};
    while (true) {
        const fd = connectSocket() catch {
            _ = c.usleep(1_000_000);
            continue;
        };
        sendAll(fd, "CMD subscribe events\n") catch {};
        var reader = LineReader{ .fd = fd };
        var line_buf: [65536]u8 = undefined;
        if (c.getenv("TESSA_CTL_DEBUG") != null) {
            writeAll(2, "tessa-ctl: event stream waiting");
            writeAll(2, &nl);
        }
        while (try reader.next(&line_buf)) |line| {
            if (c.getenv("TESSA_CTL_DEBUG") != null) {
                writeAll(2, "tessa-ctl: received ");
                writeAll(2, line);
                writeAll(2, &nl);
            }
            if (!std.mem.startsWith(u8, line, "EVENT")) continue;
            if (!eventMatches(line, filter)) continue;
            writeLine(line);
        }
        _ = c.close(fd);
        _ = c.usleep(1_000_000);
    }
}

fn sendCommand(line: []const u8) !void {
    const fd = try connectSocket();
    sendAll(fd, line) catch |err| {
        _ = c.close(fd);
        return err;
    };
    _ = c.close(fd);
}

fn joinArgs(args: []const []const u8, first: usize, buf: []u8) []const u8 {
    var out: usize = 0;
    var i = first;
    while (i < args.len) : (i += 1) {
        if (out > 0 and out < buf.len) {
            buf[out] = ' ';
            out += 1;
        }
        const n = @min(args[i].len, buf.len - out);
        @memcpy(buf[out .. out + n], args[i][0..n]);
        out += n;
        if (out >= buf.len) break;
    }
    return buf[0..out];
}

fn sanitize(dest: []u8, src: []const u8) []const u8 {
    var n = @min(src.len, dest.len - 1);
    if (n < src.len) {
        while (n > 0 and (src[n] & 0xC0) == 0x80) n -= 1;
    }
    for (src[0..n], 0..) |ch, i| {
        dest[i] = if (ch == '\t' or ch == '\n' or ch == '\r') ' ' else ch;
    }
    dest[n] = 0;
    return dest[0..n];
}

fn runStatus(args: []const []const u8) !void {
    if (args.len < 2) return error.BadArguments;
    var id_buf: [48]u8 = undefined;
    const id = sanitize(&id_buf, args[1]);
    if (id.len == 0) return error.BadArguments;

    var clear = false;
    var exec_index: ?usize = null;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--clear")) clear = true;
        if (std.mem.eql(u8, args[i], "--exec")) {
            exec_index = i;
            break;
        }
    }

    const text_end = exec_index orelse args.len;
    var text_join_buf: [1024]u8 = undefined;
    const text_join = joinArgs(args[0..text_end], 2, &text_join_buf);

    var exec_join_buf: [1024]u8 = undefined;
    const exec_join = if (exec_index) |idx| joinArgs(args, idx + 1, &exec_join_buf) else "";

    var text_buf: [160]u8 = undefined;
    var command_buf: [256]u8 = undefined;
    const text = if (clear) "" else sanitize(&text_buf, text_join);
    const command = if (clear) "" else sanitize(&command_buf, exec_join);

    var line: [1200]u8 = undefined;
    const msg = std.fmt.bufPrint(&line, "CMD\tstatus\t{s}\t{s}\t{s}\n", .{
        id, text, command,
    }) catch return error.LineTooLong;
    try sendCommand(msg);
}

fn runRpc(args: []const []const u8) !void {
    if (args.len < 2) return error.BadArguments;
    var json_buf: [8192]u8 = undefined;
    const json = joinArgs(args, 1, &json_buf);
    const fd = try connectSocket();
    defer _ = c.close(fd);
    var line_buf: [8192]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, "{s}\n", .{json}) catch return error.LineTooLong;
    try sendAll(fd, line);
    var reader = LineReader{ .fd = fd };
    var reply_buf: [131072]u8 = undefined;
    const reply = (try reader.next(&reply_buf)) orelse return error.NoReply;
    writeLine(reply);
}

fn runDispatch(args: []const []const u8) !void {
    if (args.len < 2) return error.BadArguments;
    var cmd_buf: [2048]u8 = undefined;
    const command = joinArgs(args, 1, &cmd_buf);
    var line: [2096]u8 = undefined;
    const msg = std.fmt.bufPrint(&line, "CMD {s}\n", .{command}) catch return error.LineTooLong;
    try sendCommand(msg);
}

fn runWorkspace(args: []const []const u8) !void {
    if (args.len < 2) return error.BadArguments;
    var line: [256]u8 = undefined;
    const msg = if (args.len >= 3)
        std.fmt.bufPrint(&line, "CMD workspace {s} {s}\n", .{ args[1], args[2] }) catch return error.LineTooLong
    else
        std.fmt.bufPrint(&line, "CMD workspace {s}\n", .{args[1]}) catch return error.LineTooLong;
    try sendCommand(msg);
}

fn runState(args: []const []const u8) !void {
    if (args.len > 1 and std.mem.eql(u8, args[1], "--json")) {
        try printJson("CMD state-json\n", "STATE_JSON");
    } else {
        try printState();
    }
}

fn printPerf(json: bool, reset: bool) !void {
    if (reset) try sendCommand("CMD perf-reset\n");
    const fd = try connectSocket();
    defer _ = c.close(fd);
    try sendAll(fd, if (json) "CMD perf-json\n" else "CMD perf\n");
    var reader = LineReader{ .fd = fd };
    var line_buf: [65536]u8 = undefined;
    if (json) {
        const line = (try reader.next(&line_buf)) orelse return error.Closed;
        writeLine(line);
        return;
    }
    while (try reader.next(&line_buf)) |line| {
        writeLine(line);
        if (std.mem.eql(u8, line, "END")) return;
    }
    return error.Closed;
}

fn runPerf(args: []const []const u8) !void {
    var json = false;
    var reset = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (std.mem.eql(u8, arg, "--reset")) {
            reset = true;
        } else {
            return error.BadArguments;
        }
    }
    if (reset) {
        try sendCommand("CMD perf-reset\n");
        writeLine("perf: reset");
        return;
    }
    try printPerf(json, false);
}

const CompareResult = struct {
    errors: usize = 0,
    changes: usize = 0,
};

fn showConfigCompare(path: []const u8, show_diff: bool) !CompareResult {
    const fd = try connectSocket();
    defer _ = c.close(fd);
    var line: [768]u8 = undefined;
    const command = std.fmt.bufPrint(&line, "CMD config-compare {s}\n", .{path}) catch
        return error.PathTooLong;
    try sendAll(fd, command);
    var reader = LineReader{ .fd = fd };
    var line_buf: [65536]u8 = undefined;
    var in_compare = false;
    var in_diff = false;
    var result = CompareResult{};
    while (try reader.next(&line_buf)) |text| {
        if (std.mem.eql(u8, text, "CONFIG_COMPARE")) {
            in_compare = true;
            continue;
        }
        if (!in_compare) continue;
        if (std.mem.eql(u8, text, "DIFF")) {
            in_diff = true;
            continue;
        }
        if (std.mem.eql(u8, text, "END")) break;
        if (std.mem.startsWith(u8, text, "diagnostic ")) {
            if (std.mem.startsWith(u8, text, "diagnostic error ")) result.errors += 1;
            writeLine(text);
            continue;
        }
        if (in_diff and (text.len > 0 and (text[0] == '-' or text[0] == '+'))) {
            result.changes += 1;
            if (show_diff) writeLine(text);
        }
    }
    if (show_diff) {
        if (result.changes == 0) writeLine("effective config: no changes");
    } else if (result.errors == 0) {
        writeLine("config: ok");
    }
    return result;
}

fn fetchConfigPath(out: []u8) ![]const u8 {
    const fd = try connectSocket();
    defer _ = c.close(fd);
    try sendAll(fd, "CMD config\n");
    var reader = LineReader{ .fd = fd };
    var line_buf: [65536]u8 = undefined;
    while (try reader.next(&line_buf)) |line| {
        if (std.mem.startsWith(u8, line, "config_path ")) {
            const value = line["config_path ".len..];
            if (value.len == 0 or value.len > out.len) return error.NoConfigPath;
            @memcpy(out[0..value.len], value);
            return out[0..value.len];
        }
        if (std.mem.eql(u8, line, "END")) break;
    }
    return error.NoConfigPath;
}

fn pathZ(path: []const u8, buf: *[512:0]u8) ?[*:0]const u8 {
    if (path.len >= buf.len) return null;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return @ptrCast(buf);
}

fn copyFileToFd(source: ?[*:0]const u8, out_fd: c_int) !void {
    if (source) |src| {
        const in_fd = c.open(src, c.O_RDONLY);
        if (in_fd < 0) return error.OpenFailed;
        defer _ = c.close(in_fd);
        var buf: [8192]u8 = undefined;
        while (true) {
            const n = c.read(in_fd, &buf, buf.len);
            if (n < 0) return error.ReadFailed;
            if (n == 0) break;
            var off: usize = 0;
            const total: usize = @intCast(n);
            while (off < total) {
                const w = c.write(out_fd, buf[off..].ptr, total - off);
                if (w <= 0) return error.WriteFailed;
                off += @intCast(w);
            }
        }
    }
    _ = c.fsync(out_fd);
}

fn createTempCopy(source: []const u8, path_buf: *[512:0]u8) ![]const u8 {
    const tmpdir = if (c.getenv("TMPDIR")) |p| std.mem.span(p) else "/tmp";
    const written = std.fmt.bufPrint(path_buf[0..511], "{s}/tessa-config-edit-XXXXXX", .{tmpdir}) catch
        return error.PathTooLong;
    path_buf[written.len] = 0;
    const fd = c.mkstemp(path_buf);
    if (fd < 0) return error.TempFailed;
    defer _ = c.close(fd);

    var source_z: [512:0]u8 = undefined;
    const src = pathZ(source, &source_z);
    copyFileToFd(src, fd) catch |err| {
        _ = c.unlink(path_buf);
        return err;
    };
    return std.mem.sliceTo(path_buf, 0);
}

fn replaceFile(source: []const u8, dest: []const u8) !void {
    var source_z: [512:0]u8 = undefined;
    var dest_z: [512:0]u8 = undefined;
    const src = pathZ(source, &source_z) orelse return error.PathTooLong;
    const dst = pathZ(dest, &dest_z) orelse return error.PathTooLong;

    var st: c.struct_stat = undefined;
    const have_stat = c.stat(dst, &st) == 0;
    const out_fd = c.open(dst, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o644));
    if (out_fd < 0) return error.OpenFailed;
    defer _ = c.close(out_fd);
    try copyFileToFd(src, out_fd);
    if (have_stat) _ = c.fchmod(out_fd, st.st_mode & 0o7777);
}

fn runEditor(path: []const u8) !void {
    const editor = if (c.getenv("VISUAL")) |p|
        std.mem.span(p)
    else if (c.getenv("EDITOR")) |p|
        std.mem.span(p)
    else
        "vi";
    var command: [2048:0]u8 = undefined;
    const written = std.fmt.bufPrint(command[0..2047], "{s} '{s}'", .{ editor, path }) catch
        return error.CommandTooLong;
    command[written.len] = 0;
    const rc = c.system(&command);
    if (rc != 0) return error.EditorFailed;
}

fn confirm(prompt: []const u8) bool {
    writeAll(2, prompt);
    var buf: [16]u8 = undefined;
    const n = c.read(0, &buf, buf.len);
    if (n <= 0) return false;
    return buf[0] == 'y' or buf[0] == 'Y';
}

fn runConfigCheck(args: []const []const u8) !void {
    if (args.len > 1) {
        const result = try showConfigCompare(args[1], false);
        if (result.errors > 0) return error.ConfigInvalid;
        return;
    }
    try printConfigCheck();
}

fn runConfigDiff(args: []const []const u8) !void {
    if (args.len < 2) return error.BadArguments;
    _ = try showConfigCompare(args[1], true);
}

fn filesEqual(a: []const u8, b: []const u8) bool {
    var a_z: [512:0]u8 = undefined;
    var b_z: [512:0]u8 = undefined;
    const a_path = pathZ(a, &a_z) orelse return false;
    const b_path = pathZ(b, &b_z) orelse return false;
    const a_fd = c.open(a_path, c.O_RDONLY);
    if (a_fd < 0) return false;
    defer _ = c.close(a_fd);
    const b_fd = c.open(b_path, c.O_RDONLY);
    if (b_fd < 0) return false;
    defer _ = c.close(b_fd);

    var a_buf: [8192]u8 = undefined;
    var b_buf: [8192]u8 = undefined;
    while (true) {
        const a_n = c.read(a_fd, &a_buf, a_buf.len);
        if (a_n < 0) return false;
        const b_n = c.read(b_fd, &b_buf, b_buf.len);
        if (b_n < 0) return false;
        if (a_n != b_n) return false;
        if (a_n == 0) return true;
        const n: usize = @intCast(a_n);
        if (!std.mem.eql(u8, a_buf[0..n], b_buf[0..n])) return false;
    }
}

fn runConfigEdit(args: []const []const u8) !void {
    var path_buf: [512]u8 = undefined;
    const target = if (args.len > 1)
        args[1]
    else
        try fetchConfigPath(&path_buf);

    var temp_buf: [512:0]u8 = undefined;
    const temp = try createTempCopy(target, &temp_buf);
    defer _ = c.unlink(&temp_buf);

    runEditor(temp) catch |err| {
        if (err == error.EditorFailed) {
            std.debug.print("tessa-ctl: editor exited with an error; changes not applied\n", .{});
            return;
        }
        return err;
    };

    const result = try showConfigCompare(temp, true);
    const file_changed = !filesEqual(temp, target);
    if (result.changes == 0 and !file_changed) {
        writeLine("no changes; not saving");
        return;
    }
    const prompt = if (result.errors > 0)
        "config has errors; save anyway? Changes will not apply until fixed. [y/N] "
    else if (result.changes == 0)
        "panel-only or comment changes; save and reload? [y/N] "
    else
        "apply changes and reload? [y/N] ";
    if (!confirm(prompt)) {
        writeLine("discarded");
        return;
    }
    try replaceFile(temp, target);
    try sendCommand("CMD reload\n");
    var applied: [600]u8 = undefined;
    const msg = std.fmt.bufPrint(&applied, "applied {s}", .{target}) catch "applied";
    writeLine(msg);
}

fn runConfig(args: []const []const u8) !void {
    if (args.len > 1 and std.mem.eql(u8, args[1], "--json")) {
        try printJson("CMD config-json\n", "CONFIG_JSON");
    } else {
        try printConfig();
    }
}

fn runMode(args: []const []const u8) !void {
    var line: [128]u8 = undefined;
    const msg = if (args.len > 1)
        std.fmt.bufPrint(&line, "CMD mode {s}\n", .{args[1]}) catch return error.LineTooLong
    else
        "CMD mode\n";
    try sendCommand(msg);
}

fn runLayout(args: []const []const u8) !void {
    var line: [256]u8 = undefined;
    const msg = if (args.len > 2)
        std.fmt.bufPrint(&line, "CMD layout {s} {s}\n", .{ args[1], args[2] }) catch return error.LineTooLong
    else if (args.len > 1)
        std.fmt.bufPrint(&line, "CMD layout {s}\n", .{args[1]}) catch return error.LineTooLong
    else
        "CMD layout\n";
    try sendCommand(msg);
}

fn runResize(args: []const []const u8) !void {
    if (args.len < 3) return error.BadArguments;
    _ = std.fmt.parseInt(i32, args[1], 10) catch return error.BadArguments;
    _ = std.fmt.parseInt(i32, args[2], 10) catch return error.BadArguments;
    var line: [128]u8 = undefined;
    const msg = std.fmt.bufPrint(&line, "CMD resize {s} {s}\n", .{ args[1], args[2] }) catch
        return error.LineTooLong;
    try sendCommand(msg);
}

fn runSpawn(args: []const []const u8) !void {
    if (args.len < 2) return error.BadArguments;
    var cmd_buf: [2048]u8 = undefined;
    const command = joinArgs(args, 1, &cmd_buf);
    var line: [2096]u8 = undefined;
    const msg = std.fmt.bufPrint(&line, "CMD spawn {s}\n", .{command}) catch return error.LineTooLong;
    try sendCommand(msg);
}

fn runLauncher(args: []const []const u8) !void {
    var query_buf: [1024]u8 = undefined;
    const query = joinArgs(args, 1, &query_buf);
    var line: [1100]u8 = undefined;
    const msg = if (query.len > 0)
        std.fmt.bufPrint(&line, "CMD launcher {s}\n", .{query}) catch return error.LineTooLong
    else
        "CMD launcher\n";
    try sendCommand(msg);
}

fn runPanel(args: []const []const u8) !void {
    if (args.len < 2) return error.BadArguments;
    var line: [256]u8 = undefined;
    const msg = if (args.len > 2)
        std.fmt.bufPrint(&line, "CMD panel {s} {s}\n", .{ args[1], args[2] }) catch return error.LineTooLong
    else
        std.fmt.bufPrint(&line, "CMD panel {s}\n", .{args[1]}) catch return error.LineTooLong;
    try sendCommand(msg);
}

fn runQuit() !void {
    try sendCommand("CMD quit\n");
}

fn runNotificationAction(args: []const []const u8) !void {
    if (args.len < 3) return error.BadArguments;
    var line: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&line, "CMD notification-action {s} {s}\n", .{
        args[1], args[2],
    }) catch return error.LineTooLong;
    try sendCommand(msg);
}

fn runSpecial(args: []const []const u8, move: bool) !void {
    if (args.len < 2) return error.BadArguments;
    var line: [256]u8 = undefined;
    const msg = if (move)
        std.fmt.bufPrint(&line, "CMD move-to-special {s}\n", .{args[1]}) catch return error.LineTooLong
    else
        std.fmt.bufPrint(&line, "CMD special {s}\n", .{args[1]}) catch return error.LineTooLong;
    try sendCommand(msg);
}

pub fn main(init: std.process.Init.Minimal) void {
    var args_buf: [32][]const u8 = undefined;
    var arg_count: usize = 0;
    var it = init.args.iterate();
    defer it.deinit();
    _ = it.next();
    while (it.next()) |arg| {
        if (arg_count < args_buf.len) {
            args_buf[arg_count] = arg;
            arg_count += 1;
        }
    }
    const args = args_buf[0..arg_count];

    const cmd = if (arg_count > 0) args[0] else "state";
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        usage();
        return;
    }

    const result: anyerror!void = if (std.mem.eql(u8, cmd, "state"))
        runState(args)
    else if (std.mem.eql(u8, cmd, "config"))
        runConfig(args)
    else if (std.mem.eql(u8, cmd, "config-check"))
        runConfigCheck(args)
    else if (std.mem.eql(u8, cmd, "config-diff"))
        runConfigDiff(args)
    else if (std.mem.eql(u8, cmd, "config-edit"))
        runConfigEdit(args)
    else if (std.mem.eql(u8, cmd, "perf"))
        runPerf(args)
    else if (std.mem.eql(u8, cmd, "rpc"))
        runRpc(args)
    else if (std.mem.eql(u8, cmd, "events"))
        printEvents(if (args.len > 1) args[1] else "")
    else if (std.mem.eql(u8, cmd, "dispatch"))
        runDispatch(args)
    else if (std.mem.eql(u8, cmd, "workspace"))
        runWorkspace(args)
    else if (std.mem.eql(u8, cmd, "special"))
        runSpecial(args, false)
    else if (std.mem.eql(u8, cmd, "move-to-special"))
        runSpecial(args, true)
    else if (std.mem.eql(u8, cmd, "spawn"))
        runSpawn(args)
    else if (std.mem.eql(u8, cmd, "launcher"))
        runLauncher(args)
    else if (std.mem.eql(u8, cmd, "panel"))
        runPanel(args)
    else if (std.mem.eql(u8, cmd, "notify-action"))
        runNotificationAction(args)
    else if (std.mem.eql(u8, cmd, "layout"))
        runLayout(args)
    else if (std.mem.eql(u8, cmd, "mode"))
        runMode(args)
    else if (std.mem.eql(u8, cmd, "resize"))
        runResize(args)
    else if (std.mem.eql(u8, cmd, "status"))
        runStatus(args)
    else if (std.mem.eql(u8, cmd, "quit"))
        runQuit()
    else
        error.UnknownCommand;

    result catch |err| {
        if (err == error.UnknownCommand) {
            usage();
            std.process.exit(2);
        }
        if (err == error.ConfigInvalid) std.process.exit(1);
        std.debug.print("tessa-ctl: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
