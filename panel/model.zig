const std = @import("std");
const c = @import("c.zig").c;
const apps = @import("apps.zig");

pub const MAX_WINDOWS = 64;
pub const MAX_OUTPUTS = 8;
pub const WS_COUNT = 9;
pub const MAX_WORKSPACE_NAME = 32;
pub const MAX_RESULTS = 256;
pub const MAX_STATUS = 8;
pub const MAX_CUSTOM_APPS = 16;
pub const POWER_ACTION_COUNT = 5;
pub const MAX_CLIPBOARD_ENTRIES = 8;
pub const MAX_CLIPBOARD_BYTES = 16384;
pub const MAX_NOTIFICATIONS = 4;
pub const MAX_NOTIFICATION_ACTIONS = 4;
pub const MAX_NOTIFICATION_ICON = 64;
pub const MAX_NOTIFICATION_ICON_BYTES = MAX_NOTIFICATION_ICON * MAX_NOTIFICATION_ICON * 4;
pub const MAX_TRAY_ITEMS = 8;
pub const MAX_TRAY_ICON = 32;
pub const MAX_TRAY_ICON_BYTES = MAX_TRAY_ICON * MAX_TRAY_ICON * 4;

pub const OverlayMode = enum { none, launcher, calendar, power, clipboard, screenshot, media, tray, audio };
pub const WallpaperFit = enum { cover, contain, stretch };
pub const BarModule = enum {
    logo,
    workspaces,
    chips,
    clock,
    battery,
    network,
    volume,
    stats,
    media,
    tray,
    status,
};
pub const BAR_MODULE_COUNT = @typeInfo(BarModule).@"enum".fields.len;

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
    notification,
    media,
    media_prev,
    media_toggle,
    media_next,
    tray,
    tray_entry,
    volume,
    audio_down,
    audio_mute,
    audio_up,
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
    scratchpad: bool = false,
    visible: bool = true,
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

pub const SurfaceKind = enum { background, bar, overlay, toasts };

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

pub const NotificationAction = struct {
    key: [64]u8 = [_]u8{0} ** 64,
    key_len: usize = 0,
    label: [96]u8 = [_]u8{0} ** 96,
    label_len: usize = 0,
};

pub const NotificationEntry = struct {
    id: u32 = 0,
    app: [64]u8 = [_]u8{0} ** 64,
    app_len: usize = 0,
    summary: [160]u8 = [_]u8{0} ** 160,
    summary_len: usize = 0,
    body: [512]u8 = [_]u8{0} ** 512,
    body_len: usize = 0,
    expire_ms: i64 = 0,
    actions: [MAX_NOTIFICATION_ACTIONS]NotificationAction = undefined,
    action_count: usize = 0,
    icon_w: u32 = 0,
    icon_h: u32 = 0,
    icon_len: usize = 0,
    icon_data: [MAX_NOTIFICATION_ICON_BYTES]u8 = [_]u8{0} ** MAX_NOTIFICATION_ICON_BYTES,
    icon_surface: ?*c.cairo_surface_t = null,
};

pub const ToastActionHit = struct {
    x: f64 = 0,
    y: f64 = 0,
    w: f64 = 0,
    h: f64 = 0,
    id: u32 = 0,
    action: usize = 0,
};

pub const TOAST_BASE_HEIGHT: i32 = 82;
pub const TOAST_ACTION_EXTRA: i32 = 30;

pub fn toastActionCount(n: *const NotificationEntry) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < n.action_count and i < n.actions.len) : (i += 1) {
        const action = &n.actions[i];
        if (action.key_len == 0 or
            std.mem.eql(u8, action.key[0..action.key_len], "default")) continue;
        count += 1;
        if (count >= 3) break;
    }
    return count;
}

pub fn toastHeight(n: *const NotificationEntry) i32 {
    return TOAST_BASE_HEIGHT + if (toastActionCount(n) > 0) TOAST_ACTION_EXTRA else 0;
}

