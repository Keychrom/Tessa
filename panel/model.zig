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
pub const MAX_NOTIFICATIONS = 50;
pub const MAX_TOASTS = 4;
pub const MAX_MEDIA_ART = 128;
pub const MAX_MEDIA_ART_BYTES = MAX_MEDIA_ART * MAX_MEDIA_ART * 4;
pub const MAX_NOTIFICATION_ACTIONS = 4;
pub const MAX_NOTIFICATION_ICON = 64;
pub const MAX_NOTIFICATION_ICON_BYTES = MAX_NOTIFICATION_ICON * MAX_NOTIFICATION_ICON * 4;
pub const MAX_TRAY_ITEMS = 8;
pub const MAX_TRAY_ICON = 32;
pub const MAX_TRAY_ICON_BYTES = MAX_TRAY_ICON * MAX_TRAY_ICON * 4;
pub const MAX_EXTENSIONS = 16;
pub const MAX_WIFI_APS = 32;
pub const MAX_BT_DEVICES = 24;
pub const MAX_CONTROL_ACTIONS = 4;
pub const MAX_CONTROL_INPUT = 128;
pub const MAX_WIFI_SSID = 64;
pub const MAX_WIFI_PATH = 256;
pub const MAX_BT_PATH = 256;
pub const MAX_BT_NAME = 96;
pub const MAX_CONTROL_ERROR = 160;

pub const OverlayMode = enum { none, launcher, calendar, power, clipboard, screenshot, media, tray, audio, extensions, module, control, wifi, bluetooth };
pub const LauncherStyle = enum { centered, start };
pub const PanelStyle = enum { classic, unified };
pub const ControlView = enum { home, wifi, bluetooth, notifications, calendar, tray, power };
pub const BarPosition = enum { top, bottom, left, right };
pub const PanelRenderer = enum { cairo, gpu };
pub const OverlayRenderer = enum { cairo, gpu };
pub const WallpaperAnimation = enum { off, on, auto };
pub const WallpaperEngine = enum { cairo, procedural };
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
    layout,
    groups,
    mode,
    effects,
};
pub const BAR_MODULE_COUNT = @typeInfo(BarModule).@"enum".field_names.len;

pub const BarModuleSpec = struct {
    module: BarModule,
    name: []const u8,
    description: []const u8,
    context: bool = false,
    default: bool = false,
    priority: i32 = 50,
};

pub const bar_module_specs = [_]BarModuleSpec{
    .{ .module = .logo, .name = "logo", .description = "Tessa mark and launcher shortcut", .default = true, .priority = 100 },
    .{ .module = .workspaces, .name = "workspaces", .description = "Nine workspace pills", .default = true, .priority = 100 },
    .{ .module = .chips, .name = "chips", .description = "Window chips for the active workspace", .default = true, .priority = 70 },
    .{ .module = .clock, .name = "clock", .description = "Clock and date", .default = true, .priority = 100 },
    .{ .module = .battery, .name = "battery", .description = "Battery status", .default = true, .priority = 50 },
    .{ .module = .network, .name = "network", .description = "Network status", .default = true, .priority = 50 },
    .{ .module = .volume, .name = "volume", .description = "Volume indicator", .default = true, .priority = 60 },
    .{ .module = .stats, .name = "stats", .description = "CPU, memory, and trend sparkline", .default = true, .priority = 20 },
    .{ .module = .media, .name = "media", .description = "MPRIS media controls", .default = true, .priority = 40 },
    .{ .module = .tray, .name = "tray", .description = "StatusNotifier tray icons", .default = true, .priority = 35 },
    .{ .module = .status, .name = "status", .description = "Extension status entries", .default = true, .priority = 80 },
    .{ .module = .layout, .name = "layout", .description = "Active tiling layout", .context = true, .priority = 60 },
    .{ .module = .groups, .name = "groups", .description = "Window group indicator", .context = true, .priority = 55 },
    .{ .module = .mode, .name = "mode", .description = "Active input mode", .context = true, .priority = 65 },
    .{ .module = .effects, .name = "effects", .description = "Blur, shadow, and animation state", .context = true, .priority = 30 },
};

pub fn barModuleByName(name: []const u8) ?BarModule {
    for (bar_module_specs) |spec| {
        if (std.mem.eql(u8, name, spec.name)) return spec.module;
    }
    if (std.mem.eql(u8, name, "mark")) return .logo;
    if (std.mem.eql(u8, name, "workspace")) return .workspaces;
    if (std.mem.eql(u8, name, "title") or std.mem.eql(u8, name, "windows")) return .chips;
    if (std.mem.eql(u8, name, "date")) return .clock;
    if (std.mem.eql(u8, name, "audio")) return .volume;
    if (std.mem.eql(u8, name, "cpu") or std.mem.eql(u8, name, "memory")) return .stats;
    return null;
}

pub const DEFAULT_BAR_MODULE_COUNT = blk: {
    var count: usize = 0;
    for (bar_module_specs) |spec| {
        if (spec.default) count += 1;
    }
    break :blk count;
};

pub const ControlFeature = enum {
    wifi,
    bluetooth,
    focus,
    notifications,
    media,
    volume,
    brightness,
    power_profile,
    battery,
    quick_actions,
    tray,
    calendar,
    power,
};
pub const CONTROL_FEATURE_COUNT = @typeInfo(ControlFeature).@"enum".field_names.len;

pub const ControlFeatureSpec = struct {
    feature: ControlFeature,
    name: []const u8,
    description: []const u8,
    default: bool = true,
};

pub const control_feature_specs = [_]ControlFeatureSpec{
    .{ .feature = .wifi, .name = "wifi", .description = "NetworkManager Wi-Fi status and networks" },
    .{ .feature = .bluetooth, .name = "bluetooth", .description = "BlueZ adapters, devices, and pairing" },
    .{ .feature = .focus, .name = "focus", .description = "Do-not-disturb / Focus toggle" },
    .{ .feature = .notifications, .name = "notifications", .description = "Notification history and actions" },
    .{ .feature = .media, .name = "media", .description = "MPRIS media card, artwork, and seek" },
    .{ .feature = .volume, .name = "volume", .description = "Output volume slider and mute" },
    .{ .feature = .brightness, .name = "brightness", .description = "Backlight brightness slider" },
    .{ .feature = .power_profile, .name = "power_profile", .description = "Power-profiles-daemon profile" },
    .{ .feature = .battery, .name = "battery", .description = "Battery status and power actions" },
    .{ .feature = .quick_actions, .name = "quick_actions", .description = "Screenshot, clipboard, settings, and custom actions" },
    .{ .feature = .tray, .name = "tray", .description = "StatusNotifier tray view" },
    .{ .feature = .calendar, .name = "calendar", .description = "Calendar view for the clock" },
    .{ .feature = .power, .name = "power", .description = "Lock, suspend, reboot, and power off" },
};

pub fn controlFeatureBit(feature: ControlFeature) u32 {
    return @as(u32, 1) << @intFromEnum(feature);
}

pub const CONTROL_FEATURE_ALL: u32 = (@as(u32, 1) << CONTROL_FEATURE_COUNT) - 1;

pub fn controlFeatureEnabled(feature: ControlFeature) bool {
    return (g.control_features & controlFeatureBit(feature)) != 0;
}

pub const ControlActionEntry = struct {
    label: [64]u8 = @splat(0),
    label_len: usize = 0,
    command: [256]u8 = @splat(0),
    command_len: usize = 0,
};

pub const WifiAp = struct {
    ssid: [MAX_WIFI_SSID]u8 = @splat(0),
    ssid_len: usize = 0,
    signal: u8 = 0,
    flags: u32 = 0,
    path: [MAX_WIFI_PATH]u8 = @splat(0),
    path_len: usize = 0,
    conn_path: [MAX_WIFI_PATH]u8 = @splat(0),
    conn_path_len: usize = 0,
};

pub const WIFI_AP_SECURED: u32 = 1 << 0;
pub const WIFI_AP_SAVED: u32 = 1 << 1;
pub const WIFI_AP_ACTIVE: u32 = 1 << 2;
pub const WIFI_AP_SAE: u32 = 1 << 3;
pub const WIFI_AP_ENTERPRISE: u32 = 1 << 4;

