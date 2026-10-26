const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const layout = @import("layout.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");

const Server = types.Server;
const Output = types.Output;
const LayerSurface = types.LayerSurface;

fn lSurface(ls: *c.wlr_layer_surface_v1) *c.wlr_surface {
    return @ptrCast(@alignCast(ls.surface));
}
fn lTree(sl: *c.wlr_scene_layer_surface_v1) *c.wlr_scene_tree {
    return @ptrCast(@alignCast(sl.tree));
}

pub fn init(server: *Server) void {
    initOutputConfig(server);

    server.new_output.notify = onNewOutput;
    c.wl_signal_add(&server.backend.events.new_output, &server.new_output);

    server.new_layer_surface.notify = onNewLayerSurface;
    c.wl_signal_add(&server.layer_shell.events.new_surface, &server.new_layer_surface);

    initOutputManagement(server);
}

fn layerTree(server: *Server, layer: anytype) *c.wlr_scene_tree {
    const n: u32 = @intCast(layer);
    if (n == 0) return server.tree_bg;
    if (n == 1) return server.tree_bottom;
    if (n == 2) return server.tree_top;
    return server.tree_overlay;
}

fn findOutput(server: *Server, wlr: *c.wlr_output) ?*Output {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |out| {
            if (out.wlr == wlr) return out;
        }
    }
    return null;
}

pub fn arrangeLayers(out: *Output) void {
    const server = out.server;
    var full: c.wlr_box = undefined;
    core.outputBox(server, out, &full);
    var usable = full;

    const layers = [_]u32{ 3, 2, 1, 0 };

    var pass: usize = 0;
    while (pass < 2) : (pass += 1) {
        const want_exclusive = pass == 0;
        for (layers) |layer| {
            var i: usize = 0;
            while (i < server.layers.len) : (i += 1) {
                const ls = server.layers[i] orelse continue;
                if (ls.output != out) continue;
                if (!ls.wlr.initialized) continue;
                if (@as(u32, @intCast(ls.wlr.current.layer)) != layer) continue;
                const is_exclusive = ls.wlr.current.exclusive_zone > 0;
                if (is_exclusive != want_exclusive) continue;
                c.wlr_scene_layer_surface_v1_configure(ls.scene_layer, &full, &usable);
            }
        }
    }

    if (usable.x != out.usable.x or usable.y != out.usable.y or
        usable.width != out.usable.width or usable.height != out.usable.height)
    {
        out.usable = usable;
        layout.arrangeOutput(server, out);
        core.markDirty(server);
    }
}

fn onOutputFrame(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const out: *Output = @fieldParentPtr("frame", listener.?);
    const so = c.wlr_scene_get_scene_output(out.server.scene, out.wlr) orelse return;
    _ = c.wlr_scene_output_commit(so, null);
    var now: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    c.wlr_scene_output_send_frame_done(so, &now);
}

fn onOutputRequestState(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const out: *Output = @fieldParentPtr("request_state", listener.?);
    const event: *c.wlr_output_event_request_state = @ptrCast(@alignCast(data.?));
    _ = c.wlr_output_commit_state(out.wlr, event.state);
}

fn updateOutputConfiguration(server: *Server) void {
    const manager = server.output_manager orelse return;
    const config = c.wlr_output_configuration_v1_create();
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        const head_raw = c.wlr_output_configuration_head_v1_create(config, out.wlr);
        if (head_raw != null) {
            const head: *c.wlr_output_configuration_head_v1 = @ptrCast(@alignCast(head_raw));
            var box = c.wlr_box{ .x = 0, .y = 0, .width = 0, .height = 0 };
            core.outputBox(server, out, &box);
            head.state.x = box.x;
            head.state.y = box.y;
        }
    }
    c.wlr_output_manager_v1_set_configuration(manager, config);
}

fn onOutputTest(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("output_test", listener.?);
    const config: *c.wlr_output_configuration_v1 = @ptrCast(@alignCast(data.?));
    defer c.wlr_output_configuration_v1_destroy(config);

    var len: usize = 0;
    const states = c.wlr_output_configuration_v1_build_state(config, &len) orelse {
        c.wlr_output_configuration_v1_send_failed(config);
        return;
    };
    defer c.free(states);
    if (c.wlr_backend_test(server.backend, states, len)) {
        c.wlr_output_configuration_v1_send_succeeded(config);
    } else {
        c.wlr_output_configuration_v1_send_failed(config);
    }
}