pub const TrayItem = struct {
    title: [160]u8 = [_]u8{0} ** 160,
    title_len: usize = 0,
    icon_name: [128]u8 = [_]u8{0} ** 128,
    icon_name_len: usize = 0,
    status: u8 = 0,
    icon_w: u32 = 0,
    icon_h: u32 = 0,
    icon_len: usize = 0,
    icon_data: [MAX_TRAY_ICON_BYTES]u8 = [_]u8{0} ** MAX_TRAY_ICON_BYTES,
    icon_surface: ?*c.cairo_surface_t = null,
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
    touch: ?*c.wl_touch = null,
    touch_id: i32 = -1,

    xkb_ctx: ?*c.xkb_context = null,
    xkb_keymap: ?*c.xkb_keymap = null,
    xkb_state: ?*c.xkb_state = null,

    bar: Surface = undefined,
    bg: Surface = undefined,
    overlay: ?*Surface = null,
    overlay_mode: OverlayMode = .none,
    toasts: ?*Surface = null,
    toasts_output: [64]u8 = [_]u8{0} ** 64,
    toasts_output_len: usize = 0,

    outputs: [MAX_OUTPUTS]OutputInfo = [_]OutputInfo{.{}} ** MAX_OUTPUTS,
    output_count: usize = 0,
    target_output: ?*c.wl_output = null,
    target_name: [64]u8 = [_]u8{0} ** 64,
    target_name_len: usize = 0,
    target_make: [64]u8 = [_]u8{0} ** 64,
    target_make_len: usize = 0,
    target_model: [64]u8 = [_]u8{0} ** 64,
    target_model_len: usize = 0,
    target_serial: [64]u8 = [_]u8{0} ** 64,
    target_serial_len: usize = 0,
    focused_output_name: [64]u8 = [_]u8{0} ** 64,
    focused_output_name_len: usize = 0,
    is_focused_output: bool = false,
    scale: i32 = 1,

    active_ws: usize = 1,
    ws_names: [WS_COUNT][MAX_WORKSPACE_NAME]u8 = undefined,
    ws_name_lens: [WS_COUNT]usize = [_]usize{0} ** WS_COUNT,
    occ: [10]u32 = [_]u32{0} ** 10,
    focused_id: u64 = 0,
    windows: [MAX_WINDOWS]WindowInfo = undefined,
    window_count: usize = 0,
    statuses: [MAX_STATUS]StatusInfo = undefined,
    status_count: usize = 0,
    notifications: [MAX_NOTIFICATIONS]NotificationEntry = undefined,
    notification_count: usize = 0,
    notification_fd: c_int = -1,
    notification_buf: [65536]u8 = undefined,
    notification_len: usize = 0,
    notification_service_ready: bool = false,
    notification_owner: bool = true,
    toast_hits: [MAX_NOTIFICATIONS]HitRect = undefined,
    toast_hit_count: usize = 0,
    toast_action_hits: [MAX_NOTIFICATIONS * 3]ToastActionHit = undefined,
    toast_action_hit_count: usize = 0,

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
    battery_percent: i32 = -1,
    battery_charging: bool = false,
    network_present: bool = false,
    network_wireless: bool = false,
    network_label: [32]u8 = [_]u8{0} ** 32,
    network_label_len: usize = 0,
    media_status: u8 = 0,
    media_title: [160]u8 = [_]u8{0} ** 160,
    media_title_len: usize = 0,
    media_artist: [160]u8 = [_]u8{0} ** 160,
    media_artist_len: usize = 0,
    media_player: [64]u8 = [_]u8{0} ** 64,
    media_player_len: usize = 0,
    media_fd: c_int = -1,
    media_buf: [16384]u8 = undefined,
    media_len: usize = 0,
    tray_items: [MAX_TRAY_ITEMS]TrayItem = undefined,
    tray_count: usize = 0,
    tray_fd: c_int = -1,
    tray_buf: [131072]u8 = undefined,
    tray_len: usize = 0,
    tray_ready: bool = false,
    tray_selected: usize = 0,
    volume_percent: i32 = -1,
    volume_muted: bool = false,
    volume_source: [16]u8 = [_]u8{0} ** 16,
    volume_source_len: usize = 0,
    audio_fd: c_int = -1,
    audio_buf: [4096]u8 = undefined,
    audio_len: usize = 0,
    audio_ready: bool = false,
    volume_status: [512]u8 = [_]u8{0} ** 512,
    volume_status_len: usize = 0,
    volume_up: [512]u8 = [_]u8{0} ** 512,
    volume_up_len: usize = 0,
    volume_down: [512]u8 = [_]u8{0} ** 512,
    volume_down_len: usize = 0,
    volume_mute: [512]u8 = [_]u8{0} ** 512,
    volume_mute_len: usize = 0,

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

    screenshot_manager: ?*c.zwlr_screencopy_manager_v1 = null,
    screenshot_frame: ?*c.zwlr_screencopy_frame_v1 = null,
    screenshot_frame_listener: c.zwlr_screencopy_frame_v1_listener = undefined,
    screenshot_buffer: ?*c.wl_buffer = null,
    screenshot_data: ?*anyopaque = null,
    screenshot_size: usize = 0,
    screenshot_width: u32 = 0,
    screenshot_height: u32 = 0,
    screenshot_stride: u32 = 0,
    screenshot_format: u32 = 0,
    screenshot_pending: bool = false,
    screenshot_ready: bool = false,
    screenshot_dragging: bool = false,
    screenshot_start_x: f64 = 0,
    screenshot_start_y: f64 = 0,
    screenshot_end_x: f64 = 0,
    screenshot_end_y: f64 = 0,
    screenshot_dir: [512]u8 = [_]u8{0} ** 512,
    screenshot_dir_len: usize = 0,

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
    next_system_ms: i64 = 0,

    accent: [3]f64 = .{ 0.886, 0.408, 0.31 },
    bg_rgb: [3]f64 = .{ 0.039, 0.059, 0.102 },
    bg_top: [3]f64 = .{ 0, 0, 0 },
    bg_top_set: bool = false,
    bg_bottom: [3]f64 = .{ 0, 0, 0 },
    bg_bottom_set: bool = false,
    wallpaper_art: bool = true,
    wallpaper_image: [512]u8 = undefined,
    wallpaper_image_len: usize = 0,
    wallpaper_shader: [512]u8 = undefined,
    wallpaper_shader_len: usize = 0,
    wallpaper_fit: WallpaperFit = .cover,
    wallpaper_surface: ?*c.cairo_surface_t = null,
    panel_bg: [3]f64 = .{ 0.055, 0.075, 0.115 },
    panel_fg: [3]f64 = .{ 0.93, 0.95, 0.98 },
    bar_bg: [3]f64 = .{ 0.055, 0.075, 0.115 },
    launcher_bg: [3]f64 = .{ 0.055, 0.072, 0.105 },
    popover_bg: [3]f64 = .{ 0.055, 0.072, 0.105 },
    toast_bg: [3]f64 = .{ 0.055, 0.075, 0.115 },
    bar_fg: [3]f64 = .{ 0.93, 0.95, 0.98 },
    launcher_fg: [3]f64 = .{ 0.93, 0.95, 0.98 },
    popover_fg: [3]f64 = .{ 0.93, 0.95, 0.98 },
    toast_fg: [3]f64 = .{ 0.93, 0.95, 0.98 },
    bar_bg_set: bool = false,
    launcher_bg_set: bool = false,
    popover_bg_set: bool = false,
    toast_bg_set: bool = false,
    bar_fg_set: bool = false,
    launcher_fg_set: bool = false,
    popover_fg_set: bool = false,
    toast_fg_set: bool = false,
    bar_height: i32 = 44,
    bar_top_margin: i32 = 12,
    bar_side_margin: i32 = 16,
    bar_layout: [256]u8 = undefined,
    bar_layout_len: usize = 0,
    bar_layout_set: bool = false,
    bar_modules: [BAR_MODULE_COUNT]BarModule = .{
        .logo,
        .workspaces,
        .chips,
        .clock,
        .battery,
        .network,
        .volume,
        .stats,
        .media,
        .tray,
        .status,
    },
    bar_module_count: usize = BAR_MODULE_COUNT,
    show_logo: bool = true,
    show_workspaces: bool = true,
    show_chips: bool = true,
    show_clock: bool = true,
    show_battery: bool = true,
    show_network: bool = true,
    show_volume: bool = true,
    show_stats: bool = true,
    show_media: bool = true,
    show_tray: bool = true,
    show_status: bool = true,
    font: [64]u8 = undefined,
    font_len: usize = 0,
    bar_font: [64]u8 = undefined,
    bar_font_len: usize = 0,
    launcher_font: [64]u8 = undefined,
    launcher_font_len: usize = 0,
    popover_font: [64]u8 = undefined,
    popover_font_len: usize = 0,
    toast_font: [64]u8 = undefined,
    toast_font_len: usize = 0,
    terminal: [128]u8 = undefined,
    terminal_len: usize = 0,
    terminal_explicit: bool = false,
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

pub fn barFont() []const u8 {
    if (g.bar_font_len > 0) return g.bar_font[0..g.bar_font_len];
    return g.font[0..g.font_len];
}

pub fn launcherFont() []const u8 {
    if (g.launcher_font_len > 0) return g.launcher_font[0..g.launcher_font_len];
    return g.font[0..g.font_len];
}

pub fn popoverFont() []const u8 {
    if (g.popover_font_len > 0) return g.popover_font[0..g.popover_font_len];
    return g.font[0..g.font_len];
}

pub fn toastFont() []const u8 {
    if (g.toast_font_len > 0) return g.toast_font[0..g.toast_font_len];
    return g.font[0..g.font_len];
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

fn parseHexColor(hex_in: []const u8, out: *[3]f64) bool {
    var hex = hex_in;
    if (hex.len > 0 and hex[0] == '#') hex = hex[1..];
    if (hex.len < 6) return false;
    const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return false;
    const gg = std.fmt.parseInt(u8, hex[2..4], 16) catch return false;
    const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return false;
    out[0] = @as(f64, @floatFromInt(r)) / 255.0;
    out[1] = @as(f64, @floatFromInt(gg)) / 255.0;
    out[2] = @as(f64, @floatFromInt(b)) / 255.0;
    return true;
}

fn hexColor(hex_in: []const u8, out: *[3]f64) void {
    _ = parseHexColor(hex_in, out);
}

fn globMatch(pattern: []const u8, text: []const u8) bool {
    if (pattern.len == 0) return true;
    var p: usize = 0;
    var t: usize = 0;
    var star: ?usize = null;
    var star_text: usize = 0;
    while (t < text.len) {
        if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star = p;
            star_text = t;
            p += 1;
        } else if (star) |s| {
            star_text += 1;
            t = star_text;
            p = s + 1;
        } else {
            return false;
        }
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

const OutputTheme = struct {
    matched: bool = false,
    accent: ?[3]f64 = null,
    bg: ?[3]f64 = null,
    bg_top: ?[3]f64 = null,
    bg_bottom: ?[3]f64 = null,
    panel_bg: ?[3]f64 = null,
    panel_fg: ?[3]f64 = null,
    bar_height: ?i32 = null,
    bar_top_margin: ?i32 = null,
    bar_side_margin: ?i32 = null,
};

var output_theme: OutputTheme = .{};

const ThemeRole = struct {
    name: [32]u8 = [_]u8{0} ** 32,
    name_len: usize = 0,
    color: [3]f64 = .{ 0, 0, 0 },
};

var theme_roles: [16]ThemeRole = undefined;
var theme_role_count: usize = 0;

fn parseThemeRole(value: []const u8) void {
    const eq = std.mem.indexOfScalar(u8, value, '=') orelse return;
    const name = trim(value[0..eq]);
    var color_text = trim(value[eq + 1 ..]);
    if (color_text.len >= 2 and
        ((color_text[0] == '"' and color_text[color_text.len - 1] == '"') or
            (color_text[0] == '\'' and color_text[color_text.len - 1] == '\'')))
    {
        color_text = color_text[1 .. color_text.len - 1];
    }
    var color: [3]f64 = undefined;
    if (!parseHexColor(color_text, &color)) return;

    var existing: ?usize = null;
    var i: usize = 0;
    while (i < theme_role_count) : (i += 1) {
        if (std.mem.eql(u8, theme_roles[i].name[0..theme_roles[i].name_len], name)) {
            existing = i;
            break;
        }
    }
    const index = existing orelse blk: {
        if (theme_role_count >= theme_roles.len) return;
        const n = theme_role_count;
        theme_role_count += 1;
        theme_roles[n] = .{};
        break :blk n;
    };
    const role = &theme_roles[index];
    copyTrunc(&role.name, &role.name_len, name);
    role.color = color;
}

fn applyThemeRoles() void {
    var i: usize = 0;
    while (i < theme_role_count) : (i += 1) {
        const role = &theme_roles[i];
        const name = role.name[0..role.name_len];
        if (std.mem.eql(u8, name, "accent")) {
            g.accent = role.color;
        } else if (std.mem.eql(u8, name, "window.background")) {
            g.bg_rgb = role.color;
        } else if (std.mem.eql(u8, name, "panel.background")) {
            g.panel_bg = role.color;
            if (!g.bar_bg_set) g.bar_bg = role.color;
            if (!g.launcher_bg_set) g.launcher_bg = role.color;
            if (!g.popover_bg_set) g.popover_bg = role.color;
            if (!g.toast_bg_set) g.toast_bg = role.color;
        } else if (std.mem.eql(u8, name, "panel.foreground")) {
            g.panel_fg = role.color;
            if (!g.bar_fg_set) g.bar_fg = role.color;
            if (!g.launcher_fg_set) g.launcher_fg = role.color;
            if (!g.popover_fg_set) g.popover_fg = role.color;
            if (!g.toast_fg_set) g.toast_fg = role.color;
        } else if (std.mem.eql(u8, name, "bar.background")) {
            g.bar_bg = role.color;
        } else if (std.mem.eql(u8, name, "launcher.background")) {
            g.launcher_bg = role.color;
        } else if (std.mem.eql(u8, name, "popover.background")) {
            g.popover_bg = role.color;
        } else if (std.mem.eql(u8, name, "toast.background")) {
            g.toast_bg = role.color;
        } else if (std.mem.eql(u8, name, "bar.foreground")) {
            g.bar_fg = role.color;
        } else if (std.mem.eql(u8, name, "launcher.foreground")) {
            g.launcher_fg = role.color;
        } else if (std.mem.eql(u8, name, "popover.foreground")) {
            g.popover_fg = role.color;
        } else if (std.mem.eql(u8, name, "toast.foreground")) {
            g.toast_fg = role.color;
        } else if (std.mem.eql(u8, name, "wallpaper.top")) {
            g.bg_top = role.color;
            g.bg_top_set = true;
        } else if (std.mem.eql(u8, name, "wallpaper.bottom")) {
            g.bg_bottom = role.color;
            g.bg_bottom_set = true;
        }
    }
}

fn applyOutputTheme() void {
    if (!output_theme.matched) return;
    if (output_theme.accent) |v| g.accent = v;
    if (output_theme.bg) |v| g.bg_rgb = v;
    if (output_theme.bg_top) |v| {
        g.bg_top = v;
        g.bg_top_set = true;
    }
    if (output_theme.bg_bottom) |v| {
        g.bg_bottom = v;
        g.bg_bottom_set = true;
    }
    if (output_theme.panel_bg) |v| {
        g.panel_bg = v;
        if (!g.bar_bg_set) g.bar_bg = v;
        if (!g.launcher_bg_set) g.launcher_bg = v;
        if (!g.popover_bg_set) g.popover_bg = v;
        if (!g.toast_bg_set) g.toast_bg = v;
    }
    if (output_theme.panel_fg) |v| {
        g.panel_fg = v;
        if (!g.bar_fg_set) g.bar_fg = v;
        if (!g.launcher_fg_set) g.launcher_fg = v;
        if (!g.popover_fg_set) g.popover_fg = v;
        if (!g.toast_fg_set) g.toast_fg = v;
    }
    if (output_theme.bar_height) |v| g.bar_height = v;
    if (output_theme.bar_top_margin) |v| g.bar_top_margin = v;
    if (output_theme.bar_side_margin) |v| g.bar_side_margin = v;
}

fn parseOutputTheme(value: []const u8) void {
    var theme = OutputTheme{};
    var output_buf: [64]u8 = undefined;
    var output_len: usize = 0;
    var make_buf: [64]u8 = undefined;
    var make_len: usize = 0;
    var model_buf: [64]u8 = undefined;
    var model_len: usize = 0;
    var serial_buf: [64]u8 = undefined;
    var serial_len: usize = 0;
    var ws: usize = 0;

    var clauses = std.mem.splitScalar(u8, value, ';');
    while (clauses.next()) |raw| {
        const clause = trim(raw);
        if (clause.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, clause, '=') orelse continue;
        const key = trim(clause[0..eq]);
        var val = trim(clause[eq + 1 ..]);
        if (val.len >= 2 and
            ((val[0] == '"' and val[val.len - 1] == '"') or
                (val[0] == '\'' and val[val.len - 1] == '\'')))
        {
            val = val[1 .. val.len - 1];
        }
        if (std.mem.eql(u8, key, "output") or std.mem.eql(u8, key, "monitor")) {
            output_len = @min(val.len, output_buf.len);
            @memcpy(output_buf[0..output_len], val[0..output_len]);
        } else if (std.mem.eql(u8, key, "make") or std.mem.eql(u8, key, "vendor")) {
            make_len = @min(val.len, make_buf.len);
            @memcpy(make_buf[0..make_len], val[0..make_len]);
        } else if (std.mem.eql(u8, key, "model")) {
            model_len = @min(val.len, model_buf.len);
            @memcpy(model_buf[0..model_len], val[0..model_len]);
        } else if (std.mem.eql(u8, key, "serial") or std.mem.eql(u8, key, "edid-serial")) {
            serial_len = @min(val.len, serial_buf.len);
            @memcpy(serial_buf[0..serial_len], val[0..serial_len]);
        } else if (std.mem.eql(u8, key, "ws") or std.mem.eql(u8, key, "workspace")) {
            ws = std.fmt.parseInt(usize, val, 10) catch 0;
        } else if (std.mem.eql(u8, key, "accent")) {
            var v: [3]f64 = undefined;
            if (parseHexColor(val, &v)) theme.accent = v;
        } else if (std.mem.eql(u8, key, "bg")) {
            var v: [3]f64 = undefined;
            if (parseHexColor(val, &v)) theme.bg = v;
        } else if (std.mem.eql(u8, key, "bg_top") or std.mem.eql(u8, key, "bg-top")) {
            var v: [3]f64 = undefined;
            if (parseHexColor(val, &v)) theme.bg_top = v;
        } else if (std.mem.eql(u8, key, "bg_bottom") or std.mem.eql(u8, key, "bg-bottom")) {
            var v: [3]f64 = undefined;
            if (parseHexColor(val, &v)) theme.bg_bottom = v;
        } else if (std.mem.eql(u8, key, "panel_bg") or std.mem.eql(u8, key, "panel-bg")) {
            var v: [3]f64 = undefined;
            if (parseHexColor(val, &v)) theme.panel_bg = v;
        } else if (std.mem.eql(u8, key, "panel_fg") or std.mem.eql(u8, key, "panel-fg")) {
            var v: [3]f64 = undefined;
            if (parseHexColor(val, &v)) theme.panel_fg = v;
        } else if (std.mem.eql(u8, key, "bar_height") or std.mem.eql(u8, key, "bar-height")) {
            theme.bar_height = std.fmt.parseInt(i32, val, 10) catch null;
        } else if (std.mem.eql(u8, key, "bar_top_margin") or std.mem.eql(u8, key, "bar-top-margin")) {
            theme.bar_top_margin = std.fmt.parseInt(i32, val, 10) catch null;
        } else if (std.mem.eql(u8, key, "bar_side_margin") or std.mem.eql(u8, key, "bar-side-margin")) {
            theme.bar_side_margin = std.fmt.parseInt(i32, val, 10) catch null;
        }
    }

    if (ws != 0) return;
    if (output_len == 0 and make_len == 0 and model_len == 0 and serial_len == 0) return;
    if (output_len > 0 and
        !globMatch(output_buf[0..output_len], g.target_name[0..g.target_name_len])) return;
    if (make_len > 0 and
        !globMatch(make_buf[0..make_len], g.target_make[0..g.target_make_len])) return;
    if (model_len > 0 and
        !globMatch(model_buf[0..model_len], g.target_model[0..g.target_model_len])) return;
    if (serial_len > 0 and
        !globMatch(serial_buf[0..serial_len], g.target_serial[0..g.target_serial_len])) return;
    output_theme.matched = true;
    if (theme.accent) |v| output_theme.accent = v;
    if (theme.bg) |v| output_theme.bg = v;
    if (theme.bg_top) |v| output_theme.bg_top = v;
    if (theme.bg_bottom) |v| output_theme.bg_bottom = v;
    if (theme.panel_bg) |v| output_theme.panel_bg = v;
    if (theme.panel_fg) |v| output_theme.panel_fg = v;
    if (theme.bar_height) |v| output_theme.bar_height = v;
    if (theme.bar_top_margin) |v| output_theme.bar_top_margin = v;
    if (theme.bar_side_margin) |v| output_theme.bar_side_margin = v;
}

fn parseWorkspaceName(value: []const u8) void {
    var it = std.mem.tokenizeAny(u8, value, " \t");
    const ws_text = it.next() orelse return;
    const name = it.next() orelse return;
    if (it.next() != null) return;
    const ws = std.fmt.parseInt(usize, ws_text, 10) catch return;
    if (ws < 1 or ws > WS_COUNT) return;
    if (name.len == 0 or name.len >= MAX_WORKSPACE_NAME) return;
    const index = ws - 1;
    copyTrunc(&g.ws_names[index], &g.ws_name_lens[index], name);
}

fn parsePanelBool(value: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "on") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.mem.eql(u8, value, "1")) return true;
    if (std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "off") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.mem.eql(u8, value, "0")) return false;
    return null;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn disableAllBarModules() void {
    g.show_logo = false;
    g.show_workspaces = false;
    g.show_chips = false;
    g.show_clock = false;
    g.show_battery = false;
    g.show_network = false;
    g.show_volume = false;
    g.show_stats = false;
    g.show_media = false;
    g.show_tray = false;
    g.show_status = false;
}

/// Comma/space-separated module list. Unknown names are ignored so a panel
/// can run with a config written for a newer Tessa build. The listed order is
/// used for the right-hand cluster; the logo, workspace pills, and window chips
/// keep their anchored positions.
fn parseBarLayout(value: []const u8) void {
    disableAllBarModules();
    g.bar_module_count = 0;
    var it = std.mem.tokenizeAny(u8, value, ", \t|");
    while (it.next()) |raw| {
        const name = trim(raw);
        const module: BarModule = if (std.mem.eql(u8, name, "logo") or std.mem.eql(u8, name, "mark"))
            .logo
        else if (std.mem.eql(u8, name, "workspaces") or std.mem.eql(u8, name, "workspace"))
            .workspaces
        else if (std.mem.eql(u8, name, "title") or std.mem.eql(u8, name, "chips") or
            std.mem.eql(u8, name, "windows"))
            .chips
        else if (std.mem.eql(u8, name, "clock") or std.mem.eql(u8, name, "date"))
            .clock
        else if (std.mem.eql(u8, name, "battery"))
            .battery
        else if (std.mem.eql(u8, name, "network"))
            .network
        else if (std.mem.eql(u8, name, "volume") or std.mem.eql(u8, name, "audio"))
            .volume
        else if (std.mem.eql(u8, name, "stats") or std.mem.eql(u8, name, "cpu") or
            std.mem.eql(u8, name, "memory"))
            .stats
        else if (std.mem.eql(u8, name, "media"))
            .media
        else if (std.mem.eql(u8, name, "tray"))
            .tray
        else if (std.mem.eql(u8, name, "status"))
            .status
        else
            continue;

        var seen = false;
        for (g.bar_modules[0..g.bar_module_count]) |existing| {
            if (existing == module) {
                seen = true;
                break;
            }
        }
        if (seen) continue;
        if (g.bar_module_count < g.bar_modules.len) {
            g.bar_modules[g.bar_module_count] = module;
            g.bar_module_count += 1;
        }

        switch (module) {
            .logo => g.show_logo = true,
            .workspaces => g.show_workspaces = true,
            .chips => g.show_chips = true,
            .clock => g.show_clock = true,
            .battery => g.show_battery = true,
            .network => g.show_network = true,
            .volume => g.show_volume = true,
            .stats => g.show_stats = true,
            .media => g.show_media = true,
            .tray => g.show_tray = true,
            .status => g.show_status = true,
        }
    }
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
        } else if (std.mem.eql(u8, key, "output-rule") or std.mem.eql(u8, key, "output_rule")) {
            parseOutputTheme(val);
        } else if (std.mem.eql(u8, key, "workspace-name") or std.mem.eql(u8, key, "workspace_name")) {
            parseWorkspaceName(val);
        } else if (std.mem.eql(u8, key, "theme-role") or std.mem.eql(u8, key, "theme_role")) {
            parseThemeRole(val);
        } else if (std.mem.eql(u8, key, "terminal")) {
            copyTrunc(&g.terminal, &g.terminal_len, val);
            g.terminal_explicit = true;
        } else if (std.mem.eql(u8, key, "font")) {
            copyTrunc(&g.font, &g.font_len, val);
        } else if (std.mem.eql(u8, key, "bar_font") or std.mem.eql(u8, key, "bar-font")) {
            copyTrunc(&g.bar_font, &g.bar_font_len, val);
        } else if (std.mem.eql(u8, key, "launcher_font") or std.mem.eql(u8, key, "launcher-font")) {
            copyTrunc(&g.launcher_font, &g.launcher_font_len, val);
        } else if (std.mem.eql(u8, key, "popover_font") or std.mem.eql(u8, key, "popover-font")) {
            copyTrunc(&g.popover_font, &g.popover_font_len, val);
        } else if (std.mem.eql(u8, key, "toast_font") or std.mem.eql(u8, key, "toast-font")) {
            copyTrunc(&g.toast_font, &g.toast_font_len, val);
        } else if (std.mem.eql(u8, key, "bar_layout") or std.mem.eql(u8, key, "bar-layout") or
            std.mem.eql(u8, key, "bar_modules") or std.mem.eql(u8, key, "bar-modules"))
        {
            copyTrunc(&g.bar_layout, &g.bar_layout_len, val);
            g.bar_layout_set = true;
            parseBarLayout(val);
        } else if (std.mem.eql(u8, key, "bar_bg") or std.mem.eql(u8, key, "bar-bg")) {
            hexColor(val, &g.bar_bg);
            g.bar_bg_set = true;
        } else if (std.mem.eql(u8, key, "launcher_bg") or std.mem.eql(u8, key, "launcher-bg")) {
            hexColor(val, &g.launcher_bg);
            g.launcher_bg_set = true;
        } else if (std.mem.eql(u8, key, "popover_bg") or std.mem.eql(u8, key, "popover-bg")) {
            hexColor(val, &g.popover_bg);
            g.popover_bg_set = true;
        } else if (std.mem.eql(u8, key, "toast_bg") or std.mem.eql(u8, key, "toast-bg")) {
            hexColor(val, &g.toast_bg);
            g.toast_bg_set = true;
        } else if (std.mem.eql(u8, key, "bar_fg") or std.mem.eql(u8, key, "bar-fg")) {
            hexColor(val, &g.bar_fg);
            g.bar_fg_set = true;
        } else if (std.mem.eql(u8, key, "launcher_fg") or std.mem.eql(u8, key, "launcher-fg")) {
            hexColor(val, &g.launcher_fg);
            g.launcher_fg_set = true;
        } else if (std.mem.eql(u8, key, "popover_fg") or std.mem.eql(u8, key, "popover-fg")) {
            hexColor(val, &g.popover_fg);
            g.popover_fg_set = true;
        } else if (std.mem.eql(u8, key, "toast_fg") or std.mem.eql(u8, key, "toast-fg")) {
            hexColor(val, &g.toast_fg);
            g.toast_fg_set = true;
        } else if (std.mem.eql(u8, key, "accent")) {
            hexColor(val, &g.accent);
        } else if (std.mem.eql(u8, key, "bg")) {
            hexColor(val, &g.bg_rgb);
        } else if (std.mem.eql(u8, key, "bg_top")) {
            hexColor(val, &g.bg_top);
            g.bg_top_set = true;
        } else if (std.mem.eql(u8, key, "bg_bottom")) {
            hexColor(val, &g.bg_bottom);
            g.bg_bottom_set = true;
        } else if (std.mem.eql(u8, key, "wallpaper_art")) {
            g.wallpaper_art = parsePanelBool(val) orelse g.wallpaper_art;
        } else if (std.mem.eql(u8, key, "wallpaper_image") or std.mem.eql(u8, key, "wallpaper-image")) {
            copyTrunc(&g.wallpaper_image, &g.wallpaper_image_len, val);
        } else if (std.mem.eql(u8, key, "wallpaper_shader") or std.mem.eql(u8, key, "wallpaper-shader")) {
            copyTrunc(&g.wallpaper_shader, &g.wallpaper_shader_len, val);
        } else if (std.mem.eql(u8, key, "wallpaper_fit") or std.mem.eql(u8, key, "wallpaper-fit")) {
            if (std.mem.eql(u8, val, "cover")) {
                g.wallpaper_fit = .cover;
            } else if (std.mem.eql(u8, val, "contain")) {
                g.wallpaper_fit = .contain;
            } else if (std.mem.eql(u8, val, "stretch")) {
                g.wallpaper_fit = .stretch;
            }
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
        } else if (std.mem.eql(u8, key, "screenshot_dir")) {
            copyTrunc(&g.screenshot_dir, &g.screenshot_dir_len, val);
        } else if (std.mem.eql(u8, key, "volume_status")) {
            copyTrunc(&g.volume_status, &g.volume_status_len, val);
        } else if (std.mem.eql(u8, key, "volume_up")) {
            copyTrunc(&g.volume_up, &g.volume_up_len, val);
        } else if (std.mem.eql(u8, key, "volume_down")) {
            copyTrunc(&g.volume_down, &g.volume_down_len, val);
        } else if (std.mem.eql(u8, key, "volume_mute")) {
            copyTrunc(&g.volume_mute, &g.volume_mute_len, val);
        } else if (std.mem.eql(u8, key, "launcher_entry")) {
            addCustomApp(val);
        }
    }
}

