const std = @import("std");
const c = @import("c.zig").c;

pub const WS_COUNT = 9;
pub const MAX_CLIENTS = 128;
pub const MAX_OUTPUTS = 8;
pub const MAX_LAYERS = 64;
pub const MAX_KEYBOARDS = 16;
pub const MAX_IPC = 8;
pub const MAX_BINDINGS = 192;
pub const MAX_MODES = 8;
pub const MAX_MODE_NAME = 32;
pub const MAX_HOOKS = 32;
pub const MAX_EVENT_RULES = 64;
pub const MAX_THEME_ROLES = 16;
pub const MAX_PROFILES = 32;
pub const MAX_WORKSPACE_RULES = 64;
pub const MAX_CURVES = 16;
pub const MAX_CURVE_NAME = 32;

pub const ReducedMotionAnimations = enum { none, fade };
pub const MAX_STATUS = 8;
pub const MAX_RULES = 64;
pub const MAX_OUTPUT_RULES = 64;
pub const MAX_LAYER_RULES = 64;
pub const MAX_CONFIG_ISSUES = 64;
pub const MAX_TOUCH_DEVICES = 8;
pub const MAX_TABLETS = 8;
pub const MAX_TABLET_TOOLS = 16;
pub const MAX_TABLET_PADS = 8;
pub const MAX_CONSTRAINTS = 32;
pub const MAX_EFFECTS = 4;

pub const MAX_TITLE = 256;
pub const MAX_APP_ID = 128;
pub const MAX_COMMAND = 512;
pub const MAX_STATUS_ID = 48;
pub const MAX_STATUS_TEXT = 160;
pub const MAX_STATUS_COMMAND = 256;

pub const CursorMode = enum {
    passthrough,
    move,
    resize,
};

pub const LayoutMode = enum {
    master,
    mosaic,
    grid,
    columns,
    custom,
};

pub const layout_cycle = [_]LayoutMode{ .master, .mosaic, .grid, .columns };

pub fn layoutFromName(name: []const u8) ?LayoutMode {
    if (std.ascii.eqlIgnoreCase(name, "master")) return .master;
    if (std.ascii.eqlIgnoreCase(name, "mosaic") or std.ascii.eqlIgnoreCase(name, "spiral")) return .mosaic;
    if (std.ascii.eqlIgnoreCase(name, "grid")) return .grid;
    if (std.ascii.eqlIgnoreCase(name, "columns") or std.ascii.eqlIgnoreCase(name, "column")) return .columns;
    if (std.ascii.eqlIgnoreCase(name, "custom") or std.ascii.eqlIgnoreCase(name, "helper")) return .custom;
    return null;
}

pub fn layoutName(mode: LayoutMode) []const u8 {
    return @tagName(mode);
}

pub const Action = enum {
    none,
    spawn,
    terminal,
    close,
    quit,
    workspace,
    move_to_workspace,
    focus,
    move,
    toggle_float,
    toggle_fullscreen,
    focus_next,
    focus_prev,
    launcher,
    clipboard,
    screenshot,
    media,
    tray,
    audio,
    reload,
    ratio,
    toggle_layout,
    set_layout,
    resize_width,
    resize_height,
    enter_mode,
};

pub const Binding = struct {
    mods: u32,
    sym: u32,
    mode: u8,
    action: Action,
    num: i32,
    ratio: f32,
    arg: [MAX_COMMAND]u8,
    arg_len: usize,
};

pub const SavedOutput = struct {
    name: [64]u8 = undefined,
    name_len: usize = 0,
    width: i32 = 0,
    height: i32 = 0,
    refresh: i32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    scale: f32 = 1,
    transform: u32 = 0,
    present: bool = false,
};

pub const WorkspacePin = struct {
    output_name: [64]u8 = undefined,
    output_len: usize = 0,
    ws: usize = 1,
};

pub const MAX_WORKSPACE_PINS = 32;

pub const SavedLayout = struct {
    output_name: [64]u8 = undefined,
    output_len: usize = 0,
    ws: usize = 1,
    mode: LayoutMode = .master,
    present: bool = false,
};

pub const MAX_SAVED_LAYOUTS = MAX_OUTPUTS * WS_COUNT;

pub const ConfigIssue = struct {
    path: [256]u8 = [_]u8{0} ** 256,
    path_len: usize = 0,
    line: u32 = 0,
    message: [192]u8 = [_]u8{0} ** 192,
    message_len: usize = 0,
    is_error: bool = true,
};