fn onOutputApply(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("output_apply", listener.?);
    const config: *c.wlr_output_configuration_v1 = @ptrCast(@alignCast(data.?));
    defer c.wlr_output_configuration_v1_destroy(config);

    var len: usize = 0;
    const states = c.wlr_output_configuration_v1_build_state(config, &len) orelse {
        c.wlr_output_configuration_v1_send_failed(config);
        return;
    };
    defer c.free(states);

    if (!c.wlr_backend_test(server.backend, states, len) or
        !c.wlr_backend_commit(server.backend, states, len))
    {
        c.wlr_output_configuration_v1_send_failed(config);
        return;
    }

    var link_ptr: ?*c.wl_list = @ptrCast(config.heads.next);
    while (link_ptr) |link| {
        if (@intFromPtr(link) == @intFromPtr(&config.heads)) break;
        const head: *c.wlr_output_configuration_head_v1 = @fieldParentPtr("link", link);
        if (head.state.enabled and head.state.output != null) {
            const outw: *c.wlr_output = @ptrCast(@alignCast(head.state.output));
            _ = c.wlr_output_layout_add(server.output_layout, outw, head.state.x, head.state.y);
        }
        link_ptr = @ptrCast(link.next);
    }

    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        core.outputBox(server, out, &out.full);
        out.usable = out.full;
        core.updateBackground(out);
        arrangeLayers(out);
    }
    layout.arrangeAll(server);
    c.wlr_output_configuration_v1_send_succeeded(config);
    updateOutputConfiguration(server);
    saveOutputConfig(server);
    core.markDirty(server);
}

fn findSavedOutput(server: *Server, name: []const u8) ?*types.SavedOutput {
    var i: usize = 0;
    while (i < server.saved_output_count) : (i += 1) {
        const saved = &server.saved_outputs[i];
        if (saved.present and std.mem.eql(u8, saved.name[0..saved.name_len], name)) return saved;
    }
    return null;
}

fn loadOutputConfig(server: *Server) void {
    if (server.output_config_len == 0) return;
    var zpath: [512:0]u8 = undefined;
    core.copyZ(&zpath, server.output_config_path[0..server.output_config_len]);
    const file = c.fopen(&zpath, "r") orelse {
        core.logDebug("output config: {s} not found", .{server.output_config_path[0..server.output_config_len]});
        return;
    };
    defer _ = c.fclose(file);

    var line: [512]u8 = undefined;
    while (c.fgets(&line, @intCast(line.len), file)) |_| {
        const raw = std.mem.span(@as([*:0]const u8, @ptrCast(&line)));
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        var it = std.mem.tokenizeAny(u8, trimmed, " \t");
        const tag = it.next() orelse continue;
        if (!std.mem.eql(u8, tag, "output")) continue;
        const name = it.next() orelse continue;
        const width_s = it.next() orelse continue;
        const height_s = it.next() orelse continue;
        const refresh_s = it.next() orelse continue;
        const x_s = it.next() orelse continue;
        const y_s = it.next() orelse continue;
        const scale_s = it.next() orelse continue;
        const transform_s = it.next() orelse continue;

        var saved = findSavedOutput(server, name);
        if (saved == null) {
            if (server.saved_output_count >= server.saved_outputs.len) continue;
            saved = &server.saved_outputs[server.saved_output_count];
            server.saved_output_count += 1;
            saved.?.* = std.mem.zeroes(types.SavedOutput);
        }
        const entry = saved.?;
        core.copyString(&entry.name, &entry.name_len, name);
        entry.width = std.fmt.parseInt(i32, width_s, 10) catch 0;
        entry.height = std.fmt.parseInt(i32, height_s, 10) catch 0;
        entry.refresh = std.fmt.parseInt(i32, refresh_s, 10) catch 0;
        entry.x = std.fmt.parseInt(i32, x_s, 10) catch 0;
        entry.y = std.fmt.parseInt(i32, y_s, 10) catch 0;
        entry.scale = std.fmt.parseFloat(f32, scale_s) catch 1.0;
        entry.transform = std.fmt.parseInt(u32, transform_s, 10) catch 0;
        entry.present = true;
    }
    if (server.saved_output_count > 0) {
        core.logInfo("output config: loaded {d} entries from {s}", .{
            server.saved_output_count,
            server.output_config_path[0..server.output_config_len],
        });
    }
}