fn loadWallpaperShader() bool {
    const command = g.wallpaper_shader[0..g.wallpaper_shader_len];
    if (command.len == 0) return false;
    var command_z: [512:0]u8 = undefined;
    if (command.len >= command_z.len) return false;
    @memcpy(command_z[0..command.len], command);
    command_z[command.len] = 0;

    const pipe = c.popen(&command_z, "r") orelse {
        std.debug.print("tessa-panel: wallpaper shader could not start: {s}\n", .{command});
        return false;
    };
    var magic: [3]u8 = undefined;
    var width: c_int = 0;
    var height: c_int = 0;
    var maxval: c_int = 0;
    if (c.fscanf(pipe, "%2s %d %d %d", &magic, &width, &height, &maxval) != 4 or
        !std.mem.eql(u8, magic[0..2], "P6") or
        width < 1 or height < 1 or width > 4096 or height > 4096 or maxval != 255)
    {
        _ = c.pclose(pipe);
        std.debug.print("tessa-panel: wallpaper shader must emit binary PPM P6 (maxval 255)\n", .{});
        return false;
    }
    // fscanf leaves exactly one whitespace character before the pixel data.
    _ = c.fgetc(pipe);
    const pixels = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * 3;
    const rgb = @as(?[*]u8, @ptrCast(c.malloc(pixels))) orelse {
        _ = c.pclose(pipe);
        return false;
    };
    defer c.free(rgb);
    const got = c.fread(rgb, 1, pixels, pipe);
    const rc = c.pclose(pipe);
    if (got != pixels or rc != 0) {
        std.debug.print("tessa-panel: wallpaper shader did not emit a complete PPM frame\n", .{});
        return false;
    }

    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, height);
    if (surface == null or c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
        if (surface) |s| c.cairo_surface_destroy(s);
        return false;
    }
    const stride: usize = @intCast(c.cairo_image_surface_get_stride(surface));
    const data = c.cairo_image_surface_get_data(surface);
    if (data == null) {
        c.cairo_surface_destroy(surface);
        return false;
    }
    const bytes = data[0 .. stride * @as(usize, @intCast(height))];
    var y: usize = 0;
    while (y < @as(usize, @intCast(height))) : (y += 1) {
        var x: usize = 0;
        while (x < @as(usize, @intCast(width))) : (x += 1) {
            const src = (y * @as(usize, @intCast(width)) + x) * 3;
            const dst = y * stride + x * 4;
            const r: u32 = rgb[src];
            const gg: u32 = rgb[src + 1];
            const b: u32 = rgb[src + 2];
            const px: u32 = 0xff000000 | (r << 16) | (gg << 8) | b;
            std.mem.writeInt(u32, bytes[dst..][0..4], px, .little);
        }
    }
    c.cairo_surface_mark_dirty(surface);
    g.wallpaper_surface = surface;
    std.debug.print("tessa-panel: wallpaper shader frame {d}x{d}\n", .{ width, height });
    return true;
}