pub const RuleBool = enum { unset, on, off };

pub const AnimationKind = enum { none, open, workspace };

pub const CurveKind = enum { bezier, spring };

pub const Curve = struct {
    kind: CurveKind = .bezier,
    /// Cubic-bezier control points x1, y1, x2, y2.
    points: [4]f32 = .{ 0.33, 1.0, 0.68, 1.0 },
    /// Normalized spring damping ratio and oscillation count.
    damping: f32 = 0.55,
    frequency: f32 = 1.6,
};

pub const AnimationOverride = struct {
    enabled: RuleBool = .unset,
    animation_ms: i32 = -1,
    open_ms: i32 = -1,
    workspace_ms: i32 = -1,
    close_ms: i32 = -1,
    curve: [MAX_CURVE_NAME]u8 = [_]u8{0} ** MAX_CURVE_NAME,
    curve_len: usize = 0,
    open_curve: [MAX_CURVE_NAME]u8 = [_]u8{0} ** MAX_CURVE_NAME,
    open_curve_len: usize = 0,
    workspace_curve: [MAX_CURVE_NAME]u8 = [_]u8{0} ** MAX_CURVE_NAME,
    workspace_curve_len: usize = 0,
    close_curve: [MAX_CURVE_NAME]u8 = [_]u8{0} ** MAX_CURVE_NAME,
    close_curve_len: usize = 0,
};

pub const WindowRule = struct {
    raw: [MAX_COMMAND]u8 = [_]u8{0} ** MAX_COMMAND,
    raw_len: usize = 0,
    app_id: [MAX_APP_ID]u8 = [_]u8{0} ** MAX_APP_ID,
    app_id_len: usize = 0,
    title: [MAX_TITLE]u8 = [_]u8{0} ** MAX_TITLE,
    title_len: usize = 0,
    output: [64]u8 = [_]u8{0} ** 64,
    output_len: usize = 0,
    expr: [MAX_COMMAND]u8 = [_]u8{0} ** MAX_COMMAND,
    expr_len: usize = 0,
    workspace: usize = 0,
    has_border_active: bool = false,
    border_active_rgb: [3]f32 = .{ 0, 0, 0 },
    has_border_inactive: bool = false,
    border_inactive_rgb: [3]f32 = .{ 0, 0, 0 },
    floating: RuleBool = .unset,
    fullscreen: RuleBool = .unset,
    has_size: bool = false,
    width: i32 = 0,
    height: i32 = 0,
    has_position: bool = false,
    x: i32 = 0,
    y: i32 = 0,
    has_opacity: bool = false,
    opacity: f32 = 1.0,
    has_corner_radius: bool = false,
    corner_radius: i32 = 0,
    blur: RuleBool = .unset,
    shadow: RuleBool = .unset,
    has_border_width: bool = false,
    border_width: i32 = 0,
    anim: AnimationOverride = .{},
};

pub const LayerRule = struct {
    raw: [MAX_COMMAND]u8 = [_]u8{0} ** MAX_COMMAND,
    raw_len: usize = 0,
    namespace: [64]u8 = [_]u8{0} ** 64,
    namespace_len: usize = 0,
    output: [64]u8 = [_]u8{0} ** 64,
    output_len: usize = 0,
    /// zwlr_layer_shell_v1 layer (0 background .. 3 overlay), or -1 for any.
    layer: i32 = -1,
    has_opacity: bool = false,
    opacity: f32 = 1.0,
    has_corner_radius: bool = false,
    corner_radius: i32 = 0,
    blur: RuleBool = .unset,
};

pub const LayoutTuning = struct {
    has_layout: bool = false,
    layout: LayoutMode = .master,
    has_gaps: bool = false,
    gaps: i32 = 0,
    has_outer_gaps: bool = false,
    outer_gaps: i32 = 0,
    has_master_ratio: bool = false,
    master_ratio: f32 = 0,
    has_master_count: bool = false,
    master_count: usize = 0,
    has_mosaic_ratio: bool = false,
    mosaic_ratio: f32 = 0,
    has_mosaic_min_size: bool = false,
    mosaic_min_size: i32 = 0,
    has_grid_columns: bool = false,
    grid_columns: usize = 0,
};

