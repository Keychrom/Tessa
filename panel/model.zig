const std = @import("std");
const c = @import("c.zig").c;
const apps = @import("apps.zig");

pub const MAX_WINDOWS = 64;
pub const MAX_RESULTS = 256;
pub const BAR_HEIGHT = 44;

pub const HitKind = enum { none, menu, workspace, window, app };

pub const Hit = struct {
    kind: HitKind = .none,
    value: usize = 0,
};

pub const HitRect = struct {
    x: f64 = 0,
    y: f64 = 0,
    w: f64 = 0,
    h: f64 = 0,
    hit: Hit = .{},
};

pub const WindowInfo = struct {
    id: u64 = 0,
    ws: usize = 1,
    focused: bool = false,
    floating: bool = false,
    fullscreen: bool = false,
    app_id: [64]u8 = [_]u8{0} ** 64,
    app_len: usize = 0,
    title: [160]u8 = [_]u8{0} ** 160,
    title_len: usize = 0,
};

pub const SurfaceKind = enum { background, bar, overlay };

pub const Buffer = struct {
    wl: ?*c.wl_buffer = null,
    data: ?*anyopaque = null,
    size: usize = 0,
    busy: bool = false,
    owner: ?*Surface = null,
    listener: c.wl_buffer_listener = undefined,
};

pub const Surface = struct {
    kind: SurfaceKind = .bar,
    wl: ?*c.wl_surface = null,
    layer: ?*c.zwlr_layer_surface_v1 = null,
    width: u32 = 0,
    height: u32 = 0,
    configured: bool = false,
    dirty: bool = false,
    buffers: [3]Buffer = undefined,
    listener: c.zwlr_layer_surface_v1_listener = undefined,
};

pub const Panel = struct {
    display: ?*c.wl_display = null,
    registry: ?*c.wl_registry = null,
    compositor: ?*c.wl_compositor = null,
    shm: ?*c.wl_shm = null,
    layer_shell: ?*c.zwlr_layer_shell_v1 = null,
    seat: ?*c.wl_seat = null,
    pointer: ?*c.wl_pointer = null,
    keyboard: ?*c.wl_keyboard = null,

    xkb_ctx: ?*c.xkb_context = null,
    xkb_keymap: ?*c.xkb_keymap = null,
    xkb_state: ?*c.xkb_state = null,

    bar: Surface = undefined,
    bg: Surface = undefined,
    overlay: ?*Surface = null,

    active_ws: usize = 1,
    occ: [10]u32 = [_]u32{0} ** 10,
    focused_id: u64 = 0,
    windows: [MAX_WINDOWS]WindowInfo = undefined,
    window_count: usize = 0,

    ipc_fd: c_int = -1,
    ipc_buf: [65536]u8 = undefined,
    ipc_len: usize = 0,
    ipc_in_state: bool = false,

    clock_buf: [8]u8 = [_]u8{0} ** 8,
    date_buf: [20]u8 = [_]u8{0} ** 20,

    cpu_percent: f32 = 0,
    mem_percent: f32 = 0,
    cpu_hist: [40]f32 = [_]f32{0} ** 40,
    prev_total: u64 = 0,
    prev_idle: u64 = 0,
    have_cpu_prev: bool = false,

    pointer_surface: ?*Surface = null,
    pointer_x: f64 = 0,
    pointer_y: f64 = 0,

    bar_hits: [48]HitRect = undefined,
    bar_hit_count: usize = 0,
    hover: Hit = .{},

    overlay_hits: [8]HitRect = undefined,
    overlay_hit_count: usize = 0,
    overlay_panel: HitRect = .{},
    overlay_row_hover: usize = 999,

    launcher_open: bool = false,
    query: [128]u8 = [_]u8{0} ** 128,
    query_len: usize = 0,
    preedit: [128]u8 = [_]u8{0} ** 128,
    preedit_len: usize = 0,
    preedit_begin: i32 = 0,
    preedit_end: i32 = 0,
    text_input_manager: ?*c.zwp_text_input_manager_v3 = null,
    text_input: ?*c.zwp_text_input_v3 = null,
    text_input_listener: c.zwp_text_input_v3_listener = undefined,
    text_input_enabled: bool = false,
    text_input_focused: bool = false,
    search_rect: [4]i32 = .{ 0, 0, 1, 20 },
    selected: usize = 0,
    scroll: usize = 0,
    results: [MAX_RESULTS]usize = undefined,
    result_count: usize = 0,
    app_list: apps.AppList = undefined,

    menu_anim: f64 = 0,
    menu_from: f64 = 0,
    menu_target: f64 = 0,
    menu_anim_start: i64 = 0,

    running: bool = false,
    next_clock_ms: i64 = 0,
    next_cpu_ms: i64 = 0,
    next_blink_ms: i64 = 0,

    accent: [3]f64 = .{ 0.886, 0.408, 0.31 },
    bg_rgb: [3]f64 = .{ 0.039, 0.059, 0.102 },
    font: [64]u8 = undefined,
    font_len: usize = 0,
    terminal: [128]u8 = undefined,
    terminal_len: usize = 0,
};