fn loadWallpaperImage() void {
    if (g.wallpaper_surface) |surface| c.cairo_surface_destroy(surface);
    g.wallpaper_surface = null;
    if (loadWallpaperShader()) return;
    if (g.wallpaper_image_len == 0) return;

    var path_buf: [512:0]u8 = undefined;
    const path = g.wallpaper_image[0..g.wallpaper_image_len];
    if (path.len >= 2 and path[0] == '~' and path[1] == '/') {
        const home_ptr = c.getenv("HOME") orelse {
            std.debug.print("tessa-panel: wallpaper_image cannot expand ~ without HOME\n", .{});
            return;
        };
        const full = std.fmt.bufPrint(path_buf[0..511], "{s}/{s}", .{
            std.mem.span(home_ptr),
            path[2..],
        }) catch return;
        path_buf[full.len] = 0;
    } else {
        if (path.len >= path_buf.len) return;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;
    }

    const surface = c.cairo_image_surface_create_from_png(&path_buf);
    if (surface == null or c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
        if (surface) |s| c.cairo_surface_destroy(s);
        std.debug.print("tessa-panel: cannot load wallpaper image {s}\n", .{path});
        return;
    }
    g.wallpaper_surface = surface;
    std.debug.print("tessa-panel: wallpaper image {s} ({d}x{d})\n", .{
        path,
        c.cairo_image_surface_get_width(surface),
        c.cairo_image_surface_get_height(surface),
    });
}