pub const Profile = struct {
    name: [32]u8 = [_]u8{0} ** 32,
    name_len: usize = 0,
    tuning: LayoutTuning = .{},
};

pub const CurveDef = struct {
    name: [MAX_CURVE_NAME]u8 = [_]u8{0} ** MAX_CURVE_NAME,
    name_len: usize = 0,
    curve: Curve = .{},
};

pub const WorkspaceRule = struct {
    ws: u8 = 0,
    profile: [32]u8 = [_]u8{0} ** 32,
    profile_len: usize = 0,
    tuning: LayoutTuning = .{},
};

pub const OutputRule = struct {
    raw: [MAX_COMMAND]u8 = [_]u8{0} ** MAX_COMMAND,
    raw_len: usize = 0,
    output: [64]u8 = [_]u8{0} ** 64,
    output_len: usize = 0,
    profile: [32]u8 = [_]u8{0} ** 32,
    profile_len: usize = 0,
    ws: u8 = 0,
    has_gaps: bool = false,
    gaps: i32 = 0,
    has_outer_gaps: bool = false,
    outer_gaps: i32 = 0,
    has_master_ratio: bool = false,
    master_ratio: f32 = 0,
    has_master_count: bool = false,
    master_count: usize = 0,
    has_mosaic_ratio: bool = false,
    mosaic_ratio: f32 = 0,
    has_mosaic_min_size: bool = false,
    mosaic_min_size: i32 = 0,
    has_grid_columns: bool = false,
    grid_columns: usize = 0,
    has_layout: bool = false,
    layout: LayoutMode = .master,
    has_accent: bool = false,
    accent_rgb: [3]f32 = .{ 0, 0, 0 },
    has_bg: bool = false,
    bg_rgb: [3]f32 = .{ 0, 0, 0 },
    has_border_active: bool = false,
    border_active_rgb: [3]f32 = .{ 0, 0, 0 },
    has_border_inactive: bool = false,
    border_inactive_rgb: [3]f32 = .{ 0, 0, 0 },
    has_panel_bg: bool = false,
    panel_bg_rgb: [3]f32 = .{ 0, 0, 0 },
    has_panel_fg: bool = false,
    panel_fg_rgb: [3]f32 = .{ 0, 0, 0 },
    has_bg_top: bool = false,
    bg_top_rgb: [3]f32 = .{ 0, 0, 0 },
    has_bg_bottom: bool = false,
    bg_bottom_rgb: [3]f32 = .{ 0, 0, 0 },
    has_bar_height: bool = false,
    bar_height: i32 = 0,
    has_bar_top_margin: bool = false,
    bar_top_margin: i32 = 0,
    has_bar_side_margin: bool = false,
    bar_side_margin: i32 = 0,
};

pub const Hook = struct {
    event: [32]u8,
    event_len: usize,
    command: [MAX_COMMAND]u8,
    command_len: usize,
};

pub const EventRule = struct {
    event: [32]u8 = [_]u8{0} ** 32,
    event_len: usize = 0,
    expr: [MAX_COMMAND]u8 = [_]u8{0} ** MAX_COMMAND,
    expr_len: usize = 0,
    command: [MAX_COMMAND]u8 = [_]u8{0} ** MAX_COMMAND,
    command_len: usize = 0,
};

pub const ThemeRole = struct {
    name: [32]u8 = [_]u8{0} ** 32,
    name_len: usize = 0,
    color: [16]u8 = [_]u8{0} ** 16,
    color_len: usize = 0,
    rgb: [3]f32 = .{ 0, 0, 0 },
};

pub const StatusEntry = struct {
    id: [MAX_STATUS_ID]u8 = undefined,
    id_len: usize = 0,
    text: [MAX_STATUS_TEXT]u8 = undefined,
    text_len: usize = 0,
    command: [MAX_STATUS_COMMAND]u8 = undefined,
    command_len: usize = 0,
};