fn initOutputConfig(server: *Server) void {
    var path_buf: [512]u8 = undefined;
    var path: []const u8 = "";
    if (c.getenv("TESSA_OUTPUT_CONFIG")) |p| {
        path = core.cstr(p);
    } else if (server.config.output_config_len > 0) {
        path = server.config.output_config[0..server.config.output_config_len];
    } else if (c.getenv("XDG_CONFIG_HOME")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/tessa/outputs.conf", .{core.cstr(p)}) catch "";
    } else if (c.getenv("HOME")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/.config/tessa/outputs.conf", .{core.cstr(p)}) catch "";
    }
    if (path.len == 0) return;
    if (path.len >= server.output_config_path.len) {
        core.logInfo("output config: path too long", .{});
        return;
    }
    core.copyString(&server.output_config_path, &server.output_config_len, path);
    loadOutputConfig(server);
}

fn ensureParentDirs(path: []const u8) void {
    var buf: [512:0]u8 = undefined;
    if (path.len >= buf.len) return;
    core.copyZ(&buf, path);
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') {
            buf[i] = 0;
            _ = c.mkdir(&buf, 0o755);
            buf[i] = '/';
        }
    }
}

fn saveOutputConfig(server: *Server) void {
    if (server.output_config_len == 0) return;
    const path = server.output_config_path[0..server.output_config_len];
    ensureParentDirs(path);

    var path_z: [512:0]u8 = undefined;
    var tmp_z: [520:0]u8 = undefined;
    core.copyZ(&path_z, path);
    const tmp = std.fmt.bufPrintZ(&tmp_z, "{s}.tmp", .{path}) catch return;

    const file = c.fopen(tmp.ptr, "w") orelse {
        core.logInfo("output config: cannot write {s}", .{path});
        return;
    };

    const header = "# Tessa output configuration. Written by the compositor.\n" ++
        "# output NAME WIDTH HEIGHT REFRESH_MHZ X Y SCALE TRANSFORM\n";
    _ = c.fwrite(header.ptr, 1, header.len, file);

    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        var box = c.wlr_box{ .x = 0, .y = 0, .width = 0, .height = 0 };
        core.outputBox(server, out, &box);

        var width = out.wlr.width;
        var height = out.wlr.height;
        var refresh = out.wlr.refresh;
        if (out.wlr.current_mode != null) {
            const mode: *c.wlr_output_mode = @ptrCast(@alignCast(out.wlr.current_mode));
            width = mode.width;
            height = mode.height;
            refresh = mode.refresh;
        }
        var line_buf: [512]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "output {s} {d} {d} {d} {d} {d} {d:.3} {d}\n", .{
            core.outputName(out),
            width,
            height,
            refresh,
            box.x,
            box.y,
            out.wlr.scale,
            out.wlr.transform,
        }) catch continue;
        _ = c.fwrite(line.ptr, 1, line.len, file);
    }
    _ = c.fclose(file);

    if (c.rename(tmp.ptr, &path_z) != 0) {
        _ = c.unlink(tmp.ptr);
        core.logInfo("output config: rename failed for {s}", .{path});
        return;
    }
    _ = c.chmod(&path_z, 0o600);
    core.logInfo("output config: saved {d} output(s) to {s}", .{ server.output_count, path });
}

fn outputMode(out: *c.wlr_output, width: i32, height: i32, refresh: i32) ?*c.wlr_output_mode {
    var link: ?*c.wl_list = out.modes.next;
    while (link) |node| {
        if (@intFromPtr(node) == @intFromPtr(&out.modes)) break;
        const mode: *c.wlr_output_mode = @fieldParentPtr("link", node);
        if (mode.width == width and mode.height == height and
            (refresh == 0 or mode.refresh == refresh)) return mode;
        link = node.next;
    }
    return null;
}

fn setDefaultMode(out: *c.wlr_output, state: *c.wlr_output_state) void {
    if (c.wlr_output_is_headless(out)) {
        c.wlr_output_state_set_custom_mode(state, 1920, 1080, 60000);
    } else if (c.wlr_output_preferred_mode(out)) |mode| {
        c.wlr_output_state_set_mode(state, mode);
    }
}