fn panelCommandExists(cmd: []const u8) bool {
    if (cmd.len == 0) return false;
    if (std.mem.indexOfScalar(u8, cmd, '/') != null) {
        var z: [512:0]u8 = undefined;
        if (cmd.len >= z.len) return false;
        @memcpy(z[0..cmd.len], cmd);
        z[cmd.len] = 0;
        return c.access(&z, c.X_OK) == 0;
    }
    const path = c.getenv("PATH") orelse return false;
    var it = std.mem.splitScalar(u8, std.mem.span(path), ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        var z: [1024:0]u8 = undefined;
        const line = std.fmt.bufPrint(&z, "{s}/{s}", .{ dir, cmd }) catch continue;
        z[line.len] = 0;
        if (c.access(&z, c.X_OK) == 0) return true;
    }
    return false;
}

fn resolveTerminal() void {
    var first = g.terminal[0..g.terminal_len];
    if (std.mem.indexOfAny(u8, first, " \t")) |space| first = first[0..space];
    var first_buf: [128]u8 = undefined;
    const requested = first[0..@min(first.len, first_buf.len)];
    @memcpy(first_buf[0..requested.len], requested);
    const requested_text = first_buf[0..requested.len];
    if (panelCommandExists(requested_text)) return;
    if (g.terminal_explicit) {
        std.debug.print("tessa-panel: configured terminal '{s}' was not found in PATH\n", .{requested_text});
        return;
    }
    const fallbacks = [_][]const u8{ "foot", "kitty", "alacritty", "wezterm", "xterm" };
    for (fallbacks) |candidate| {
        if (!panelCommandExists(candidate)) continue;
        copyTrunc(&g.terminal, &g.terminal_len, candidate);
        std.debug.print("tessa-panel: terminal '{s}' not found; using '{s}'\n", .{ requested_text, candidate });
        return;
    }
    std.debug.print("tessa-panel: no terminal found; launcher Terminal apps will not start\n", .{});
}