pub const Config = struct {
    terminal: [128]u8,
    terminal_len: usize,
    gaps: i32,
    outer_gaps: i32,
    border_width: i32,
    master_ratio: f32,
    master_count: usize,
    mosaic_ratio: f32,
    mosaic_min_size: i32,
    grid_columns: usize,
    layout_helper: [MAX_COMMAND]u8,
    layout_helper_len: usize,
    layout_helper_timeout: i32,
    ws_gaps: [WS_COUNT]i32,
    ws_outer_gaps: [WS_COUNT]i32,
    ws_master_ratio: [WS_COUNT]f32,
    ws_gaps_set: [WS_COUNT]bool,
    ws_outer_set: [WS_COUNT]bool,
    ws_ratio_set: [WS_COUNT]bool,
    ws_master_count: [WS_COUNT]usize,
    ws_master_count_set: [WS_COUNT]bool,
    ws_mosaic_ratio: [WS_COUNT]f32,
    ws_mosaic_ratio_set: [WS_COUNT]bool,
    ws_mosaic_min_size: [WS_COUNT]i32,
    ws_mosaic_min_size_set: [WS_COUNT]bool,
    ws_grid_columns: [WS_COUNT]usize,
    ws_grid_columns_set: [WS_COUNT]bool,
    layout_mode: LayoutMode,
    layout_by_ws: [WS_COUNT]LayoutMode,
    layout_overrides: [WS_COUNT]bool,
    workspace_pins: [MAX_WORKSPACE_PINS]WorkspacePin,
    workspace_pin_count: usize,
    animations: bool,
    reduce_motion: bool,
    reduce_motion_animations: ReducedMotionAnimations,
    reduce_motion_fade_ms: i32,
    animation_ms: i32,
    animation_open_ms: i32,
    animation_workspace_ms: i32,
    animation_close_ms: i32,
    animation_curve: [MAX_CURVE_NAME]u8,
    animation_curve_len: usize,
    animation_open_curve: [MAX_CURVE_NAME]u8,
    animation_open_curve_len: usize,
    animation_workspace_curve: [MAX_CURVE_NAME]u8,
    animation_workspace_curve_len: usize,
    animation_close_curve: [MAX_CURVE_NAME]u8,
    animation_close_curve_len: usize,
    animation_open_x: i32,
    animation_open_y: i32,
    animation_workspace_offset: i32,
    animation_close_scale: f32,
    animation_close_fade: bool,
    curves: [MAX_CURVES]CurveDef,
    curve_count: usize,
    shadows: bool,
    corner_radius: i32,
    blur: bool,
    blur_radius: i32,
    blur_passes: i32,
    gestures: bool,
    gesture_fingers: i32,
    gesture_workspace_threshold: i32,
    gesture_launcher_threshold: i32,
    touch: bool,
    tablet: bool,
    pointer_constraints: bool,
    xim: bool,
    xim_server: [64]u8,
    xim_server_len: usize,
    xim_start: [MAX_COMMAND]u8,
    xim_start_len: usize,
    autostart_panel: bool,
    xwayland: bool,
    xwayland_display: [32]u8,
    xwayland_display_len: usize,
    kb_layout: [64]u8,
    kb_layout_len: usize,
    kb_variant: [64]u8,
    kb_variant_len: usize,
    kb_options: [128]u8,
    kb_options_len: usize,
    kb_model: [64]u8,
    kb_model_len: usize,
    kb_rules: [64]u8,
    kb_rules_len: usize,
    repeat_rate: i32,
    repeat_delay: i32,
    accent: [16]u8,
    accent_len: usize,
    accent_rgb: [3]f32,
    bg: [16]u8,
    bg_len: usize,
    border_active: [16]u8,
    border_active_len: usize,
    border_active_rgb: [3]f32,
    border_inactive: [16]u8,
    border_inactive_len: usize,
    border_inactive_rgb: [3]f32,
    font: [64]u8,
    font_len: usize,
    output_config: [512]u8,
    output_config_len: usize,
    mode_names: [MAX_MODES][MAX_MODE_NAME]u8,
    mode_name_lens: [MAX_MODES]usize,
    mode_count: usize,
    bindings: [MAX_BINDINGS]Binding,
    binding_count: usize,
    leader_mods: u32,
    leader_sym: u32,
    leader_set: bool,
    leader_timeout: i32,
    mode_timeouts: [MAX_MODES]i32,
    hooks: [MAX_HOOKS]Hook,
    hook_count: usize,
    event_rules: [MAX_EVENT_RULES]EventRule,
    event_rule_count: usize,
    theme_roles: [MAX_THEME_ROLES]ThemeRole,
    theme_role_count: usize,
    profiles: [MAX_PROFILES]Profile,
    profile_count: usize,
    workspace_rules: [MAX_WORKSPACE_RULES]WorkspaceRule,
    workspace_rule_count: usize,
    rules: [MAX_RULES]WindowRule,
    rule_count: usize,
    output_rules: [MAX_OUTPUT_RULES]OutputRule,
    output_rule_count: usize,
    layer_rules: [MAX_LAYER_RULES]LayerRule,
    layer_rule_count: usize,
};

