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
pub const MAX_STATUS = 8;
pub const MAX_RULES = 64;
pub const MAX_CONFIG_ISSUES = 64;

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

pub const WindowRule = struct {
    raw: [MAX_COMMAND]u8 = [_]u8{0} ** MAX_COMMAND,
    raw_len: usize = 0,
    app_id: [MAX_APP_ID]u8 = [_]u8{0} ** MAX_APP_ID,
    app_id_len: usize = 0,
    title: [MAX_TITLE]u8 = [_]u8{0} ** MAX_TITLE,
    title_len: usize = 0,
    output: [64]u8 = [_]u8{0} ** 64,
    output_len: usize = 0,
    workspace: usize = 0,
    floating: RuleBool = .unset,
    fullscreen: RuleBool = .unset,
    has_size: bool = false,
    width: i32 = 0,
    height: i32 = 0,
    has_position: bool = false,
    x: i32 = 0,
    y: i32 = 0,
};

pub const Hook = struct {
    event: [32]u8,
    event_len: usize,
    command: [MAX_COMMAND]u8,
    command_len: usize,
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
    layout_mode: LayoutMode,
    layout_by_ws: [WS_COUNT]LayoutMode,
    layout_overrides: [WS_COUNT]bool,
    animations: bool,
    reduce_motion: bool,
    animation_ms: i32,
    shadows: bool,
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
    hooks: [MAX_HOOKS]Hook,
    hook_count: usize,
    rules: [MAX_RULES]WindowRule,
    rule_count: usize,
};

pub const Output = struct {
    server: *Server,
    wlr: *c.wlr_output,
    scene_output: *c.wlr_scene_output,
    layout_output: *c.wlr_output_layout_output,
    usable: c.wlr_box,
    full: c.wlr_box,
    bg_rect: *c.wlr_scene_rect,
    active_ws: usize,
    ws_layouts: [WS_COUNT]LayoutMode,
    layout_overridden: [WS_COUNT]bool,
    last_focused: [WS_COUNT + 1]?*Client,

    frame: c.wl_listener,
    request_state: c.wl_listener,
    destroy: c.wl_listener,
};

pub const Client = struct {
    server: *Server,
    id: u64,
    xdg: *c.wlr_xdg_toplevel,
    output: *Output,
    frame: *c.wlr_scene_tree,
    surface_tree: *c.wlr_scene_tree,
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
    animating: bool,

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
};

pub const Popup = struct {
    server: *Server,
    xdg_popup: *c.wlr_xdg_popup,
    commit: c.wl_listener,
    destroy: c.wl_listener,
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
    config_issues: [MAX_CONFIG_ISSUES]ConfigIssue,
    config_issue_count: usize,
    config_error_count: usize,
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

    request_cursor: c.wl_listener,
    request_set_selection: c.wl_listener,
    request_set_primary_selection: c.wl_listener,
    new_virtual_keyboard: c.wl_listener,
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