pub fn loadConfig() void {
    copyTrunc(&g.terminal, &g.terminal_len, "kitty");
    g.terminal_explicit = false;
    copyTrunc(&g.font, &g.font_len, "Inter");
    g.bar_font_len = 0;
    g.launcher_font_len = 0;
    g.popover_font_len = 0;
    g.toast_font_len = 0;
    g.bar_layout_len = 0;
    g.bar_layout_set = false;
    g.bar_modules = .{
        .logo,
        .workspaces,
        .chips,
        .clock,
        .battery,
        .network,
        .volume,
        .stats,
        .media,
        .tray,
        .status,
    };
    g.bar_module_count = BAR_MODULE_COUNT;
    g.show_logo = true;
    g.show_workspaces = true;
    g.show_chips = true;
    g.show_clock = true;
    g.show_battery = true;
    g.show_network = true;
    g.show_volume = true;
    g.show_stats = true;
    g.show_media = true;
    g.show_tray = true;
    g.show_status = true;
    g.accent = .{ 0.886, 0.408, 0.31 };
    g.bg_rgb = .{ 0.039, 0.059, 0.102 };
    g.bg_top = .{ 0, 0, 0 };
    g.bg_top_set = false;
    g.bg_bottom = .{ 0, 0, 0 };
    g.bg_bottom_set = false;
    g.wallpaper_art = true;
    g.panel_bg = .{ 0.055, 0.075, 0.115 };
    g.panel_fg = .{ 0.93, 0.95, 0.98 };
    g.bar_bg = g.panel_bg;
    g.launcher_bg = .{ 0.055, 0.072, 0.105 };
    g.popover_bg = .{ 0.055, 0.072, 0.105 };
    g.toast_bg = g.panel_bg;
    g.bar_fg = g.panel_fg;
    g.launcher_fg = g.panel_fg;
    g.popover_fg = g.panel_fg;
    g.toast_fg = g.panel_fg;
    g.bar_bg_set = false;
    g.launcher_bg_set = false;
    g.popover_bg_set = false;
    g.toast_bg_set = false;
    g.bar_fg_set = false;
    g.launcher_fg_set = false;
    g.popover_fg_set = false;
    g.toast_fg_set = false;
    g.bar_height = 44;
    g.bar_top_margin = 12;
    g.bar_side_margin = 16;
    copyTrunc(&g.power_lock, &g.power_lock_len, "loginctl lock-session");
    copyTrunc(&g.power_suspend, &g.power_suspend_len, "systemctl suspend");
    copyTrunc(&g.power_reboot, &g.power_reboot_len, "systemctl reboot");
    copyTrunc(&g.power_off, &g.power_off_len, "systemctl poweroff");
    copyTrunc(&g.screenshot_dir, &g.screenshot_dir_len, "~/Pictures/Screenshots");
    g.custom_count = 0;
    output_theme = .{};
    theme_role_count = 0;
    g.wallpaper_image_len = 0;
    g.wallpaper_shader_len = 0;
    g.wallpaper_fit = .cover;
    if (g.wallpaper_surface) |surface| {
        c.cairo_surface_destroy(surface);
        g.wallpaper_surface = null;
    }
    var wsn: usize = 0;
    while (wsn < WS_COUNT) : (wsn += 1) g.ws_name_lens[wsn] = 0;

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
    resolveTerminal();
    applyThemeRoles();
    applyOutputTheme();
    loadWallpaperImage();
    g.bar_height = std.math.clamp(g.bar_height, 32, 96);
    g.bar_top_margin = std.math.clamp(g.bar_top_margin, 0, 64);
    g.bar_side_margin = std.math.clamp(g.bar_side_margin, 0, 128);
}