pub const Output = struct {
    server: *Server,
    wlr: *c.wlr_output,
    scene_output: *c.wlr_scene_output,
    layout_output: *c.wlr_output_layout_output,
    usable: c.wlr_box,
    full: c.wlr_box,
    bg_rect: *c.wlr_scene_rect,
    theme_bg: [4]f32,
    theme_accent: ?[4]f32,
    theme_border_active: ?[4]f32,
    theme_border_inactive: ?[4]f32,
    active_ws: usize,
    ws_layouts: [WS_COUNT]LayoutMode,
    layout_overridden: [WS_COUNT]bool,
    runtime_ratio: [WS_COUNT]f32,
    runtime_ratio_set: [WS_COUNT]bool,
    last_focused: [WS_COUNT + 1]?*Client,

    last_scale: f32,
    frame: c.wl_listener,
    request_state: c.wl_listener,
    commit: c.wl_listener,
    destroy: c.wl_listener,
};

pub const Client = struct {
    server: *Server,
    id: u64,
    xdg: *c.wlr_xdg_toplevel,
    output: *Output,
    frame: *c.wlr_scene_tree,
    surface_tree: *c.wlr_scene_tree,
    content_buffer: ?*c.wlr_scene_buffer,
    border_rect: *c.wlr_scene_rect,
    shadow_rects: [3]?*c.wlr_scene_rect,

    ws: usize,
    mapped: bool,
    announced: bool,
    floating: bool,
    fullscreen: bool,

    anim_off_x: i32,
    anim_off_y: i32,
    anim_from_x: i32,
    anim_from_y: i32,
    anim_start_ms: i64,
    anim_ms: i32,
    anim_curve: Curve,
    animating: bool,
    anim_kind: AnimationKind,
    close_snapshot: ?*c.wlr_buffer,
    close_snapshot_src: c.wlr_fbox,
    close_snapshot_transform: c.wl_output_transform,
    close_snapshot_w: i32,
    close_snapshot_h: i32,
    border_active_override: ?[4]f32,
    border_inactive_override: ?[4]f32,
    opacity: f32,
    corner_radius: i32,
    blur: RuleBool,
    shadow: RuleBool,
    border_width: i32,
    anim: AnimationOverride,

    x: i32,
    y: i32,
    w: i32,
    h: i32,

    float_x: i32,
    float_y: i32,
    float_w: i32,
    float_h: i32,

    last_gx: i32,
    last_gy: i32,
    last_gw: i32,
    last_gh: i32,

    title: [MAX_TITLE]u8,
    title_len: usize,
    app_id: [MAX_APP_ID]u8,
    app_id_len: usize,

    map: c.wl_listener,
    unmap: c.wl_listener,
    commit: c.wl_listener,
    destroy: c.wl_listener,
    request_move: c.wl_listener,
    request_resize: c.wl_listener,
    request_maximize: c.wl_listener,
    request_fullscreen: c.wl_listener,
    set_title: c.wl_listener,
    set_app_id: c.wl_listener,
    foreign_toplevel: ?*c.wlr_foreign_toplevel_handle_v1,
    foreign_activate: c.wl_listener,
    foreign_close: c.wl_listener,
    foreign_fullscreen: c.wl_listener,
    foreign_destroy: c.wl_listener,
    ext_foreign_toplevel: ?*c.wlr_ext_foreign_toplevel_handle_v1,
};

pub const LayerSurface = struct {
    server: *Server,
    wlr: *c.wlr_layer_surface_v1,
    scene_layer: *c.wlr_scene_layer_surface_v1,
    output: *Output,
    mapped: bool,
    opacity: f32,
    corner_radius: i32,
    blur: RuleBool,
    visual_layer: i32,
    visual_idle: ?*c.wl_event_source,

    commit: c.wl_listener,
    map: c.wl_listener,
    unmap: c.wl_listener,
    new_popup: c.wl_listener,
    destroy: c.wl_listener,
};

