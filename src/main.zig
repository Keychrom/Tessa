const std = @import("std");
const build_options = @import("build_options");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const config = @import("config.zig");
const config_watch = @import("config_watch.zig");
const layout = @import("layout.zig");
const output = @import("output.zig");
const client = @import("client.zig");
const input = @import("input.zig");
const ipc = @import("ipc.zig");
const ime = @import("ime.zig");
const lock = @import("lock.zig");
const xim = @import("xim.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");
const window_effects = @import("window_effects.zig");
const shutdown = @import("shutdown.zig");

const Server = types.Server;

pub const version = "0.2.3";

fn onSignal(sig: c_int, data: ?*anyopaque) callconv(.c) c_int {
    _ = sig;
    const server: *Server = @ptrCast(@alignCast(data.?));
    core.logInfo("signal received, shutting down", .{});
    c.wl_display_terminate(server.display);
    return 0;
}

fn addSocket(server: *Server) ?[*:0]const u8 {
    if (c.getenv("TESSA_SOCKET_NAME")) |name| {
        if (c.wl_display_add_socket(server.display, name) == 0) return name;
        core.logInfo("failed to add socket {s}", .{core.cstr(name)});
        return null;
    }
    return c.wl_display_add_socket_auto(server.display);
}

fn displayNumber(display: []const u8) ?u8 {
    if (display.len < 2 or display[0] != ':') return null;
    var n: u16 = 0;
    var digits: usize = 0;
    for (display[1..]) |ch| {
        if (ch < '0' or ch > '9') break;
        n = n * 10 + (ch - '0');
        digits += 1;
        if (n > 63) return null;
    }
    if (digits == 0) return null;
    return @intCast(n);
}

fn displaySocketExists(n: u8) bool {
    var path_buf: [64:0]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/tmp/.X11-unix/X{d}", .{n}) catch return true;
    if (c.access(path, c.F_OK) == 0) return true;
    var lock_buf: [64:0]u8 = undefined;
    const lock_path = std.fmt.bufPrintZ(&lock_buf, "/tmp/.X{d}-lock", .{n}) catch return true;
    return c.access(lock_path, c.F_OK) == 0;
}

fn xDisplayReady(display: []const u8) bool {
    const n = displayNumber(display) orelse return false;
    var path_buf: [64:0]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/tmp/.X11-unix/X{d}", .{n}) catch return false;
    return c.access(path, c.F_OK) == 0;
}

fn stopXwaylandTimer(server: *Server) void {
    if (server.xwayland_timer) |src| {
        _ = c.wl_event_source_remove(src);
        server.xwayland_timer = null;
    }
}

fn finishStartup(server: *Server) void {
    if (!server.startup_pending) return;
    server.startup_pending = false;
    if (c.getenv("TESSA_STARTUP")) |cmd| {
        core.spawn(core.cstr(cmd));
    }
    events.emit(server, .{ .name = event_names.startup });
    core.markDirty(server);
}

fn onXwaylandReady(data: ?*anyopaque) callconv(.c) c_int {
    const server: *Server = @ptrCast(@alignCast(data.?));
    const display = server.xwayland_display[0..server.xwayland_display_len];

    if (xDisplayReady(display)) {
        stopXwaylandTimer(server);
        var display_z: [34:0]u8 = undefined;
        core.copyZ(&display_z, display);
        _ = c.setenv("DISPLAY", &display_z, 1);
        core.logInfo("xwayland: connected on {s}", .{display});
        xim.init(server, display);
        finishStartup(server);
        return 0;
    }

    server.xwayland_attempts += 1;
    if (server.xwayland_attempts >= 120) {
        stopXwaylandTimer(server);
        core.logInfo("xwayland: X socket did not appear; DISPLAY was not set", .{});
        finishStartup(server);
        return 0;
    }
    if (server.xwayland_timer) |src| _ = c.wl_event_source_timer_update(src, 25);
    return 0;
}

fn pathExists(path: []const u8) bool {
    var z: [128:0]u8 = undefined;
    if (path.len >= z.len) return false;
    core.copyZ(&z, path);
    return c.access(&z, c.F_OK) == 0;
}

fn virtualGpuDetected() bool {
    const modules = [_][]const u8{
        "/sys/module/vmwgfx",
        "/sys/module/vboxvideo",
        "/sys/module/bochs",
        "/sys/module/qxl",
        "/sys/module/cirrus",
        "/sys/module/virtio_gpu",
    };
    for (modules) |path| {
        if (pathExists(path)) return true;
    }
    return false;
}

fn vmwgfxDetected() bool {
    return pathExists("/sys/module/vmwgfx");
}

