const std = @import("std");
const c = @import("c.zig").c;
const apps = @import("apps.zig");

pub const MAX_WINDOWS = 64;
pub const MAX_OUTPUTS = 8;
pub const MAX_RESULTS = 256;
pub const MAX_STATUS = 8;
pub const MAX_CUSTOM_APPS = 16;
pub const POWER_ACTION_COUNT = 5;
pub const MAX_CLIPBOARD_ENTRIES = 8;
pub const MAX_CLIPBOARD_BYTES = 16384;

pub const OverlayMode = enum { none, launcher, calendar, power, clipboard };

pub const month_names = [_][]const u8{
    "January", "February", "March",     "April",   "May",      "June",
    "July",    "August",   "September", "October", "November", "December",
};

pub const weekday_names = [_][]const u8{
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
};

pub const power_labels = [_][]const u8{
    "Lock", "Suspend", "Reboot", "Power Off", "Quit Tessa",
};

pub const power_details = [_][]const u8{
    "Lock the session",      "Suspend the machine",   "Restart the machine",
    "Shut the machine down", "End the Tessa session",
};

pub const HitKind = enum {
    none,
    menu,
    workspace,
    window,
    app,
    status,
    clock,
    calendar_prev,
    calendar_next,
    calendar_today,
    power,
    clipboard_entry,
    clipboard_clear,
};

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
    output_name: [64]u8 = [_]u8{0} ** 64,
    output_len: usize = 0,
    focused: bool = false,
    floating: bool = false,
    fullscreen: bool = false,
    app_id: [64]u8 = [_]u8{0} ** 64,
    app_len: usize = 0,
    title: [160]u8 = [_]u8{0} ** 160,
    title_len: usize = 0,
};

pub const StatusInfo = struct {
    id: [48]u8 = [_]u8{0} ** 48,
    id_len: usize = 0,
    text: [160]u8 = [_]u8{0} ** 160,
    text_len: usize = 0,
    command: [256]u8 = [_]u8{0} ** 256,
    command_len: usize = 0,
};

pub const CustomApp = struct {
    name: [160]u8 = [_]u8{0} ** 160,
    name_len: usize = 0,
    comment: [192]u8 = [_]u8{0} ** 192,
    comment_len: usize = 0,
    exec: [512]u8 = [_]u8{0} ** 512,
    exec_len: usize = 0,
};

pub const OutputInfo = struct {
    wl: ?*c.wl_output = null,
    name: [64]u8 = [_]u8{0} ** 64,
    name_len: usize = 0,
    scale: i32 = 1,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    done: bool = false,
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
    scale: i32 = 1,
    width: u32 = 0,
    height: u32 = 0,
    configured: bool = false,
    dirty: bool = false,
    buffers: [3]Buffer = undefined,
    listener: c.zwlr_layer_surface_v1_listener = undefined,
};

pub const ClipboardEntry = struct {
    text: [MAX_CLIPBOARD_BYTES]u8 = [_]u8{0} ** MAX_CLIPBOARD_BYTES,
    len: usize = 0,
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
    overlay_mode: OverlayMode = .none,

    outputs: [MAX_OUTPUTS]OutputInfo = [_]OutputInfo{.{}} ** MAX_OUTPUTS,
    output_count: usize = 0,
    target_output: ?*c.wl_output = null,
    target_name: [64]u8 = [_]u8{0} ** 64,
    target_name_len: usize = 0,
    is_focused_output: bool = false,
    scale: i32 = 1,

    active_ws: usize = 1,
    occ: [10]u32 = [_]u32{0} ** 10,
    focused_id: u64 = 0,
    windows: [MAX_WINDOWS]WindowInfo = undefined,
    window_count: usize = 0,
    statuses: [MAX_STATUS]StatusInfo = undefined,
    status_count: usize = 0,

    custom_apps: [MAX_CUSTOM_APPS]CustomApp = undefined,
    custom_count: usize = 0,

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

    overlay_hits: [16]HitRect = undefined,
    overlay_hit_count: usize = 0,
    overlay_panel: HitRect = .{},
    overlay_row_hover: usize = 999,
    overlay_hit_scale: f64 = 1,
    overlay_hit_x: f64 = 0,
    overlay_hit_y: f64 = 0,

    calendar_year: i32 = 1970,
    calendar_month: i32 = 1,
    power_selected: usize = 0,
    power_lock: [256]u8 = [_]u8{0} ** 256,
    power_lock_len: usize = 0,
    power_suspend: [256]u8 = [_]u8{0} ** 256,
    power_suspend_len: usize = 0,
    power_reboot: [256]u8 = [_]u8{0} ** 256,
    power_reboot_len: usize = 0,
    power_off: [256]u8 = [_]u8{0} ** 256,
    power_off_len: usize = 0,

    data_control_manager: ?*c.zwlr_data_control_manager_v1 = null,
    data_control_device: ?*c.zwlr_data_control_device_v1 = null,
    data_control_listener: c.zwlr_data_control_device_v1_listener = undefined,
    data_offer: ?*c.zwlr_data_control_offer_v1 = null,
    data_offer_listener: c.zwlr_data_control_offer_v1_listener = undefined,
    data_offer_mime: [128]u8 = [_]u8{0} ** 128,
    data_offer_mime_len: usize = 0,
    data_offer_mime_rank: i32 = 0,
    data_offer_selected: bool = false,
    clipboard_fd: c_int = -1,
    clipboard_read_buf: [MAX_CLIPBOARD_BYTES]u8 = [_]u8{0} ** MAX_CLIPBOARD_BYTES,
    clipboard_read_len: usize = 0,
    clipboard_entries: [MAX_CLIPBOARD_ENTRIES]ClipboardEntry = undefined,
    clipboard_count: usize = 0,
    clipboard_selected: usize = 0,
    clipboard_send_text: [MAX_CLIPBOARD_BYTES]u8 = [_]u8{0} ** MAX_CLIPBOARD_BYTES,
    clipboard_send_len: usize = 0,
    clipboard_source: ?*c.zwlr_data_control_source_v1 = null,
    clipboard_source_listener: c.zwlr_data_control_source_v1_listener = undefined,

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
    panel_bg: [3]f64 = .{ 0.055, 0.075, 0.115 },
    panel_fg: [3]f64 = .{ 0.93, 0.95, 0.98 },
    bar_height: i32 = 44,
    bar_top_margin: i32 = 12,
    bar_side_margin: i32 = 16,
    font: [64]u8 = undefined,
    font_len: usize = 0,
    terminal: [128]u8 = undefined,
    terminal_len: usize = 0,
};