pub const LockSurface = struct {
    server: *Server,
    wlr: *c.wlr_session_lock_surface_v1,
    output: *Output,
    scene: *c.wlr_scene_surface,
    destroy: c.wl_listener,
};

pub const Keyboard = struct {
    server: *Server,
    wlr: *c.wlr_keyboard,
    device: *c.wlr_input_device,
    virtual_keyboard: ?*c.wlr_virtual_keyboard_v1,
    modifiers: c.wl_listener,
    key: c.wl_listener,
    keymap: c.wl_listener,
    destroy: c.wl_listener,
};

pub const TextInput = struct {
    server: *Server,
    input: *c.wlr_text_input_v3,
    enable: c.wl_listener,
    commit: c.wl_listener,
    disable: c.wl_listener,
    destroy: c.wl_listener,
};

pub const ImPopup = struct {
    server: *Server,
    popup: *c.wlr_input_popup_surface_v2,
    scene: *c.wlr_scene_tree,
    mapped: bool,
    commit: c.wl_listener,
    map: c.wl_listener,
    unmap: c.wl_listener,
    destroy: c.wl_listener,
};

pub const IpcClient = struct {
    server: *Server,
    fd: c_int,
    source: ?*c.wl_event_source,
    buf: [8192]u8,
    len: usize,
    alive: bool,
    wants_state: bool,
    wants_events: bool,
    json_events: bool,
    rpc_subscription: [128]u8,
    rpc_subscription_len: usize,
};

pub const Popup = struct {
    server: *Server,
    xdg_popup: *c.wlr_xdg_popup,
    commit: c.wl_listener,
    destroy: c.wl_listener,
};

pub const TouchDevice = struct {
    server: *Server,
    device: *c.wlr_input_device,
    destroy: c.wl_listener,
};

pub const Tablet = struct {
    server: *Server,
    device: *c.wlr_input_device,
    wlr: *c.wlr_tablet,
    v2: *c.wlr_tablet_v2_tablet,
    axis: c.wl_listener,
    proximity: c.wl_listener,
    tip: c.wl_listener,
    button: c.wl_listener,
    destroy: c.wl_listener,
};

pub const TabletTool = struct {
    server: *Server,
    tablet: ?*Tablet,
    wlr: *c.wlr_tablet_tool,
    v2: *c.wlr_tablet_v2_tablet_tool,
    surface: ?*c.wlr_surface,
    tablet_down: bool,
    pointer_down: bool,
    buttons: u32,
    pointer_buttons: u32,
    destroy: c.wl_listener,
    set_cursor: c.wl_listener,
};

pub const TabletPad = struct {
    server: *Server,
    device: *c.wlr_input_device,
    wlr: *c.wlr_tablet_pad,
    v2: *c.wlr_tablet_v2_tablet_pad,
    tablet_v2: ?*c.wlr_tablet_v2_tablet,
    enter_surface: ?*c.wlr_surface,
    attach: c.wl_listener,
    button: c.wl_listener,
    ring: c.wl_listener,
    strip: c.wl_listener,
    destroy: c.wl_listener,
};

pub const PointerConstraint = struct {
    server: *Server,
    wlr: *c.wlr_pointer_constraint_v1,
    set_region: c.wl_listener,
    destroy: c.wl_listener,
};

pub const CloseEffect = struct {
    server: *Server,
    client_id: u64,
    workspace: usize,
    output_name: [64]u8,
    output_len: usize,
    tree: *c.wlr_scene_tree,
    content: *c.wlr_scene_buffer,
    border: [4]*c.wlr_scene_rect,
    shadow: *c.wlr_scene_rect,
    border_width: f64,
    frame_x: f64,
    frame_y: f64,
    frame_w: f64,
    frame_h: f64,
    content_x: f64,
    content_y: f64,
    content_w: f64,
    content_h: f64,
    start_ms: i64,
    ms: i32,
    fade_only: bool,
    base_opacity: f32,
    shadow_enabled: bool,
    curve: Curve,
    close_scale: f64,
    close_fade: bool,
    border_color: [4]f32,
    shadow_color: [4]f32,
};