/// Resolved panel settings for `tessa-panel --check` and config tooling.
pub fn printConfigSummary() void {
    std.debug.print("panel font={s}\n", .{g.font[0..g.font_len]});
    std.debug.print("panel bar-font={s} launcher-font={s} popover-font={s} toast-font={s}\n", .{
        barFont(),
        launcherFont(),
        popoverFont(),
        toastFont(),
    });
    std.debug.print("panel bar-bg={d:.3},{d:.3},{d:.3} launcher-bg={d:.3},{d:.3},{d:.3} popover-bg={d:.3},{d:.3},{d:.3} toast-bg={d:.3},{d:.3},{d:.3}\n", .{
        g.bar_bg[0],      g.bar_bg[1],      g.bar_bg[2],
        g.launcher_bg[0], g.launcher_bg[1], g.launcher_bg[2],
        g.popover_bg[0],  g.popover_bg[1],  g.popover_bg[2],
        g.toast_bg[0],    g.toast_bg[1],    g.toast_bg[2],
    });
    std.debug.print("panel bar-fg={d:.3},{d:.3},{d:.3} launcher-fg={d:.3},{d:.3},{d:.3} popover-fg={d:.3},{d:.3},{d:.3} toast-fg={d:.3},{d:.3},{d:.3}\n", .{
        g.bar_fg[0],      g.bar_fg[1],      g.bar_fg[2],
        g.launcher_fg[0], g.launcher_fg[1], g.launcher_fg[2],
        g.popover_fg[0],  g.popover_fg[1],  g.popover_fg[2],
        g.toast_fg[0],    g.toast_fg[1],    g.toast_fg[2],
    });
    std.debug.print("panel bar-layout={s}\n", .{g.bar_layout[0..g.bar_layout_len]});
    std.debug.print("panel modules=", .{});
    for (g.bar_modules[0..g.bar_module_count], 0..) |module, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{s}", .{@tagName(module)});
    }
    std.debug.print("\n", .{});
    std.debug.print("panel wallpaper-shader={s} wallpaper-image={s} fit={s}\n", .{
        g.wallpaper_shader[0..g.wallpaper_shader_len],
        g.wallpaper_image[0..g.wallpaper_image_len],
        @tagName(g.wallpaper_fit),
    });
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