pub var g: Panel = undefined;

pub const LauncherLayout = struct {
    x: f64,
    y: f64,
    scale: f64,
};

/// Scale the 760x620 launcher design uniformly into the available logical
/// surface. Keeping one transform for drawing, hit tests, and IME placement
/// avoids separate small-screen layout rules.
pub fn launcherLayout(w: f64, h: f64) LauncherLayout {
    const fit_x = @max(0.25, (w - 80.0) / 760.0);
    const fit_y = @max(0.25, (h - 80.0) / 620.0);
    const scale = @min(1.0, @min(fit_x, fit_y));
    return .{
        .x = (w - 760.0 * scale) / 2.0,
        .y = (h - 620.0 * scale) / 2.0 - 8.0 * scale,
        .scale = scale,
    };
}

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

fn addCustomApp(value: []const u8) void {
    if (g.custom_count >= g.custom_apps.len) return;
    const bar = std.mem.indexOfScalar(u8, value, '|') orelse {
        std.debug.print("tessa-panel: launcher_entry needs 'Name | command'\n", .{});
        return;
    };
    const name = trim(value[0..bar]);
    const command = trim(value[bar + 1 ..]);
    if (name.len == 0 or command.len == 0) return;

    const app = &g.custom_apps[g.custom_count];
    app.* = std.mem.zeroes(CustomApp);
    copyTrunc(&app.name, &app.name_len, name);
    copyTrunc(&app.exec, &app.exec_len, command);
    copyTrunc(&app.comment, &app.comment_len, "Custom launcher entry");
    g.custom_count += 1;
}

fn resolveInclude(dest: []u8, base: []const u8, value: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(value)) {
        return std.fmt.bufPrint(dest, "{s}", .{value}) catch "";
    }
    const dir = std.fs.path.dirname(base) orelse ".";
    return std.fmt.bufPrint(dest, "{s}/{s}", .{ dir, value }) catch "";
}