pub const BtDevice = struct {
    path: [MAX_BT_PATH]u8 = @splat(0),
    path_len: usize = 0,
    name: [MAX_BT_NAME]u8 = @splat(0),
    name_len: usize = 0,
    icon: u8 = 0,
    flags: u8 = 0,
    rssi: i16 = 0,
    battery: i8 = -1,
};

pub const BT_DEVICE_PAIRED: u8 = 1 << 0;
pub const BT_DEVICE_CONNECTED: u8 = 1 << 1;
pub const BT_DEVICE_TRUSTED: u8 = 1 << 2;

pub const BtAgentKind = enum { none, confirm, pin, passkey, display_passkey, authorize };

pub const ControlModal = enum { none, wifi_password, wifi_hidden, wifi_forget, bt_confirm, bt_pin, bt_passkey };

pub const DragTarget = enum { none, volume, brightness, seek };

pub const ControlAction = enum(usize) {
    back,
    wifi_toggle,
    wifi_scan,
    wifi_disconnect,
    wifi_forget,
    wifi_hidden,
    bt_toggle,
    bt_scan,
    bt_pair,
    bt_connect,
    bt_disconnect,
    bt_forget,
    dnd,
    clear_notifications,
    view_notifications,
    view_calendar,
    view_tray,
    view_power,
    power_lock,
    power_suspend,
    power_reboot,
    power_off,
    power_quit,
    quick_screenshot,
    quick_clipboard,
    quick_settings,
    quick_lock,
    quick_custom_base,
    modal_confirm,
    modal_cancel,
    field_ssid,
    field_password,
    profile_base,
};

pub const MODULE_BACKGROUND: u16 = 1 << 0;
pub const MODULE_BAR: u16 = 1 << 1;
pub const MODULE_LAUNCHER: u16 = 1 << 2;
pub const MODULE_POPOVERS: u16 = 1 << 3;
pub const MODULE_NOTIFICATIONS: u16 = 1 << 4;
pub const MODULE_TOASTS: u16 = 1 << 5;
pub const MODULE_TRAY: u16 = 1 << 6;
pub const MODULE_MEDIA: u16 = 1 << 7;
pub const MODULE_AUDIO: u16 = 1 << 8;
pub const MODULE_ALL: u16 = (1 << 9) - 1;

pub fn moduleEnabled(bit: u16) bool {
    return (g.modules & bit) != 0;
}

fn parsePanelModules(value: []const u8) bool {
    var result: u16 = 0;
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |raw| {
        const name = std.mem.trim(u8, raw, " \t");
        if (name.len == 0) continue;
        if (std.ascii.eqlIgnoreCase(name, "all")) {
            result |= MODULE_ALL;
        } else if (std.ascii.eqlIgnoreCase(name, "none")) {
            // no bit
        } else if (std.ascii.eqlIgnoreCase(name, "background") or
            std.ascii.eqlIgnoreCase(name, "wallpaper"))
        {
            result |= MODULE_BACKGROUND;
        } else if (std.ascii.eqlIgnoreCase(name, "bar")) {
            result |= MODULE_BAR;
        } else if (std.ascii.eqlIgnoreCase(name, "launcher")) {
            result |= MODULE_LAUNCHER;
        } else if (std.ascii.eqlIgnoreCase(name, "popovers") or
            std.ascii.eqlIgnoreCase(name, "popover"))
        {
            result |= MODULE_POPOVERS;
        } else if (std.ascii.eqlIgnoreCase(name, "notifications") or
            std.ascii.eqlIgnoreCase(name, "notification"))
        {
            result |= MODULE_NOTIFICATIONS;
        } else if (std.ascii.eqlIgnoreCase(name, "toasts") or
            std.ascii.eqlIgnoreCase(name, "toast"))
        {
            result |= MODULE_TOASTS;
        } else if (std.ascii.eqlIgnoreCase(name, "tray")) {
            result |= MODULE_TRAY;
        } else if (std.ascii.eqlIgnoreCase(name, "media")) {
            result |= MODULE_MEDIA;
        } else if (std.ascii.eqlIgnoreCase(name, "audio") or
            std.ascii.eqlIgnoreCase(name, "volume"))
        {
            result |= MODULE_AUDIO;
        } else {
            return false;
        }
    }
    g.modules = result;
    return true;
}

fn parseControlFeatures(value: []const u8) u32 {
    var result: u32 = 0;
    var it = std.mem.tokenizeAny(u8, value, ", \t|");
    while (it.next()) |name| {
        if (std.ascii.eqlIgnoreCase(name, "all")) {
            result |= CONTROL_FEATURE_ALL;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(name, "none")) continue;
        for (control_feature_specs) |spec| {
            if (std.ascii.eqlIgnoreCase(name, spec.name)) {
                result |= controlFeatureBit(spec.feature);
                break;
            }
        }
    }
    return result;
}

fn addControlAction(value: []const u8) void {
    if (g.control_action_count >= g.control_actions.len) return;
    const bar = std.mem.indexOfScalar(u8, value, '|') orelse return;
    const label = std.mem.trim(u8, value[0..bar], " \t");
    const command = std.mem.trim(u8, value[bar + 1 ..], " \t");
    if (label.len == 0 or command.len == 0) return;
    const entry = &g.control_actions[g.control_action_count];
    entry.* = .{};
    copyTrunc(&entry.label, &entry.label_len, label);
    copyTrunc(&entry.command, &entry.command_len, command);
    g.control_action_count += 1;
}

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
    extension,
    module_action,
    bar_overflow,
    launcher_lock,
    launcher_power,
    controls,
    wifi,
    bluetooth,
    control_action,
    control_view,
    control_slider,
    control_ap,
    control_bt_device,
    control_notification,
    control_power,
    control_profile,
    control_input,
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
    output_name: [64]u8 = @splat(0),
    output_len: usize = 0,
    focused: bool = false,
    floating: bool = false,
    fullscreen: bool = false,
    scratchpad: bool = false,
    visible: bool = true,
    group_id: u32 = 0,
    group_active: bool = false,
    column: i32 = -1,
    tile: i32 = -1,
    app_id: [64]u8 = @splat(0),
    app_len: usize = 0,
    title: [160]u8 = @splat(0),
    title_len: usize = 0,
};

pub const StatusInfo = struct {
    id: [48]u8 = @splat(0),
    id_len: usize = 0,
    text: [160]u8 = @splat(0),
    text_len: usize = 0,
    command: [256]u8 = @splat(0),
    command_len: usize = 0,
    icon: [32]u8 = @splat(0),
    icon_len: usize = 0,
    priority: i32 = 0,
    popover: [512]u8 = @splat(0),
    popover_len: usize = 0,
};

pub const MAX_MODULE_ACTIONS = 8;
pub const MAX_MODULE_TITLE = 64;
pub const MAX_MODULE_BODY = 160;
pub const MAX_MODULE_LABEL = 56;

pub const ModuleAction = struct {
    label: [MAX_MODULE_LABEL]u8 = @splat(0),
    label_len: usize = 0,
    command: [256]u8 = @splat(0),
    command_len: usize = 0,
};

/// Declarative content for a popover owned by an external bar module.
pub const ModulePopover = struct {
    title: [MAX_MODULE_TITLE]u8 = @splat(0),
    title_len: usize = 0,
    body: [MAX_MODULE_BODY]u8 = @splat(0),
    body_len: usize = 0,
    actions: [MAX_MODULE_ACTIONS]ModuleAction = @splat(.{}),
    action_count: usize = 0,
};

pub const ExtensionInfo = struct {
    id: [32]u8 = @splat(0),
    id_len: usize = 0,
    state: [16]u8 = @splat(0),
    state_len: usize = 0,
    api: u8 = 1,
    pid: i32 = -1,
    ready: bool = false,
    restarts: u32 = 0,
    enabled: bool = true,
    permissions: [96]u8 = @splat(0),
    permissions_len: usize = 0,
};

