const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");

const Server = types.Server;
const Output = types.Output;

pub const MOD_SHIFT: u32 = 1 << 0;
pub const MOD_CAPS: u32 = 1 << 1;
pub const MOD_CTRL: u32 = 1 << 2;
pub const MOD_ALT: u32 = 1 << 3;
pub const MOD_MOD2: u32 = 1 << 4;
pub const MOD_MOD3: u32 = 1 << 5;
pub const MOD_LOGO: u32 = 1 << 6;
pub const MOD_MOD5: u32 = 1 << 7;
pub const MOD_NUM: u32 = 1 << 8;

pub fn logInfo(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("tessa: " ++ fmt ++ "\n", args);
}

pub fn logDebug(comptime fmt: []const u8, args: anytype) void {
    if (c.getenv("TESSA_DEBUG") == null) return;
    std.debug.print("tessa: " ++ fmt ++ "\n", args);
}

pub fn cstr(ptr: anytype) []const u8 {
    const p: ?[*:0]const u8 = @ptrCast(ptr);
    if (p) |q| return std.mem.span(q);
    return "";
}

pub fn copyString(dest: []u8, dest_len: *usize, src: []const u8) void {
    const n = utf8Truncate(src, dest.len - 1).len;
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
    dest_len.* = n;
}

pub fn copyStringBuf(dest: []u8, src: []const u8) []const u8 {
    const n = utf8Truncate(src, dest.len - 1).len;
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
    return dest[0..n];
}

pub fn copyZ(dest: []u8, src: []const u8) void {
    const n = utf8Truncate(src, dest.len - 1).len;
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
}

pub fn utf8Truncate(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    var n = max;
    while (n > 0 and (s[n] & 0xC0) == 0x80) n -= 1;
    return s[0..n];
}

pub fn markDirty(server: *Server) void {
    server.ipc_dirty = true;
    if (server.schedule_ipc) |f| f(server);
}

pub fn firstOutput(server: *Server) ?*Output {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |out| return out;
    }
    return null;
}

pub fn outputAt(server: *Server, lx: f64, ly: f64) ?*Output {
    const wlr = c.wlr_output_layout_output_at(server.output_layout, lx, ly) orelse
        return firstOutput(server);
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |out| {
            if (out.wlr == wlr) return out;
        }
    }
    return firstOutput(server);
}

pub fn focusedOutput(server: *Server) ?*Output {
    return outputAt(server, server.cursor.x, server.cursor.y);
}

pub fn focusOutput(server: *Server) ?*Output {
    if (server.focused_output) |out| return out;
    return focusedOutput(server);
}

pub fn outputName(out: *Output) []const u8 {
    return cstr(out.wlr.name);
}

pub fn outputByName(server: *Server, name: []const u8) ?*Output {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        if (std.mem.eql(u8, outputName(out), name)) return out;
    }
    return null;
}

pub fn spawnPanel(server: *Server, out: *Output) void {
    if (!server.config.autostart_panel) return;
    if (c.getenv("TESSA_NO_PANEL") != null) return;
    const bin: [*:0]const u8 = if (c.getenv("TESSA_PANEL_BIN")) |p| p else "tessa-panel";
    var name_buf: [128:0]u8 = undefined;
    copyZ(&name_buf, outputName(out));
    const pid = c.fork();
    if (pid == 0) {
        _ = c.signal(c.SIGCHLD, c.SIG_DFL);
        _ = c.setenv("TESSA_PANEL_OUTPUT", &name_buf, 1);
        _ = c.execlp(bin, bin, @as(?[*:0]const u8, null));
        c._exit(127);
    }
    logInfo("starting panel for {s}", .{outputName(out)});
}

pub fn spawn(cmd: []const u8) void {
    var buf: [2048]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{cmd}) catch return;
    const pid = c.fork();
    if (pid == 0) {
        _ = c.setsid();
        _ = c.signal(c.SIGCHLD, c.SIG_DFL);
        _ = c.execl("/bin/sh", "/bin/sh", "-c", z.ptr, @as(?[*:0]const u8, null));
        c._exit(127);
    }
}

pub const EnvVar = struct {
    name: [*:0]const u8,
    value: []const u8,
};