fn startXwayland(server: *Server) void {
    if (!server.config.xwayland) return;
    if (c.getenv("TESSA_NO_XWAYLAND") != null) return;

    const bin: [*:0]const u8 = if (c.getenv("TESSA_XWAYLAND_BIN")) |p| p else "xwayland-satellite";
    if (!core.commandExists(core.cstr(bin))) {
        core.logInfo("xwayland: '{s}' not found; X11 apps disabled", .{core.cstr(bin)});
        return;
    }

    var display_buf: [34:0]u8 = undefined;
    var display = server.config.xwayland_display[0..server.config.xwayland_display_len];
    if (display.len == 0 or std.mem.eql(u8, display, "auto")) {
        var found = false;
        var n: u8 = 0;
        while (n < 64) : (n += 1) {
            if (displaySocketExists(n)) continue;
            const selected = std.fmt.bufPrint(&display_buf, ":{d}", .{n}) catch return;
            display_buf[selected.len] = 0;
            display = display_buf[0..selected.len];
            found = true;
            break;
        }
        if (!found) {
            core.logInfo("xwayland: no free X display, disabled", .{});
            return;
        }
    } else if (displayNumber(display) == null) {
        core.logInfo("xwayland: invalid display '{s}', disabled", .{display});
        return;
    }

    server.xwayland_display_len = @min(display.len, server.xwayland_display.len);
    @memcpy(server.xwayland_display[0..server.xwayland_display_len], display[0..server.xwayland_display_len]);
    server.xwayland_attempts = 0;

    var display_z: [34:0]u8 = undefined;
    core.copyZ(&display_z, display);
    core.logInfo("starting XWayland on {s}", .{display});
    core.spawnProgramArg(bin, &display_z);

    // xwayland-satellite needs the compositor event loop to service its Wayland
    // connection. Do not block here: set DISPLAY from a timer only once the X
    // socket is actually accepting connections.
    const loop = c.wl_display_get_event_loop(server.display);
    server.xwayland_timer = c.wl_event_loop_add_timer(loop, onXwaylandReady, server);
    if (server.xwayland_timer) |src| {
        _ = c.wl_event_source_timer_update(src, 25);
    } else {
        server.xwayland_display_len = 0;
        core.logInfo("xwayland: could not create readiness timer; DISPLAY was not set", .{});
    }
}

