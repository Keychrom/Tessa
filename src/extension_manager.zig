//! Supervised extension processes and cooperative permission scopes.
//!
//! Extensions are ordinary same-user processes. They receive a token in their
//! environment and announce it with `HELLO 1 <token>` on the control socket.
//! The token scopes their commands; it is not a sandbox. A process that already
//! has the user's filesystem access can always read the token or bypass Tessa.

const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");

const Server = types.Server;
const ExtensionRuntime = types.ExtensionRuntime;

const INITIAL_RESTART_MS: i32 = 500;
const MAX_RESTART_MS: i32 = 8000;
const STABLE_RUN_MS: i64 = 10_000;
var token_counter: u64 = 0;

fn openPidfd(pid: c.pid_t) ?c_int {
    const rc = std.os.linux.pidfd_open(@intCast(pid), 0);
    return switch (std.posix.errno(rc)) {
        .SUCCESS => @intCast(rc),
        else => null,
    };
}

fn currentMs() i64 {
    return core.timeNowMs();
}

pub fn permissionsText(buf: []u8, scopes: u16) []const u8 {
    var off: usize = 0;
    const items = [_]struct { bit: u16, name: []const u8 }{
        .{ .bit = types.EXT_PERM_READ, .name = "read" },
        .{ .bit = types.EXT_PERM_EVENTS, .name = "events" },
        .{ .bit = types.EXT_PERM_STATUS, .name = "status" },
        .{ .bit = types.EXT_PERM_WINDOW, .name = "window" },
        .{ .bit = types.EXT_PERM_WORKSPACE, .name = "workspace" },
        .{ .bit = types.EXT_PERM_LAYOUT, .name = "layout" },
        .{ .bit = types.EXT_PERM_SPAWN, .name = "spawn" },
        .{ .bit = types.EXT_PERM_PANEL, .name = "panel" },
        .{ .bit = types.EXT_PERM_CONTROL, .name = "control" },
        .{ .bit = types.EXT_PERM_EXTENSIONS, .name = "extensions" },
    };
    for (items) |item| {
        if (scopes & item.bit == 0) continue;
        if (off > 0 and off < buf.len) {
            buf[off] = ',';
            off += 1;
        }
        if (off + item.name.len > buf.len) break;
        @memcpy(buf[off .. off + item.name.len], item.name);
        off += item.name.len;
    }
    return buf[0..off];
}

pub fn stateName(state: types.ExtensionState) []const u8 {
    return @tagName(state);
}

fn makeToken(ext: *ExtensionRuntime) void {
    var raw: [types.MAX_EXTENSION_TOKEN / 2]u8 = undefined;
    token_counter +%= 0x9e3779b97f4a7c15;
    const seed = @as(u64, @bitCast(core.timeNowMs())) ^ token_counter ^ @as(u64, @intFromPtr(ext));
    var prng = std.Random.DefaultPrng.init(seed);
    prng.random().bytes(&raw);
    const hex = "0123456789abcdef";
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        ext.token[i * 2] = hex[raw[i] >> 4];
        ext.token[i * 2 + 1] = hex[raw[i] & 0x0f];
    }
    ext.token_len = raw.len * 2;
}

fn findIndex(server: *Server, id: []const u8) ?usize {
    var i: usize = 0;
    while (i < server.extension_count) : (i += 1) {
        const ext = &server.extensions[i];
        if (std.mem.eql(u8, ext.manifest.id[0..ext.manifest.id_len], id)) return i;
    }
    return null;
}

pub fn findById(server: *Server, id: []const u8) ?*ExtensionRuntime {
    const index = findIndex(server, id) orelse return null;
    return &server.extensions[index];
}

fn depsSatisfied(server: *Server, ext: *ExtensionRuntime) bool {
    var i: usize = 0;
    while (i < ext.manifest.require_count) : (i += 1) {
        const dep_id = ext.manifest.requires[i][0..ext.manifest.require_lens[i]];
        const dep = findById(server, dep_id) orelse return false;
        if (dep.state != .running and dep.state != .ready) return false;
    }
    return true;
}

fn disarmRestart(ext: *ExtensionRuntime) void {
    if (ext.restart_timer) |timer| _ = c.wl_event_source_timer_update(timer, 0);
}

fn closePidfd(ext: *ExtensionRuntime) void {
    if (ext.source) |source| {
        _ = c.wl_event_source_remove(source);
        ext.source = null;
    }
    if (ext.fd >= 0) {
        _ = c.close(ext.fd);
        ext.fd = -1;
    }
}

fn emitLifecycle(server: *Server, name: []const u8, ext: *ExtensionRuntime) void {
    events.emit(server, .{
        .name = name,
        .arg = ext.manifest.id[0..ext.manifest.id_len],
    });
}