pub const CustomApp = struct {
    name: [160]u8 = @splat(0),
    name_len: usize = 0,
    comment: [192]u8 = @splat(0),
    comment_len: usize = 0,
    exec: [512]u8 = @splat(0),
    exec_len: usize = 0,
};

pub const OutputInfo = struct {
    wl: ?*c.wl_output = null,
    name: [64]u8 = @splat(0),
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
    gpu: ?*c.TessaGpuSurface = null,
    listener: c.zwlr_layer_surface_v1_listener = undefined,
};

pub const ClipboardEntry = struct {
    text: [MAX_CLIPBOARD_BYTES]u8 = @splat(0),
    len: usize = 0,
};

pub const NotificationAction = struct {
    key: [64]u8 = @splat(0),
    key_len: usize = 0,
    label: [96]u8 = @splat(0),
    label_len: usize = 0,
};

pub const NotificationEntry = struct {
    id: u32 = 0,
    app: [64]u8 = @splat(0),
    app_len: usize = 0,
    summary: [160]u8 = @splat(0),
    summary_len: usize = 0,
    body: [512]u8 = @splat(0),
    body_len: usize = 0,
    created_ms: i64 = 0,
    expire_ms: i64 = 0,
    toast_visible: bool = false,
    actions: [MAX_NOTIFICATION_ACTIONS]NotificationAction = undefined,
    action_count: usize = 0,
    icon_w: u32 = 0,
    icon_h: u32 = 0,
    icon_len: usize = 0,
    icon_data: [MAX_NOTIFICATION_ICON_BYTES]u8 = @splat(0),
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
    title: [160]u8 = @splat(0),
    title_len: usize = 0,
    icon_name: [128]u8 = @splat(0),
    icon_name_len: usize = 0,
    status: u8 = 0,
    icon_w: u32 = 0,
    icon_h: u32 = 0,
    icon_len: usize = 0,
    icon_data: [MAX_TRAY_ICON_BYTES]u8 = @splat(0),
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
    toasts_output: [64]u8 = @splat(0),
    toasts_output_len: usize = 0,

    outputs: [MAX_OUTPUTS]OutputInfo = @splat(.{}),
    output_count: usize = 0,
    target_output: ?*c.wl_output = null,
    target_name: [64]u8 = @splat(0),
    target_name_len: usize = 0,
    target_make: [64]u8 = @splat(0),
    target_make_len: usize = 0,
    target_model: [64]u8 = @splat(0),
    target_model_len: usize = 0,
    target_serial: [64]u8 = @splat(0),
    target_serial_len: usize = 0,
    focused_output_name: [64]u8 = @splat(0),
    focused_output_name_len: usize = 0,
    is_focused_output: bool = false,
    scale: i32 = 1,

    active_ws: usize = 1,
    active_layout: [24]u8 = @splat(0),
    active_layout_len: usize = 0,
    input_mode: [24]u8 = @splat(0),
    input_mode_len: usize = 0,
    ws_names: [WS_COUNT][MAX_WORKSPACE_NAME]u8 = undefined,
    ws_name_lens: [WS_COUNT]usize = @splat(0),
    occ: [10]u32 = @splat(0),
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
    dnd: bool = false,
    toast_hits: [MAX_TOASTS]HitRect = undefined,
    toast_hit_count: usize = 0,
    toast_action_hits: [MAX_TOASTS * 3]ToastActionHit = undefined,
    toast_action_hit_count: usize = 0,

    custom_apps: [MAX_CUSTOM_APPS]CustomApp = undefined,
    custom_count: usize = 0,

    ipc_fd: c_int = -1,
    ipc_buf: [65536]u8 = undefined,
    ipc_len: usize = 0,
    ipc_in_state: bool = false,

    clock_buf: [8]u8 = @splat(0),
    date_buf: [20]u8 = @splat(0),

    cpu_percent: f32 = 0,
    mem_percent: f32 = 0,
    cpu_hist: [40]f32 = @splat(0),
    prev_total: u64 = 0,
    prev_idle: u64 = 0,
    have_cpu_prev: bool = false,
    battery_percent: i32 = -1,
    battery_charging: bool = false,
    network_present: bool = false,
    network_wireless: bool = false,
    network_label: [32]u8 = @splat(0),
    network_label_len: usize = 0,
    media_status: u8 = 0,
    media_title: [160]u8 = @splat(0),
    media_title_len: usize = 0,
    media_artist: [160]u8 = @splat(0),
    media_artist_len: usize = 0,
    media_player: [64]u8 = @splat(0),
    media_player_len: usize = 0,
    media_art_url: [512]u8 = @splat(0),
    media_art_url_len: usize = 0,
    media_art_surface: ?*c.cairo_surface_t = null,
    media_length_us: i64 = 0,
    media_position_us: i64 = 0,
    media_track_id: [256]u8 = @splat(0),
    media_track_id_len: usize = 0,
    media_fd: c_int = -1,
    media_buf: [MAX_MEDIA_ART_BYTES + 4096]u8 = undefined,
    media_len: usize = 0,
    tray_items: [MAX_TRAY_ITEMS]TrayItem = undefined,
    tray_count: usize = 0,
    tray_fd: c_int = -1,
    tray_buf: [131072]u8 = undefined,
    tray_len: usize = 0,
    tray_ready: bool = false,
    tray_selected: usize = 0,
    extensions: [MAX_EXTENSIONS]ExtensionInfo = undefined,
    extension_count: usize = 0,
    extension_selected: usize = 0,
    module_popover: ModulePopover = .{},
    module_selected: usize = 0,
    module_source: [512]u8 = @splat(0),
    module_source_len: usize = 0,
    volume_percent: i32 = -1,
    volume_muted: bool = false,
    volume_source: [16]u8 = @splat(0),
    volume_source_len: usize = 0,
    audio_fd: c_int = -1,
    audio_buf: [4096]u8 = undefined,
    audio_len: usize = 0,
    audio_ready: bool = false,
    volume_status: [512]u8 = @splat(0),
    volume_status_len: usize = 0,
    volume_up: [512]u8 = @splat(0),
    volume_up_len: usize = 0,
    volume_down: [512]u8 = @splat(0),
    volume_down_len: usize = 0,
    volume_mute: [512]u8 = @splat(0),
    volume_mute_len: usize = 0,

    system_fd: c_int = -1,
    system_buf: [65536]u8 = undefined,
    system_len: usize = 0,
    system_ready: bool = false,
    system_owner: bool = false,
    wifi_present: bool = false,
    wifi_enabled: bool = false,
    wifi_hw_enabled: bool = false,
    wifi_scanning: bool = false,
    wifi_state: u8 = 0,
    wifi_ssid: [MAX_WIFI_SSID]u8 = @splat(0),
    wifi_ssid_len: usize = 0,
    wifi_signal: u8 = 0,
    wifi_aps: [MAX_WIFI_APS]WifiAp = undefined,
    wifi_ap_count: usize = 0,
    wifi_selected: usize = 0,
    wifi_scroll: usize = 0,
    wifi_error: [MAX_CONTROL_ERROR]u8 = @splat(0),
    wifi_error_len: usize = 0,
    wifi_modal: ControlModal = .none,
    wifi_modal_ap: usize = 0,
    wifi_modal_hidden: bool = false,
    control_input: [MAX_CONTROL_INPUT]u8 = @splat(0),
    control_input_len: usize = 0,
    control_input_secure: bool = false,
    control_field: usize = 0,
    control_ssid: [MAX_WIFI_SSID]u8 = @splat(0),
    control_ssid_len: usize = 0,
    bt_present: bool = false,
    bt_powered: bool = false,
    bt_discovering: bool = false,
    bt_name: [MAX_BT_NAME]u8 = @splat(0),
    bt_name_len: usize = 0,
    bt_devices: [MAX_BT_DEVICES]BtDevice = undefined,
    bt_count: usize = 0,
    bt_selected: usize = 0,
    bt_scroll: usize = 0,
    bt_error: [MAX_CONTROL_ERROR]u8 = @splat(0),
    bt_error_len: usize = 0,
    bt_detail_path: [MAX_BT_PATH]u8 = @splat(0),
    bt_detail_path_len: usize = 0,
    bt_agent: BtAgentKind = .none,
    bt_agent_name: [MAX_BT_NAME]u8 = @splat(0),
    bt_agent_name_len: usize = 0,
    bt_agent_passkey: [16]u8 = @splat(0),
    bt_agent_passkey_len: usize = 0,
    bt_modal: ControlModal = .none,
    brightness_percent: i32 = -1,
    brightness_max: u32 = 0,
    brightness_name: [64]u8 = @splat(0),
    brightness_name_len: usize = 0,
    ppd_available: bool = false,
    ppd_profile: [32]u8 = @splat(0),
    ppd_profile_len: usize = 0,
    ppd_profiles: [4][32]u8 = undefined,
    ppd_profile_lens: [4]usize = @splat(0),
    ppd_profile_count: usize = 0,

    control_view: ControlView = .home,
    control_scroll: f64 = 0,
    control_content_height: f64 = 0,
    control_visible_height: f64 = 0,
    control_panel_rect: HitRect = .{},
    control_drag: DragTarget = .none,
    control_drag_ms: i64 = 0,
    control_volume_slider: HitRect = .{},
    control_brightness_slider: HitRect = .{},
    control_seek_slider: HitRect = .{},
    control_input_active: bool = false,
    control_input_rect: [4]i32 = .{ 0, 0, 1, 20 },

    pointer_surface: ?*Surface = null,
    pointer_x: f64 = 0,
    pointer_y: f64 = 0,

    bar_hits: [48]HitRect = undefined,
    bar_hit_count: usize = 0,
    hover: Hit = .{},

    overlay_hits: [96]HitRect = undefined,
    overlay_hit_count: usize = 0,
    overlay_panel: HitRect = .{},
    overlay_row_hover: usize = 999,
    overlay_hit_scale: f64 = 1,
    overlay_hit_x: f64 = 0,
    overlay_hit_y: f64 = 0,

    calendar_year: i32 = 1970,
    calendar_month: i32 = 1,
    power_selected: usize = 0,
    power_lock: [256]u8 = @splat(0),
    power_lock_len: usize = 0,
    power_suspend: [256]u8 = @splat(0),
    power_suspend_len: usize = 0,
    power_reboot: [256]u8 = @splat(0),
    power_reboot_len: usize = 0,
    power_off: [256]u8 = @splat(0),
    power_off_len: usize = 0,

    data_control_manager: ?*c.zwlr_data_control_manager_v1 = null,
    data_control_device: ?*c.zwlr_data_control_device_v1 = null,
    data_control_listener: c.zwlr_data_control_device_v1_listener = undefined,
    data_offer: ?*c.zwlr_data_control_offer_v1 = null,
    data_offer_listener: c.zwlr_data_control_offer_v1_listener = undefined,
    data_offer_mime: [128]u8 = @splat(0),
    data_offer_mime_len: usize = 0,
    data_offer_mime_rank: i32 = 0,
    data_offer_selected: bool = false,
    clipboard_fd: c_int = -1,
    clipboard_read_buf: [MAX_CLIPBOARD_BYTES]u8 = @splat(0),
    clipboard_read_len: usize = 0,
    clipboard_entries: [MAX_CLIPBOARD_ENTRIES]ClipboardEntry = undefined,
    clipboard_count: usize = 0,
    clipboard_selected: usize = 0,
    clipboard_send_text: [MAX_CLIPBOARD_BYTES]u8 = @splat(0),
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
    screenshot_dir: [512]u8 = @splat(0),
    screenshot_dir_len: usize = 0,

    launcher_open: bool = false,
    launcher_style: LauncherStyle = .centered,
    launcher_open_style: LauncherStyle = .centered,
    selected_anim: f64 = 0,
    query: [128]u8 = @splat(0),
    query_len: usize = 0,
    preedit: [128]u8 = @splat(0),
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
    next_system_ms: i64 = 0,
    next_wallpaper_ms: i64 = 0,
    last_input_ms: i64 = 0,
    gpu_frame_pending: bool = false,
    gpu_frame_ms: i64 = 0,
    gpu_frame_callback: ?*c.wl_callback = null,

    accent: [3]f64 = .{ 0.886, 0.408, 0.31 },
    bg_rgb: [3]f64 = .{ 0.039, 0.059, 0.102 },
    bg_top: [3]f64 = .{ 0, 0, 0 },
    bg_top_set: bool = false,
    bg_bottom: [3]f64 = .{ 0, 0, 0 },
    bg_bottom_set: bool = false,
    wallpaper_art: bool = true,
    wallpaper_art_opacity: f64 = 0.55,
    wallpaper_image: [512]u8 = undefined,
    wallpaper_image_len: usize = 0,
    wallpaper_shader: [512]u8 = undefined,
    wallpaper_shader_len: usize = 0,
    wallpaper_fit: WallpaperFit = .cover,
    wallpaper_surface: ?*c.cairo_surface_t = null,
    panel_renderer: PanelRenderer = .cairo,
    overlay_renderer: OverlayRenderer = .cairo,
    wallpaper_engine: WallpaperEngine = .cairo,
    wallpaper_animation: WallpaperAnimation = .off,
    wallpaper_fps: i32 = 30,
    wallpaper_idle_pause: i32 = 120,
    reduce_motion: bool = false,
    bg_base_dirty: bool = true,
    mark_dirty: bool = true,
    overlay_content_dirty: bool = true,
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
    bar_position: BarPosition = .top,
    bar_top_margin: i32 = 12,
    bar_side_margin: i32 = 16,
    bar_layout: [256]u8 = undefined,
    bar_layout_len: usize = 0,
    bar_layout_set: bool = false,
    modules: u16 = MODULE_ALL,
    panel_style: PanelStyle = .classic,
    control_features: u32 = CONTROL_FEATURE_ALL,
    control_actions: [MAX_CONTROL_ACTIONS]ControlActionEntry = undefined,
    control_action_count: usize = 0,
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
        .layout,
        .groups,
        .mode,
        .effects,
    },
    bar_module_count: usize = DEFAULT_BAR_MODULE_COUNT,
    bar_priorities: [BAR_MODULE_COUNT]i32 = @splat(50),
    bar_overflow: bool = true,
    bar_hidden: [BAR_MODULE_COUNT]bool = @splat(false),
    bar_hidden_count: usize = 0,
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
    show_layout: bool = false,
    show_groups: bool = false,
    show_mode: bool = false,
    show_effects: bool = false,
    blur_enabled: bool = true,
    shadows_enabled: bool = true,
    animations_enabled: bool = true,
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