pub var g: Panel = undefined;

pub fn nowMs() i64 {
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
    return @as(i64, ts.tv_sec) * 1000 + @divTrunc(@as(i64, ts.tv_nsec), 1_000_000);
}

pub fn copyTrunc(dest: []u8, len: *usize, src: []const u8) void {
    var n = @min(src.len, dest.len - 1);
    if (n < src.len) {
        while (n > 0 and (src[n] & 0xC0) == 0x80) n -= 1;
    }
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
    len.* = n;
}

fn hexColor(hex_in: []const u8, out: *[3]f64) void {
    var hex = hex_in;
    if (hex.len > 0 and hex[0] == '#') hex = hex[1..];
    if (hex.len < 6) return;
    const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return;
    const gg = std.fmt.parseInt(u8, hex[2..4], 16) catch return;
    const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return;
    out[0] = @as(f64, @floatFromInt(r)) / 255.0;
    out[1] = @as(f64, @floatFromInt(gg)) / 255.0;
    out[2] = @as(f64, @floatFromInt(b)) / 255.0;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

pub fn loadConfig() void {
    copyTrunc(&g.terminal, &g.terminal_len, "kitty");
    copyTrunc(&g.font, &g.font_len, "Inter");
    g.accent = .{ 0.886, 0.408, 0.31 };
    g.bg_rgb = .{ 0.039, 0.059, 0.102 };

    var path_buf: [512]u8 = undefined;
    var path: []const u8 = "";
    if (c.getenv("TESSA_CONFIG")) |p| {
        path = std.mem.span(p);
    } else if (c.getenv("XDG_CONFIG_HOME")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/tessa/config", .{std.mem.span(p)}) catch "";
    } else if (c.getenv("HOME")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/.config/tessa/config", .{std.mem.span(p)}) catch "";
    }
    if (path.len == 0) return;

    var zpath: [512:0]u8 = undefined;
    const n = @min(path.len, zpath.len - 1);
    @memcpy(zpath[0..n], path[0..n]);
    zpath[n] = 0;
    const file = c.fopen(&zpath, "r") orelse return;
    defer _ = c.fclose(file);

    var line: [1024]u8 = undefined;
    while (c.fgets(&line, @intCast(line.len), file)) |_| {
        const raw = std.mem.span(@as([*:0]const u8, @ptrCast(&line)));
        const t = trim(raw);
        if (t.len == 0 or t[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = trim(t[0..eq]);
        const val = trim(t[eq + 1 ..]);
        if (std.mem.eql(u8, key, "terminal")) {
            copyTrunc(&g.terminal, &g.terminal_len, val);
        } else if (std.mem.eql(u8, key, "font")) {
            copyTrunc(&g.font, &g.font_len, val);
        } else if (std.mem.eql(u8, key, "accent")) {
            hexColor(val, &g.accent);
        } else if (std.mem.eql(u8, key, "bg")) {
            hexColor(val, &g.bg_rgb);
        }
    }
}

pub fn updateClock() bool {
    var t: c.time_t = c.time(null);
    var tm: c.tm = undefined;
    _ = c.localtime_r(&t, &tm);

    var time_buf: [8]u8 = [_]u8{0} ** 8;
    _ = c.strftime(&time_buf, time_buf.len, "%H:%M", &tm);
    var date_buf: [20]u8 = [_]u8{0} ** 20;
    _ = c.strftime(&date_buf, date_buf.len, "%a %d %b", &tm);

    var changed = false;
    if (!std.mem.eql(u8, time_buf[0..5], g.clock_buf[0..5])) {
        @memcpy(g.clock_buf[0..5], time_buf[0..5]);
        g.clock_buf[5] = 0;
        changed = true;
    }

    const date_len = std.mem.indexOfScalar(u8, &date_buf, 0) orelse date_buf.len;
    for (date_buf[0..date_len]) |*ch| {
        if (ch.* >= 'a' and ch.* <= 'z') ch.* -= 32;
    }
    const old_len = std.mem.indexOfScalar(u8, &g.date_buf, 0) orelse g.date_buf.len;
    if (date_len != old_len or !std.mem.eql(u8, date_buf[0..date_len], g.date_buf[0..old_len])) {
        @memset(&g.date_buf, 0);
        @memcpy(g.date_buf[0..date_len], date_buf[0..date_len]);
        changed = true;
    }
    return changed;
}

fn parseU64(s: []const u8) u64 {
    return std.fmt.parseInt(u64, s, 10) catch 0;
}

pub fn updateCpu() void {
    const file = c.fopen("/proc/stat", "r") orelse return;
    defer _ = c.fclose(file);
    var line: [512]u8 = undefined;
    if (c.fgets(&line, @intCast(line.len), file) == null) return;
    const raw = std.mem.span(@as([*:0]const u8, @ptrCast(&line)));
    var it = std.mem.tokenizeAny(u8, raw, " \t\n");
    _ = it.next(); // cpu

    var values: [8]u64 = [_]u64{0} ** 8;
    var idx: usize = 0;
    while (it.next()) |tok| {
        if (idx >= values.len) break;
        values[idx] = parseU64(tok);
        idx += 1;
    }
    var total: u64 = 0;
    for (values) |v| total += v;
    const idle = values[3] + values[4];

    if (g.have_cpu_prev and total > g.prev_total) {
        const dt = total - g.prev_total;
        const di = idle - g.prev_idle;
        const busy = if (dt > di) dt - di else 0;
        g.cpu_percent = @as(f32, @floatFromInt(busy)) * 100.0 / @as(f32, @floatFromInt(dt));
    }
    g.prev_total = total;
    g.prev_idle = idle;
    g.have_cpu_prev = true;

    var i: usize = 0;
    while (i + 1 < g.cpu_hist.len) : (i += 1) g.cpu_hist[i] = g.cpu_hist[i + 1];
    g.cpu_hist[g.cpu_hist.len - 1] = g.cpu_percent;
}

pub fn updateMem() void {
    const file = c.fopen("/proc/meminfo", "r") orelse return;
    defer _ = c.fclose(file);
    var total_kb: u64 = 0;
    var avail_kb: u64 = 0;
    var line: [256]u8 = undefined;
    while (c.fgets(&line, @intCast(line.len), file)) |_| {
        const raw = std.mem.span(@as([*:0]const u8, @ptrCast(&line)));
        var it = std.mem.tokenizeAny(u8, raw, " \t\n");
        const key = it.next() orelse continue;
        if (std.mem.eql(u8, key, "MemTotal:")) {
            total_kb = parseU64(it.next() orelse "0");
        } else if (std.mem.eql(u8, key, "MemAvailable:")) {
            avail_kb = parseU64(it.next() orelse "0");
        }
    }
    if (total_kb > 0 and avail_kb <= total_kb) {
        g.mem_percent = @as(f32, @floatFromInt(total_kb - avail_kb)) * 100.0 /
            @as(f32, @floatFromInt(total_kb));
    }
}

pub fn recomputeResults() void {
    g.result_count = apps.filter(&g.app_list, g.query[0..g.query_len], &g.results);
    if (g.result_count == 0) {
        g.selected = 0;
        g.scroll = 0;
        return;
    }
    if (g.selected >= g.result_count) g.selected = g.result_count - 1;
    const visible: usize = 7;
    if (g.selected < g.scroll) g.scroll = g.selected;
    if (g.selected >= g.scroll + visible) g.scroll = g.selected - (visible - 1);
    const max_scroll = if (g.result_count > visible) g.result_count - visible else 0;
    if (g.scroll > max_scroll) g.scroll = max_scroll;
}

pub fn setQuery(str: []const u8) void {
    copyTrunc(&g.query, &g.query_len, str);
    g.selected = 0;
    g.scroll = 0;
    recomputeResults();
}

pub fn decodeEscapes(dest: []u8, len: *usize, src: []const u8) void {
    var j: usize = 0;
    var i: usize = 0;
    while (i < src.len and j + 1 < dest.len) {
        if (src[i] == '\\' and i + 1 < src.len) {
            i += 1;
            switch (src[i]) {
                'n' => dest[j] = '\n',
                'r' => dest[j] = '\r',
                't' => dest[j] = '\t',
                '\\' => dest[j] = '\\',
                else => dest[j] = src[i],
            }
            i += 1;
        } else {
            dest[j] = src[i];
            i += 1;
        }
        j += 1;
    }
    dest[j] = 0;
    len.* = j;
}
