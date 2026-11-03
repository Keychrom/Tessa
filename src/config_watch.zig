const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const config = @import("config.zig");

const Server = types.Server;

const DEBOUNCE_MS = 150;
const WATCH_MASK = c.IN_CLOSE_WRITE | c.IN_MOVED_TO | c.IN_CREATE | c.IN_DELETE;

fn isConfigFile(name: []const u8) bool {
    var path_buf: [512]u8 = undefined;
    const path = config.resolvePath(&path_buf);
    if (path.len == 0) return false;
    if (std.mem.eql(u8, name, std.fs.path.basename(path))) return true;
    // Includes conventionally live next to the main config and use .conf.
    return std.mem.endsWith(u8, name, ".conf");
}

fn scheduleReload(server: *Server) void {
    if (server.config_reload_timer) |timer| {
        _ = c.wl_event_source_timer_update(timer, DEBOUNCE_MS);
    }
}

fn onRead(fd: c_int, mask: u32, data: ?*anyopaque) callconv(.c) c_int {
    _ = mask;
    const server: *Server = @ptrCast(@alignCast(data.?));
    var buf: [4096]u8 = undefined;
    const event_size = @sizeOf(c.struct_inotify_event);

    while (true) {
        const n = c.read(fd, buf[0..].ptr, buf.len);
        if (n <= 0) break;
        const len: usize = @intCast(n);
        var off: usize = 0;
        while (off + event_size <= len) {
            var event: c.struct_inotify_event = undefined;
            @memcpy(std.mem.asBytes(&event), buf[off .. off + event_size]);
            const name_start = off + event_size;
            const event_len: usize = @intCast(event.len);
            if (name_start + event_len > len) break;

            if (event.mask & c.IN_Q_OVERFLOW != 0) {
                scheduleReload(server);
            } else if (event_len > 0) {
                const raw = buf[name_start .. name_start + event_len];
                const name_len = std.mem.indexOfScalar(u8, raw, 0) orelse raw.len;
                if (isConfigFile(raw[0..name_len])) scheduleReload(server);
            }
            off = name_start + event_len;
        }
    }
    return 0;
}

fn onReload(data: ?*anyopaque) callconv(.c) c_int {
    const server: *Server = @ptrCast(@alignCast(data.?));
    if (server.reload_runtime) |reload| {
        core.logInfo("config watch: reloading after file change", .{});
        reload(server);
    }
    return 0;
}

pub fn refreshThemeWatch(server: *Server) void {
    if (server.config_watch_fd < 0) return;
    if (server.config_theme_watch >= 0 and server.config_theme_watch != server.config_dir_watch) {
        _ = c.inotify_rm_watch(server.config_watch_fd, server.config_theme_watch);
    }
    server.config_theme_watch = -1;

    if (server.config.theme_dir_len == 0) return;
    const theme_dir = server.config.theme_dir[0..server.config.theme_dir_len];
    var ztheme: [512:0]u8 = undefined;
    core.copyZ(&ztheme, theme_dir);
    const wd = c.inotify_add_watch(server.config_watch_fd, &ztheme, WATCH_MASK);
    if (wd < 0) {
        core.logInfo("config watch: cannot watch theme {s}", .{theme_dir});
    } else if (wd == server.config_dir_watch) {
        core.logInfo("config watch: theme directory is already watched", .{});
    } else {
        server.config_theme_watch = wd;
        core.logInfo("config watch: watching theme {s}", .{theme_dir});
    }
}

pub fn init(server: *Server) void {
    server.config_watch_fd = -1;
    server.config_dir_watch = -1;
    server.config_theme_watch = -1;
    server.config_watch_source = null;
    server.config_reload_timer = null;

    var path_buf: [512]u8 = undefined;
    const path = config.resolvePath(&path_buf);
    if (path.len == 0) return;
    const dir = std.fs.path.dirname(path) orelse ".";

    var zdir: [512:0]u8 = undefined;
    core.copyZ(&zdir, dir);

    const fd = c.inotify_init1(c.IN_NONBLOCK | c.IN_CLOEXEC);
    if (fd < 0) {
        core.logInfo("config watch: inotify_init1 failed", .{});
        return;
    }
    const wd = c.inotify_add_watch(fd, &zdir, WATCH_MASK);
    if (wd < 0) {
        core.logInfo("config watch: cannot watch {s}", .{dir});
        _ = c.close(fd);
        return;
    }
    server.config_watch_fd = fd;
    server.config_dir_watch = wd;
    refreshThemeWatch(server);

    const loop = c.wl_display_get_event_loop(server.display);
    const source = c.wl_event_loop_add_fd(
        loop,
        fd,
        @intCast(c.WL_EVENT_READABLE),
        onRead,
        server,
    );
    if (source == null) {
        server.config_watch_fd = -1;
        server.config_dir_watch = -1;
        server.config_theme_watch = -1;
        _ = c.close(fd);
        core.logInfo("config watch: cannot add event source", .{});
        return;
    }
    server.config_watch_fd = fd;
    server.config_watch_source = source;
    server.config_reload_timer = c.wl_event_loop_add_timer(loop, onReload, server);
    core.logInfo("config watch: watching {s}", .{dir});
}

pub fn deinit(server: *Server) void {
    if (server.config_reload_timer) |timer| {
        _ = c.wl_event_source_remove(timer);
        server.config_reload_timer = null;
    }
    if (server.config_watch_source) |source| {
        _ = c.wl_event_source_remove(source);
        server.config_watch_source = null;
    }
    if (server.config_watch_fd >= 0) {
        _ = c.close(server.config_watch_fd);
        server.config_watch_fd = -1;
    }
    server.config_dir_watch = -1;
    server.config_theme_watch = -1;
}