/// Compact Windows-style start menu, anchored to the bar edge. The 360x620
/// design is scaled down on small outputs.
pub fn startMenuLayout(w: f64, h: f64) LauncherLayout {
    const side: f64 = @floatFromInt(g.bar_side_margin);
    const edge: f64 = @floatFromInt(g.bar_top_margin);
    const thickness: f64 = @floatFromInt(g.bar_height);
    const gap = 8.0;

    var avail_w = w - side * 2.0;
    var avail_h = h - (edge + thickness + gap) - 8.0;
    switch (g.bar_position) {
        .left, .right => {
            avail_w = w - (edge + thickness + gap) - 8.0;
            avail_h = h - side * 2.0;
        },
        else => {},
    }
    const fit_x = avail_w / 360.0;
    const fit_y = avail_h / 620.0;
    const scale = std.math.clamp(@min(1.0, @min(fit_x, fit_y)), 0.35, 1.0);

    var x = side;
    var y = edge + thickness + gap;
    switch (g.bar_position) {
        .bottom => y = h - edge - thickness - gap - 620.0 * scale,
        .left => {
            x = edge + thickness + gap;
            y = side;
        },
        .right => {
            x = w - edge - thickness - gap - 360.0 * scale;
            y = side;
        },
        else => {},
    }
    x = std.math.clamp(x, 8.0, @max(8.0, w - 360.0 * scale - 8.0));
    y = std.math.clamp(y, 8.0, @max(8.0, h - 620.0 * scale - 8.0));
    return .{ .x = x, .y = y, .scale = scale };
}