pub fn spawnWithEnv(cmd: []const u8, envs: []const EnvVar) void {
    var buf: [2048]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{cmd}) catch return;
    const pid = c.fork();
    if (pid == 0) {
        _ = c.setsid();
        _ = c.signal(c.SIGCHLD, c.SIG_DFL);
        for (envs) |env| {
            var value_buf: [1024:0]u8 = undefined;
            copyZ(&value_buf, env.value);
            _ = c.setenv(env.name, &value_buf, 1);
        }
        _ = c.execl("/bin/sh", "/bin/sh", "-c", z.ptr, @as(?[*:0]const u8, null));
        c._exit(127);
    }
}

pub fn spawnProgram(prog: [*:0]const u8) void {
    const pid = c.fork();
    if (pid == 0) {
        _ = c.signal(c.SIGCHLD, c.SIG_DFL);
        _ = c.execlp(prog, prog, @as(?[*:0]const u8, null));
        c._exit(127);
    }
}

pub fn spawnProgramArg(prog: [*:0]const u8, arg: [*:0]const u8) void {
    const pid = c.fork();
    if (pid == 0) {
        _ = c.signal(c.SIGCHLD, c.SIG_DFL);
        _ = c.execlp(prog, prog, arg, @as(?[*:0]const u8, null));
        c._exit(127);
    }
}

pub fn outputBox(server: *Server, out: *Output, box: *c.wlr_box) void {
    c.wlr_output_layout_get_box(server.output_layout, out.wlr, box);
}

pub fn updateBackground(out: *Output) void {
    const s = out.server;
    outputBox(s, out, &out.full);
    c.wlr_scene_node_set_position(&out.bg_rect.node, out.full.x, out.full.y);
    c.wlr_scene_rect_set_size(out.bg_rect, out.full.width, out.full.height);
}

pub fn activeVisible(server: *Server, client: *types.Client) bool {
    _ = server;
    return client.mapped and client.ws == client.output.active_ws;
}

pub fn clientIndex(server: *Server, client: *types.Client) ?usize {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        if (server.clients[i]) |cl| {
            if (cl == client) return i;
        }
    }
    return null;
}

pub fn outputIndexOf(server: *Server, out: *Output) ?usize {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |o| {
            if (o == out) return i;
        }
    }
    return null;
}

pub fn popupIndex(server: *Server, popup: *types.ImPopup) ?usize {
    var i: usize = 0;
    while (i < server.im_popups.len) : (i += 1) {
        if (server.im_popups[i]) |p| {
            if (p == popup) return i;
        }
    }
    return null;
}

pub fn lockSurfaceIndex(server: *Server, ls: *types.LockSurface) ?usize {
    var i: usize = 0;
    while (i < server.lock_surfaces.len) : (i += 1) {
        if (server.lock_surfaces[i]) |s| {
            if (s == ls) return i;
        }
    }
    return null;
}

pub fn layerIndexOf(server: *Server, layer: *types.LayerSurface) ?usize {
    var i: usize = 0;
    while (i < server.layers.len) : (i += 1) {
        if (server.layers[i]) |l| {
            if (l == layer) return i;
        }
    }
    return null;
}

pub fn removeAt(comptime T: type, arr: []?*T, count: *usize, index: usize) void {
    if (index >= count.*) return;
    arr[index] = arr[count.* - 1];
    arr[count.* - 1] = null;
    count.* -= 1;
}

pub fn parseHexColor(hex_in: []const u8, out: *[3]f32) void {
    var hex = hex_in;
    if (hex.len > 0 and hex[0] == '#') hex = hex[1..];
    if (hex.len < 6) return;
    const r: u8 = std.fmt.parseInt(u8, hex[0..2], 16) catch return;
    const g: u8 = std.fmt.parseInt(u8, hex[2..4], 16) catch return;
    const b: u8 = std.fmt.parseInt(u8, hex[4..6], 16) catch return;
    out[0] = @as(f32, @floatFromInt(r)) / 255.0;
    out[1] = @as(f32, @floatFromInt(g)) / 255.0;
    out[2] = @as(f32, @floatFromInt(b)) / 255.0;
}

pub fn timeNowMs() i64 {
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
    return @as(i64, ts.tv_sec) * 1000 + @divTrunc(@as(i64, ts.tv_nsec), 1_000_000);
}