pub const Server = struct {
    display: *c.wl_display,
    backend: *c.wlr_backend,
    renderer: *c.wlr_renderer,
    allocator: *c.wlr_allocator,
    scene: *c.wlr_scene,
    scene_layout: *c.wlr_scene_output_layout,
    output_layout: *c.wlr_output_layout,
    xdg_shell: *c.wlr_xdg_shell,
    layer_shell: *c.wlr_layer_shell_v1,
    seat: *c.wlr_seat,
    cursor: *c.wlr_cursor,
    cursor_mgr: *c.wlr_xcursor_manager,

    tree_bg: *c.wlr_scene_tree,
    tree_bottom: *c.wlr_scene_tree,
    tree_windows: *c.wlr_scene_tree,
    tree_floating: *c.wlr_scene_tree,
    tree_fullscreen: *c.wlr_scene_tree,
    tree_effects: *c.wlr_scene_tree,
    tree_top: *c.wlr_scene_tree,
    tree_overlay: *c.wlr_scene_tree,
    tree_popup: *c.wlr_scene_tree,
    tree_lock: *c.wlr_scene_tree,

    outputs: [MAX_OUTPUTS]?*Output,
    output_count: usize,
    saved_outputs: [MAX_OUTPUTS]SavedOutput,
    saved_output_count: usize,
    saved_layouts: [MAX_SAVED_LAYOUTS]SavedLayout,
    saved_layout_count: usize,
    output_config_path: [512]u8,
    output_config_len: usize,
    clients: [MAX_CLIENTS]?*Client,
    client_count: usize,
    layers: [MAX_LAYERS]?*LayerSurface,
    layer_count: usize,
    keyboards: [MAX_KEYBOARDS]?*Keyboard,
    keyboard_count: usize,
    ipcs: [MAX_IPC]?*IpcClient,
    ipc_count: usize,
    statuses: [MAX_STATUS]StatusEntry,
    status_count: usize,
    text_inputs: [16]?*TextInput,
    text_input_count: usize,
    im_popups: [8]?*ImPopup,
    im_popup_count: usize,
    xdg_decoration_manager: ?*c.wlr_xdg_decoration_manager_v1,
    xdg_activation: ?*c.wlr_xdg_activation_v1,
    foreign_toplevel_manager: ?*c.wlr_foreign_toplevel_manager_v1,
    ext_foreign_toplevel_list: ?*c.wlr_ext_foreign_toplevel_list_v1,
    cursor_shape_manager: ?*c.wlr_cursor_shape_manager_v1,
    text_input_manager: ?*c.wlr_text_input_manager_v3,
    input_method_manager: ?*c.wlr_input_method_manager_v2,
    input_method: ?*c.wlr_input_method_v2,
    im_grab: ?*c.wlr_input_method_keyboard_grab_v2,
    ime_focus_surface: ?*c.wlr_surface,
    ime_focus_x: i32,
    ime_focus_y: i32,
    virtual_keyboard_manager: ?*c.wlr_virtual_keyboard_manager_v1,
    virtual_pointer_manager: ?*c.wlr_virtual_pointer_manager_v1,
    pointer_gestures: ?*c.wlr_pointer_gestures_v1,
    tablet_manager: ?*c.wlr_tablet_manager_v2,
    pointer_constraints_manager: ?*c.wlr_pointer_constraints_v1,
    touch_devices: [MAX_TOUCH_DEVICES]?*TouchDevice,
    touch_device_count: usize,
    tablets: [MAX_TABLETS]?*Tablet,
    tablet_count: usize,
    tablet_tools: [MAX_TABLET_TOOLS]?*TabletTool,
    tablet_tool_count: usize,
    tablet_pads: [MAX_TABLET_PADS]?*TabletPad,
    tablet_pad_count: usize,
    constraints: [MAX_CONSTRAINTS]?*PointerConstraint,
    constraint_count: usize,
    active_constraint: ?*c.wlr_pointer_constraint_v1,
    effects: [MAX_EFFECTS]?*CloseEffect,
    effect_count: usize,
    gesture_active: bool,
    gesture_fingers: u32,
    gesture_dx: f64,
    gesture_dy: f64,
    gesture_forward: bool,
    gesture_handled: bool,
    xim_timer: ?*c.wl_event_source,
    xim_display: [34]u8,
    xim_display_len: usize,
    xim_attempts: u32,
    xim_started: bool,

    active_ws: usize,
    focused: ?*Client,
    focused_output: ?*Output,
    focused_layer: ?*LayerSurface,
    next_client_id: u64,
    panel_notify_owner_assigned: bool,

    session_lock_manager: ?*c.wlr_session_lock_manager_v1,
    session_lock: ?*c.wlr_session_lock_v1,
    locked: bool,
    lock_saved_layer: ?*LayerSurface,
    lock_surfaces: [MAX_OUTPUTS]?*LockSurface,
    lock_surface_count: usize,
    new_session_lock: c.wl_listener,
    new_lock_surface: c.wl_listener,
    lock_unlock: c.wl_listener,
    lock_destroy: c.wl_listener,

    idle_notifier: ?*c.wlr_idle_notifier_v1,
    idle_inhibit_manager: ?*c.wlr_idle_inhibit_manager_v1,
    idle_inhibitor_count: usize,
    new_idle_inhibitor: c.wl_listener,
    output_power_manager: ?*c.wlr_output_power_manager_v1,
    output_power_set_mode: c.wl_listener,
    output_manager: ?*c.wlr_output_manager_v1,
    output_apply: c.wl_listener,
    output_test: c.wl_listener,

    config: Config,
    active_mode: u8,
    active_mode_name: [MAX_MODE_NAME]u8,
    active_mode_name_len: usize,
    mode_timer: ?*c.wl_event_source,
    mode_timeout_ms: i32,
    config_issues: [MAX_CONFIG_ISSUES]ConfigIssue,
    config_issue_count: usize,
    config_error_count: usize,
    config_watch_fd: c_int,
    config_watch_source: ?*c.wl_event_source,
    config_reload_timer: ?*c.wl_event_source,
    layout_helper_fd: c_int,
    layout_helper_pid: c.pid_t,
    layout_helper_hash: u64,
    layout_helper_fail_until: i64,
    ipc_fd: c_int,
    ipc_source: ?*c.wl_event_source,
    ipc_idle: ?*c.wl_event_source,
    ipc_path: [256]u8,
    ipc_dirty: bool,
    schedule_ipc: ?*const fn (*Server) void,
    broadcast_line: ?*const fn (*Server, []const u8) void,
    reload_runtime: ?*const fn (*Server) void,
    save_display_state: ?*const fn (*Server) void,

    cursor_mode: CursorMode,
    grabbed: ?*Client,
    grab_swallowed: bool,
    grab_x: f64,
    grab_y: f64,
    grab_box: c.wlr_box,
    resize_edges: u32,

    new_output: c.wl_listener,
    new_input: c.wl_listener,
    new_xdg_toplevel: c.wl_listener,
    new_xdg_popup: c.wl_listener,
    new_toplevel_decoration: c.wl_listener,
    request_activate: c.wl_listener,
    request_set_shape: c.wl_listener,
    new_layer_surface: c.wl_listener,

    cursor_motion: c.wl_listener,
    cursor_motion_absolute: c.wl_listener,
    cursor_button: c.wl_listener,
    cursor_axis: c.wl_listener,
    cursor_frame: c.wl_listener,
    cursor_touch_down: c.wl_listener,
    cursor_touch_up: c.wl_listener,
    cursor_touch_motion: c.wl_listener,
    cursor_touch_cancel: c.wl_listener,
    cursor_touch_frame: c.wl_listener,
    gesture_swipe_begin: c.wl_listener,
    gesture_swipe_update: c.wl_listener,
    gesture_swipe_end: c.wl_listener,
    gesture_pinch_begin: c.wl_listener,
    gesture_pinch_update: c.wl_listener,
    gesture_pinch_end: c.wl_listener,
    gesture_hold_begin: c.wl_listener,
    gesture_hold_end: c.wl_listener,
    new_pointer_constraint: c.wl_listener,

    request_cursor: c.wl_listener,
    request_set_selection: c.wl_listener,
    request_set_primary_selection: c.wl_listener,
    new_virtual_keyboard: c.wl_listener,
    new_virtual_pointer: c.wl_listener,
    relative_pointer_manager: ?*c.wlr_relative_pointer_manager_v1,
    new_text_input: c.wl_listener,
    new_input_method: c.wl_listener,
    im_commit: c.wl_listener,
    im_grab_keyboard: c.wl_listener,
    im_destroy: c.wl_listener,
    im_grab_destroy: c.wl_listener,
    im_new_popup: c.wl_listener,

    sigint: ?*c.wl_event_source,
    sigterm: ?*c.wl_event_source,
};