fn setSavedMode(out: *c.wlr_output, state: *c.wlr_output_state, saved: *types.SavedOutput) void {
    if (saved.width <= 0 or saved.height <= 0) {
        setDefaultMode(out, state);
        return;
    }
    if (outputMode(out, saved.width, saved.height, saved.refresh)) |mode| {
        c.wlr_output_state_set_mode(state, mode);
    } else {
        c.wlr_output_state_set_custom_mode(state, saved.width, saved.height, saved.refresh);
    }
}

pub fn initOutputManagement(server: *Server) void {
    const raw = c.wlr_output_manager_v1_create(server.display);
    if (raw == null) return;
    const manager: *c.wlr_output_manager_v1 = @ptrCast(@alignCast(raw));
    server.output_manager = manager;
    server.output_apply.notify = onOutputApply;
    c.wl_signal_add(&manager.events.apply, &server.output_apply);
    server.output_test.notify = onOutputTest;
    c.wl_signal_add(&manager.events.@"test", &server.output_test);
    updateOutputConfiguration(server);
    core.logInfo("output-management-v1 enabled", .{});
}

fn onOutputDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const out: *Output = @fieldParentPtr("destroy", listener.?);
    const server = out.server;

    c.wl_list_remove(&out.frame.link);
    c.wl_list_remove(&out.request_state.link);
    c.wl_list_remove(&out.destroy.link);
    c.wlr_scene_node_destroy(&out.bg_rect.node);

    const idx = core.outputIndexOf(server, out) orelse {
        c.free(out);
        return;
    };

    if (server.output_count <= 1) {
        core.logInfo("last output disappeared, terminating", .{});
        c.wl_display_terminate(server.display);
        return;
    }

    core.removeAt(types.Output, server.outputs[0..], &server.output_count, idx);

    var fallback: ?*Output = null;
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |o| {
            fallback = o;
            break;
        }
    }
    if (fallback) |fb| {
        var k: usize = 0;
        while (k < server.clients.len) : (k += 1) {
            const cl = server.clients[k] orelse continue;
            if (cl.output == out) {
                cl.output = fb;
                cl.ws = fb.active_ws;
                cl.float_x = fb.full.x;
                cl.float_y = fb.full.y;
            }
        }
        if (server.focused_output == out) {
            server.focused_output = fb;
        }
    }

    core.logInfo("output removed: {s}", .{core.cstr(out.wlr.name)});
    var removed_buf: [64]u8 = undefined;
    const removed_name = core.copyStringBuf(&removed_buf, core.outputName(out));
    var geometry_buf: [64]u8 = undefined;
    const geometry = std.fmt.bufPrint(&geometry_buf, "{d}x{d}+{d}+{d}", .{
        out.full.width,
        out.full.height,
        out.full.x,
        out.full.y,
    }) catch "";
    events.emit(server, .{
        .name = event_names.output_removed,
        .output = removed_name,
        .arg = geometry,
    });
    c.free(out);
    layout.arrangeAll(server);
    updateOutputConfiguration(server);
    core.markDirty(server);
}