pub fn main() !void {
    _ = c.signal(c.SIGCHLD, c.SIG_IGN);
    const debug = c.getenv("TESSA_DEBUG") != null;
    c.wlr_log_init(if (debug) c.WLR_DEBUG else c.WLR_INFO, null);

    const server = @as(*Server, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Server)).?)));
    server.active_ws = 1;
    server.next_client_id = 1;
    server.ipc_fd = -1;
    server.effect_helper = .{};
    server.layout_refresh = layout.arrangeAll;
    server.ipc_dirty = true;

    config.load(server);

    const virtual_gpu = virtualGpuDetected();
    if (virtual_gpu and c.getenv("WLR_NO_HARDWARE_CURSORS") == null) {
        _ = c.setenv("WLR_NO_HARDWARE_CURSORS", "1", 1);
        core.logInfo("platform: virtual GPU detected; using software cursors", .{});
    }
    // vmwgfx (VMware/VirtualBox VMSVGA) rejects the handle close performed by
    // wlroots' linux-dmabuf import path. Clients then receive a fatal dmabuf
    // import error, so keep them on wl_shm unless explicitly overridden.
    const allow_linux_dmabuf = server.config.linux_dmabuf and
        (!vmwgfxDetected() or c.getenv("TESSA_ALLOW_LINUX_DMABUF") != null);

    server.display = c.wl_display_create() orelse {
        core.logInfo("failed to create wl_display", .{});
        return error.DisplayCreateFailed;
    };
    defer c.wl_display_destroy(server.display);

    server.backend = c.wlr_backend_autocreate(c.wl_display_get_event_loop(server.display), null) orelse {
        core.logInfo("failed to create backend", .{});
        return error.BackendCreateFailed;
    };

    const renderer = if (comptime build_options.scenefx)
        c.fx_renderer_create(server.backend)
    else
        c.wlr_renderer_autocreate(server.backend);
    server.renderer = renderer orelse {
        core.logInfo("failed to create renderer", .{});
        return error.RendererCreateFailed;
    };
    // wlr_renderer_init_wl_display() also creates linux-dmabuf v4, bypassing
    // the vmwgfx guard below. Create wl_shm directly and add dmabuf only when
    // the platform supports it.
    if (!c.wlr_renderer_init_wl_shm(server.renderer, server.display)) {
        core.logInfo("failed to initialize wl_shm", .{});
        return error.ShmCreateFailed;
    }

    server.allocator = c.wlr_allocator_autocreate(server.backend, server.renderer) orelse {
        core.logInfo("failed to create allocator", .{});
        return error.AllocatorCreateFailed;
    };

    server.output_layout = c.wlr_output_layout_create(server.display);
    server.scene = c.wlr_scene_create();
    server.scene_layout = c.wlr_scene_attach_output_layout(server.scene, server.output_layout) orelse {
        core.logInfo("failed to attach scene output layout", .{});
        return error.SceneLayoutFailed;
    };

    server.tree_bg = c.wlr_scene_tree_create(&server.scene.tree);
    server.tree_bottom = c.wlr_scene_tree_create(&server.scene.tree);
    server.tree_windows = c.wlr_scene_tree_create(&server.scene.tree);
    server.tree_floating = c.wlr_scene_tree_create(&server.scene.tree);
    server.tree_top = c.wlr_scene_tree_create(&server.scene.tree);
    server.tree_fullscreen = c.wlr_scene_tree_create(&server.scene.tree);
    server.tree_effects = c.wlr_scene_tree_create(&server.scene.tree);
    server.tree_overlay = c.wlr_scene_tree_create(&server.scene.tree);
    window_effects.configure(server);

    _ = c.wlr_compositor_create(server.display, 6, server.renderer);
    _ = c.wlr_subcompositor_create(server.display);
    _ = c.wlr_data_device_manager_create(server.display);
    if (c.wlr_data_control_manager_v1_create(server.display) != null) {
        core.logInfo("wlr-data-control-v1 enabled", .{});
    }
    _ = c.wlr_screencopy_manager_v1_create(server.display);
    if (allow_linux_dmabuf) {
        if (c.wlr_linux_dmabuf_v1_create_with_renderer(server.display, 5, server.renderer) != null) {
            core.logInfo("linux-dmabuf-v1 enabled", .{});
        }
    } else if (!server.config.linux_dmabuf) {
        core.logInfo("linux-dmabuf-v1 disabled by config", .{});
    } else {
        core.logInfo("linux-dmabuf-v1 disabled on vmwgfx; set TESSA_ALLOW_LINUX_DMABUF=1 to override", .{});
    }
    if (c.wlr_ext_output_image_capture_source_manager_v1_create(server.display, 1) != null) {
        core.logInfo("ext-output-image-capture-source enabled", .{});
    }
    if (c.wlr_ext_image_copy_capture_manager_v1_create(server.display, 1) != null) {
        core.logInfo("ext-image-copy-capture enabled", .{});
    }
    if (c.wlr_viewporter_create(server.display) == null) {
        core.logInfo("failed to create viewporter", .{});
    }
    if (c.wlr_fractional_scale_manager_v1_create(server.display, 1) == null) {
        core.logInfo("failed to create fractional-scale manager", .{});
    }
    if (c.wlr_xdg_output_manager_v1_create(server.display, server.output_layout) == null) {
        core.logInfo("failed to create xdg-output manager", .{});
    }

    server.xdg_shell = c.wlr_xdg_shell_create(server.display, 5) orelse {
        core.logInfo("failed to create xdg-shell", .{});
        return error.XdgShellFailed;
    };
    server.layer_shell = c.wlr_layer_shell_v1_create(server.display, 4) orelse {
        core.logInfo("failed to create layer-shell", .{});
        return error.LayerShellFailed;
    };

    input.init(server);
    output.init(server);
    client.init(server);
    ime.init(server);
    lock.init(server);
    ipc.init(server);
    config_watch.init(server);

    const socket = addSocket(server) orelse {
        core.logInfo("failed to add Wayland socket", .{});
        return error.SocketFailed;
    };
    _ = c.setenv("WAYLAND_DISPLAY", socket, 1);
    _ = c.setenv("XDG_SESSION_TYPE", "wayland", 1);
    _ = c.setenv("XDG_SESSION_DESKTOP", "tessa", 1);
    _ = c.setenv("XDG_CURRENT_DESKTOP", "Tessa", 1);

    const loop = c.wl_display_get_event_loop(server.display);
    server.sigint = c.wl_event_loop_add_signal(loop, c.SIGINT, onSignal, server);
    server.sigterm = c.wl_event_loop_add_signal(loop, c.SIGTERM, onSignal, server);

    if (!c.wlr_backend_start(server.backend)) {
        core.logInfo("failed to start backend", .{});
        return error.BackendStartFailed;
    }

    core.logInfo("tessa {s} running", .{version});
    core.logInfo("  WAYLAND_DISPLAY={s}", .{std.mem.span(socket)});
    core.logInfo("  terminal={s} gaps={d} border={d} ratio={d:.2}", .{
        server.config.terminal[0..server.config.terminal_len],
        server.config.gaps,
        server.config.border_width,
        server.config.master_ratio,
    });

    if (server.config.autostart_panel and c.getenv("TESSA_NO_PANEL") == null) {
        core.logInfo("panels will be started per output", .{});
    }

    server.startup_pending = true;
    startXwayland(server);

    // With XWayland enabled, run startup hooks only after the satellite's X
    // socket exists so X11-aware startup commands see DISPLAY/XMODIFIERS.
    if (server.xwayland_timer == null) finishStartup(server);
    c.wl_display_run(server.display);

    core.logInfo("shutting down", .{});
    events.emit(server, .{ .name = event_names.shutdown });
    ipc.deinit(server);
    c.wl_display_destroy_clients(server.display);
    shutdown.cleanupGlobals(server);
}
