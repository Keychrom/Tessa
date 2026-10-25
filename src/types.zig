const c = @import("c.zig").c;

pub const WS_COUNT = 9;
pub const MAX_CLIENTS = 128;
pub const MAX_OUTPUTS = 8;
pub const MAX_LAYERS = 64;
pub const MAX_KEYBOARDS = 16;
pub const MAX_IPC = 8;
pub const MAX_BINDINGS = 96;

pub const MAX_TITLE = 256;
pub const MAX_APP_ID = 128;
pub const MAX_COMMAND = 512;

pub const CursorMode = enum {
    passthrough,
    move,
    resize,
};

pub const LayoutMode = enum {
    master,
    mosaic,
};

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
    reload,
    ratio,
    toggle_layout,
};

pub const Binding = struct {
    mods: u32,
    sym: u32,
    action: Action,
    num: i32,
    ratio: f32,
    arg: [MAX_COMMAND]u8,
    arg_len: usize,
};

pub const Config = struct {
    terminal: [128]u8,
    terminal_len: usize,
    gaps: i32,
    outer_gaps: i32,
    border_width: i32,
    master_ratio: f32,
    layout_mode: LayoutMode,
    autostart_panel: bool,
    accent: [16]u8,
    accent_len: usize,
    accent_rgb: [3]f32,
    bg: [16]u8,
    bg_len: usize,
    font: [64]u8,
    font_len: usize,
    bindings: [MAX_BINDINGS]Binding,
    binding_count: usize,
};

pub const Output = struct {
    server: *Server,
    wlr: *c.wlr_output,
    scene_output: *c.wlr_scene_output,
    layout_output: *c.wlr_output_layout_output,
    usable: c.wlr_box,
    full: c.wlr_box,
    bg_rect: *c.wlr_scene_rect,

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

    ws: usize,
    mapped: bool,
    floating: bool,
    fullscreen: bool,

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
    destroy: c.wl_listener,
};

pub const Keyboard = struct {
    server: *Server,
    wlr: *c.wlr_keyboard,
    device: *c.wlr_input_device,
    modifiers: c.wl_listener,
    key: c.wl_listener,
    destroy: c.wl_listener,
};

pub const IpcClient = struct {
    server: *Server,
    fd: c_int,
    source: ?*c.wl_event_source,
    buf: [8192]u8,
    len: usize,
    alive: bool,
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

    outputs: [MAX_OUTPUTS]?*Output,
    output_count: usize,
    clients: [MAX_CLIENTS]?*Client,
    client_count: usize,
    layers: [MAX_LAYERS]?*LayerSurface,
    layer_count: usize,
    keyboards: [MAX_KEYBOARDS]?*Keyboard,
    keyboard_count: usize,
    ipcs: [MAX_IPC]?*IpcClient,
    ipc_count: usize,

    active_ws: usize,
    focused: ?*Client,
    focused_layer: ?*LayerSurface,
    last_focused: [WS_COUNT + 1]?*Client,
    next_client_id: u64,

    config: Config,
    ipc_fd: c_int,
    ipc_source: ?*c.wl_event_source,
    ipc_idle: ?*c.wl_event_source,
    ipc_path: [256]u8,
    ipc_dirty: bool,
    schedule_ipc: ?*const fn (*Server) void,

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
    new_layer_surface: c.wl_listener,

    cursor_motion: c.wl_listener,
    cursor_motion_absolute: c.wl_listener,
    cursor_button: c.wl_listener,
    cursor_axis: c.wl_listener,
    cursor_frame: c.wl_listener,

    request_cursor: c.wl_listener,
    request_set_selection: c.wl_listener,

    sigint: ?*c.wl_event_source,
    sigterm: ?*c.wl_event_source,
};