/// Direction the start menu slides from while opening.
pub fn startMenuSlide() struct { x: f64, y: f64 } {
    return switch (g.bar_position) {
        .top => .{ .x = 0, .y = 14 },
        .bottom => .{ .x = 0, .y = -14 },
        .left => .{ .x = 14, .y = 0 },
        .right => .{ .x = -14, .y = 0 },
    };
}

pub fn barHorizontal() bool {
    return g.bar_position == .top or g.bar_position == .bottom;
}

/// Bar rectangle in output coordinates. The surface itself is configured by
/// the compositor; this mirrors the anchors and margins used by createBar().
pub fn barOutputRect(w: f64, h: f64) struct { x: f64, y: f64, w: f64, h: f64 } {
    const side: f64 = @floatFromInt(g.bar_side_margin);
    const edge: f64 = @floatFromInt(g.bar_top_margin);
    const thickness: f64 = @floatFromInt(g.bar_height);
    return switch (g.bar_position) {
        .top => .{ .x = side, .y = edge, .w = w - side * 2.0, .h = thickness },
        .bottom => .{ .x = side, .y = h - edge - thickness, .w = w - side * 2.0, .h = thickness },
        .left => .{ .x = edge, .y = side, .w = thickness, .h = h - side * 2.0 },
        .right => .{ .x = w - edge - thickness, .y = side, .w = thickness, .h = h - side * 2.0 },
    };
}

pub const ControlLayout = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    columns: usize,
};

/// The unified control center is a single card anchored to the bar edge. It
/// uses two columns on wide horizontal bars and one column on vertical bars or
/// narrow outputs.
pub fn controlCenterLayout(w: f64, h: f64) ControlLayout {
    const edge: f64 = @floatFromInt(g.bar_top_margin);
    const thickness: f64 = @floatFromInt(g.bar_height);
    const gap = 8.0;
    var width: f64 = 0;
    var height: f64 = 0;
    var x: f64 = 0;
    var y: f64 = 0;

    if (barHorizontal()) {
        width = @min(820.0, @max(320.0, w - 24.0));
        height = @min(660.0, @max(300.0, h - (edge + thickness + gap) - 20.0));
        x = (w - width) / 2.0;
        y = if (g.bar_position == .top)
            edge + thickness + gap
        else
            h - edge - thickness - gap - height;
        if (y < 8.0) y = 8.0;
        if (y + height > h - 8.0) height = @max(240.0, h - 16.0 - y);
    } else {
        width = @min(520.0, @max(320.0, w - (edge + thickness + gap) - 20.0));
        height = @min(900.0, @max(300.0, h - 24.0));
        x = if (g.bar_position == .left)
            edge + thickness + gap
        else
            w - edge - thickness - gap - width;
        if (x < 8.0) x = 8.0;
        y = (h - height) / 2.0;
    }
    if (x + width > w - 8.0) width = @max(240.0, w - 8.0 - x);
    if (y + height > h - 8.0) height = @max(200.0, h - 8.0 - y);
    return .{
        .x = x,
        .y = y,
        .w = width,
        .h = height,
        .columns = if (width >= 680.0 and barHorizontal()) 2 else 1,
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
    name: [32]u8 = @splat(0),
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
    g.show_layout = false;
    g.show_groups = false;
    g.show_mode = false;
    g.show_effects = false;
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
        const module = barModuleByName(name) orelse continue;

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
            .layout => g.show_layout = true,
            .groups => g.show_groups = true,
            .mode => g.show_mode = true,
            .effects => g.show_effects = true,
        }
    }
}

fn parseBarPriority(value: []const u8) void {
    var it = std.mem.tokenizeAny(u8, value, ", \t|");
    while (it.next()) |raw| {
        const item = trim(raw);
        const eq = std.mem.indexOfScalar(u8, item, '=') orelse continue;
        const name = trim(item[0..eq]);
        const module = barModuleByName(name) orelse continue;
        const priority = std.fmt.parseInt(i32, trim(item[eq + 1 ..]), 10) catch continue;
        g.bar_priorities[@intFromEnum(module)] = priority;
    }
}

pub fn barPriority(module: BarModule) i32 {
    return g.bar_priorities[@intFromEnum(module)];
}

pub fn barModuleName(module: BarModule) []const u8 {
    for (bar_module_specs) |spec| {
        if (spec.module == module) return spec.name;
    }
    return "unknown";
}

/// Right-cluster modules that currently have something to show. The planner
/// only runs in the right cluster; the logo, workspaces, and window chips keep
/// their anchored positions.
fn barModuleActive(module: BarModule) bool {
    return switch (module) {
        .logo => g.show_logo,
        .workspaces => g.show_workspaces,
        .chips => g.show_chips,
        .clock => g.show_clock,
        .battery => g.show_battery and g.battery_percent >= 0,
        .network => g.show_network and g.network_present,
        .volume => g.show_volume and g.volume_percent >= 0,
        .stats => g.show_stats,
        .media => g.show_media and (g.media_status == 1 or g.media_status == 2),
        .tray => g.show_tray and g.tray_count > 0,
        .status => g.show_status and g.status_count > 0,
        .layout => g.show_layout,
        .groups => g.show_groups,
        .mode => g.show_mode and g.input_mode_len > 0 and
            !std.mem.eql(u8, g.input_mode[0..g.input_mode_len], "default"),
        .effects => g.show_effects,
    };
}

/// Hard minimum widths retained from the pre-overflow layout. Modules below
/// their minimum are skipped without counting as overflow.
fn barModuleBaseFits(module: BarModule, width: f64) bool {
    return switch (module) {
        .battery => width > 900.0,
        .network => width > 1000.0,
        .volume => width > 1080.0,
        .stats => width > 1180.0,
        .media => width > 1250.0,
        .tray => width > 980.0,
        else => true,
    };
}

fn barModuleCost(module: BarModule) f64 {
    return switch (module) {
        .clock => 138.0,
        .battery => 34.0,
        .network => if (g.bt_present and controlFeatureEnabled(.bluetooth)) 52.0 else 34.0,
        .volume => 34.0,
        .stats => 172.0,
        .media => 196.0,
        .tray => @max(96.0, @as(f64, @floatFromInt(g.tray_count)) * 24.0 + 10.0),
        .status => 90.0,
        .layout => 96.0,
        .groups => 76.0,
        .mode => 96.0,
        .effects => 48.0,
        .logo, .workspaces, .chips => 0.0,
    };
}

pub const BarPlan = struct {
    hidden: [BAR_MODULE_COUNT]bool = @splat(false),
    hidden_count: usize = 0,
};

fn planBarImpl(width: f64, available: f64, assume_active: bool) BarPlan {
    var plan = BarPlan{};
    if (!g.bar_overflow or available <= 0) return plan;

    var candidates: [BAR_MODULE_COUNT]BarModule = undefined;
    var candidate_count: usize = 0;
    var total: f64 = 0;
    var count: usize = 0;

    for (g.bar_modules[0..g.bar_module_count]) |module| {
        switch (module) {
            .logo, .workspaces, .chips => continue,
            else => {},
        }
        if (!barModuleBaseFits(module, width)) continue;
        if (!assume_active and !barModuleActive(module)) continue;
        candidates[candidate_count] = module;
        candidate_count += 1;
        total += barModuleCost(module);
        count += 1;
    }
    if (count > 1) total += @as(f64, @floatFromInt(count - 1)) * 10.0;

    // Reserve room for the "+N" chip before deciding the final set.
    while (count > 0 and total + 36.0 > available) {
        var lowest: ?usize = null;
        for (candidates[0..candidate_count], 0..) |module, i| {
            if (plan.hidden[@intFromEnum(module)]) continue;
            if (lowest) |best| {
                if (g.bar_priorities[@intFromEnum(module)] <
                    g.bar_priorities[@intFromEnum(candidates[best])])
                {
                    lowest = i;
                }
            } else {
                lowest = i;
            }
        }
        const index = lowest orelse break;
        const module = candidates[index];
        plan.hidden[@intFromEnum(module)] = true;
        plan.hidden_count += 1;
        total -= barModuleCost(module) + 10.0;
        count -= 1;
    }
    return plan;
}