fn loadConfigFile(path: []const u8, depth: usize) void {
    if (depth > 8) return;
    var zpath: [512:0]u8 = undefined;
    if (path.len >= zpath.len) return;
    const n = path.len;
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
        if (std.mem.eql(u8, key, "include")) {
            var include_buf: [512]u8 = undefined;
            const include_path = resolveInclude(&include_buf, path, val);
            if (include_path.len > 0) loadConfigFile(include_path, depth + 1);
        } else if (std.mem.eql(u8, key, "terminal")) {
            copyTrunc(&g.terminal, &g.terminal_len, val);
        } else if (std.mem.eql(u8, key, "font")) {
            copyTrunc(&g.font, &g.font_len, val);
        } else if (std.mem.eql(u8, key, "accent")) {
            hexColor(val, &g.accent);
        } else if (std.mem.eql(u8, key, "bg")) {
            hexColor(val, &g.bg_rgb);
        } else if (std.mem.eql(u8, key, "panel_bg")) {
            hexColor(val, &g.panel_bg);
        } else if (std.mem.eql(u8, key, "panel_fg")) {
            hexColor(val, &g.panel_fg);
        } else if (std.mem.eql(u8, key, "bar_height")) {
            g.bar_height = std.fmt.parseInt(i32, val, 10) catch g.bar_height;
        } else if (std.mem.eql(u8, key, "bar_top_margin")) {
            g.bar_top_margin = std.fmt.parseInt(i32, val, 10) catch g.bar_top_margin;
        } else if (std.mem.eql(u8, key, "bar_side_margin")) {
            g.bar_side_margin = std.fmt.parseInt(i32, val, 10) catch g.bar_side_margin;
        } else if (std.mem.eql(u8, key, "power_lock")) {
            copyTrunc(&g.power_lock, &g.power_lock_len, val);
        } else if (std.mem.eql(u8, key, "power_suspend")) {
            copyTrunc(&g.power_suspend, &g.power_suspend_len, val);
        } else if (std.mem.eql(u8, key, "power_reboot")) {
            copyTrunc(&g.power_reboot, &g.power_reboot_len, val);
        } else if (std.mem.eql(u8, key, "power_off")) {
            copyTrunc(&g.power_off, &g.power_off_len, val);
        } else if (std.mem.eql(u8, key, "launcher_entry")) {
            addCustomApp(val);
        }
    }
}

pub fn loadConfig() void {
    copyTrunc(&g.terminal, &g.terminal_len, "kitty");
    copyTrunc(&g.font, &g.font_len, "Inter");
    g.accent = .{ 0.886, 0.408, 0.31 };
    g.bg_rgb = .{ 0.039, 0.059, 0.102 };
    g.panel_bg = .{ 0.055, 0.075, 0.115 };
    g.panel_fg = .{ 0.93, 0.95, 0.98 };
    g.bar_height = 44;
    g.bar_top_margin = 12;
    g.bar_side_margin = 16;
    copyTrunc(&g.power_lock, &g.power_lock_len, "loginctl lock-session");
    copyTrunc(&g.power_suspend, &g.power_suspend_len, "systemctl suspend");
    copyTrunc(&g.power_reboot, &g.power_reboot_len, "systemctl reboot");
    copyTrunc(&g.power_off, &g.power_off_len, "systemctl poweroff");
    g.custom_count = 0;

    var path_buf: [512]u8 = undefined;
    var path: []const u8 = "";
    if (c.getenv("TESSA_CONFIG")) |p| {
        path = std.mem.span(p);
    } else if (c.getenv("XDG_CONFIG_HOME")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/tessa/config", .{std.mem.span(p)}) catch "";
    } else if (c.getenv("HOME")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/.config/tessa/config", .{std.mem.span(p)}) catch "";
    }
    if (path.len > 0) loadConfigFile(path, 0);
    g.bar_height = std.math.clamp(g.bar_height, 32, 96);
    g.bar_top_margin = std.math.clamp(g.bar_top_margin, 0, 64);
    g.bar_side_margin = std.math.clamp(g.bar_side_margin, 0, 128);
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

pub fn daysInMonth(year: i32, month: i32) i32 {
    return switch (month) {
        2 => if (@mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0)) 29 else 28,
        4, 6, 9, 11 => 30,
        else => 31,
    };
}

pub fn firstWeekday(year: i32, month: i32) i32 {
    var tm: c.tm = std.mem.zeroes(c.tm);
    tm.tm_year = @intCast(year - 1900);
    tm.tm_mon = @intCast(month - 1);
    tm.tm_mday = 1;
    tm.tm_isdst = -1;
    _ = c.mktime(&tm);
    return @mod(@as(i32, @intCast(tm.tm_wday)), 7);
}

pub fn resetCalendarToday() void {
    var t: c.time_t = c.time(null);
    var tm: c.tm = undefined;
    _ = c.localtime_r(&t, &tm);
    g.calendar_year = @as(i32, @intCast(tm.tm_year)) + 1900;
    g.calendar_month = @as(i32, @intCast(tm.tm_mon)) + 1;
}

pub fn shiftCalendar(months: i32) void {
    var month = g.calendar_month + months;
    var year = g.calendar_year;
    while (month > 12) {
        month -= 12;
        year += 1;
    }
    while (month < 1) {
        month += 12;
        year -= 1;
    }
    g.calendar_year = year;
    g.calendar_month = month;
}

pub fn powerCommand(index: usize) []const u8 {
    return switch (index) {
        0 => g.power_lock[0..g.power_lock_len],
        1 => g.power_suspend[0..g.power_suspend_len],
        2 => g.power_reboot[0..g.power_reboot_len],
        3 => g.power_off[0..g.power_off_len],
        else => "",
    };
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