fn onNewOutput(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_output", listener.?);
    const wlr_out: *c.wlr_output = @ptrCast(@alignCast(data.?));

    if (!c.wlr_output_init_render(wlr_out, server.allocator, server.renderer)) {
        core.logInfo("failed to init render for output {s}", .{core.cstr(wlr_out.name)});
        return;
    }

    const saved = findSavedOutput(server, core.cstr(wlr_out.name));
    var state: c.wlr_output_state = undefined;
    c.wlr_output_state_init(&state);
    c.wlr_output_state_set_enabled(&state, true);
    var scale: f32 = 1.0;
    if (saved) |entry| {
        if (entry.scale >= 0.1 and entry.scale <= 10.0) scale = entry.scale;
    }
    c.wlr_output_state_set_scale(&state, scale);
    if (saved) |entry| {
        if (entry.transform <= 7) c.wlr_output_state_set_transform(&state, entry.transform);
        setSavedMode(wlr_out, &state, entry);
    } else {
        setDefaultMode(wlr_out, &state);
    }
    var committed = c.wlr_output_commit_state(wlr_out, &state);
    if (!committed and saved != null) {
        core.logInfo("saved output state for {s} failed; using defaults", .{core.cstr(wlr_out.name)});
        c.wlr_output_state_finish(&state);
        c.wlr_output_state_init(&state);
        c.wlr_output_state_set_enabled(&state, true);
        c.wlr_output_state_set_scale(&state, scale);
        if (saved) |entry| {
            if (entry.transform <= 7) c.wlr_output_state_set_transform(&state, entry.transform);
        }
        setDefaultMode(wlr_out, &state);
        committed = c.wlr_output_commit_state(wlr_out, &state);
    }
    if (!committed) {
        core.logInfo("failed to commit initial state for output {s}", .{core.cstr(wlr_out.name)});
    }
    c.wlr_output_state_finish(&state);

    const out = @as(*Output, @ptrCast(@alignCast(c.calloc(1, @sizeOf(Output)).?)));
    out.server = server;
    out.wlr = wlr_out;
    out.active_ws = 1;

    out.frame.notify = onOutputFrame;
    c.wl_signal_add(&wlr_out.events.frame, &out.frame);
    out.request_state.notify = onOutputRequestState;
    c.wl_signal_add(&wlr_out.events.request_state, &out.request_state);
    out.destroy.notify = onOutputDestroy;
    c.wl_signal_add(&wlr_out.events.destroy, &out.destroy);

    if (saved) |entry| {
        out.layout_output = c.wlr_output_layout_add(server.output_layout, wlr_out, entry.x, entry.y);
    } else {
        out.layout_output = c.wlr_output_layout_add_auto(server.output_layout, wlr_out);
    }
    out.scene_output = c.wlr_scene_output_create(server.scene, wlr_out);
    c.wlr_scene_output_layout_add_output(server.scene_layout, out.layout_output, out.scene_output);

    const bg = [4]f32{ 0.025, 0.04, 0.075, 1.0 };
    out.bg_rect = c.wlr_scene_rect_create(server.tree_bg, 1, 1, &bg);

    core.outputBox(server, out, &out.full);
    out.usable = out.full;
    core.updateBackground(out);

    if (server.output_count < server.outputs.len) {
        server.outputs[server.output_count] = out;
        server.output_count += 1;
    } else {
        core.logInfo("too many outputs, ignoring {s}", .{core.cstr(wlr_out.name)});
        c.free(out);
        return;
    }

    core.logInfo("output added: {s} {d}x{d} @ {d},{d}", .{
        core.cstr(wlr_out.name),
        out.full.width,
        out.full.height,
        out.full.x,
        out.full.y,
    });

    if (server.focused_output == null) server.focused_output = out;
    core.spawnPanel(server, out);

    arrangeLayers(out);
    layout.arrangeAll(server);
    updateOutputConfiguration(server);
    var geometry_buf: [64]u8 = undefined;
    const geometry = std.fmt.bufPrint(&geometry_buf, "{d}x{d}+{d}+{d}", .{
        out.full.width,
        out.full.height,
        out.full.x,
        out.full.y,
    }) catch "";
    events.emit(server, .{
        .name = event_names.output_added,
        .output = core.outputName(out),
        .arg = geometry,
    });
    core.markDirty(server);
}

fn onLayerCommit(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LayerSurface = @fieldParentPtr("commit", listener.?);

    if (ls.wlr.initialized) {
        const target = layerTree(ls.server, ls.wlr.current.layer);
        const tree = lTree(ls.scene_layer);
        const parent: ?*c.wlr_scene_tree = if (tree.node.parent) |p|
            @ptrCast(@alignCast(p))
        else
            null;
        if (parent != target) {
            c.wlr_scene_node_reparent(&tree.node, target);
        }
    }

    if (ls.wlr.initial_commit or ls.wlr.current.committed != 0 or
        lSurface(ls.wlr).mapped != ls.mapped)
    {
        arrangeLayers(ls.output);
    }
}

fn onLayerMap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LayerSurface = @fieldParentPtr("map", listener.?);
    ls.mapped = true;

    const interactive: u32 = @intCast(ls.wlr.current.keyboard_interactive);
    const layer_n: u32 = @intCast(ls.wlr.current.layer);
    core.logInfo("layer map: {s} layer={d} keyboard={d}", .{
        core.cstr(ls.wlr.namespace),
        layer_n,
        interactive,
    });
    if (interactive != 0 and layer_n >= 2) {
        layout.focusLayer(ls.server, ls);
    }

    arrangeLayers(ls.output);
    core.markDirty(ls.server);
}