pub fn planBar(width: f64, available: f64) BarPlan {
    return planBarImpl(width, available, false);
}

/// Approximate row height used by the vertical (left/right) bar. Keep this in
/// sync with drawBarVertical().
pub fn barModuleHeight(module: BarModule) f64 {
    return switch (module) {
        .clock => 46.0,
        .battery, .network, .volume => 26.0,
        .stats => 38.0,
        .media => 28.0,
        .tray => @max(24.0, @as(f64, @floatFromInt(g.tray_count)) * 24.0),
        .status => @max(24.0, @as(f64, @floatFromInt(g.status_count)) * 24.0),
        .layout, .groups, .mode, .effects => 24.0,
        .logo, .workspaces, .chips => 0.0,
    };
}

/// Overflow plan for a vertical bar. Each module is one or more stacked rows;
/// hidden modules collapse into the same "+N" chip as the horizontal bar.
pub fn planBarVertical(available: f64) BarPlan {
    var plan = BarPlan{};
    if (!g.bar_overflow or available <= 0) return plan;

    var candidates: [BAR_MODULE_COUNT]BarModule = undefined;
    var candidate_count: usize = 0;
    var total: f64 = 0;
    for (g.bar_modules[0..g.bar_module_count]) |module| {
        switch (module) {
            .logo, .workspaces, .chips => continue,
            else => {},
        }
        if (!barModuleActive(module)) continue;
        candidates[candidate_count] = module;
        candidate_count += 1;
        total += barModuleHeight(module);
    }
    if (candidate_count > 1) {
        total += @as(f64, @floatFromInt(candidate_count - 1)) * 6.0;
    }

    var remaining = candidate_count;
    while (remaining > 0 and total + 24.0 > available) {
        var lowest: ?usize = null;
        for (candidates[0..candidate_count], 0..) |module, i| {
            if (plan.hidden[@intFromEnum(module)]) continue;
            if (lowest) |best| {
                if (g.bar_priorities[@intFromEnum(module)] <
                    g.bar_priorities[@intFromEnum(candidates[best])])
                {
                    lowest = i;
                }
            } else {
                lowest = i;
            }
        }
        const index = lowest orelse break;
        const module = candidates[index];
        plan.hidden[@intFromEnum(module)] = true;
        plan.hidden_count += 1;
        total -= barModuleHeight(module) + 6.0;
        remaining -= 1;
    }
    return plan;
}

