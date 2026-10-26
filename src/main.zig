const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const config = @import("config.zig");
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
const shutdown = @import("shutdown.zig");

const Server = types.Server;

pub const version = "0.1.0";

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

fn displaySocketExists(n: u8) bool {
    var path_buf: [64:0]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/tmp/.X11-unix/X{d}", .{n}) catch return true;
    if (c.access(path, c.F_OK) == 0) return true;
    var lock_buf: [64:0]u8 = undefined;
    const lock_path = std.fmt.bufPrintZ(&lock_buf, "/tmp/.X{d}-lock", .{n}) catch return true;
    return c.access(lock_path, c.F_OK) == 0;
}

fn startXwayland(server: *Server) void {
    if (!server.config.xwayland) return;
    if (c.getenv("TESSA_NO_XWAYLAND") != null) return;

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
    } else if (display.len < 2 or display[0] != ':') {
        core.logInfo("xwayland: invalid display '{s}', disabled", .{display});
        return;
    }

    var display_z: [34:0]u8 = undefined;
    core.copyZ(&display_z, display);
    _ = c.setenv("DISPLAY", &display_z, 1);
    xim.init(server, display);

    const bin: [*:0]const u8 = if (c.getenv("TESSA_XWAYLAND_BIN")) |p| p else "xwayland-satellite";
    core.logInfo("starting XWayland on {s}", .{display});
    core.spawnProgramArg(bin, &display_z);
}

pub fn main() !void {
    _ = c.signal(c.SIGCHLD, c.SIG_IGN);
    const debug = c.getenv("TESSA_DEBUG") != null;
    c.wlr_log_init(if (debug) c.WLR_DEBUG else c.WLR_INFO, null);

    const server = @as(*Server, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Server)).?)));
    server.active_ws = 1;
    server.next_client_id = 1;
    server.ipc_fd = -1;
    server.layout_helper_fd = -1;
    server.ipc_dirty = true;

    config.load(server);

    server.display = c.wl_display_create() orelse {
        core.logInfo("failed to create wl_display", .{});
        return error.DisplayCreateFailed;
    };
    defer c.wl_display_destroy(server.display);

    server.backend = c.wlr_backend_autocreate(c.wl_display_get_event_loop(server.display), null) orelse {
        core.logInfo("failed to create backend", .{});
        return error.BackendCreateFailed;
    };

    server.renderer = c.wlr_renderer_autocreate(server.backend) orelse {
        core.logInfo("failed to create renderer", .{});
        return error.RendererCreateFailed;
    };
    _ = c.wlr_renderer_init_wl_display(server.renderer, server.display);

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
    server.tree_overlay = c.wlr_scene_tree_create(&server.scene.tree);

    _ = c.wlr_compositor_create(server.display, 5, server.renderer);
    _ = c.wlr_subcompositor_create(server.display);
    _ = c.wlr_data_device_manager_create(server.display);
    if (c.wlr_data_control_manager_v1_create(server.display) != null) {
        core.logInfo("wlr-data-control-v1 enabled", .{});
    }
    _ = c.wlr_screencopy_manager_v1_create(server.display);
    if (c.wlr_linux_dmabuf_v1_create_with_renderer(server.display, 5, server.renderer) != null) {
        core.logInfo("linux-dmabuf-v1 enabled", .{});
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

    startXwayland(server);

    if (c.getenv("TESSA_STARTUP")) |cmd| {
        core.spawn(core.cstr(cmd));
    }

    events.emit(server, .{ .name = event_names.startup });
    core.markDirty(server);
    c.wl_display_run(server.display);

    core.logInfo("shutting down", .{});
    events.emit(server, .{ .name = event_names.shutdown });
    ipc.deinit(server);
    c.wl_display_destroy_clients(server.display);
    shutdown.cleanupGlobals(server);
}