fn readTextFile(path: []const u8, buf: []u8) []const u8 {
    if (path.len == 0 or path.len >= 1024 or buf.len < 2) return "";
    var zpath: [1024:0]u8 = undefined;
    @memcpy(zpath[0..path.len], path);
    zpath[path.len] = 0;
    const file = c.fopen(&zpath, "r") orelse return "";
    defer _ = c.fclose(file);
    const n = c.fread(buf.ptr, 1, buf.len - 1, file);
    buf[n] = 0;
    return buf[0..n];
}

fn environmentPath(name: [*:0]const u8, fallback: []const u8) []const u8 {
    if (c.getenv(name)) |value| return std.mem.span(value);
    return fallback;
}

fn readBattery() bool {
    const base = environmentPath("TESSA_POWER_SUPPLY_PATH", "/sys/class/power_supply");
    if (base.len >= 496) return false;
    var base_z: [512:0]u8 = undefined;
    @memcpy(base_z[0..base.len], base);
    base_z[base.len] = 0;
    const dir = c.opendir(&base_z) orelse return false;
    defer _ = c.closedir(dir);

    while (c.readdir(dir)) |ent| {
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&ent.*.d_name)));
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        var path_buf: [1024]u8 = undefined;
        var type_buf: [32]u8 = undefined;
        const type_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/type", .{ base, name }) catch continue;
        const kind = trim(readTextFile(type_path, &type_buf));
        if (!std.ascii.eqlIgnoreCase(kind, "Battery")) continue;

        var capacity_buf: [32]u8 = undefined;
        const capacity_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/capacity", .{ base, name }) catch continue;
        const capacity = std.fmt.parseInt(i32, trim(readTextFile(capacity_path, &capacity_buf)), 10) catch continue;
        if (capacity < 0 or capacity > 100) continue;

        var status_buf: [64]u8 = undefined;
        const status_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/status", .{ base, name }) catch continue;
        const status = trim(readTextFile(status_path, &status_buf));
        g.battery_percent = capacity;
        g.battery_charging = std.ascii.eqlIgnoreCase(status, "Charging") or
            std.ascii.eqlIgnoreCase(status, "Full");
        return true;
    }
    return false;
}

fn readNetwork() bool {
    const route_path = environmentPath("TESSA_ROUTE_PATH", "/proc/net/route");
    const net_base = environmentPath("TESSA_NET_PATH", "/sys/class/net");
    var route_buf: [8192]u8 = undefined;
    const routes = readTextFile(route_path, &route_buf);
    if (routes.len == 0) return false;

    var best_iface: [64]u8 = undefined;
    var best_len: usize = 0;
    var best_metric: u32 = std.math.maxInt(u32);
    var lines = std.mem.splitScalar(u8, routes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const iface = fields.next() orelse continue;
        const destination = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const flags_s = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const metric_s = fields.next() orelse continue;
        if (!std.mem.eql(u8, destination, "00000000")) continue;
        const flags = std.fmt.parseInt(u32, flags_s, 16) catch continue;
        if ((flags & 1) == 0) continue;
        if (iface.len >= best_iface.len) continue;
        const metric = std.fmt.parseInt(u32, metric_s, 10) catch 0;
        if (metric >= best_metric) continue;
        @memcpy(best_iface[0..iface.len], iface);
        best_len = iface.len;
        best_metric = metric;
    }
    if (best_len == 0) {
        g.network_present = false;
        return false;
    }

    var path_buf: [1024]u8 = undefined;
    var state_buf: [32]u8 = undefined;
    const iface = best_iface[0..best_len];
    const state_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/operstate", .{ net_base, iface }) catch return false;
    const state = trim(readTextFile(state_path, &state_buf));
    if (!std.mem.eql(u8, state, "up")) {
        g.network_present = false;
        return false;
    }

    const wireless_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/wireless", .{ net_base, iface }) catch return false;
    var zpath: [1024:0]u8 = undefined;
    @memcpy(zpath[0..wireless_path.len], wireless_path);
    zpath[wireless_path.len] = 0;
    const wireless = c.access(&zpath, c.F_OK) == 0;
    g.network_present = true;
    g.network_wireless = wireless;
    copyTrunc(&g.network_label, &g.network_label_len, if (wireless) "Wi-Fi" else "LAN");
    return true;
}

pub fn updateSystemStatus() bool {
    const old_battery = g.battery_percent;
    const old_charging = g.battery_charging;
    const old_network = g.network_present;
    const old_wireless = g.network_wireless;
    if (!readBattery()) {
        g.battery_percent = -1;
        g.battery_charging = false;
    }
    if (!readNetwork()) {
        g.network_present = false;
        g.network_wireless = false;
        g.network_label_len = 0;
        g.network_label[0] = 0;
    }
    return old_battery != g.battery_percent or
        old_charging != g.battery_charging or
        old_network != g.network_present or
        old_wireless != g.network_wireless;
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