fn onLayerUnmap(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LayerSurface = @fieldParentPtr("unmap", listener.?);
    ls.mapped = false;
    layout.restoreFocusAfterLayer(ls.server, ls);
    arrangeLayers(ls.output);
    core.markDirty(ls.server);
}

fn onLayerNewPopup(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const ls: *LayerSurface = @fieldParentPtr("new_popup", listener.?);
    const popup: *c.wlr_xdg_popup = @ptrCast(@alignCast(data.?));
    const base: *c.wlr_xdg_surface = @ptrCast(@alignCast(popup.base));
    const tree = lTree(ls.scene_layer);
    base.data = @ptrCast(c.wlr_scene_xdg_surface_create(tree, base));
    core.logInfo("layer popup created", .{});
}

fn onLayerDestroy(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    const ls: *LayerSurface = @fieldParentPtr("destroy", listener.?);
    const server = ls.server;
    const out = ls.output;

    c.wl_list_remove(&ls.commit.link);
    c.wl_list_remove(&ls.map.link);
    c.wl_list_remove(&ls.unmap.link);
    c.wl_list_remove(&ls.new_popup.link);
    c.wl_list_remove(&ls.destroy.link);

    if (server.focused_layer == ls) {
        server.focused_layer = null;
    }
    if (server.lock_saved_layer == ls) {
        server.lock_saved_layer = null;
    }

    if (core.layerIndexOf(server, ls)) |idx| {
        core.removeAt(types.LayerSurface, server.layers[0..], &server.layer_count, idx);
    }

    arrangeLayers(out);
    core.markDirty(server);
    c.free(ls);
}

fn onNewLayerSurface(listener: ?*c.wl_listener, data: ?*anyopaque) callconv(.c) void {
    const server: *Server = @fieldParentPtr("new_layer_surface", listener.?);
    const wlr_ls: *c.wlr_layer_surface_v1 = @ptrCast(@alignCast(data.?));

    var out: ?*Output = null;
    if (wlr_ls.output) |wlr_out| {
        out = findOutput(server, wlr_out);
    }
    if (out == null) out = core.focusOutput(server);
    if (out == null) out = core.firstOutput(server);
    if (out == null) {
        c.wlr_layer_surface_v1_destroy(wlr_ls);
        return;
    }

    wlr_ls.output = out.?.wlr;

    const scene_layer_raw = c.wlr_scene_layer_surface_v1_create(
        layerTree(server, wlr_ls.current.layer),
        wlr_ls,
    ) orelse {
        c.wlr_layer_surface_v1_destroy(wlr_ls);
        return;
    };
    const scene_layer: *c.wlr_scene_layer_surface_v1 = @ptrCast(@alignCast(scene_layer_raw));

    const ls = @as(*LayerSurface, @ptrCast(@alignCast(c.calloc(1, @sizeOf(LayerSurface)).?)));
    ls.server = server;
    ls.wlr = wlr_ls;
    ls.scene_layer = scene_layer;
    ls.output = out.?;
    ls.mapped = false;

    ls.commit.notify = onLayerCommit;
    c.wl_signal_add(&lSurface(wlr_ls).events.commit, &ls.commit);
    ls.map.notify = onLayerMap;
    c.wl_signal_add(&lSurface(wlr_ls).events.map, &ls.map);
    ls.unmap.notify = onLayerUnmap;
    c.wl_signal_add(&lSurface(wlr_ls).events.unmap, &ls.unmap);
    ls.new_popup.notify = onLayerNewPopup;
    c.wl_signal_add(&wlr_ls.events.new_popup, &ls.new_popup);
    ls.destroy.notify = onLayerDestroy;
    c.wl_signal_add(&wlr_ls.events.destroy, &ls.destroy);

    if (server.layer_count < server.layers.len) {
        server.layers[server.layer_count] = ls;
        server.layer_count += 1;
    } else {
        c.wlr_layer_surface_v1_destroy(wlr_ls);
        return;
    }

    core.logInfo("layer surface: {s} layer={d}", .{
        core.cstr(wlr_ls.namespace),
        @as(u32, @intCast(wlr_ls.current.layer)),
    });
}