/// Diagnostic used by `tessa-panel --bar-plan WIDTH [LEFT]`: assumes every
/// configured right-cluster module is active, so priorities can be tuned
/// without opening a session at that size.
pub fn printBarPlan(width: f64, left: f64) void {
    const available = @max(0.0, width - 32.0 - left);
    const plan = planBarImpl(width, available, true);
    std.debug.print("bar-plan: width={d:.0} available={d:.0} hidden={d} overflow={s}\n", .{
        width,
        available,
        plan.hidden_count,
        if (g.bar_overflow) "on" else "off",
    });
    for (g.bar_modules[0..g.bar_module_count]) |module| {
        switch (module) {
            .logo, .workspaces, .chips => continue,
            else => {},
        }
        const name = barModuleName(module);
        if (!barModuleBaseFits(module, width)) {
            std.debug.print("skip: {s} priority={d} cost={d:.0} reason=minimum-width\n", .{
                name, barPriority(module), barModuleCost(module),
            });
        } else if (plan.hidden[@intFromEnum(module)]) {
            std.debug.print("hidden: {s} priority={d} cost={d:.0}\n", .{
                name, barPriority(module), barModuleCost(module),
            });
        } else {
            std.debug.print("visible: {s} priority={d} cost={d:.0}\n", .{
                name, barPriority(module), barModuleCost(module),
            });
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

fn isDirectory(path: []const u8) bool {
    var zpath: [512:0]u8 = undefined;
    if (path.len >= zpath.len) return false;
    @memcpy(zpath[0..path.len], path);
    zpath[path.len] = 0;
    var st: c.struct_stat = undefined;
    if (c.stat(&zpath, &st) != 0) return false;
    return (st.st_mode & 0o170000) == 0o040000;
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
        if (std.mem.eql(u8, key, "include") or std.mem.eql(u8, key, "theme")) {
            var include_buf: [512]u8 = undefined;
            const resolved = resolveInclude(&include_buf, path, val);
            if (resolved.len > 0) {
                if (std.mem.eql(u8, key, "theme") and isDirectory(resolved)) {
                    var theme_buf: [512]u8 = undefined;
                    const theme_path = std.fmt.bufPrint(&theme_buf, "{s}/theme.conf", .{resolved}) catch "";
                    if (theme_path.len > 0) loadConfigFile(theme_path, depth + 1);
                } else {
                    loadConfigFile(resolved, depth + 1);
                }
            }
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
        } else if (std.mem.eql(u8, key, "bar_priority") or std.mem.eql(u8, key, "bar-priority")) {
            parseBarPriority(val);
        } else if (std.mem.eql(u8, key, "bar_overflow") or std.mem.eql(u8, key, "bar-overflow")) {
            g.bar_overflow = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1") or
                std.mem.eql(u8, val, "yes") or std.mem.eql(u8, val, "on");
        } else if (std.mem.eql(u8, key, "panel_modules") or std.mem.eql(u8, key, "panel-modules")) {
            _ = parsePanelModules(val);
        } else if (std.mem.eql(u8, key, "launcher_style") or std.mem.eql(u8, key, "launcher-style")) {
            if (std.mem.eql(u8, val, "start") or std.mem.eql(u8, val, "windows")) {
                g.launcher_style = .start;
            } else if (std.mem.eql(u8, val, "centered") or std.mem.eql(u8, val, "wofi")) {
                g.launcher_style = .centered;
            }
        } else if (std.mem.eql(u8, key, "panel_style") or std.mem.eql(u8, key, "panel-style")) {
            if (std.mem.eql(u8, val, "unified") or std.mem.eql(u8, val, "control") or std.mem.eql(u8, val, "control-center")) {
                g.panel_style = .unified;
            } else if (std.mem.eql(u8, val, "classic") or std.mem.eql(u8, val, "traditional")) {
                g.panel_style = .classic;
            } else {
                std.debug.print("tessa-panel: invalid panel_style '{s}' (classic|unified)\n", .{val});
            }
        } else if (std.mem.eql(u8, key, "control_features") or std.mem.eql(u8, key, "control-features")) {
            g.control_features = parseControlFeatures(val);
        } else if (std.mem.eql(u8, key, "control_action") or std.mem.eql(u8, key, "control-action")) {
            addControlAction(val);
        } else if (std.mem.eql(u8, key, "panel_renderer") or std.mem.eql(u8, key, "panel-renderer")) {
            if (std.mem.eql(u8, val, "gpu") or std.mem.eql(u8, val, "egl")) {
                g.panel_renderer = .gpu;
            } else if (std.mem.eql(u8, val, "cairo") or std.mem.eql(u8, val, "software")) {
                g.panel_renderer = .cairo;
            }
        } else if (std.mem.eql(u8, key, "overlay_renderer") or std.mem.eql(u8, key, "overlay-renderer")) {
            if (std.mem.eql(u8, val, "gpu") or std.mem.eql(u8, val, "egl")) {
                g.overlay_renderer = .gpu;
            } else if (std.mem.eql(u8, val, "cairo") or std.mem.eql(u8, val, "software")) {
                g.overlay_renderer = .cairo;
            }
        } else if (std.mem.eql(u8, key, "wallpaper_engine") or std.mem.eql(u8, key, "wallpaper-engine")) {
            if (std.mem.eql(u8, val, "procedural") or std.mem.eql(u8, val, "gpu") or std.mem.eql(u8, val, "shader")) {
                g.wallpaper_engine = .procedural;
            } else if (std.mem.eql(u8, val, "cairo") or std.mem.eql(u8, val, "texture")) {
                g.wallpaper_engine = .cairo;
            }
        } else if (std.mem.eql(u8, key, "reduce_motion") or std.mem.eql(u8, key, "reduce-motion")) {
            g.reduce_motion = parsePanelBool(val) orelse g.reduce_motion;
        } else if (std.mem.eql(u8, key, "wallpaper_animation") or std.mem.eql(u8, key, "wallpaper-animation")) {
            if (std.mem.eql(u8, val, "auto")) {
                g.wallpaper_animation = .auto;
            } else if (parsePanelBool(val)) |on| {
                g.wallpaper_animation = if (on) .on else .off;
            }
        } else if (std.mem.eql(u8, key, "wallpaper_fps") or std.mem.eql(u8, key, "wallpaper-fps")) {
            if (std.fmt.parseInt(i32, val, 10)) |v| {
                g.wallpaper_fps = std.math.clamp(v, 1, 120);
            } else |_| {}
        } else if (std.mem.eql(u8, key, "wallpaper_idle_pause") or std.mem.eql(u8, key, "wallpaper-idle-pause")) {
            if (std.fmt.parseInt(i32, val, 10)) |v| {
                g.wallpaper_idle_pause = std.math.clamp(v, 0, 3600);
            } else |_| {}
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
        } else if (std.mem.eql(u8, key, "blur")) {
            g.blur_enabled = parsePanelBool(val) orelse g.blur_enabled;
        } else if (std.mem.eql(u8, key, "shadows")) {
            g.shadows_enabled = parsePanelBool(val) orelse g.shadows_enabled;
        } else if (std.mem.eql(u8, key, "animations")) {
            g.animations_enabled = parsePanelBool(val) orelse g.animations_enabled;
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
        } else if (std.mem.eql(u8, key, "wallpaper_art_opacity") or std.mem.eql(u8, key, "wallpaper-art-opacity")) {
            if (std.fmt.parseFloat(f64, val)) |v| {
                g.wallpaper_art_opacity = std.math.clamp(v, 0.0, 1.0);
            } else |_| {}
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
        } else if (std.mem.eql(u8, key, "bar_position") or std.mem.eql(u8, key, "bar-position")) {
            if (std.mem.eql(u8, val, "top")) {
                g.bar_position = .top;
            } else if (std.mem.eql(u8, val, "bottom")) {
                g.bar_position = .bottom;
            } else if (std.mem.eql(u8, val, "left")) {
                g.bar_position = .left;
            } else if (std.mem.eql(u8, val, "right")) {
                g.bar_position = .right;
            } else {
                std.debug.print("tessa-panel: invalid bar_position '{s}' (top|bottom|left|right)\n", .{val});
            }
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

/// Reads the small declarative UI file referenced by a status widget.
///
///   title = Weather
///   body = Tokyo, clear, 18 C
///   action = Refresh | ~/.config/tessa/widgets/weather/refresh.sh
///
/// The panel owns rendering and input; the module only writes this file and
/// publishes the widget with `tessa-ctl status --popover <file>`.
pub fn loadModulePopover(path: []const u8) bool {
    g.module_popover = .{};
    g.module_selected = 0;
    if (path.len == 0 or path.len >= 512) return false;
    var zpath: [512:0]u8 = undefined;
    @memcpy(zpath[0..path.len], path);
    zpath[path.len] = 0;
    const file = c.fopen(&zpath, "r") orelse return false;
    defer _ = c.fclose(file);

    var line: [1024]u8 = undefined;
    while (c.fgets(&line, @intCast(line.len), file)) |_| {
        const raw = std.mem.span(@as([*:0]const u8, @ptrCast(&line)));
        const t = trim(raw);
        if (t.len == 0 or t[0] == '#' or t[0] == '[') continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = trim(t[0..eq]);
        const val = trim(t[eq + 1 ..]);
        if (std.mem.eql(u8, key, "title")) {
            copyTrunc(&g.module_popover.title, &g.module_popover.title_len, val);
        } else if (std.mem.eql(u8, key, "body") or std.mem.eql(u8, key, "subtitle")) {
            copyTrunc(&g.module_popover.body, &g.module_popover.body_len, val);
        } else if (std.mem.eql(u8, key, "action") or std.mem.eql(u8, key, "item")) {
            if (g.module_popover.action_count >= g.module_popover.actions.len) continue;
            const sep = std.mem.indexOfScalar(u8, val, '|');
            const label = trim(if (sep) |at| val[0..at] else val);
            const command = if (sep) |at| trim(val[at + 1 ..]) else "";
            if (label.len == 0) continue;
            const action = &g.module_popover.actions[g.module_popover.action_count];
            copyTrunc(&action.label, &action.label_len, label);
            copyTrunc(&action.command, &action.command_len, command);
            g.module_popover.action_count += 1;
        }
    }
    return g.module_popover.title_len > 0 or
        g.module_popover.body_len > 0 or
        g.module_popover.action_count > 0;
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
    g.launcher_style = .centered;
    g.launcher_open_style = .centered;
    g.panel_renderer = .cairo;
    g.overlay_renderer = .cairo;
    g.wallpaper_engine = .cairo;
    g.wallpaper_animation = .off;
    g.wallpaper_fps = 30;
    g.wallpaper_idle_pause = 120;
    g.reduce_motion = false;
    g.bg_base_dirty = true;
    g.mark_dirty = true;
    g.overlay_content_dirty = true;
    g.next_wallpaper_ms = 0;
    g.selected_anim = 0;
    copyTrunc(&g.font, &g.font_len, "Inter");
    g.bar_font_len = 0;
    g.launcher_font_len = 0;
    g.popover_font_len = 0;
    g.toast_font_len = 0;
    g.bar_layout_len = 0;
    g.bar_layout_set = false;
    g.modules = MODULE_ALL;
    g.panel_style = .classic;
    g.control_features = CONTROL_FEATURE_ALL;
    g.control_action_count = 0;
    g.dnd = false;
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
        .layout,
        .groups,
        .mode,
        .effects,
    };
    g.bar_module_count = DEFAULT_BAR_MODULE_COUNT;
    for (bar_module_specs, 0..) |spec, i| g.bar_priorities[i] = spec.priority;
    g.bar_overflow = true;
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
    g.show_layout = false;
    g.show_groups = false;
    g.show_mode = false;
    g.show_effects = false;
    g.blur_enabled = true;
    g.shadows_enabled = true;
    g.animations_enabled = true;
    g.accent = .{ 0.886, 0.408, 0.31 };
    g.bg_rgb = .{ 0.039, 0.059, 0.102 };
    g.bg_top = .{ 0, 0, 0 };
    g.bg_top_set = false;
    g.bg_bottom = .{ 0, 0, 0 };
    g.bg_bottom_set = false;
    g.wallpaper_art = true;
    g.wallpaper_art_opacity = 0.55;
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
    g.bar_position = .top;
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
    g.bg_base_dirty = true;
    g.mark_dirty = true;
    g.overlay_content_dirty = true;
    g.next_wallpaper_ms = 0;
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
    std.debug.print("panel bar-position={s} bar-height={d} top-margin={d} side-margin={d}\n", .{
        @tagName(g.bar_position),
        g.bar_height,
        g.bar_top_margin,
        g.bar_side_margin,
    });
    std.debug.print("panel style={s} control-features=", .{@tagName(g.panel_style)});
    var first_feature = true;
    for (control_feature_specs) |spec| {
        if (!controlFeatureEnabled(spec.feature)) continue;
        if (!first_feature) std.debug.print(",", .{});
        first_feature = false;
        std.debug.print("{s}", .{spec.name});
    }
    std.debug.print("\n", .{});
    std.debug.print("panel panel-modules=", .{});
    const module_items = [_]struct { bit: u16, name: []const u8 }{
        .{ .bit = MODULE_BACKGROUND, .name = "background" },
        .{ .bit = MODULE_BAR, .name = "bar" },
        .{ .bit = MODULE_LAUNCHER, .name = "launcher" },
        .{ .bit = MODULE_POPOVERS, .name = "popovers" },
        .{ .bit = MODULE_NOTIFICATIONS, .name = "notifications" },
        .{ .bit = MODULE_TOASTS, .name = "toasts" },
        .{ .bit = MODULE_TRAY, .name = "tray" },
        .{ .bit = MODULE_MEDIA, .name = "media" },
        .{ .bit = MODULE_AUDIO, .name = "audio" },
    };
    var first_module = true;
    for (module_items) |item| {
        if (g.modules & item.bit == 0) continue;
        if (!first_module) std.debug.print(",", .{});
        first_module = false;
        std.debug.print("{s}", .{item.name});
    }
    std.debug.print("\n", .{});
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
    std.debug.print("panel renderer={s} overlay-renderer={s} wallpaper-engine={s} wallpaper-animation={s} fps={d} idle-pause={d}\n", .{
        @tagName(g.panel_renderer),
        @tagName(g.overlay_renderer),
        @tagName(g.wallpaper_engine),
        @tagName(g.wallpaper_animation),
        g.wallpaper_fps,
        g.wallpaper_idle_pause,
    });
}

fn stdoutWrite(s: []const u8) void {
    _ = c.write(1, s.ptr, s.len);
}

fn writeRgbToken(name: []const u8, rgb: [3]f64, first: *bool) void {
    if (!first.*) stdoutWrite(",");
    first.* = false;
    var buf: [160]u8 = undefined;
    const text = std.fmt.bufPrint(
        &buf,
        "\"{s}\":[{d:.4},{d:.4},{d:.4}]",
        .{ name, rgb[0], rgb[1], rgb[2] },
    ) catch return;
    stdoutWrite(text);
}

/// Built-in module catalogue for `tessa-panel --list-modules`.
pub fn printModules(json: bool) void {
    const surfaces = [_]struct { name: []const u8, description: []const u8 }{
        .{ .name = "background", .description = "Wallpaper and background surface" },
        .{ .name = "bar", .description = "Layer-shell taskbar" },
        .{ .name = "launcher", .description = "Searchable application launcher" },
        .{ .name = "popovers", .description = "Calendar, power, clipboard, media, tray, audio, screenshot" },
        .{ .name = "notifications", .description = "Desktop notification service" },
        .{ .name = "toasts", .description = "Notification toast surfaces" },
        .{ .name = "tray", .description = "StatusNotifier tray integration" },
        .{ .name = "media", .description = "MPRIS media integration" },
        .{ .name = "audio", .description = "Volume backend integration" },
    };

    if (json) {
        stdoutWrite("{\"schema\":1,\"bar\":[");
        for (bar_module_specs, 0..) |spec, i| {
            if (i > 0) stdoutWrite(",");
            var buf: [320]u8 = undefined;
            const text = std.fmt.bufPrint(
                &buf,
                "{{\"id\":\"{s}\",\"default\":{s},\"context\":{s},\"description\":\"{s}\"}}",
                .{
                    spec.name,
                    if (spec.default) "true" else "false",
                    if (spec.context) "true" else "false",
                    spec.description,
                },
            ) catch "";
            stdoutWrite(text);
        }
        stdoutWrite("],\"control_features\":[");
        for (control_feature_specs, 0..) |spec, i| {
            if (i > 0) stdoutWrite(",");
            var buf: [320]u8 = undefined;
            const text = std.fmt.bufPrint(
                &buf,
                "{{\"id\":\"{s}\",\"default\":{s},\"enabled\":{s},\"description\":\"{s}\"}}",
                .{
                    spec.name,
                    if (spec.default) "true" else "false",
                    if (controlFeatureEnabled(spec.feature)) "true" else "false",
                    spec.description,
                },
            ) catch "";
            stdoutWrite(text);
        }
        stdoutWrite("],\"surfaces\":[");
        for (surfaces, 0..) |surface, i| {
            if (i > 0) stdoutWrite(",");
            var buf: [256]u8 = undefined;
            const text = std.fmt.bufPrint(
                &buf,
                "{{\"id\":\"{s}\",\"description\":\"{s}\"}}",
                .{ surface.name, surface.description },
            ) catch "";
            stdoutWrite(text);
        }
        stdoutWrite("]}\n");
        return;
    }

    for (bar_module_specs) |spec| {
        var buf: [320]u8 = undefined;
        const text = std.fmt.bufPrint(
            &buf,
            "BAR\t{s}\t{s}\t{s}\t{s}\n",
            .{
                spec.name,
                if (spec.default) "default" else "opt-in",
                if (spec.context) "context" else "core",
                spec.description,
            },
        ) catch "";
        stdoutWrite(text);
    }
    for (control_feature_specs) |spec| {
        var buf: [320]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "CONTROL\t{s}\t{s}\t{s}\n", .{
            spec.name,
            if (controlFeatureEnabled(spec.feature)) "enabled" else "disabled",
            spec.description,
        }) catch "";
        stdoutWrite(text);
    }
    for (surfaces) |surface| {
        var buf: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "SURFACE\t{s}\t{s}\n", .{
            surface.name,
            surface.description,
        }) catch "";
        stdoutWrite(text);
    }
}

/// Resolved semantic tokens for external shells and theme tooling.
pub fn printThemeJson() void {
    stdoutWrite("{\"schema\":1,\"tokens\":{");
    var first = true;
    writeRgbToken("accent", g.accent, &first);
    writeRgbToken("background", g.bg_rgb, &first);
    writeRgbToken("wallpaper.top", if (g.bg_top_set) g.bg_top else g.bg_rgb, &first);
    writeRgbToken("wallpaper.bottom", if (g.bg_bottom_set) g.bg_bottom else g.bg_rgb, &first);
    writeRgbToken("panel.background", g.panel_bg, &first);
    writeRgbToken("panel.foreground", g.panel_fg, &first);
    writeRgbToken("bar.background", g.bar_bg, &first);
    writeRgbToken("bar.foreground", g.bar_fg, &first);
    writeRgbToken("launcher.background", g.launcher_bg, &first);
    writeRgbToken("launcher.foreground", g.launcher_fg, &first);
    writeRgbToken("popover.background", g.popover_bg, &first);
    writeRgbToken("popover.foreground", g.popover_fg, &first);
    writeRgbToken("toast.background", g.toast_bg, &first);
    writeRgbToken("toast.foreground", g.toast_fg, &first);
    stdoutWrite("},\"fonts\":{");
    var buf: [384]u8 = undefined;
    const fonts = std.fmt.bufPrint(
        &buf,
        "\"body\":\"{s}\",\"bar\":\"{s}\",\"launcher\":\"{s}\",\"popover\":\"{s}\",\"toast\":\"{s}\"",
        .{ g.font[0..g.font_len], barFont(), launcherFont(), popoverFont(), toastFont() },
    ) catch "";
    stdoutWrite(fonts);
    stdoutWrite("},\"bar\":{");
    const geometry = std.fmt.bufPrint(
        &buf,
        "\"height\":{d},\"top_margin\":{d},\"side_margin\":{d}",
        .{ g.bar_height, g.bar_top_margin, g.bar_side_margin },
    ) catch "";
    stdoutWrite(geometry);
    stdoutWrite("},\"effects\":{");
    const effects = std.fmt.bufPrint(
        &buf,
        "\"blur\":{s},\"shadows\":{s},\"animations\":{s}",
        .{
            if (g.blur_enabled) "true" else "false",
            if (g.shadows_enabled) "true" else "false",
            if (g.animations_enabled) "true" else "false",
        },
    ) catch "";
    stdoutWrite(effects);
    stdoutWrite("}}\n");
}

pub fn updateClock() bool {
    var t: c.time_t = c.time(null);
    var tm: c.tm = undefined;
    _ = c.localtime_r(&t, &tm);

    var time_buf: [8]u8 = @splat(0);
    _ = c.strftime(&time_buf, time_buf.len, "%H:%M", &tm);
    var date_buf: [20]u8 = @splat(0);
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

    var values: [8]u64 = @splat(0);
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