fn setError(ext: *ExtensionRuntime, message: []const u8) void {
    core.copyString(&ext.last_error, &ext.last_error_len, message);
}

fn scheduleRestart(server: *Server, ext: *ExtensionRuntime) void {
    if (!ext.manifest.enabled) return;
    var delay = INITIAL_RESTART_MS;
    var i: u32 = 0;
    while (i < ext.failures and delay < MAX_RESTART_MS) : (i += 1) {
        delay *= 2;
    }
    if (delay > MAX_RESTART_MS) delay = MAX_RESTART_MS;
    if (ext.restart_timer) |timer| {
        _ = c.wl_event_source_timer_update(timer, delay);
    }
    core.logInfo("extension '{s}' restarting in {d} ms (failure {d})", .{
        ext.manifest.id[0..ext.manifest.id_len],
        delay,
        ext.failures,
    });
    _ = server;
}

fn onExit(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = fd;
    _ = mask;
    const ext: *ExtensionRuntime = @ptrCast(@alignCast(data.?));
    const server = ext.server orelse return 0;
    const pid = ext.pid;
    ext.pid = -1;
    closePidfd(ext);
    if (ext.state == .stopped or ext.state == .disabled) return 0;

    const now = currentMs();
    if (ext.started_ms > 0 and now - ext.started_ms >= STABLE_RUN_MS) {
        ext.failures = 0;
    } else {
        ext.failures += 1;
    }
    ext.ready = false;
    ext.state = .failed;
    setError(ext, "process exited");
    emitLifecycle(server, event_names.extension_failed, ext);
    core.logInfo("extension '{s}' process {d} exited", .{
        ext.manifest.id[0..ext.manifest.id_len],
        pid,
    });
    scheduleRestart(server, ext);
    return 0;
}

fn onRestartTimer(data: ?*anyopaque) callconv(.c) c_int {
    const ext: *ExtensionRuntime = @ptrCast(@alignCast(data.?));
    const server = ext.server orelse return 0;
    if (ext.state != .failed or ext.pid > 0) return 0;
    startOne(server, ext);
    return 0;
}

pub fn startOne(server: *Server, ext: *ExtensionRuntime) void {
    if (!ext.manifest.enabled) {
        ext.state = .disabled;
        return;
    }
    if (ext.manifest.command_len == 0) {
        ext.state = .failed;
        setError(ext, "missing command");
        return;
    }
    if (!depsSatisfied(server, ext)) {
        ext.state = .blocked;
        return;
    }
    if (ext.pid > 0) return;

    if (ext.token_len == 0) makeToken(ext);

    var id_buf: [types.MAX_EXTENSION_ID + 1]u8 = undefined;
    core.copyZ(&id_buf, ext.manifest.id[0..ext.manifest.id_len]);
    var token_buf: [types.MAX_EXTENSION_TOKEN + 1]u8 = undefined;
    core.copyZ(&token_buf, ext.token[0..ext.token_len]);
    var api_buf: [8:0]u8 = undefined;
    const api_text = std.fmt.bufPrint(&api_buf, "{d}", .{ext.manifest.api}) catch "1";
    api_buf[api_text.len] = 0;
    var perm_buf: [128]u8 = undefined;
    var perm_z: [129:0]u8 = undefined;
    const perms = permissionsText(&perm_buf, ext.manifest.permissions);
    core.copyZ(&perm_z, perms);

    ext.state = .running;
    ext.ready = false;
    ext.last_error_len = 0;
    const pid = c.fork();
    if (pid < 0) {
        ext.state = .failed;
        ext.failures += 1;
        setError(ext, "fork failed");
        scheduleRestart(server, ext);
        return;
    }
    if (pid == 0) {
        core.resetChildSignals();
        _ = c.setsid();
        _ = c.setenv("TESSA_EXTENSION_ID", &id_buf, 1);
        _ = c.setenv("TESSA_EXTENSION_TOKEN", &token_buf, 1);
        _ = c.setenv("TESSA_EXTENSION_API", &api_buf, 1);
        _ = c.setenv("TESSA_EXTENSION_PERMISSIONS", &perm_z, 1);
        const command = @as([*:0]const u8, @ptrCast(&ext.manifest.command));
        _ = c.execl("/bin/sh", "/bin/sh", "-c", command, @as(?[*:0]const u8, null));
        c._exit(127);
    }

    if (ext.started_ms > 0) ext.restarts += 1;
    ext.pid = pid;
    ext.started_ms = currentMs();
    if (!ext.ready) ext.state = .running;
    emitLifecycle(server, event_names.extension_start, ext);
    core.logInfo("extension '{s}' started (pid {d}, api {d})", .{
        ext.manifest.id[0..ext.manifest.id_len],
        pid,
        ext.manifest.api,
    });

    const pidfd = openPidfd(pid) orelse {
        core.logInfo("extension '{s}': pidfd_open failed; crash recovery disabled", .{
            ext.manifest.id[0..ext.manifest.id_len],
        });
        return;
    };
    ext.fd = pidfd;
    const loop = c.wl_display_get_event_loop(server.display);
    const source = c.wl_event_loop_add_fd(
        loop,
        pidfd,
        @intCast(c.WL_EVENT_READABLE),
        onExit,
        ext,
    );
    if (source == null) {
        _ = c.close(pidfd);
        ext.fd = -1;
        return;
    }
    ext.source = source;
}

pub fn stopOne(server: *Server, ext: *ExtensionRuntime, intentional: bool) void {
    _ = server;
    disarmRestart(ext);
    closePidfd(ext);
    const was_active = ext.state == .running or ext.state == .ready or ext.state == .starting;
    if (ext.pid > 0) {
        _ = c.kill(ext.pid, c.SIGTERM);
        ext.pid = -1;
    }
    ext.ready = false;
    ext.state = if (ext.manifest.enabled) .stopped else .disabled;
    if (intentional and was_active) {
        if (ext.server) |srv| emitLifecycle(srv, event_names.extension_stop, ext);
    }
}

fn advance(server: *Server) void {
    var changed = true;
    var guard: usize = 0;
    while (changed and guard < server.extension_count + 1) : (guard += 1) {
        changed = false;
        var oi: usize = 0;
        while (oi < server.extension_order_count) : (oi += 1) {
            const index: usize = server.extension_order[oi];
            if (index >= server.extension_count) continue;
            const ext = &server.extensions[index];
            if (ext.state == .blocked and ext.manifest.enabled and depsSatisfied(server, ext)) {
                startOne(server, ext);
                changed = true;
            }
        }
    }
}

pub fn startAll(server: *Server) void {
    server.extension_count = 0;
    server.extension_order_count = 0;
    var i: usize = 0;
    while (i < server.config.extension_count and i < server.extensions.len) : (i += 1) {
        server.extensions[i] = .{
            .manifest = server.config.extensions[i],
            .server = server,
        };
        server.extension_count += 1;
    }
    server.extension_order_count = server.config.extension_order_count;
    i = 0;
    while (i < server.extension_order_count) : (i += 1) {
        server.extension_order[i] = server.config.extension_order[i];
    }

    const loop = c.wl_display_get_event_loop(server.display);
    i = 0;
    while (i < server.extension_count) : (i += 1) {
        const ext = &server.extensions[i];
        ext.restart_timer = c.wl_event_loop_add_timer(loop, onRestartTimer, ext);
        if (!ext.manifest.enabled) {
            ext.state = .disabled;
            continue;
        }
        startOne(server, ext);
    }
    advance(server);
    server.extensions_started = true;
}

pub fn reload(server: *Server) void {
    var i: usize = 0;
    while (i < server.extension_count) : (i += 1) {
        stopOne(server, &server.extensions[i], false);
        if (server.extensions[i].restart_timer) |timer| {
            _ = c.wl_event_source_remove(timer);
            server.extensions[i].restart_timer = null;
        }
    }
    startAll(server);
}

pub fn shutdown(server: *Server) void {
    var i: usize = 0;
    while (i < server.extension_count) : (i += 1) {
        stopOne(server, &server.extensions[i], false);
        if (server.extensions[i].restart_timer) |timer| {
            _ = c.wl_event_source_remove(timer);
            server.extensions[i].restart_timer = null;
        }
    }
    server.extensions_started = false;
}

pub fn authenticate(server: *Server, token: []const u8) ?*ExtensionRuntime {
    var i: usize = 0;
    while (i < server.extension_count) : (i += 1) {
        const ext = &server.extensions[i];
        if (ext.token_len == 0 or ext.token_len != token.len) continue;
        if (!std.mem.eql(u8, ext.token[0..ext.token_len], token)) continue;
        if (ext.state != .running and ext.state != .ready) return null;
        if (!ext.ready) {
            ext.ready = true;
            ext.state = .ready;
            emitLifecycle(server, event_names.extension_ready, ext);
            advance(server);
        }
        return ext;
    }
    return null;
}

pub fn setEnabled(server: *Server, id: []const u8, enabled: bool) bool {
    var i: usize = 0;
    while (i < server.extension_count) : (i += 1) {
        const ext = &server.extensions[i];
        if (!std.mem.eql(u8, ext.manifest.id[0..ext.manifest.id_len], id)) continue;
        ext.manifest.enabled = enabled;
        if (!enabled) {
            stopOne(server, ext, true);
        } else if (ext.state == .disabled or ext.state == .stopped) {
            ext.state = .stopped;
            startOne(server, ext);
            advance(server);
        }
        return true;
    }
    return false;
}
