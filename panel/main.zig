const std = @import("std");
const c = @import("c.zig").c;
const m = @import("model.zig");
const draw = @import("draw.zig");
const apps = @import("apps.zig");

const g = &m.g;

extern fn tessa_notifications_start() c_int;
extern fn tessa_notifications_stop() void;
extern fn tessa_notifications_close(id: c_uint, reason: c_uint) void;
extern fn tessa_notifications_action(id: c_uint, key: [*:0]const u8) void;
extern fn tessa_media_start() c_int;
extern fn tessa_media_stop() void;
extern fn tessa_media_command(code: c_uint) void;
extern fn tessa_tray_start() c_int;
extern fn tessa_tray_stop() void;
extern fn tessa_tray_activate(index: c_uint, code: c_uint) void;
extern fn tessa_audio_start(status_cmd: [*:0]const u8, up_cmd: [*:0]const u8, down_cmd: [*:0]const u8, mute_cmd: [*:0]const u8) c_int;
extern fn tessa_audio_stop() void;
extern fn tessa_audio_command(code: c_uint) void;

var registry_listener: c.wl_registry_listener = undefined;
var seat_listener: c.wl_seat_listener = undefined;
var keyboard_listener: c.wl_keyboard_listener = undefined;
var pointer_listener: c.wl_pointer_listener = undefined;
var shm_listener: c.wl_shm_listener = undefined;
var output_listener: c.wl_output_listener = undefined;

fn logMsg(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("tessa-panel: " ++ fmt ++ "\n", args);
}

fn logDebug(comptime fmt: []const u8, args: anytype) void {
    if (c.getenv("TESSA_DEBUG") == null) return;
    logMsg(fmt, args);
}

fn surfaceFor(wl_surface: ?*c.wl_surface) ?*m.Surface {
    if (wl_surface == null) return null;
    if (g.bar.wl == wl_surface) return &g.bar;
    if (g.bg.wl == wl_surface) return &g.bg;
    if (g.overlay) |ov| {
        if (ov.wl == wl_surface) return ov;
    }
    if (g.toasts) |toasts| {
        if (toasts.wl == wl_surface) return toasts;
    }
    return null;
}

fn onLayerConfigure(data: ?*anyopaque, layer: ?*c.zwlr_layer_surface_v1, serial: u32, width: u32, height: u32) callconv(.c) void {
    _ = layer;
    const s: *m.Surface = @ptrCast(@alignCast(data.?));
    if (s.layer) |ls| c.zwlr_layer_surface_v1_ack_configure(ls, serial);
    draw.configureSurface(s, width, height);
    if (s.kind == .overlay and g.overlay_mode == .launcher) {
        computeSearchRect();
        if (g.text_input_enabled) syncTextInput(c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER);
    }
}

fn destroyOverlay() void {
    const s = g.overlay orelse return;
    if (g.overlay_mode == .screenshot) freeScreenshot();
    g.overlay = null;
    g.overlay_mode = .none;
    g.launcher_open = false;
    g.menu_anim = 0;
    if (g.pointer_surface == s) g.pointer_surface = null;
    destroyTextInput();
    draw.destroyBuffers(s);
    if (s.layer) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (s.wl) |wl| c.wl_surface_destroy(wl);
    c.free(s);
}

fn onLayerClosed(data: ?*anyopaque, layer: ?*c.zwlr_layer_surface_v1) callconv(.c) void {
    _ = layer;
    const s: *m.Surface = @ptrCast(@alignCast(data.?));
    if (s.kind == .overlay) {
        destroyOverlay();
    } else if (s.kind == .toasts) {
        destroyToasts();
    } else {
        g.running = false;
    }
}

fn createLayerSurface(
    s: *m.Surface,
    output: ?*c.wl_output,
    kind: m.SurfaceKind,
    layer: u32,
    anchors: u32,
    width: u32,
    height: u32,
    top: i32,
    right: i32,
    bottom: i32,
    left: i32,
    exclusive: i32,
    keyboard: u32,
    namespace: [*:0]const u8,
) bool {
    const compositor = g.compositor orelse return false;
    const shell = g.layer_shell orelse return false;

    s.kind = kind;
    s.width = 0;
    s.height = 0;
    s.configured = false;
    s.dirty = true;
    s.listener = std.mem.zeroes(c.zwlr_layer_surface_v1_listener);
    s.listener.configure = onLayerConfigure;
    s.listener.closed = onLayerClosed;
    var i: usize = 0;
    while (i < s.buffers.len) : (i += 1) {
        s.buffers[i] = std.mem.zeroes(m.Buffer);
        s.buffers[i].owner = s;
    }

    const wl = c.wl_compositor_create_surface(compositor) orelse return false;
    s.wl = wl;
    s.scale = g.scale;
    c.wl_surface_set_buffer_scale(wl, g.scale);

    const ls = c.zwlr_layer_shell_v1_get_layer_surface(shell, wl, output, layer, namespace) orelse {
        c.wl_surface_destroy(wl);
        s.wl = null;
        return false;
    };
    s.layer = ls;

    c.zwlr_layer_surface_v1_set_size(ls, width, height);
    c.zwlr_layer_surface_v1_set_anchor(ls, anchors);
    c.zwlr_layer_surface_v1_set_exclusive_zone(ls, exclusive);
    c.zwlr_layer_surface_v1_set_margin(ls, top, right, bottom, left);
    c.zwlr_layer_surface_v1_set_keyboard_interactivity(ls, keyboard);
    _ = c.zwlr_layer_surface_v1_add_listener(ls, &s.listener, s);

    if (kind == .background) {
        const region = c.wl_compositor_create_region(compositor);
        if (region) |r| {
            c.wl_surface_set_input_region(wl, r);
            c.wl_region_destroy(r);
        }
    }

    c.wl_surface_commit(wl);
    return true;
}

fn applyPanelScale(scale: i32) void {
    const scl = @max(1, scale);
    if (g.scale == scl) return;
    g.scale = scl;
    draw.setSurfaceScale(&g.bg, scl);
    draw.setSurfaceScale(&g.bar, scl);
    if (g.overlay) |ov| draw.setSurfaceScale(ov, scl);
    if (g.toasts) |toasts| draw.setSurfaceScale(toasts, scl);
    g.bg.dirty = true;
    g.bar.dirty = true;
    if (g.overlay) |ov| {
        ov.dirty = true;
        if (g.overlay_mode == .launcher) {
            computeSearchRect();
            if (g.text_input_enabled) syncTextInput(c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER);
        }
    }
    logMsg("output scale: {d}", .{scl});
}

fn createBar() void {
    const created = createLayerSurface(
        &g.bar,
        g.target_output,
        .bar,
        @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP),
        @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT),
        0,
        @intCast(g.bar_height),
        g.bar_top_margin,
        g.bar_side_margin,
        0,
        g.bar_side_margin,
        g.bar_height,
        0,
        "tessa-bar",
    );
    if (created) {
        logMsg("bar: {d}px top={d} side={d}", .{
            g.bar_height,
            g.bar_top_margin,
            g.bar_side_margin,
        });
    }
}

fn destroyBar() void {
    if (g.pointer_surface == &g.bar) g.pointer_surface = null;
    draw.destroyBuffers(&g.bar);
    if (g.bar.layer) |ls| {
        g.bar.layer = null;
        c.zwlr_layer_surface_v1_destroy(ls);
    }
    if (g.bar.wl) |wl| {
        g.bar.wl = null;
        c.wl_surface_destroy(wl);
    }
    g.bar.configured = false;
    g.bar.width = 0;
    g.bar.height = 0;
    g.bar.dirty = true;
    g.bar_hit_count = 0;
}

fn createChrome() void {
    _ = createLayerSurface(
        &g.bg,
        g.target_output,
        .background,
        0,
        @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT),
        0,
        0,
        0,
        0,
        0,
        0,
        -1,
        0,
        "tessa-background",
    );
    createBar();
}

fn computeSearchRect() void {
    const s = g.overlay orelse return;
    if (s.width == 0 or s.height == 0) return;
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    const l = m.launcherLayout(W, H);
    const x: i32 = @intFromFloat(@round(l.x + 78.0 * l.scale));
    const y: i32 = @intFromFloat(@round(l.y + 106.0 * l.scale));
    const w: i32 = @max(1, @as(i32, @intFromFloat(@round(l.scale))));
    const h: i32 = @max(8, @as(i32, @intFromFloat(@round(20.0 * l.scale))));
    g.search_rect = .{ x, y, w, h };
}

fn syncTextInput(cause: u32) void {
    const ti = g.text_input orelse return;
    if (!g.text_input_enabled) return;
    c.zwp_text_input_v3_set_content_type(
        ti,
        @intCast(c.ZWP_TEXT_INPUT_V3_CONTENT_HINT_COMPLETION),
        @intCast(c.ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NORMAL),
    );
    c.zwp_text_input_v3_set_surrounding_text(ti, @ptrCast(&g.query), @intCast(g.query_len), @intCast(g.query_len));
    c.zwp_text_input_v3_set_text_change_cause(ti, cause);
    c.zwp_text_input_v3_set_cursor_rectangle(ti, g.search_rect[0], g.search_rect[1], g.search_rect[2], g.search_rect[3]);
    c.zwp_text_input_v3_commit(ti);
}

fn onTiEnter(data: ?*anyopaque, ti: ?*c.zwp_text_input_v3, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = ti;
    _ = surface;
    g.text_input_focused = true;
    logDebug("text input enter rect={d},{d} {d}x{d}", .{ g.search_rect[0], g.search_rect[1], g.search_rect[2], g.search_rect[3] });
    syncTextInput(c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER);
}

fn onTiLeave(data: ?*anyopaque, ti: ?*c.zwp_text_input_v3, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = ti;
    _ = surface;
    g.text_input_focused = false;
}

fn onTiPreedit(data: ?*anyopaque, ti: ?*c.zwp_text_input_v3, text: [*c]const u8, begin: i32, end: i32) callconv(.c) void {
    _ = data;
    _ = ti;
    if (text != null) {
        m.copyTrunc(&g.preedit, &g.preedit_len, std.mem.span(text));
    } else {
        g.preedit_len = 0;
        g.preedit[0] = 0;
    }
    g.preedit_begin = begin;
    g.preedit_end = end;
    logDebug("preedit len={d}", .{g.preedit_len});
    if (g.overlay) |s| s.dirty = true;
}

fn onTiCommit(data: ?*anyopaque, ti: ?*c.zwp_text_input_v3, text: [*c]const u8) callconv(.c) void {
    _ = data;
    _ = ti;
    logDebug("commit string", .{});
    if (text != null) appendQueryUtf8(std.mem.span(text));
    g.preedit_len = 0;
    g.preedit[0] = 0;
    if (g.overlay) |s| s.dirty = true;
    syncTextInput(c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_INPUT_METHOD);
}

fn onTiDelete(data: ?*anyopaque, ti: ?*c.zwp_text_input_v3, before: u32, after: u32) callconv(.c) void {
    _ = data;
    _ = ti;
    _ = after;
    const n = @min(g.query_len, @as(usize, before));
    g.query_len -= n;
    g.query[g.query_len] = 0;
    g.preedit_len = 0;
    g.preedit[0] = 0;
    g.selected = 0;
    g.scroll = 0;
    m.recomputeResults();
    if (g.overlay) |s| s.dirty = true;
    syncTextInput(c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_INPUT_METHOD);
}

fn onTiDone(data: ?*anyopaque, ti: ?*c.zwp_text_input_v3, serial: u32) callconv(.c) void {
    _ = data;
    _ = ti;
    _ = serial;
    if (g.overlay) |s| s.dirty = true;
}

fn createTextInput() void {
    if (g.text_input != null) return;
    const mgr = g.text_input_manager orelse {
        logMsg("text input manager is unavailable", .{});
        return;
    };
    const seat = g.seat orelse {
        logMsg("seat is unavailable for text input", .{});
        return;
    };
    const ti = c.zwp_text_input_manager_v3_get_text_input(mgr, seat) orelse {
        logMsg("get_text_input returned null", .{});
        return;
    };
    logDebug("text input created", .{});
    g.text_input = ti;
    g.text_input_listener = std.mem.zeroes(c.zwp_text_input_v3_listener);
    g.text_input_listener.enter = onTiEnter;
    g.text_input_listener.leave = onTiLeave;
    g.text_input_listener.preedit_string = onTiPreedit;
    g.text_input_listener.commit_string = onTiCommit;
    g.text_input_listener.delete_surrounding_text = onTiDelete;
    g.text_input_listener.done = onTiDone;
    _ = c.zwp_text_input_v3_add_listener(ti, &g.text_input_listener, null);
}

fn enableTextInput() void {
    createTextInput();
    const ti = g.text_input orelse return;
    if (g.text_input_enabled) {
        syncTextInput(c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER);
        return;
    }
    computeSearchRect();
    c.zwp_text_input_v3_set_content_type(
        ti,
        @intCast(c.ZWP_TEXT_INPUT_V3_CONTENT_HINT_COMPLETION),
        @intCast(c.ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NORMAL),
    );
    c.zwp_text_input_v3_set_surrounding_text(ti, @ptrCast(&g.query), @intCast(g.query_len), @intCast(g.query_len));
    c.zwp_text_input_v3_set_text_change_cause(ti, c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER);
    c.zwp_text_input_v3_set_cursor_rectangle(ti, g.search_rect[0], g.search_rect[1], g.search_rect[2], g.search_rect[3]);
    c.zwp_text_input_v3_enable(ti);
    c.zwp_text_input_v3_commit(ti);
    g.text_input_enabled = true;
    logDebug("text input enabled", .{});
}

fn disableTextInput() void {
    const ti = g.text_input orelse return;
    if (g.text_input_enabled) {
        c.zwp_text_input_v3_disable(ti);
        c.zwp_text_input_v3_commit(ti);
        g.text_input_enabled = false;
    }
    g.text_input_focused = false;
}

fn destroyTextInput() void {
    disableTextInput();
    if (g.text_input) |ti| {
        c.zwp_text_input_v3_destroy(ti);
        g.text_input = null;
    }
    g.preedit_len = 0;
    g.preedit[0] = 0;
}

fn ensureOverlay() bool {
    if (g.overlay != null) return true;
    const s = @as(*m.Surface, @ptrCast(@alignCast(c.calloc(1, @sizeOf(m.Surface)).?)));
    s.* = std.mem.zeroes(m.Surface);
    if (!createLayerSurface(
        s,
        g.target_output,
        .overlay,
        @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY),
        @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT),
        0,
        0,
        0,
        0,
        0,
        0,
        -1,
        @intCast(c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE),
        "tessa-overlay",
    )) {
        c.free(s);
        return false;
    }
    g.overlay = s;
    return true;
}

fn beginOverlay(mode: m.OverlayMode) void {
    g.overlay_mode = mode;
    g.launcher_open = mode == .launcher;
    g.hover = .{};
    g.overlay_row_hover = 999;
    g.preedit_len = 0;
    g.preedit[0] = 0;
    g.menu_from = g.menu_anim;
    g.menu_target = 1;
    g.menu_anim_start = m.nowMs();
    g.next_blink_ms = m.nowMs() + 500;
    if (mode == .launcher) {
        enableTextInput();
    } else {
        disableTextInput();
    }
    g.overlay.?.dirty = true;
    g.bar.dirty = true;
}

fn openLauncher(query_arg: []const u8) void {
    if (g.overlay != null and
        (g.overlay_mode != .launcher or !g.launcher_open or g.menu_target == 0))
    {
        destroyOverlay();
    }
    if (g.overlay != null and g.launcher_open) {
        if (query_arg.len == 0) {
            closeOverlay();
            return;
        }
        m.setQuery(query_arg);
        g.overlay.?.dirty = true;
        return;
    }

    if (!ensureOverlay()) return;
    beginOverlay(.launcher);
    m.setQuery(query_arg);
    g.overlay.?.dirty = true;
}

fn openCalendar() void {
    if (g.overlay != null and g.overlay_mode == .calendar and g.menu_target == 1) {
        closeOverlay();
        return;
    }
    if (g.overlay != null) destroyOverlay();
    m.resetCalendarToday();
    if (!ensureOverlay()) return;
    beginOverlay(.calendar);
    logDebug("calendar open", .{});
}

fn openPower() void {
    if (g.overlay != null and g.overlay_mode == .power and g.menu_target == 1) {
        closeOverlay();
        return;
    }
    if (g.overlay != null) destroyOverlay();
    if (!ensureOverlay()) return;
    g.power_selected = 0;
    beginOverlay(.power);
    logDebug("power menu open", .{});
}

fn openMedia() void {
    if (g.overlay != null and g.overlay_mode == .media and g.menu_target == 1) {
        closeOverlay();
        return;
    }
    if (g.overlay != null) destroyOverlay();
    if (!ensureOverlay()) return;
    beginOverlay(.media);
    logDebug("media: controls open", .{});
}

fn openClipboard() void {
    if (g.overlay != null and g.overlay_mode == .clipboard and g.menu_target == 1) {
        closeOverlay();
        return;
    }
    if (g.overlay != null) destroyOverlay();
    if (!ensureOverlay()) return;
    g.clipboard_selected = 0;
    beginOverlay(.clipboard);
    logDebug("clipboard open ({d} entries)", .{g.clipboard_count});
}

fn openPanel(name: []const u8) void {
    if (std.mem.eql(u8, name, "calendar")) {
        openCalendar();
    } else if (std.mem.eql(u8, name, "power")) {
        openPower();
    } else if (std.mem.eql(u8, name, "clipboard")) {
        openClipboard();
    } else if (std.mem.eql(u8, name, "screenshot")) {
        openScreenshot();
    } else if (std.mem.eql(u8, name, "media")) {
        openMedia();
    } else if (std.mem.eql(u8, name, "tray")) {
        openTray();
    } else if (std.mem.eql(u8, name, "audio")) {
        openAudio();
    } else {
        logDebug("unknown panel '{s}'", .{name});
    }
}

fn closeOverlay() void {
    if (g.overlay == null or g.menu_target == 0) return;
    disableTextInput();
    g.launcher_open = false;
    g.menu_from = g.menu_anim;
    g.menu_target = 0;
    g.menu_anim_start = m.nowMs();
    g.overlay.?.dirty = true;
    logDebug("overlay close", .{});
}

fn tickAnimation(now: i64) void {
    const s = g.overlay orelse return;
    const dur: i64 = 150;
    var p = @as(f64, @floatFromInt(now - g.menu_anim_start)) / @as(f64, @floatFromInt(dur));
    p = std.math.clamp(p, 0, 1);
    const eased = 1.0 - std.math.pow(f64, 1.0 - p, 3.0);
    g.menu_anim = g.menu_from + (g.menu_target - g.menu_from) * eased;
    s.dirty = true;
    if (p >= 1.0) {
        g.menu_anim = g.menu_target;
        if (g.menu_target == 0 and g.launcher_open == false) {
            destroyOverlay();
        }
    }
}

fn sendWorkspace(ws: usize) void {
    if (g.target_name_len > 0) {
        sendCmd("CMD workspace {d} {s}\n", .{ ws, g.target_name[0..g.target_name_len] });
    } else {
        sendCmd("CMD workspace {d}\n", .{ws});
    }
}

fn sendCmd(comptime fmt: []const u8, args: anytype) void {
    if (g.ipc_fd < 0) return;
    var buf: [2048]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = c.send(g.ipc_fd, s.ptr, s.len, c.MSG_NOSIGNAL);
}

fn launchApp(app_index: usize) void {
    if (app_index >= g.app_list.count) return;
    var cmd_buf: [2048]u8 = undefined;
    const cmd = apps.buildCommand(&g.app_list, app_index, g.terminal[0..g.terminal_len], &cmd_buf);
    if (cmd.len == 0) return;
    var clean_buf: [2048]u8 = undefined;
    var n: usize = 0;
    for (cmd) |ch| {
        if (n + 1 >= clean_buf.len) break;
        clean_buf[n] = if (ch == '\n' or ch == '\r') ' ' else ch;
        n += 1;
    }
    sendCmd("CMD spawn {s}\n", .{clean_buf[0..n]});
    closeOverlay();
}

fn runPowerAction(index: usize) void {
    if (index >= m.POWER_ACTION_COUNT) return;
    logMsg("power action: {s}", .{m.power_labels[index]});
    if (index == 4) {
        sendCmd("CMD quit\n", .{});
    } else {
        const command = m.powerCommand(index);
        if (command.len > 0) sendCmd("CMD spawn {s}\n", .{command});
    }
    closeOverlay();
}

fn refreshOverlay() void {
    if (g.overlay) |s| s.dirty = true;
}

fn shiftCalendar(months: i32) void {
    m.shiftCalendar(months);
    refreshOverlay();
    logDebug("calendar month {d}-{d}", .{ g.calendar_year, g.calendar_month });
}

fn resetCalendar() void {
    m.resetCalendarToday();
    refreshOverlay();
    logDebug("calendar today {d}-{d}", .{ g.calendar_year, g.calendar_month });
}

fn movePowerSelection(delta: isize) void {
    const count: isize = m.POWER_ACTION_COUNT;
    var next = @as(isize, @intCast(g.power_selected)) + delta;
    while (next < 0) next += count;
    while (next >= count) next -= count;
    g.power_selected = @intCast(next);
    refreshOverlay();
}

fn activateOverlayHit(h: m.Hit) void {
    switch (h.kind) {
        .app => launchApp(h.value),
        .calendar_prev => shiftCalendar(-1),
        .calendar_next => shiftCalendar(1),
        .calendar_today => resetCalendar(),
        .power => runPowerAction(h.value),
        .clipboard_entry => clipboardSelect(h.value),
        .clipboard_clear => clipboardClear(),
        .media_prev => mediaCommand(3),
        .media_toggle => mediaCommand(1),
        .media_next => mediaCommand(2),
        .tray_entry => trayActivate(h.value, 1),
        .audio_down => audioCommand(2),
        .audio_mute => audioCommand(3),
        .audio_up => audioCommand(1),
        else => {},
    }
}

fn mediaCommand(code: u32) void {
    tessa_media_command(code);
    logDebug("media: command {d}", .{code});
}

fn clipboardPromote(index: usize) void {
    if (index == 0 or index >= g.clipboard_count) return;
    const saved = g.clipboard_entries[index];
    var i = index;
    while (i > 0) : (i -= 1) {
        g.clipboard_entries[i] = g.clipboard_entries[i - 1];
    }
    g.clipboard_entries[0] = saved;
}

fn clipboardAdd(text: []const u8) void {
    if (text.len == 0) return;
    var existing: ?usize = null;
    var i: usize = 0;
    while (i < g.clipboard_count) : (i += 1) {
        if (std.mem.eql(u8, g.clipboard_entries[i].text[0..g.clipboard_entries[i].len], text)) {
            existing = i;
            break;
        }
    }
    if (existing == 0) {
        g.clipboard_selected = 0;
        return;
    }
    if (existing) |idx| {
        clipboardPromote(idx);
    } else {
        if (g.clipboard_count < g.clipboard_entries.len) g.clipboard_count += 1;
        var j = g.clipboard_count - 1;
        while (j > 0) : (j -= 1) {
            g.clipboard_entries[j] = g.clipboard_entries[j - 1];
        }
        const entry = &g.clipboard_entries[0];
        entry.* = std.mem.zeroes(m.ClipboardEntry);
        m.copyTrunc(&entry.text, &entry.len, text);
    }
    g.clipboard_selected = 0;
    refreshOverlay();
    logDebug("clipboard: captured {d} bytes ({d} entries)", .{ text.len, g.clipboard_count });
}

fn clipboardSelect(index: usize) void {
    if (index >= g.clipboard_count) return;
    const entry = &g.clipboard_entries[index];
    m.copyTrunc(&g.clipboard_send_text, &g.clipboard_send_len, entry.text[0..entry.len]);
    if (g.data_control_device == null or g.data_control_manager == null) {
        logMsg("clipboard: data control device is unavailable", .{});
        closeOverlay();
        return;
    }
    if (g.clipboard_source) |old| {
        g.clipboard_source = null;
        c.zwlr_data_control_source_v1_destroy(old);
    }
    const source = c.zwlr_data_control_manager_v1_create_data_source(g.data_control_manager.?) orelse {
        logMsg("clipboard: cannot create data source", .{});
        closeOverlay();
        return;
    };
    g.clipboard_source_listener = std.mem.zeroes(c.zwlr_data_control_source_v1_listener);
    g.clipboard_source_listener.send = onClipboardSourceSend;
    g.clipboard_source_listener.cancelled = onClipboardSourceCancelled;
    _ = c.zwlr_data_control_source_v1_add_listener(source, &g.clipboard_source_listener, null);
    c.zwlr_data_control_source_v1_offer(source, "text/plain;charset=utf-8");
    c.zwlr_data_control_source_v1_offer(source, "UTF8_STRING");
    c.zwlr_data_control_source_v1_offer(source, "text/plain");
    c.zwlr_data_control_source_v1_offer(source, "TEXT");
    c.zwlr_data_control_source_v1_offer(source, "STRING");
    g.clipboard_source = source;
    c.zwlr_data_control_device_v1_set_selection(g.data_control_device.?, source);
    if (g.display) |display| _ = c.wl_display_flush(display);

    clipboardPromote(index);
    g.clipboard_selected = 0;
    logDebug("clipboard: selected entry {d}", .{index});
    closeOverlay();
}

fn clipboardClear() void {
    g.clipboard_count = 0;
    g.clipboard_selected = 0;
    refreshOverlay();
    logDebug("clipboard: history cleared", .{});
}

fn moveClipboardSelection(delta: isize) void {
    if (g.clipboard_count == 0) return;
    const count: isize = @intCast(g.clipboard_count);
    var next = @as(isize, @intCast(g.clipboard_selected)) + delta;
    while (next < 0) next += count;
    while (next >= count) next -= count;
    g.clipboard_selected = @intCast(next);
    refreshOverlay();
}

fn mimeRank(mime: []const u8) i32 {
    if (std.ascii.eqlIgnoreCase(mime, "text/plain;charset=utf-8")) return 5;
    if (std.ascii.eqlIgnoreCase(mime, "UTF8_STRING")) return 4;
    if (std.ascii.eqlIgnoreCase(mime, "text/plain")) return 3;
    if (std.ascii.eqlIgnoreCase(mime, "TEXT")) return 2;
    if (std.ascii.eqlIgnoreCase(mime, "STRING")) return 1;
    return 0;
}

fn addCustomApps() void {
    var i: usize = 0;
    while (i < g.custom_count) : (i += 1) {
        const app = &g.custom_apps[i];
        apps.addEntry(
            &g.app_list,
            app.name[0..app.name_len],
            app.exec[0..app.exec_len],
            app.comment[0..app.comment_len],
        );
    }
}

fn restartAudioService() void {
    tessa_audio_stop();
    g.audio_fd = -1;
    g.audio_ready = false;
    g.audio_len = 0;
    g.volume_percent = -1;
    g.volume_muted = false;
    g.volume_source_len = 0;
    g.volume_source[0] = 0;
    startAudioService();
    g.bar.dirty = true;
    if (g.overlay_mode == .audio) refreshOverlay();
}

fn reloadPanelConfig() void {
    const old_height = g.bar_height;
    const old_top = g.bar_top_margin;
    const old_side = g.bar_side_margin;
    var old_volume_status: [512]u8 = undefined;
    var old_volume_up: [512]u8 = undefined;
    var old_volume_down: [512]u8 = undefined;
    var old_volume_mute: [512]u8 = undefined;
    const old_status_len = g.volume_status_len;
    const old_up_len = g.volume_up_len;
    const old_down_len = g.volume_down_len;
    const old_mute_len = g.volume_mute_len;
    @memcpy(old_volume_status[0..old_status_len], g.volume_status[0..old_status_len]);
    @memcpy(old_volume_up[0..old_up_len], g.volume_up[0..old_up_len]);
    @memcpy(old_volume_down[0..old_down_len], g.volume_down[0..old_down_len]);
    @memcpy(old_volume_mute[0..old_mute_len], g.volume_mute[0..old_mute_len]);

    m.loadConfig();
    const volume_changed =
        old_status_len != g.volume_status_len or
        !std.mem.eql(u8, old_volume_status[0..old_status_len], g.volume_status[0..g.volume_status_len]) or
        old_up_len != g.volume_up_len or
        !std.mem.eql(u8, old_volume_up[0..old_up_len], g.volume_up[0..g.volume_up_len]) or
        old_down_len != g.volume_down_len or
        !std.mem.eql(u8, old_volume_down[0..old_down_len], g.volume_down[0..g.volume_down_len]) or
        old_mute_len != g.volume_mute_len or
        !std.mem.eql(u8, old_volume_mute[0..old_mute_len], g.volume_mute[0..g.volume_mute_len]);
    apps.scan(&g.app_list);
    addCustomApps();
    m.recomputeResults();
    if (volume_changed) restartAudioService();
    if (g.bar_height != old_height or g.bar_top_margin != old_top or
        g.bar_side_margin != old_side)
    {
        destroyBar();
        createBar();
    } else {
        g.bar.dirty = true;
    }
    if (g.bar_height != old_height or g.bar_top_margin != old_top or
        g.bar_side_margin != old_side)
    {
        destroyToasts();
        updateToastsSurface();
    }
    g.bg.dirty = true;
    if (g.overlay) |ov| ov.dirty = true;
    logMsg("config reloaded ({d} launcher entries)", .{g.app_list.count});
}

fn launchSelected() void {
    if (g.result_count == 0) return;
    if (g.selected >= g.result_count) return;
    launchApp(g.results[g.selected]);
}

fn ensureSelectionVisible() void {
    const visible: usize = 7;
    if (g.result_count == 0) {
        g.selected = 0;
        g.scroll = 0;
        return;
    }
    if (g.selected >= g.result_count) g.selected = g.result_count - 1;
    if (g.selected < g.scroll) g.scroll = g.selected;
    if (g.selected >= g.scroll + visible) g.scroll = g.selected - (visible - 1);
    const max_scroll = if (g.result_count > visible) g.result_count - visible else 0;
    if (g.scroll > max_scroll) g.scroll = max_scroll;
}

fn appendQueryUtf8(data: []const u8) void {
    for (data) |ch| {
        if (ch < 0x20) return;
    }
    if (g.query_len + data.len >= g.query.len) return;
    @memcpy(g.query[g.query_len .. g.query_len + data.len], data);
    g.query_len += data.len;
    g.query[g.query_len] = 0;
    g.selected = 0;
    g.scroll = 0;
    m.recomputeResults();
    if (g.overlay) |s| s.dirty = true;
    syncTextInput(c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER);
    g.next_blink_ms = m.nowMs() + 500;
}

fn backspaceQuery() void {
    if (g.query_len == 0) return;
    var n = g.query_len - 1;
    while (n > 0 and (g.query[n] & 0xC0) == 0x80) n -= 1;
    g.query_len = n;
    g.query[g.query_len] = 0;
    g.selected = 0;
    g.scroll = 0;
    m.recomputeResults();
    if (g.overlay) |s| s.dirty = true;
    syncTextInput(c.ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER);
    g.next_blink_ms = m.nowMs() + 500;
}

fn onKeyboardKeymap(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, format: u32, fd: c_int, size: u32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    logDebug("keymap format={d} size={d}", .{ format, size });
    defer _ = c.close(fd);
    if (format != 1 or size == 0) return;
    const map = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (map == null or @intFromPtr(map.?) == std.math.maxInt(usize)) return;
    defer _ = c.munmap(map, size);

    const ctx = g.xkb_ctx orelse return;
    const keymap = c.xkb_keymap_new_from_buffer(
        ctx,
        @ptrCast(map.?),
        size,
        c.XKB_KEYMAP_FORMAT_TEXT_V1,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    ) orelse return;
    const state = c.xkb_state_new(keymap) orelse {
        c.xkb_keymap_unref(keymap);
        return;
    };

    if (g.xkb_state) |old| c.xkb_state_unref(old);
    if (g.xkb_keymap) |old| c.xkb_keymap_unref(old);
    g.xkb_keymap = keymap;
    g.xkb_state = state;
}

fn onKeyboardEnter(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface, keys: ?*c.wl_array) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = surface;
    _ = keys;
}

fn onKeyboardLeave(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = surface;
}

fn onKeyboardModifiers(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, depressed: u32, latched: u32, locked: u32, group: u32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = group;
    if (g.xkb_state) |state| {
        _ = c.xkb_state_update_mask(state, depressed, latched, locked, 0, 0, 0);
    }
}

fn onKeyboardKey(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, serial: u32, time: u32, key: u32, state: u32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = time;
    if (state == 1 and g.overlay != null) logDebug("panel key {d} xkb={}", .{ key, g.xkb_state != null });
    if (state != 1 or g.overlay == null) return;
    const xstate = g.xkb_state orelse return;
    const keycode: c.xkb_keycode_t = key + 8;
    const sym = c.xkb_state_key_get_one_sym(xstate, keycode);
    logDebug("panel keysym {d}", .{sym});

    if (g.overlay_mode == .power) {
        if (sym == c.XKB_KEY_Escape) {
            closeOverlay();
        } else if (sym == c.XKB_KEY_Up) {
            movePowerSelection(-1);
        } else if (sym == c.XKB_KEY_Down) {
            movePowerSelection(1);
        } else if (sym == c.XKB_KEY_Home) {
            g.power_selected = 0;
            refreshOverlay();
        } else if (sym == c.XKB_KEY_End) {
            g.power_selected = m.POWER_ACTION_COUNT - 1;
            refreshOverlay();
        } else if (sym == c.XKB_KEY_Return or sym == c.XKB_KEY_KP_Enter) {
            runPowerAction(g.power_selected);
        }
        return;
    }

    if (g.overlay_mode == .calendar) {
        if (sym == c.XKB_KEY_Escape) {
            closeOverlay();
        } else if (sym == c.XKB_KEY_Left or sym == c.XKB_KEY_Page_Up) {
            shiftCalendar(-1);
        } else if (sym == c.XKB_KEY_Right or sym == c.XKB_KEY_Page_Down) {
            shiftCalendar(1);
        } else if (sym == c.XKB_KEY_Home or sym == c.XKB_KEY_t) {
            resetCalendar();
        }
        return;
    }

    if (g.overlay_mode == .screenshot) {
        if (sym == c.XKB_KEY_Escape) {
            cancelScreenshot();
        } else if (sym == c.XKB_KEY_Return or sym == c.XKB_KEY_KP_Enter) {
            saveFullScreenshot();
        }
        return;
    }

    if (g.overlay_mode == .media) {
        if (sym == c.XKB_KEY_Escape) {
            closeOverlay();
        } else if (sym == c.XKB_KEY_space) {
            mediaCommand(1);
        } else if (sym == c.XKB_KEY_Left) {
            mediaCommand(3);
        } else if (sym == c.XKB_KEY_Right) {
            mediaCommand(2);
        }
        return;
    }

    if (g.overlay_mode == .clipboard) {
        if (sym == c.XKB_KEY_Escape) {
            closeOverlay();
        } else if (sym == c.XKB_KEY_Up) {
            moveClipboardSelection(-1);
        } else if (sym == c.XKB_KEY_Down) {
            moveClipboardSelection(1);
        } else if (sym == c.XKB_KEY_Home) {
            g.clipboard_selected = 0;
            refreshOverlay();
        } else if (sym == c.XKB_KEY_End) {
            if (g.clipboard_count > 0) g.clipboard_selected = g.clipboard_count - 1;
            refreshOverlay();
        } else if (sym == c.XKB_KEY_Return or sym == c.XKB_KEY_KP_Enter) {
            clipboardSelect(g.clipboard_selected);
        }
        return;
    }

    if (g.overlay_mode == .tray) {
        if (sym == c.XKB_KEY_Escape) {
            closeOverlay();
        } else if (sym == c.XKB_KEY_Up) {
            moveTraySelection(-1);
        } else if (sym == c.XKB_KEY_Down) {
            moveTraySelection(1);
        } else if (sym == c.XKB_KEY_Home) {
            g.tray_selected = 0;
            refreshOverlay();
        } else if (sym == c.XKB_KEY_End) {
            if (g.tray_count > 0) g.tray_selected = g.tray_count - 1;
            refreshOverlay();
        } else if (sym == c.XKB_KEY_Return or sym == c.XKB_KEY_KP_Enter) {
            activateTraySelection();
        }
        return;
    }

    if (g.overlay_mode == .audio) {
        if (sym == c.XKB_KEY_Escape) {
            closeOverlay();
        } else if (sym == c.XKB_KEY_Up or sym == c.XKB_KEY_Right or sym == c.XKB_KEY_Page_Up) {
            audioCommand(1);
        } else if (sym == c.XKB_KEY_Down or sym == c.XKB_KEY_Left or sym == c.XKB_KEY_Page_Down) {
            audioCommand(2);
        } else if (sym == c.XKB_KEY_m) {
            audioCommand(3);
        }
        return;
    }

    if (!g.launcher_open) return;
    if (sym == c.XKB_KEY_Escape) {
        closeOverlay();
        return;
    }
    if (sym == c.XKB_KEY_Return or sym == c.XKB_KEY_KP_Enter) {
        launchSelected();
        return;
    }
    if (sym == c.XKB_KEY_BackSpace) {
        backspaceQuery();
        return;
    }
    if (sym == c.XKB_KEY_Up) {
        if (g.result_count > 0) {
            g.selected = if (g.selected == 0) g.result_count - 1 else g.selected - 1;
            ensureSelectionVisible();
            if (g.overlay) |s| s.dirty = true;
        }
        return;
    }
    if (sym == c.XKB_KEY_Down or sym == c.XKB_KEY_Tab) {
        if (g.result_count > 0) {
            g.selected = (g.selected + 1) % g.result_count;
            ensureSelectionVisible();
            if (g.overlay) |s| s.dirty = true;
        }
        return;
    }
    if (sym == 0xfe20) { // ISO_Left_Tab
        if (g.result_count > 0) {
            g.selected = if (g.selected == 0) g.result_count - 1 else g.selected - 1;
            ensureSelectionVisible();
            if (g.overlay) |s| s.dirty = true;
        }
        return;
    }
    if (sym == c.XKB_KEY_Page_Down) {
        if (g.result_count > 0) {
            g.selected = @min(g.selected + 7, g.result_count - 1);
            ensureSelectionVisible();
            if (g.overlay) |s| s.dirty = true;
        }
        return;
    }
    if (sym == c.XKB_KEY_Page_Up) {
        g.selected = g.selected -| 7;
        ensureSelectionVisible();
        if (g.overlay) |s| s.dirty = true;
        return;
    }
    if (sym == c.XKB_KEY_Home) {
        g.selected = 0;
        ensureSelectionVisible();
        if (g.overlay) |s| s.dirty = true;
        return;
    }
    if (sym == c.XKB_KEY_End) {
        if (g.result_count > 0) g.selected = g.result_count - 1;
        ensureSelectionVisible();
        if (g.overlay) |s| s.dirty = true;
        return;
    }

    const state_eff = c.XKB_STATE_MODS_EFFECTIVE;
    if (c.xkb_state_mod_name_is_active(xstate, "Control", state_eff) != 0 or
        c.xkb_state_mod_name_is_active(xstate, "Mod1", state_eff) != 0 or
        c.xkb_state_mod_name_is_active(xstate, "Mod4", state_eff) != 0)
    {
        return;
    }

    var buf: [32]u8 = undefined;
    const n = c.xkb_state_key_get_utf8(xstate, keycode, &buf, buf.len);
    if (n > 0) {
        appendQueryUtf8(buf[0..@intCast(n)]);
    }
}

fn onDataControlFinished(data: ?*anyopaque, device: ?*c.zwlr_data_control_device_v1) callconv(.c) void {
    _ = data;
    _ = device;
    logDebug("clipboard: data control finished", .{});
}

const ScreenshotSelection = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
};

fn freeScreenshot() void {
    if (g.screenshot_frame) |frame| {
        c.zwlr_screencopy_frame_v1_destroy(frame);
        g.screenshot_frame = null;
    }
    if (g.screenshot_buffer) |buffer| {
        c.wl_buffer_destroy(buffer);
        g.screenshot_buffer = null;
    }
    if (g.screenshot_data) |data| {
        if (g.screenshot_size > 0) _ = c.munmap(data, g.screenshot_size);
        g.screenshot_data = null;
    }
    g.screenshot_size = 0;
    g.screenshot_width = 0;
    g.screenshot_height = 0;
    g.screenshot_stride = 0;
    g.screenshot_format = 0;
    g.screenshot_pending = false;
    g.screenshot_ready = false;
    g.screenshot_dragging = false;
    g.screenshot_start_x = 0;
    g.screenshot_start_y = 0;
    g.screenshot_end_x = 0;
    g.screenshot_end_y = 0;
}

fn screenshotEnsureDir(path: []const u8) bool {
    if (path.len == 0 or path.len >= 512) return false;
    var buf: [512:0]u8 = undefined;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (buf[i] == '/') {
            buf[i] = 0;
            _ = c.mkdir(&buf, 0o755);
            buf[i] = '/';
        }
    }
    _ = c.mkdir(&buf, 0o755);
    return true;
}

fn screenshotDirectory(dest: []u8) []const u8 {
    const configured = g.screenshot_dir[0..g.screenshot_dir_len];
    if (std.mem.startsWith(u8, configured, "~/")) {
        if (c.getenv("HOME")) |home| {
            return std.fmt.bufPrint(dest, "{s}/{s}", .{
                std.mem.span(home),
                configured[2..],
            }) catch configured;
        }
    }
    return configured;
}

fn screenshotPath(dest: *[1024]u8) ?[]const u8 {
    var dir_buf: [512]u8 = undefined;
    const dir = screenshotDirectory(&dir_buf);
    if (dir.len == 0 or !screenshotEnsureDir(dir)) {
        logMsg("screenshot: cannot create the screenshot directory", .{});
        return null;
    }

    var t: c.time_t = c.time(null);
    var tm: c.tm = undefined;
    _ = c.localtime_r(&t, &tm);
    var stamp: [32]u8 = [_]u8{0} ** 32;
    _ = c.strftime(&stamp, stamp.len, "%Y%m%d-%H%M%S", &tm);
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_REALTIME, &ts);
    const ms = @divTrunc(@as(i64, ts.tv_nsec), 1_000_000);
    return std.fmt.bufPrint(dest, "{s}/tessa-{s}-{d}.png", .{
        dir,
        std.mem.sliceTo(&stamp, 0),
        ms,
    }) catch null;
}

fn screenshotSelection() ScreenshotSelection {
    const ov = g.overlay orelse return .{ .x = 0, .y = 0, .w = 1, .h = 1 };
    const W: f64 = @floatFromInt(ov.width);
    const H: f64 = @floatFromInt(ov.height);
    const sx = std.math.clamp(@min(g.screenshot_start_x, g.screenshot_end_x), 0, W);
    const sy = std.math.clamp(@min(g.screenshot_start_y, g.screenshot_end_y), 0, H);
    const ex = std.math.clamp(@max(g.screenshot_start_x, g.screenshot_end_x), 0, W);
    const ey = std.math.clamp(@max(g.screenshot_start_y, g.screenshot_end_y), 0, H);
    return .{ .x = sx, .y = sy, .w = ex - sx, .h = ey - sy };
}

fn saveScreenshot(sel: ScreenshotSelection) void {
    if (!g.screenshot_ready or g.screenshot_data == null) return;
    const scale: f64 = @floatFromInt(@max(1, g.scale));
    const origin_x: f64 = sel.x * scale;
    const origin_y: f64 = sel.y * scale;
    const pixel_w: i32 = @max(1, @as(i32, @intFromFloat(@round(sel.w * scale))));
    const pixel_h: i32 = @max(1, @as(i32, @intFromFloat(@round(sel.h * scale))));
    var crop_x: i32 = @intFromFloat(@round(origin_x));
    var crop_y: i32 = @intFromFloat(@round(origin_y));
    const image_w: i32 = @intCast(g.screenshot_width);
    const image_h: i32 = @intCast(g.screenshot_height);
    crop_x = std.math.clamp(crop_x, 0, @max(0, image_w - 1));
    crop_y = std.math.clamp(crop_y, 0, @max(0, image_h - 1));
    const crop_w = @min(pixel_w, image_w - crop_x);
    const crop_h = @min(pixel_h, image_h - crop_y);
    if (crop_w <= 0 or crop_h <= 0) return;

    const cairo_format: c.cairo_format_t = if (g.screenshot_format == c.WL_SHM_FORMAT_XRGB8888)
        c.CAIRO_FORMAT_RGB24
    else
        c.CAIRO_FORMAT_ARGB32;
    const full = c.cairo_image_surface_create_for_data(
        @ptrCast(g.screenshot_data.?),
        cairo_format,
        image_w,
        image_h,
        @intCast(g.screenshot_stride),
    ) orelse {
        logMsg("screenshot: cannot wrap the captured buffer", .{});
        freeScreenshot();
        closeOverlay();
        return;
    };
    const cropped = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, crop_w, crop_h) orelse {
        c.cairo_surface_destroy(full);
        logMsg("screenshot: cannot allocate the output image", .{});
        freeScreenshot();
        closeOverlay();
        return;
    };
    const cr = c.cairo_create(cropped) orelse {
        c.cairo_surface_destroy(cropped);
        c.cairo_surface_destroy(full);
        logMsg("screenshot: cannot create the output context", .{});
        freeScreenshot();
        closeOverlay();
        return;
    };
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_surface(cr, full, -@as(f64, @floatFromInt(crop_x)), -@as(f64, @floatFromInt(crop_y)));
    c.cairo_paint(cr);
    c.cairo_destroy(cr);

    var path_buf: [1024]u8 = undefined;
    const path = screenshotPath(&path_buf);
    if (path) |p| {
        var zpath: [1024:0]u8 = undefined;
        if (p.len < zpath.len) {
            @memcpy(zpath[0..p.len], p);
            zpath[p.len] = 0;
            const status = c.cairo_surface_write_to_png(cropped, &zpath);
            if (status == c.CAIRO_STATUS_SUCCESS) {
                logMsg("screenshot: saved {s} ({d}x{d})", .{ p, crop_w, crop_h });
            } else {
                logMsg("screenshot: PNG write failed ({d})", .{status});
            }
        } else {
            logMsg("screenshot: output path is too long", .{});
        }
    }
    c.cairo_surface_destroy(cropped);
    c.cairo_surface_destroy(full);
    freeScreenshot();
    closeOverlay();
}

fn saveFullScreenshot() void {
    const ov = g.overlay orelse return;
    saveScreenshot(.{
        .x = 0,
        .y = 0,
        .w = @floatFromInt(ov.width),
        .h = @floatFromInt(ov.height),
    });
}

fn saveSelectedScreenshot() void {
    var sel = screenshotSelection();
    if (sel.w < 8 or sel.h < 8) {
        const ov = g.overlay orelse return;
        sel = .{
            .x = 0,
            .y = 0,
            .w = @floatFromInt(ov.width),
            .h = @floatFromInt(ov.height),
        };
    }
    saveScreenshot(sel);
}

fn cancelScreenshot() void {
    logDebug("screenshot: cancelled", .{});
    freeScreenshot();
    closeOverlay();
}

fn beginScreenshotOverlay() void {
    if (g.overlay != null) {
        logDebug("screenshot: overlay is already open", .{});
        freeScreenshot();
        return;
    }
    if (!ensureOverlay()) {
        freeScreenshot();
        return;
    }
    g.screenshot_dragging = false;
    g.screenshot_start_x = 0;
    g.screenshot_start_y = 0;
    g.screenshot_end_x = 0;
    g.screenshot_end_y = 0;
    beginOverlay(.screenshot);
    logDebug("screenshot: capture ready {d}x{d}", .{ g.screenshot_width, g.screenshot_height });
}

fn onScreenshotBuffer(data: ?*anyopaque, frame: ?*c.zwlr_screencopy_frame_v1, format: u32, width: u32, height: u32, stride: u32) callconv(.c) void {
    _ = data;
    if (frame == null or g.screenshot_buffer != null) return;
    if (width == 0 or height == 0 or stride == 0) return;
    const shm = g.shm orelse return;
    const size: usize = @as(usize, stride) * @as(usize, height);
    const fd = c.memfd_create("tessa-screenshot", c.MFD_CLOEXEC);
    if (fd < 0) {
        onScreenshotFailed(null, frame);
        return;
    }
    if (c.ftruncate(fd, @intCast(size)) < 0) {
        _ = c.close(fd);
        onScreenshotFailed(null, frame);
        return;
    }
    const map = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
    if (map == null or @intFromPtr(map.?) == std.math.maxInt(usize)) {
        _ = c.close(fd);
        onScreenshotFailed(null, frame);
        return;
    }
    const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
    _ = c.close(fd);
    if (pool == null) {
        _ = c.munmap(map, size);
        onScreenshotFailed(null, frame);
        return;
    }
    const buffer = c.wl_shm_pool_create_buffer(
        pool,
        0,
        @intCast(width),
        @intCast(height),
        @intCast(stride),
        @intCast(format),
    );
    c.wl_shm_pool_destroy(pool);
    if (buffer == null) {
        _ = c.munmap(map, size);
        onScreenshotFailed(null, frame);
        return;
    }

    g.screenshot_buffer = buffer;
    g.screenshot_data = map;
    g.screenshot_size = size;
    g.screenshot_width = width;
    g.screenshot_height = height;
    g.screenshot_stride = stride;
    g.screenshot_format = format;
    c.zwlr_screencopy_frame_v1_copy(frame.?, buffer.?);
}

fn onScreenshotFlags(data: ?*anyopaque, frame: ?*c.zwlr_screencopy_frame_v1, flags: u32) callconv(.c) void {
    _ = data;
    _ = frame;
    _ = flags;
}

fn onScreenshotReady(data: ?*anyopaque, frame: ?*c.zwlr_screencopy_frame_v1, tv_sec_hi: u32, tv_sec_lo: u32, tv_nsec: u32) callconv(.c) void {
    _ = data;
    _ = tv_sec_hi;
    _ = tv_sec_lo;
    _ = tv_nsec;
    if (frame) |value| c.zwlr_screencopy_frame_v1_destroy(value);
    g.screenshot_frame = null;
    g.screenshot_pending = false;
    if (g.screenshot_data == null or g.screenshot_buffer == null) {
        onScreenshotFailed(null, null);
        return;
    }
    g.screenshot_ready = true;
    beginScreenshotOverlay();
}

fn onScreenshotFailed(data: ?*anyopaque, frame: ?*c.zwlr_screencopy_frame_v1) callconv(.c) void {
    _ = data;
    if (frame) |value| c.zwlr_screencopy_frame_v1_destroy(value);
    if (g.screenshot_frame == frame) g.screenshot_frame = null;
    logMsg("screenshot: screen capture failed", .{});
    freeScreenshot();
}

fn openScreenshot() void {
    if (g.overlay != null) {
        logMsg("screenshot: close the current overlay first", .{});
        return;
    }
    if (g.screenshot_pending or g.screenshot_ready) freeScreenshot();
    const manager = g.screenshot_manager orelse {
        logMsg("screenshot: screencopy is unavailable", .{});
        return;
    };
    const output = g.target_output orelse {
        logMsg("screenshot: no target output", .{});
        return;
    };
    const frame = c.zwlr_screencopy_manager_v1_capture_output(manager, 0, output) orelse {
        logMsg("screenshot: cannot create a screencopy frame", .{});
        return;
    };
    g.screenshot_frame = frame;
    g.screenshot_pending = true;
    g.screenshot_frame_listener = std.mem.zeroes(c.zwlr_screencopy_frame_v1_listener);
    g.screenshot_frame_listener.buffer = onScreenshotBuffer;
    g.screenshot_frame_listener.flags = onScreenshotFlags;
    g.screenshot_frame_listener.ready = onScreenshotReady;
    g.screenshot_frame_listener.failed = onScreenshotFailed;
    _ = c.zwlr_screencopy_frame_v1_add_listener(frame, &g.screenshot_frame_listener, null);
    logDebug("screenshot: capturing output", .{});
}

const TOAST_WIDTH: i32 = 380;
const TOAST_GAP: i32 = 8;

fn toastSurfaceHeight() i32 {
    if (g.notification_count == 0) return 0;
    var height: i32 = 0;
    var i: usize = 0;
    while (i < g.notification_count) : (i += 1) {
        height += m.toastHeight(&g.notifications[i]);
    }
    const count: i32 = @intCast(g.notification_count);
    return height + (count - 1) * TOAST_GAP;
}

fn outputInfoFor(wl: ?*c.wl_output) ?*m.OutputInfo {
    if (wl == null) return null;
    var i: usize = 0;
    while (i < g.output_count) : (i += 1) {
        if (g.outputs[i].wl == wl) return &g.outputs[i];
    }
    return null;
}

fn focusedOutputInfo() ?*m.OutputInfo {
    if (g.focused_output_name_len > 0) {
        var i: usize = 0;
        while (i < g.output_count) : (i += 1) {
            const info = &g.outputs[i];
            if (info.name_len == g.focused_output_name_len and
                std.mem.eql(u8, info.name[0..info.name_len], g.focused_output_name[0..g.focused_output_name_len]))
            {
                return info;
            }
        }
    }
    return outputInfoFor(g.target_output);
}

fn destroyToasts() void {
    const s = g.toasts orelse return;
    g.toasts = null;
    g.toasts_output_len = 0;
    g.toasts_output[0] = 0;
    if (g.pointer_surface == s) g.pointer_surface = null;
    draw.destroyBuffers(s);
    if (s.layer) |layer| c.zwlr_layer_surface_v1_destroy(layer);
    if (s.wl) |wl| c.wl_surface_destroy(wl);
    c.free(s);
    g.toast_hit_count = 0;
    g.toast_action_hit_count = 0;
}

fn updateToastsSurface() void {
    if (g.notification_count == 0) {
        destroyToasts();
        return;
    }
    const height = toastSurfaceHeight();
    const focused = focusedOutputInfo();
    const out_name = if (focused) |info| info.name[0..info.name_len] else g.target_name[0..g.target_name_len];
    if (g.toasts) |s| {
        const same_output = g.toasts_output_len == out_name.len and
            std.mem.eql(u8, g.toasts_output[0..g.toasts_output_len], out_name);
        if (!same_output) {
            destroyToasts();
        } else {
            if (s.layer) |layer| {
                c.zwlr_layer_surface_v1_set_size(layer, @intCast(TOAST_WIDTH), @intCast(height));
            }
            if (s.wl) |wl| c.wl_surface_commit(wl);
            s.dirty = true;
            return;
        }
    }

    const s = @as(*m.Surface, @ptrCast(@alignCast(c.calloc(1, @sizeOf(m.Surface)).?)));
    s.* = std.mem.zeroes(m.Surface);
    const top = g.bar_top_margin + g.bar_height + 8;
    if (!createLayerSurface(
        s,
        if (focused) |info| info.wl else g.target_output,
        .toasts,
        @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP),
        @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT),
        @intCast(TOAST_WIDTH),
        @intCast(height),
        top,
        g.bar_side_margin,
        0,
        0,
        0,
        0,
        "tessa-notifications",
    )) {
        c.free(s);
        return;
    }
    if (focused) |info| draw.setSurfaceScale(s, info.scale);
    g.toasts = s;
    m.copyTrunc(&g.toasts_output, &g.toasts_output_len, out_name);
    logDebug("notifications: toast surface {d}x{d} output={s}", .{
        TOAST_WIDTH,
        height,
        g.toasts_output[0..g.toasts_output_len],
    });
}

fn freeNotificationIcon(n: *m.NotificationEntry) void {
    if (n.icon_surface) |surf| {
        c.cairo_surface_destroy(surf);
        n.icon_surface = null;
    }
}

fn notificationRemoveAt(index: usize, notify_service: bool, reason: u32) void {
    if (index >= g.notification_count) return;
    const id = g.notifications[index].id;
    freeNotificationIcon(&g.notifications[index]);
    var i = index;
    while (i + 1 < g.notification_count) : (i += 1) {
        g.notifications[i] = g.notifications[i + 1];
    }
    g.notification_count -= 1;
    updateToastsSurface();
    if (notify_service) tessa_notifications_close(id, reason);
    logDebug("notification: removed id={d} total={d}", .{ id, g.notification_count });
}

fn notificationFind(id: u32) ?usize {
    var i: usize = 0;
    while (i < g.notification_count) : (i += 1) {
        if (g.notifications[i].id == id) return i;
    }
    return null;
}

fn notificationDismiss(id: u32) void {
    if (notificationFind(id)) |index| {
        notificationRemoveAt(index, true, 2);
    }
}

fn notificationDefaultAction(n: *const m.NotificationEntry) ?usize {
    var i: usize = 0;
    while (i < n.action_count and i < n.actions.len) : (i += 1) {
        const action = &n.actions[i];
        if (action.key_len > 0 and
            std.mem.eql(u8, action.key[0..action.key_len], "default")) return i;
    }
    return null;
}

fn notificationAction(index: usize, action_index: usize) void {
    if (index >= g.notification_count) return;
    const n = &g.notifications[index];
    if (action_index >= n.action_count) return;
    const action = &n.actions[action_index];
    if (action.key_len > 0) {
        tessa_notifications_action(n.id, action.key[0..action.key_len :0].ptr);
    }
    notificationRemoveAt(index, false, 0);
}

fn notificationActionByKey(id: u32, key: []const u8) void {
    const index = notificationFind(id) orelse return;
    const n = &g.notifications[index];
    var i: usize = 0;
    while (i < n.action_count and i < n.actions.len) : (i += 1) {
        const action = &n.actions[i];
        if (action.key_len == key.len and
            std.mem.eql(u8, action.key[0..action.key_len], key))
        {
            notificationAction(index, i);
            return;
        }
    }
}

fn notificationDefaultOrDismiss(index: usize) void {
    if (index >= g.notification_count) return;
    const n = &g.notifications[index];
    if (notificationDefaultAction(n)) |action_index| {
        notificationAction(index, action_index);
    } else {
        notificationRemoveAt(index, true, 2);
    }
}

fn clearNotifications() void {
    while (g.notification_count > 0) {
        notificationRemoveAt(g.notification_count - 1, false, 0);
    }
}

fn notificationAdd(
    id: u32,
    replaces_id: u32,
    timeout: i32,
    app: []const u8,
    summary: []const u8,
    body: []const u8,
    actions: []const m.NotificationAction,
    icon_name: []const u8,
    icon_data: []const u8,
    icon_w: u32,
    icon_h: u32,
) void {
    _ = replaces_id;
    var entry = std.mem.zeroes(m.NotificationEntry);
    entry.id = id;
    m.copyTrunc(&entry.app, &entry.app_len, app);
    m.copyTrunc(&entry.summary, &entry.summary_len, summary);
    m.copyTrunc(&entry.body, &entry.body_len, body);
    entry.action_count = @min(actions.len, entry.actions.len);
    var ai: usize = 0;
    while (ai < entry.action_count) : (ai += 1) {
        const src = &actions[ai];
        const dst = &entry.actions[ai];
        m.copyTrunc(&dst.key, &dst.key_len, src.key[0..src.key_len]);
        m.copyTrunc(&dst.label, &dst.label_len, src.label[0..src.label_len]);
    }
    if (icon_w > 0 and icon_h > 0 and
        icon_data.len == @as(usize, icon_w) * @as(usize, icon_h) * 4 and
        icon_data.len <= m.MAX_NOTIFICATION_ICON_BYTES)
    {
        @memcpy(entry.icon_data[0..icon_data.len], icon_data);
        entry.icon_w = icon_w;
        entry.icon_h = icon_h;
        entry.icon_len = icon_data.len;
    } else if (icon_name.len > 0) {
        entry.icon_surface = loadNotificationIcon(icon_name);
    }
    const effective: i64 = if (timeout == 0)
        0
    else if (timeout < 0)
        5000
    else
        @min(@as(i64, timeout), 60000);
    entry.expire_ms = if (effective == 0) 0 else m.nowMs() + @max(@as(i64, 1000), effective);

    if (notificationFind(id)) |existing| {
        freeNotificationIcon(&g.notifications[existing]);
        var i = existing;
        while (i > 0) : (i -= 1) {
            g.notifications[i] = g.notifications[i - 1];
        }
        g.notifications[0] = entry;
    } else {
        if (g.notification_count >= m.MAX_NOTIFICATIONS) {
            notificationRemoveAt(g.notification_count - 1, true, 4);
        }
        if (g.notification_count < m.MAX_NOTIFICATIONS) g.notification_count += 1;
        var i = g.notification_count - 1;
        while (i > 0) : (i -= 1) {
            g.notifications[i] = g.notifications[i - 1];
        }
        g.notifications[0] = entry;
    }
    updateToastsSurface();
    logDebug("notification: added id={d} total={d} actions={d} icon={d}x{d}", .{
        id,
        g.notification_count,
        entry.action_count,
        entry.icon_w,
        entry.icon_h,
    });
}

fn expireNotifications(now: i64) void {
    var i: usize = 0;
    while (i < g.notification_count) {
        if (g.notifications[i].expire_ms > 0 and now >= g.notifications[i].expire_ms) {
            notificationRemoveAt(i, true, 1);
        } else {
            i += 1;
        }
    }
}

fn readU32(bytes: []const u8, offset: usize) u32 {
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn notificationShift(count: usize) void {
    if (count >= g.notification_len) {
        g.notification_len = 0;
        return;
    }
    const remain = g.notification_len - count;
    std.mem.copyForwards(u8, g.notification_buf[0..remain], g.notification_buf[count..g.notification_len]);
    g.notification_len = remain;
}

fn processNotificationMessages() void {
    while (g.notification_len > 0) {
        const kind = g.notification_buf[0];
        if (kind == 1) {
            if (g.notification_len < 48) return;
            const id = readU32(&g.notification_buf, 4);
            const replaces = readU32(&g.notification_buf, 8);
            const timeout_bits = readU32(&g.notification_buf, 12);
            const timeout: i32 = @bitCast(timeout_bits);
            const app_len: usize = @intCast(readU32(&g.notification_buf, 16));
            const summary_len: usize = @intCast(readU32(&g.notification_buf, 20));
            const body_len: usize = @intCast(readU32(&g.notification_buf, 24));
            const action_count: usize = @intCast(readU32(&g.notification_buf, 28));
            const icon_name_len: usize = @intCast(readU32(&g.notification_buf, 32));
            const icon_w = readU32(&g.notification_buf, 36);
            const icon_h = readU32(&g.notification_buf, 40);
            const icon_len: usize = @intCast(readU32(&g.notification_buf, 44));
            var total = 48 + app_len + summary_len + body_len + icon_name_len + icon_len;
            if (total > g.notification_buf.len) {
                logMsg("notification: oversized message", .{});
                g.notification_len = 0;
                return;
            }
            if (g.notification_len < total) return;
            const app = g.notification_buf[48 .. 48 + app_len];
            const summary = g.notification_buf[48 + app_len .. 48 + app_len + summary_len];
            const body_start = 48 + app_len + summary_len;
            const body = g.notification_buf[body_start .. body_start + body_len];
            const icon_name_start = body_start + body_len;
            const icon_name = g.notification_buf[icon_name_start .. icon_name_start + icon_name_len];
            const icon_start = icon_name_start + icon_name_len;
            const icon_data = g.notification_buf[icon_start .. icon_start + icon_len];

            var actions: [m.MAX_NOTIFICATION_ACTIONS]m.NotificationAction = undefined;
            const action_total = @min(action_count, actions.len);
            var action_parsed: usize = 0;
            var off = total;
            while (action_parsed < action_total) : (action_parsed += 1) {
                if (off + 8 > g.notification_buf.len) {
                    logMsg("notification: truncated actions", .{});
                    g.notification_len = 0;
                    return;
                }
                const key_len: usize = @intCast(readU32(&g.notification_buf, off));
                const label_len: usize = @intCast(readU32(&g.notification_buf, off + 4));
                if (key_len >= actions[action_parsed].key.len or
                    label_len >= actions[action_parsed].label.len or
                    off + 8 + key_len + label_len > g.notification_buf.len)
                {
                    logMsg("notification: malformed action", .{});
                    g.notification_len = 0;
                    return;
                }
                actions[action_parsed] = std.mem.zeroes(m.NotificationAction);
                @memcpy(actions[action_parsed].key[0..key_len], g.notification_buf[off + 8 .. off + 8 + key_len]);
                actions[action_parsed].key[key_len] = 0;
                actions[action_parsed].key_len = key_len;
                @memcpy(actions[action_parsed].label[0..label_len], g.notification_buf[off + 8 + key_len .. off + 8 + key_len + label_len]);
                actions[action_parsed].label[label_len] = 0;
                actions[action_parsed].label_len = label_len;
                off += 8 + key_len + label_len;
            }
            if (off > total) total = off;
            if (g.notification_len < total) return;

            notificationAdd(
                id,
                replaces,
                timeout,
                app,
                summary,
                body,
                actions[0..action_parsed],
                icon_name,
                icon_data,
                icon_w,
                icon_h,
            );
            notificationShift(total);
        } else if (kind == 2) {
            if (g.notification_len < 5) return;
            const id = readU32(&g.notification_buf, 1);
            if (notificationFind(id)) |index| notificationRemoveAt(index, false, 0);
            notificationShift(5);
        } else if (kind == 3) {
            g.notification_service_ready = true;
            logMsg("notifications: service ready", .{});
            notificationShift(1);
        } else if (kind == 4) {
            if (g.notification_len < 5) return;
            const len: usize = @intCast(readU32(&g.notification_buf, 1));
            if (g.notification_len < 5 + len) return;
            logMsg("notifications: {s}", .{g.notification_buf[5 .. 5 + len]});
            notificationShift(5 + len);
        } else {
            logMsg("notification: unknown event type {d}", .{kind});
            g.notification_len = 0;
            return;
        }
    }
}

fn readNotifications() void {
    if (g.notification_fd < 0) return;
    if (g.notification_len >= g.notification_buf.len) g.notification_len = 0;
    const n = c.read(
        g.notification_fd,
        g.notification_buf[g.notification_len..].ptr,
        g.notification_buf.len - g.notification_len,
    );
    if (n <= 0) {
        logMsg("notifications: service disconnected", .{});
        _ = c.close(g.notification_fd);
        g.notification_fd = -1;
        clearNotifications();
        return;
    }
    g.notification_len += @intCast(n);
    processNotificationMessages();
}

fn startNotificationService() void {
    g.notification_fd = tessa_notifications_start();
    if (g.notification_fd < 0) {
        logMsg("notifications: cannot start the D-Bus service", .{});
        return;
    }
    const flags = c.fcntl(g.notification_fd, c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(g.notification_fd, c.F_SETFL, @as(c_int, flags | c.O_NONBLOCK));
    logDebug("notifications: starting service", .{});
}

fn mediaUpdate(status: u8, title: []const u8, artist: []const u8, player: []const u8) void {
    g.media_status = status;
    m.copyTrunc(&g.media_title, &g.media_title_len, title);
    m.copyTrunc(&g.media_artist, &g.media_artist_len, artist);
    m.copyTrunc(&g.media_player, &g.media_player_len, player);
    g.bar.dirty = true;
    if (g.overlay_mode == .media) refreshOverlay();
    if (status == 0) {
        logDebug("media: no player", .{});
    } else {
        logDebug("media: state={d} title={s}", .{ status, g.media_title[0..g.media_title_len] });
    }
}

fn mediaShift(count: usize) void {
    if (count >= g.media_len) {
        g.media_len = 0;
        return;
    }
    const remain = g.media_len - count;
    std.mem.copyForwards(u8, g.media_buf[0..remain], g.media_buf[count..g.media_len]);
    g.media_len = remain;
}

fn processMediaMessages() void {
    while (g.media_len > 0) {
        const kind = g.media_buf[0];
        if (kind == 1) {
            if (g.media_len < 16) return;
            const status = g.media_buf[1];
            const title_len: usize = @intCast(readU32(&g.media_buf, 4));
            const artist_len: usize = @intCast(readU32(&g.media_buf, 8));
            const player_len: usize = @intCast(readU32(&g.media_buf, 12));
            const total = 16 + title_len + artist_len + player_len;
            if (total > g.media_buf.len) {
                g.media_len = 0;
                return;
            }
            if (g.media_len < total) return;
            const title = g.media_buf[16 .. 16 + title_len];
            const artist = g.media_buf[16 + title_len .. 16 + title_len + artist_len];
            const player = g.media_buf[16 + title_len + artist_len .. total];
            mediaUpdate(
                @min(status, 3),
                title,
                artist,
                player,
            );
            mediaShift(total);
        } else if (kind == 2) {
            logMsg("media: service ready", .{});
            mediaShift(1);
        } else if (kind == 3) {
            if (g.media_len < 5) return;
            const len: usize = @intCast(readU32(&g.media_buf, 1));
            if (g.media_len < 5 + len) return;
            logMsg("media: {s}", .{g.media_buf[5 .. 5 + len]});
            mediaShift(5 + len);
        } else {
            g.media_len = 0;
            return;
        }
    }
}

fn readMedia() void {
    if (g.media_fd < 0) return;
    if (g.media_len >= g.media_buf.len) g.media_len = 0;
    const n = c.read(g.media_fd, g.media_buf[g.media_len..].ptr, g.media_buf.len - g.media_len);
    if (n <= 0) {
        logMsg("media: service disconnected", .{});
        _ = c.close(g.media_fd);
        g.media_fd = -1;
        return;
    }
    g.media_len += @intCast(n);
    processMediaMessages();
}

fn startMediaService() void {
    g.media_fd = tessa_media_start();
    if (g.media_fd < 0) {
        logMsg("media: cannot start the MPRIS service", .{});
        return;
    }
    const flags = c.fcntl(g.media_fd, c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(g.media_fd, c.F_SETFL, @as(c_int, flags | c.O_NONBLOCK));
    logDebug("media: starting service", .{});
}

fn tryTrayPng(path: []const u8) ?*c.cairo_surface_t {
    if (path.len == 0 or path.len + 1 >= 1024) return null;
    var zbuf: [1024]u8 = undefined;
    @memcpy(zbuf[0..path.len], path);
    zbuf[path.len] = 0;
    if (c.access(zbuf[0..path.len :0].ptr, c.F_OK) != 0) return null;
    const surf = c.cairo_image_surface_create_from_png(zbuf[0..path.len :0].ptr);
    if (c.cairo_surface_status(surf) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(surf);
        return null;
    }
    if (c.cairo_image_surface_get_width(surf) <= 0 or
        c.cairo_image_surface_get_height(surf) <= 0)
    {
        c.cairo_surface_destroy(surf);
        return null;
    }
    return surf;
}

/// Look up an IconName through the common PNG locations. StatusNotifier
/// clients frequently provide only a themed name; without this fallback most
/// real-world items would render as a monogram.
fn loadTrayIcon(name: []const u8) ?*c.cairo_surface_t {
    if (name.len == 0 or name.len > 120) return null;
    if (std.mem.indexOfAny(u8, name, "/\\") != null) return null;
    if (std.mem.indexOf(u8, name, "..") != null) return null;

    const themes = [_][]const u8{ "hicolor", "Adwaita", "breeze", "Papirus", "Yaru" };
    const sizes = [_][]const u8{ "scalable", "64x64", "48x48", "32x32", "24x24" };
    const categories = [_][]const u8{ "apps", "status", "panel", "devices", "places" };
    const bases = [_][]const u8{
        "/usr/share/icons",
        "/usr/local/share/icons",
    };
    var home_buf: [512]u8 = undefined;
    var home_dot_buf: [512]u8 = undefined;
    var home_icons: []const u8 = "";
    var local_icons: []const u8 = "";
    if (c.getenv("HOME")) |home_z| {
        const home = std.mem.span(home_z);
        home_icons = std.fmt.bufPrint(&home_buf, "{s}/.local/share/icons", .{home}) catch "";
        local_icons = std.fmt.bufPrint(&home_dot_buf, "{s}/.icons", .{home}) catch "";
    }
    var path_buf: [1024]u8 = undefined;

    if (tryTrayPng(std.fmt.bufPrint(&path_buf, "/usr/share/pixmaps/{s}.png", .{name}) catch "")) |s| return s;

    var base_i: usize = 0;
    while (base_i < bases.len + 2) : (base_i += 1) {
        const base: []const u8 = switch (base_i) {
            0, 1 => bases[base_i],
            2 => home_icons,
            else => local_icons,
        };
        if (base.len == 0) continue;
        if (tryTrayPng(std.fmt.bufPrint(&path_buf, "{s}/{s}.png", .{ base, name }) catch "")) |s| return s;
        for (themes) |theme| {
            for (sizes) |size| {
                if (tryTrayPng(std.fmt.bufPrint(&path_buf, "{s}/{s}/{s}/{s}.png", .{
                    base, theme, size, name,
                }) catch "")) |s| return s;
                for (categories) |cat| {
                    if (tryTrayPng(std.fmt.bufPrint(&path_buf, "{s}/{s}/{s}/{s}/{s}.png", .{
                        base, theme, size, cat, name,
                    }) catch "")) |s| return s;
                }
            }
        }
    }
    return null;
}

fn loadNotificationIcon(name: []const u8) ?*c.cairo_surface_t {
    if (name.len == 0 or name.len > 500) return null;
    var path = name;
    if (std.mem.startsWith(u8, path, "file://")) path = path[7..];
    if ((path.len > 0 and path[0] == '/') or std.mem.indexOfScalar(u8, path, '/') != null) {
        if (tryTrayPng(path)) |s| return s;
    }
    return loadTrayIcon(name);
}

fn decodeTrayPixmap(raw: []const u8, w: u32, h: u32, out: []u8) bool {
    if (w == 0 or h == 0 or w > m.MAX_TRAY_ICON or h > m.MAX_TRAY_ICON) return false;
    const need: usize = @intCast(w * h * 4);
    if (raw.len < need or out.len < need) return false;
    const little = @import("builtin").cpu.arch.endian() == .little;
    var i: usize = 0;
    while (i < need) : (i += 4) {
        if (little) {
            out[i] = raw[i + 3];
            out[i + 1] = raw[i + 2];
            out[i + 2] = raw[i + 1];
            out[i + 3] = raw[i];
        } else {
            @memcpy(out[i .. i + 4], raw[i .. i + 4]);
        }
    }
    return true;
}

fn freeTrayItemSurface(item: *m.TrayItem) void {
    if (item.icon_surface) |surf| {
        c.cairo_surface_destroy(surf);
        item.icon_surface = null;
    }
}

fn freeTraySurfaces() void {
    var i: usize = 0;
    while (i < g.tray_count) : (i += 1) freeTrayItemSurface(&g.tray_items[i]);
}

fn clearTrayState() void {
    freeTraySurfaces();
    g.tray_count = 0;
    g.tray_selected = 0;
    g.bar.dirty = true;
    if (g.overlay_mode == .tray) refreshOverlay();
}

fn trayUpdate(count: usize, payload: []const u8) void {
    if (count > m.MAX_TRAY_ITEMS) return;
    var new_items: [m.MAX_TRAY_ITEMS]m.TrayItem = undefined;
    var parsed: usize = 0;
    var off: usize = 0;
    while (parsed < count) : (parsed += 1) {
        if (off + 24 > payload.len) break;
        const item = &new_items[parsed];
        item.* = std.mem.zeroes(m.TrayItem);
        item.status = payload[off];
        const title_len: usize = @intCast(readU32(payload, off + 4));
        const icon_name_len: usize = @intCast(readU32(payload, off + 8));
        const icon_w = readU32(payload, off + 12);
        const icon_h = readU32(payload, off + 16);
        const icon_len: usize = @intCast(readU32(payload, off + 20));
        const total = 24 + title_len + icon_name_len + icon_len;
        if (off + total > payload.len or title_len >= item.title.len or
            icon_name_len >= item.icon_name.len or icon_len > m.MAX_TRAY_ICON_BYTES or
            (icon_len != 0 and icon_len != @as(usize, @intCast(icon_w * icon_h * 4))))
        {
            break;
        }
        const start = off + 24;
        @memcpy(item.title[0..title_len], payload[start .. start + title_len]);
        item.title[title_len] = 0;
        item.title_len = title_len;
        @memcpy(item.icon_name[0..icon_name_len], payload[start + title_len .. start + title_len + icon_name_len]);
        item.icon_name[icon_name_len] = 0;
        item.icon_name_len = icon_name_len;
        const icon_start = start + title_len + icon_name_len;
        if (icon_len > 0 and decodeTrayPixmap(payload[icon_start .. icon_start + icon_len], icon_w, icon_h, &item.icon_data)) {
            item.icon_w = icon_w;
            item.icon_h = icon_h;
            item.icon_len = icon_len;
        } else if (icon_name_len > 0) {
            item.icon_surface = loadTrayIcon(item.icon_name[0..icon_name_len]);
        }
        off += total;
    }
    if (parsed != count) {
        var j: usize = 0;
        while (j < parsed) : (j += 1) freeTrayItemSurface(&new_items[j]);
        logMsg("tray: malformed state message", .{});
        return;
    }

    freeTraySurfaces();
    g.tray_count = count;
    var i: usize = 0;
    while (i < count) : (i += 1) g.tray_items[i] = new_items[i];
    if (g.tray_selected >= g.tray_count) g.tray_selected = if (g.tray_count == 0) 0 else g.tray_count - 1;
    g.bar.dirty = true;
    if (g.overlay_mode == .tray) refreshOverlay();
    if (g.tray_count == 0) {
        logDebug("tray: no items", .{});
    } else {
        logDebug("tray: {d} item(s) first={s}", .{
            g.tray_count,
            g.tray_items[0].title[0..g.tray_items[0].title_len],
        });
    }
    if (g.tray_count > 0 and g.tray_items[0].icon_len > 0) {
        logDebug("tray: icon {d}x{d}", .{
            g.tray_items[0].icon_w,
            g.tray_items[0].icon_h,
        });
    }
}

fn trayShift(count: usize) void {
    if (count >= g.tray_len) {
        g.tray_len = 0;
        return;
    }
    const remain = g.tray_len - count;
    std.mem.copyForwards(u8, g.tray_buf[0..remain], g.tray_buf[count..g.tray_len]);
    g.tray_len = remain;
}

fn processTrayMessages() void {
    while (g.tray_len > 0) {
        const kind = g.tray_buf[0];
        if (kind == 1) {
            if (g.tray_len < 5) return;
            const count: usize = @intCast(readU32(&g.tray_buf, 1));
            var total: usize = 5;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                if (total + 24 > g.tray_len) return;
                const title_len: usize = @intCast(readU32(&g.tray_buf, total + 4));
                const icon_name_len: usize = @intCast(readU32(&g.tray_buf, total + 8));
                const icon_len: usize = @intCast(readU32(&g.tray_buf, total + 20));
                const item_total = 24 + title_len + icon_name_len + icon_len;
                if (item_total > g.tray_buf.len or total + item_total > g.tray_buf.len) {
                    logMsg("tray: oversized state message", .{});
                    g.tray_len = 0;
                    return;
                }
                total += item_total;
            }
            if (total > g.tray_buf.len) {
                g.tray_len = 0;
                return;
            }
            if (g.tray_len < total) return;
            trayUpdate(count, g.tray_buf[5..total]);
            trayShift(total);
        } else if (kind == 2) {
            g.tray_ready = true;
            logMsg("tray: service ready", .{});
            trayShift(1);
        } else if (kind == 3) {
            if (g.tray_len < 5) return;
            const len: usize = @intCast(readU32(&g.tray_buf, 1));
            if (g.tray_len < 5 + len) return;
            logMsg("tray: {s}", .{g.tray_buf[5 .. 5 + len]});
            trayShift(5 + len);
        } else {
            g.tray_len = 0;
            return;
        }
    }
}

fn readTray() void {
    if (g.tray_fd < 0) return;
    if (g.tray_len >= g.tray_buf.len) g.tray_len = 0;
    const n = c.read(g.tray_fd, g.tray_buf[g.tray_len..].ptr, g.tray_buf.len - g.tray_len);
    if (n <= 0) {
        logMsg("tray: service disconnected", .{});
        _ = c.close(g.tray_fd);
        g.tray_fd = -1;
        clearTrayState();
        return;
    }
    g.tray_len += @intCast(n);
    processTrayMessages();
}

fn startTrayService() void {
    g.tray_fd = tessa_tray_start();
    if (g.tray_fd < 0) {
        logMsg("tray: cannot start the StatusNotifier watcher", .{});
        return;
    }
    const flags = c.fcntl(g.tray_fd, c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(g.tray_fd, c.F_SETFL, @as(c_int, flags | c.O_NONBLOCK));
    logDebug("tray: starting service", .{});
}

fn trayActivate(index: usize, code: u32) void {
    if (index >= g.tray_count) return;
    tessa_tray_activate(@intCast(index), @intCast(code));
    logDebug("tray: activate {d} code {d} ({s})", .{
        index,
        code,
        g.tray_items[index].title[0..g.tray_items[index].title_len],
    });
}

fn moveTraySelection(delta: isize) void {
    if (g.tray_count == 0) return;
    const count: isize = @intCast(g.tray_count);
    var next = @as(isize, @intCast(g.tray_selected)) + delta;
    while (next < 0) next += count;
    while (next >= count) next -= count;
    g.tray_selected = @intCast(next);
    refreshOverlay();
}

fn activateTraySelection() void {
    if (g.tray_selected < g.tray_count) trayActivate(g.tray_selected, 1);
}

fn openTray() void {
    if (g.overlay != null and g.overlay_mode == .tray and g.menu_target == 1) {
        closeOverlay();
        return;
    }
    if (g.overlay != null) destroyOverlay();
    if (!ensureOverlay()) return;
    if (g.tray_selected >= g.tray_count) g.tray_selected = 0;
    beginOverlay(.tray);
    logDebug("tray: popover open ({d} items)", .{g.tray_count});
}

fn audioUpdate(percent: i32, muted: bool, source: []const u8) void {
    g.volume_percent = percent;
    g.volume_muted = muted;
    m.copyTrunc(&g.volume_source, &g.volume_source_len, source);
    g.bar.dirty = true;
    if (g.overlay_mode == .audio) refreshOverlay();
    if (percent < 0) {
        logDebug("audio: unavailable ({s})", .{g.volume_source[0..g.volume_source_len]});
    } else {
        logDebug("audio: source={s} volume={d} muted={d}", .{
            g.volume_source[0..g.volume_source_len],
            percent,
            @intFromBool(muted),
        });
    }
}

fn audioShift(count: usize) void {
    if (count >= g.audio_len) {
        g.audio_len = 0;
        return;
    }
    const remain = g.audio_len - count;
    std.mem.copyForwards(u8, g.audio_buf[0..remain], g.audio_buf[count..g.audio_len]);
    g.audio_len = remain;
}

fn processAudioMessages() void {
    while (g.audio_len > 0) {
        const kind = g.audio_buf[0];
        if (kind == 1) {
            if (g.audio_len < 12) return;
            const muted = g.audio_buf[1] != 0;
            const raw_percent = readU32(&g.audio_buf, 4);
            const percent: i32 = if (raw_percent > 150) -1 else @intCast(raw_percent);
            const source_len: usize = @intCast(readU32(&g.audio_buf, 8));
            const total = 12 + source_len;
            if (total > g.audio_buf.len) {
                g.audio_len = 0;
                return;
            }
            if (g.audio_len < total) return;
            audioUpdate(percent, muted, g.audio_buf[12..total]);
            audioShift(total);
        } else if (kind == 2) {
            g.audio_ready = true;
            logMsg("audio: service ready", .{});
            audioShift(1);
        } else if (kind == 3) {
            if (g.audio_len < 5) return;
            const len: usize = @intCast(readU32(&g.audio_buf, 1));
            if (g.audio_len < 5 + len) return;
            logMsg("audio: {s}", .{g.audio_buf[5 .. 5 + len]});
            audioShift(5 + len);
        } else {
            g.audio_len = 0;
            return;
        }
    }
}

fn readAudio() void {
    if (g.audio_fd < 0) return;
    if (g.audio_len >= g.audio_buf.len) g.audio_len = 0;
    const n = c.read(g.audio_fd, g.audio_buf[g.audio_len..].ptr, g.audio_buf.len - g.audio_len);
    if (n <= 0) {
        logMsg("audio: service disconnected", .{});
        _ = c.close(g.audio_fd);
        g.audio_fd = -1;
        audioUpdate(-1, false, "");
        return;
    }
    g.audio_len += @intCast(n);
    processAudioMessages();
}

fn startAudioService() void {
    const status = g.volume_status[0..g.volume_status_len :0];
    const up = g.volume_up[0..g.volume_up_len :0];
    const down = g.volume_down[0..g.volume_down_len :0];
    const mute = g.volume_mute[0..g.volume_mute_len :0];
    g.audio_fd = tessa_audio_start(status.ptr, up.ptr, down.ptr, mute.ptr);
    if (g.audio_fd < 0) {
        logMsg("audio: cannot start the volume service", .{});
        return;
    }
    const flags = c.fcntl(g.audio_fd, c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(g.audio_fd, c.F_SETFL, @as(c_int, flags | c.O_NONBLOCK));
    logDebug("audio: starting service", .{});
}

fn audioCommand(code: u32) void {
    tessa_audio_command(@intCast(code));
    logDebug("audio: command {d}", .{code});
}

fn openAudio() void {
    if (g.overlay != null and g.overlay_mode == .audio and g.menu_target == 1) {
        closeOverlay();
        return;
    }
    if (g.overlay != null) destroyOverlay();
    if (!ensureOverlay()) return;
    beginOverlay(.audio);
    logDebug("audio: controls open", .{});
}

fn ensureDataControlDevice() void {
    if (g.data_control_device != null) return;
    const manager = g.data_control_manager orelse return;
    const seat = g.seat orelse return;
    const device = c.zwlr_data_control_manager_v1_get_data_device(manager, seat) orelse return;
    g.data_control_device = device;
    g.data_control_listener = std.mem.zeroes(c.zwlr_data_control_device_v1_listener);
    g.data_control_listener.data_offer = onDataOffer;
    g.data_control_listener.selection = onDataSelection;
    g.data_control_listener.finished = onDataControlFinished;
    _ = c.zwlr_data_control_device_v1_add_listener(device, &g.data_control_listener, null);
    logDebug("clipboard: data control device ready", .{});
}

fn resetClipboardRead() void {
    if (g.clipboard_fd >= 0) {
        _ = c.close(g.clipboard_fd);
        g.clipboard_fd = -1;
    }
    g.clipboard_read_len = 0;
}

fn ensureDataOffer(offer: *c.zwlr_data_control_offer_v1) void {
    resetClipboardRead();
    if (g.data_offer) |old| {
        if (old != offer) c.zwlr_data_control_offer_v1_destroy(old);
    }
    g.data_offer = offer;
    g.data_offer_mime_len = 0;
    g.data_offer_mime_rank = 0;
    g.data_offer_selected = false;
    g.data_offer_listener = std.mem.zeroes(c.zwlr_data_control_offer_v1_listener);
    g.data_offer_listener.offer = onDataOfferMime;
    _ = c.zwlr_data_control_offer_v1_add_listener(offer, &g.data_offer_listener, null);
}

fn maybeStartClipboardRead() void {
    if (!g.data_offer_selected or g.clipboard_fd >= 0) return;
    if (g.data_offer_mime_len == 0) return;
    const offer = g.data_offer orelse return;

    var fds = [_]c_int{ -1, -1 };
    if (c.pipe2(&fds, c.O_CLOEXEC) < 0) {
        logDebug("clipboard: pipe2 failed", .{});
        return;
    }
    var mime_buf: [128:0]u8 = undefined;
    const len = @min(g.data_offer_mime_len, mime_buf.len - 1);
    @memcpy(mime_buf[0..len], g.data_offer_mime[0..len]);
    mime_buf[len] = 0;
    c.zwlr_data_control_offer_v1_receive(offer, @ptrCast(&mime_buf), fds[1]);
    _ = c.close(fds[1]);

    const flags = c.fcntl(fds[0], c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(fds[0], c.F_SETFL, @as(c_int, flags | c.O_NONBLOCK));
    g.clipboard_fd = fds[0];
    g.clipboard_read_len = 0;
    logDebug("clipboard: reading {s}", .{g.data_offer_mime[0..len]});
}

fn finishClipboardRead() void {
    const len = g.clipboard_read_len;
    resetClipboardRead();
    if (len > 0) {
        clipboardAdd(g.clipboard_read_buf[0..len]);
    }
    if (g.data_offer) |offer| {
        c.zwlr_data_control_offer_v1_destroy(offer);
        g.data_offer = null;
    }
    g.data_offer_selected = false;
}

fn readClipboardPipe() void {
    if (g.clipboard_fd < 0) return;
    while (g.clipboard_read_len < g.clipboard_read_buf.len) {
        const remaining = g.clipboard_read_buf.len - g.clipboard_read_len;
        const n = c.read(g.clipboard_fd, g.clipboard_read_buf[g.clipboard_read_len..].ptr, remaining);
        if (n > 0) {
            g.clipboard_read_len += @intCast(n);
            continue;
        }
        if (n == 0) {
            finishClipboardRead();
            return;
        }
        return;
    }
    finishClipboardRead();
}

fn onDataOffer(data: ?*anyopaque, device: ?*c.zwlr_data_control_device_v1, offer: ?*c.zwlr_data_control_offer_v1) callconv(.c) void {
    _ = data;
    _ = device;
    if (offer) |value| ensureDataOffer(value);
}

fn onDataOfferMime(data: ?*anyopaque, offer: ?*c.zwlr_data_control_offer_v1, mime: [*c]const u8) callconv(.c) void {
    _ = data;
    _ = offer;
    if (mime == null) return;
    const name = std.mem.span(mime);
    const rank = mimeRank(name);
    if (rank <= g.data_offer_mime_rank) return;
    m.copyTrunc(&g.data_offer_mime, &g.data_offer_mime_len, name);
    g.data_offer_mime_rank = rank;
    maybeStartClipboardRead();
}

fn onDataSelection(data: ?*anyopaque, device: ?*c.zwlr_data_control_device_v1, offer: ?*c.zwlr_data_control_offer_v1) callconv(.c) void {
    _ = data;
    _ = device;
    if (offer == null) {
        resetClipboardRead();
        if (g.data_offer) |current| {
            c.zwlr_data_control_offer_v1_destroy(current);
            g.data_offer = null;
        }
        g.data_offer_selected = false;
        return;
    }
    if (g.data_offer != offer) ensureDataOffer(offer.?);
    g.data_offer_selected = true;
    maybeStartClipboardRead();
}

fn onClipboardSourceSend(data: ?*anyopaque, source: ?*c.zwlr_data_control_source_v1, mime: [*c]const u8, fd: c_int) callconv(.c) void {
    _ = data;
    _ = source;
    _ = mime;
    var sent: usize = 0;
    while (sent < g.clipboard_send_len) {
        const n = c.write(fd, g.clipboard_send_text[sent..].ptr, g.clipboard_send_len - sent);
        if (n <= 0) break;
        sent += @intCast(n);
    }
    _ = c.close(fd);
}

fn onClipboardSourceCancelled(data: ?*anyopaque, source: ?*c.zwlr_data_control_source_v1) callconv(.c) void {
    _ = data;
    if (source == null) return;
    if (g.clipboard_source == source) {
        g.clipboard_source = null;
        c.zwlr_data_control_source_v1_destroy(source.?);
    }
}

fn onSeatCapabilities(data: ?*anyopaque, seat: ?*c.wl_seat, caps: u32) callconv(.c) void {
    _ = data;
    if (seat == null) return;
    ensureDataControlDevice();
    if ((caps & c.WL_SEAT_CAPABILITY_KEYBOARD) != 0 and g.keyboard == null) {
        const kb = c.wl_seat_get_keyboard(seat) orelse return;
        g.keyboard = kb;
        _ = c.wl_keyboard_add_listener(kb, &keyboard_listener, null);
    }
    if ((caps & c.WL_SEAT_CAPABILITY_POINTER) != 0 and g.pointer == null) {
        const pointer = c.wl_seat_get_pointer(seat) orelse return;
        g.pointer = pointer;
        _ = c.wl_pointer_add_listener(pointer, &pointer_listener, null);
    }
}

fn onSeatName(data: ?*anyopaque, seat: ?*c.wl_seat, name: [*c]const u8) callconv(.c) void {
    _ = data;
    _ = seat;
    _ = name;
}

fn onShmFormat(data: ?*anyopaque, shm: ?*c.wl_shm, format: u32) callconv(.c) void {
    _ = data;
    _ = shm;
    _ = format;
}

fn outputInfo(data: ?*anyopaque) *m.OutputInfo {
    return @ptrCast(@alignCast(data.?));
}

fn onOutputGeometry(data: ?*anyopaque, output: ?*c.wl_output, x: c_int, y: c_int, physical_w: c_int, physical_h: c_int, subpixel: c_int, make: [*c]const u8, model: [*c]const u8, transform: c_int) callconv(.c) void {
    _ = output;
    _ = physical_w;
    _ = physical_h;
    _ = subpixel;
    _ = make;
    _ = model;
    _ = transform;
    const info = outputInfo(data);
    info.x = x;
    info.y = y;
}

fn onOutputMode(data: ?*anyopaque, output: ?*c.wl_output, flags: u32, width: c_int, height: c_int, refresh: c_int) callconv(.c) void {
    _ = output;
    _ = refresh;
    if ((flags & c.WL_OUTPUT_MODE_CURRENT) == 0) return;
    const info = outputInfo(data);
    info.width = width;
    info.height = height;
}

fn onOutputDone(data: ?*anyopaque, output: ?*c.wl_output) callconv(.c) void {
    _ = output;
    outputInfo(data).done = true;
}

fn onOutputScale(data: ?*anyopaque, output: ?*c.wl_output, factor: c_int) callconv(.c) void {
    const info = outputInfo(data);
    info.scale = @max(1, factor);
    if (output != null and output == g.target_output) applyPanelScale(info.scale);
}

fn onOutputName(data: ?*anyopaque, output: ?*c.wl_output, name: [*c]const u8) callconv(.c) void {
    _ = output;
    if (name == null) return;
    const info = outputInfo(data);
    m.copyTrunc(&info.name, &info.name_len, std.mem.span(name));
    if (g.target_name_len > 0 and std.mem.eql(u8, info.name[0..info.name_len], g.target_name[0..g.target_name_len])) {
        g.target_output = info.wl;
        applyPanelScale(info.scale);
    }
}

fn onOutputDescription(data: ?*anyopaque, output: ?*c.wl_output, description: [*c]const u8) callconv(.c) void {
    _ = data;
    _ = output;
    _ = description;
}

fn selectTargetOutput() void {
    if (g.target_output != null) return;
    var i: usize = 0;
    while (i < g.output_count) : (i += 1) {
        const info = &g.outputs[i];
        if (info.wl == null) continue;
        if (g.target_name_len > 0 and std.mem.eql(u8, info.name[0..info.name_len], g.target_name[0..g.target_name_len])) {
            g.target_output = info.wl;
            applyPanelScale(info.scale);
            return;
        }
    }
    if (g.target_name_len > 0) {
        logMsg("output {s} not found; using the first output", .{g.target_name[0..g.target_name_len]});
    }
    i = 0;
    while (i < g.output_count) : (i += 1) {
        if (g.outputs[i].wl) |wl| {
            g.target_output = wl;
            applyPanelScale(g.outputs[i].scale);
            if (g.target_name_len == 0 and g.outputs[i].name_len > 0) {
                m.copyTrunc(&g.target_name, &g.target_name_len, g.outputs[i].name[0..g.outputs[i].name_len]);
            }
            return;
        }
    }
}

fn onRegistryGlobal(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    _ = data;
    const reg = registry orelse g.registry orelse return;
    if (interface == null) return;
    const iface = std.mem.span(interface);

    if (std.mem.eql(u8, iface, "wl_compositor") and g.compositor == null) {
        const v = @min(version, 4);
        if (c.wl_registry_bind(reg, name, &c.wl_compositor_interface, v)) |p| {
            g.compositor = @ptrCast(@alignCast(p));
        }
    } else if (std.mem.eql(u8, iface, "wl_shm") and g.shm == null) {
        if (c.wl_registry_bind(reg, name, &c.wl_shm_interface, 1)) |p| {
            g.shm = @ptrCast(@alignCast(p));
            _ = c.wl_shm_add_listener(g.shm.?, &shm_listener, null);
        }
    } else if (std.mem.eql(u8, iface, "zwlr_layer_shell_v1") and g.layer_shell == null) {
        const v = @min(version, 4);
        if (c.wl_registry_bind(reg, name, &c.zwlr_layer_shell_v1_interface, v)) |p| {
            g.layer_shell = @ptrCast(@alignCast(p));
        }
    } else if (std.mem.eql(u8, iface, "zwp_text_input_manager_v3") and g.text_input_manager == null) {
        if (c.wl_registry_bind(reg, name, &c.zwp_text_input_manager_v3_interface, 1)) |p| {
            g.text_input_manager = @ptrCast(@alignCast(p));
        }
    } else if (std.mem.eql(u8, iface, "zwlr_data_control_manager_v1") and g.data_control_manager == null) {
        const v = @min(version, 1);
        if (c.wl_registry_bind(reg, name, &c.zwlr_data_control_manager_v1_interface, v)) |p| {
            g.data_control_manager = @ptrCast(@alignCast(p));
            ensureDataControlDevice();
        }
    } else if (std.mem.eql(u8, iface, "zwlr_screencopy_manager_v1") and g.screenshot_manager == null) {
        const v = @min(version, 1);
        if (c.wl_registry_bind(reg, name, &c.zwlr_screencopy_manager_v1_interface, v)) |p| {
            g.screenshot_manager = @ptrCast(@alignCast(p));
        }
    } else if (std.mem.eql(u8, iface, "wl_output")) {
        if (g.output_count < g.outputs.len) {
            const v = @min(version, 4);
            if (c.wl_registry_bind(reg, name, &c.wl_output_interface, v)) |p| {
                const info = &g.outputs[g.output_count];
                g.output_count += 1;
                info.wl = @ptrCast(@alignCast(p));
                _ = c.wl_output_add_listener(info.wl.?, &output_listener, info);
            }
        }
    } else if (std.mem.eql(u8, iface, "wl_seat") and g.seat == null) {
        if (c.wl_registry_bind(reg, name, &c.wl_seat_interface, 1)) |p| {
            g.seat = @ptrCast(@alignCast(p));
            _ = c.wl_seat_add_listener(g.seat.?, &seat_listener, null);
        }
    }
}

fn onRegistryGlobalRemove(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
}

fn pointerCoords(s: *m.Surface, fixed_x: c.wl_fixed_t, fixed_y: c.wl_fixed_t) void {
    g.pointer_surface = s;
    g.pointer_x = c.wl_fixed_to_double(fixed_x);
    g.pointer_y = c.wl_fixed_to_double(fixed_y);
}

fn hitIn(r: *const m.HitRect, x: f64, y: f64) bool {
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h;
}

fn hitBar(x: f64, y: f64) m.Hit {
    var i: usize = 0;
    while (i < g.bar_hit_count) : (i += 1) {
        if (hitIn(&g.bar_hits[i], x, y)) return g.bar_hits[i].hit;
    }
    return .{};
}

fn hitOverlay(x: f64, y: f64) m.Hit {
    var i: usize = 0;
    while (i < g.overlay_hit_count) : (i += 1) {
        if (hitIn(&g.overlay_hits[i], x, y)) return g.overlay_hits[i].hit;
    }
    return .{};
}

fn hitToast(x: f64, y: f64) ?u32 {
    var i: usize = 0;
    while (i < g.toast_hit_count) : (i += 1) {
        if (hitIn(&g.toast_hits[i], x, y)) return @intCast(g.toast_hits[i].hit.value);
    }
    return null;
}

fn hitToastAction(x: f64, y: f64) ?m.ToastActionHit {
    var i: usize = 0;
    while (i < g.toast_action_hit_count) : (i += 1) {
        const r = &g.toast_action_hits[i];
        if (x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h) return r.*;
    }
    return null;
}

fn hitToastClose(x: f64, y: f64) ?u32 {
    var i: usize = 0;
    while (i < g.toast_hit_count) : (i += 1) {
        const r = &g.toast_hits[i];
        if (!hitIn(r, x, y)) continue;
        if (x >= r.x + r.w - 36.0 and y < r.y + 32.0) return @intCast(r.hit.value);
    }
    return null;
}

fn notificationDefaultOrDismissById(id: u32) void {
    if (notificationFind(id)) |index| notificationDefaultOrDismiss(index);
}

fn notificationActionById(id: u32, action: usize) void {
    if (notificationFind(id)) |index| notificationAction(index, action);
}

fn updateHover() void {
    if (g.pointer_surface == &g.bar) {
        const h = hitBar(g.pointer_x, g.pointer_y);
        if (h.kind != g.hover.kind or h.value != g.hover.value) {
            g.hover = h;
            g.bar.dirty = true;
        }
    } else {
        if (g.hover.kind != .none) {
            g.hover = .{};
            g.bar.dirty = true;
        }
    }

    if (g.toasts) |toasts| {
        if (g.pointer_surface == toasts) toasts.dirty = true;
    }

    if (g.overlay) |ov| {
        if (g.pointer_surface == ov and hitIn(&g.overlay_panel, g.pointer_x, g.pointer_y)) {
            var hovered: usize = 999;
            var i: usize = 0;
            while (i < g.overlay_hit_count) : (i += 1) {
                if (hitIn(&g.overlay_hits[i], g.pointer_x, g.pointer_y)) {
                    hovered = i;
                    break;
                }
            }
            if (hovered != g.overlay_row_hover) {
                g.overlay_row_hover = hovered;
                ov.dirty = true;
            }
        } else if (g.overlay_row_hover != 999) {
            g.overlay_row_hover = 999;
            ov.dirty = true;
        }
    }
}

fn onPointerEnter(data: ?*anyopaque, pointer: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface, sx: c.wl_fixed_t, sy: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = pointer;
    _ = serial;
    const s = surfaceFor(surface) orelse return;
    pointerCoords(s, sx, sy);
    if (g.overlay_mode == .screenshot) {
        refreshOverlay();
        return;
    }
    updateHover();
}

fn onPointerLeave(data: ?*anyopaque, pointer: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = pointer;
    _ = serial;
    const s = surfaceFor(surface) orelse return;
    if (g.pointer_surface == s) g.pointer_surface = null;
    if (s.kind == .toasts) s.dirty = true;
    if (g.overlay_mode == .screenshot) {
        refreshOverlay();
        return;
    }
    updateHover();
}

fn onPointerMotion(data: ?*anyopaque, pointer: ?*c.wl_pointer, time: u32, sx: c.wl_fixed_t, sy: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = pointer;
    _ = time;
    if (g.pointer_surface == null) return;
    g.pointer_x = c.wl_fixed_to_double(sx);
    g.pointer_y = c.wl_fixed_to_double(sy);
    if (g.overlay_mode == .screenshot) {
        if (g.screenshot_dragging) {
            g.screenshot_end_x = g.pointer_x;
            g.screenshot_end_y = g.pointer_y;
        }
        refreshOverlay();
        return;
    }
    updateHover();
}

fn onPointerButton(data: ?*anyopaque, pointer: ?*c.wl_pointer, serial: u32, time: u32, button: u32, state: u32) callconv(.c) void {
    _ = data;
    _ = pointer;
    _ = serial;
    _ = time;
    const pointer_surface = g.pointer_surface orelse return;
    if (g.overlay_mode == .screenshot and g.overlay == pointer_surface) {
        if (button == 0x110) {
            if (state == 1) {
                if (!g.screenshot_ready) return;
                g.screenshot_dragging = true;
                g.screenshot_start_x = g.pointer_x;
                g.screenshot_start_y = g.pointer_y;
                g.screenshot_end_x = g.pointer_x;
                g.screenshot_end_y = g.pointer_y;
                refreshOverlay();
            } else if (g.screenshot_dragging) {
                g.screenshot_end_x = g.pointer_x;
                g.screenshot_end_y = g.pointer_y;
                g.screenshot_dragging = false;
                saveSelectedScreenshot();
            }
        } else if (button == 0x111 and state == 1) {
            cancelScreenshot();
        }
        return;
    }
    if (g.toasts == pointer_surface) {
        if (state == 1) {
            if (button == 0x111) {
                if (hitToast(g.pointer_x, g.pointer_y)) |id| notificationDismiss(id);
            } else if (button == 0x110) {
                if (hitToastAction(g.pointer_x, g.pointer_y)) |hit| {
                    notificationActionById(hit.id, hit.action);
                } else if (hitToastClose(g.pointer_x, g.pointer_y)) |id| {
                    notificationDismiss(id);
                } else if (hitToast(g.pointer_x, g.pointer_y)) |id| {
                    notificationDefaultOrDismissById(id);
                }
            }
        }
        return;
    }
    if (state != 1) return;
    const s = pointer_surface;

    if (s == &g.bar) {
        const h = hitBar(g.pointer_x, g.pointer_y);
        switch (h.kind) {
            .menu => {
                if (button == 0x111) {
                    openPower();
                } else if (button == 0x110) {
                    openLauncher("");
                }
            },
            .clock => {
                if (button == 0x110) openCalendar();
            },
            .media => {
                if (button == 0x110) openMedia();
            },
            .tray => {
                if (button == 0x110) {
                    trayActivate(h.value, 1);
                } else if (button == 0x111) {
                    openTray();
                }
            },
            .volume => {
                if (button == 0x110) openAudio();
            },
            .workspace => {
                if (button == 0x110) sendWorkspace(h.value);
            },
            .window => {
                if (button == 0x110) {
                    sendCmd("CMD focus {d}\n", .{h.value});
                } else if (button == 0x111) {
                    sendCmd("CMD close {d}\n", .{h.value});
                }
            },
            .status => {
                if (button == 0x110 and h.value < g.status_count) {
                    const st = &g.statuses[h.value];
                    if (st.command_len > 0) {
                        sendCmd("CMD spawn {s}{c}", .{ st.command[0..st.command_len], @as(u8, 10) });
                    }
                }
            },
            else => {},
        }
    } else if (g.overlay) |ov| {
        if (s != ov) return;
        if (button == 0x111) {
            closeOverlay();
            return;
        }
        if (!hitIn(&g.overlay_panel, g.pointer_x, g.pointer_y)) {
            closeOverlay();
            return;
        }
        activateOverlayHit(hitOverlay(g.pointer_x, g.pointer_y));
    }
}

fn onPointerAxis(data: ?*anyopaque, pointer: ?*c.wl_pointer, time: u32, axis: u32, value: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = pointer;
    _ = time;
    _ = axis;
    const v = c.wl_fixed_to_double(value);
    if (v == 0) return;

    if (g.pointer_surface == &g.bar) {
        var ws = g.active_ws;
        if (v > 0) {
            ws = if (ws >= 9) 1 else ws + 1;
        } else {
            ws = if (ws <= 1) 9 else ws - 1;
        }
        sendWorkspace(ws);
    } else if (g.overlay_mode == .calendar) {
        shiftCalendar(if (v > 0) 1 else -1);
    } else if (g.overlay_mode == .power) {
        movePowerSelection(if (v > 0) 1 else -1);
    } else if (g.overlay_mode == .clipboard) {
        moveClipboardSelection(if (v > 0) 1 else -1);
    } else if (g.overlay_mode == .tray) {
        moveTraySelection(if (v > 0) 1 else -1);
    } else if (g.overlay_mode == .audio) {
        audioCommand(if (v > 0) 2 else 1);
    } else if (g.overlay != null and g.launcher_open) {
        if (g.result_count > 0) {
            if (v > 0) {
                g.selected = @min(g.selected + 1, g.result_count - 1);
            } else {
                g.selected = g.selected -| 1;
            }
            ensureSelectionVisible();
            if (g.overlay) |s| s.dirty = true;
        }
    }
}

fn initListeners() void {
    registry_listener = std.mem.zeroes(c.wl_registry_listener);
    registry_listener.global = onRegistryGlobal;
    registry_listener.global_remove = onRegistryGlobalRemove;

    seat_listener = std.mem.zeroes(c.wl_seat_listener);
    seat_listener.capabilities = onSeatCapabilities;
    seat_listener.name = onSeatName;

    keyboard_listener = std.mem.zeroes(c.wl_keyboard_listener);
    keyboard_listener.keymap = onKeyboardKeymap;
    keyboard_listener.enter = onKeyboardEnter;
    keyboard_listener.leave = onKeyboardLeave;
    keyboard_listener.key = onKeyboardKey;
    keyboard_listener.modifiers = onKeyboardModifiers;

    pointer_listener = std.mem.zeroes(c.wl_pointer_listener);
    pointer_listener.enter = onPointerEnter;
    pointer_listener.leave = onPointerLeave;
    pointer_listener.motion = onPointerMotion;
    pointer_listener.button = onPointerButton;
    pointer_listener.axis = onPointerAxis;

    shm_listener = std.mem.zeroes(c.wl_shm_listener);
    shm_listener.format = onShmFormat;

    output_listener = std.mem.zeroes(c.wl_output_listener);
    output_listener.geometry = onOutputGeometry;
    output_listener.mode = onOutputMode;
    output_listener.done = onOutputDone;
    output_listener.scale = onOutputScale;
    output_listener.name = onOutputName;
    output_listener.description = onOutputDescription;
}

fn splitTabs(line: []const u8, fields: [][]const u8) usize {
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= line.len and count < fields.len) : (i += 1) {
        if (i == line.len or line[i] == 9) {
            fields[count] = line[start..i];
            count += 1;
            start = i + 1;
        }
    }
    return count;
}

fn handleStateLine(line: []const u8) void {
    if (std.mem.eql(u8, line, "STATE")) {
        g.window_count = 0;
        g.occ = [_]u32{0} ** 10;
        g.focused_id = 0;
        g.is_focused_output = false;
        g.status_count = 0;
        g.ipc_in_state = true;
        return;
    }
    if (std.mem.eql(u8, line, "END")) {
        g.ipc_in_state = false;
        g.occ = [_]u32{0} ** 10;
        var wi: usize = 0;
        while (wi < g.window_count) : (wi += 1) {
            const ws = g.windows[wi].ws;
            if (ws >= 1 and ws <= 9) g.occ[ws] += 1;
        }
        g.bar.dirty = true;
        if (c.getenv("TESSA_PANEL_DEBUG") != null) {
            logMsg("state: output={s} ws={d} windows={d}", .{
                g.target_name[0..g.target_name_len],
                g.active_ws,
                g.window_count,
            });
        }
        return;
    }
    if (!g.ipc_in_state) return;

    if (std.mem.startsWith(u8, line, "STATUS") and line.len > 6 and line[6] == 9) {
        var fields: [4][]const u8 = undefined;
        const count = splitTabs(line, &fields);
        if (count < 4 or g.status_count >= g.statuses.len) return;
        const st = &g.statuses[g.status_count];
        st.* = std.mem.zeroes(m.StatusInfo);
        m.decodeEscapes(&st.id, &st.id_len, fields[1]);
        m.decodeEscapes(&st.text, &st.text_len, fields[2]);
        m.decodeEscapes(&st.command, &st.command_len, fields[3]);
        g.status_count += 1;
        return;
    }

    if (std.mem.startsWith(u8, line, "WIN\t")) {
        var fields: [9][]const u8 = undefined;
        var count: usize = 0;
        var start: usize = 0;
        var i: usize = 0;
        while (i <= line.len and count < fields.len) : (i += 1) {
            if (i == line.len or line[i] == '\t') {
                fields[count] = line[start..i];
                count += 1;
                start = i + 1;
            }
        }
        if (count < 9) return;
        if (g.target_name_len > 0 and
            !std.mem.eql(u8, fields[8], g.target_name[0..g.target_name_len])) return;
        if (g.window_count >= g.windows.len) return;
        const w = &g.windows[g.window_count];
        w.* = std.mem.zeroes(m.WindowInfo);
        w.id = std.fmt.parseInt(u64, fields[1], 10) catch 0;
        w.ws = std.fmt.parseInt(usize, fields[2], 10) catch 1;
        w.focused = std.mem.eql(u8, fields[3], "1");
        w.floating = std.mem.eql(u8, fields[4], "1");
        w.fullscreen = std.mem.eql(u8, fields[5], "1");
        m.decodeEscapes(&w.app_id, &w.app_len, fields[6]);
        m.decodeEscapes(&w.title, &w.title_len, fields[7]);
        m.decodeEscapes(&w.output_name, &w.output_len, fields[8]);
        g.window_count += 1;
        return;
    }

    var it = std.mem.tokenizeAny(u8, line, " \t");
    const cmd = it.next() orelse return;
    if (std.mem.eql(u8, cmd, "OUT")) {
        const name = it.next() orelse return;
        const ws_s = it.next() orelse return;
        const focused_s = it.next() orelse return;
        const ws = std.fmt.parseInt(usize, ws_s, 10) catch return;
        if (g.target_name_len > 0 and std.mem.eql(u8, name, g.target_name[0..g.target_name_len])) {
            if (ws >= 1 and ws <= 9) g.active_ws = ws;
            g.is_focused_output = std.mem.eql(u8, focused_s, "1");
        }
        if (std.mem.eql(u8, focused_s, "1")) {
            const changed = g.focused_output_name_len != name.len or
                !std.mem.eql(u8, g.focused_output_name[0..g.focused_output_name_len], name);
            if (changed) {
                m.copyTrunc(&g.focused_output_name, &g.focused_output_name_len, name);
                if (g.notification_count > 0) updateToastsSurface();
            }
        }
    } else if (std.mem.eql(u8, cmd, "ACTIVE")) {
        const s = it.next() orelse return;
        const v = std.fmt.parseInt(usize, s, 10) catch return;
        if (g.target_name_len == 0 and v >= 1 and v <= 9) g.active_ws = v;
    } else if (std.mem.eql(u8, cmd, "OCC")) {
        _ = it.next() orelse return;
        _ = it.next() orelse return;
    } else if (std.mem.eql(u8, cmd, "FOCUSED")) {
        const s = it.next() orelse return;
        g.focused_id = std.fmt.parseInt(u64, s, 10) catch 0;
    }
}

fn onEvent(line: []const u8) void {
    if (!std.mem.startsWith(u8, line, "EVENT")) return;

    if (line.len > 5 and line[5] == 9) {
        var fields: [16][]const u8 = undefined;
        const count = splitTabs(line, &fields);
        if (count < 2) return;
        const name = fields[1];

        if (std.mem.eql(u8, name, "config-reload")) {
            reloadPanelConfig();
            return;
        }
        if (std.mem.eql(u8, name, "notification-action")) {
            var id: u32 = 0;
            var action_buf: [128]u8 = undefined;
            var action_len: usize = 0;
            var fi: usize = 2;
            while (fi < count) : (fi += 1) {
                const eq = std.mem.indexOfScalar(u8, fields[fi], '=') orelse continue;
                const key = fields[fi][0..eq];
                const value = fields[fi][eq + 1 ..];
                if (std.mem.eql(u8, key, "id")) {
                    id = std.fmt.parseInt(u32, value, 10) catch 0;
                } else if (std.mem.eql(u8, key, "action")) {
                    m.decodeEscapes(&action_buf, &action_len, value);
                }
            }
            if (id > 0 and action_len > 0) {
                notificationActionByKey(id, action_buf[0..action_len]);
            }
            return;
        }
        if (!std.mem.eql(u8, name, "launcher") and !std.mem.eql(u8, name, "panel")) return;

        var event_output: [64]u8 = undefined;
        var event_output_len: usize = 0;
        var query: [128]u8 = undefined;
        var query_len: usize = 0;
        var fi: usize = 2;
        while (fi < count) : (fi += 1) {
            const eq = std.mem.indexOfScalar(u8, fields[fi], '=') orelse continue;
            const key = fields[fi][0..eq];
            const value = fields[fi][eq + 1 ..];
            if (std.mem.eql(u8, key, "output")) {
                m.decodeEscapes(&event_output, &event_output_len, value);
            } else if (std.mem.eql(u8, key, "arg") or std.mem.eql(u8, key, "query")) {
                m.decodeEscapes(&query, &query_len, value);
            }
        }

        if (event_output_len > 0 and g.target_name_len > 0) {
            if (!std.mem.eql(u8, event_output[0..event_output_len], g.target_name[0..g.target_name_len])) return;
        } else if (!g.is_focused_output) {
            return;
        }
        if (std.mem.eql(u8, name, "panel")) {
            openPanel(query[0..query_len]);
        } else {
            openLauncher(query[0..query_len]);
        }
        return;
    }

    var it = std.mem.tokenizeAny(u8, line, " \t");
    const tag = it.next() orelse return;
    if (!std.mem.eql(u8, tag, "EVENT")) return;
    const name = it.next() orelse return;
    if (std.mem.eql(u8, name, "launcher")) {
        if (!g.is_focused_output) return;
        const rest = it.rest();
        openLauncher(std.mem.trim(u8, rest, " \t"));
    }
}

fn handleIpcLine(line: []const u8) void {
    if (line.len == 0) return;
    if (std.mem.startsWith(u8, line, "EVENT ")) {
        onEvent(line);
    } else if (std.mem.startsWith(u8, line, "EVENT") and line.len > 5 and line[5] == 9) {
        onEvent(line);
    } else {
        handleStateLine(line);
    }
}

fn readIpc() void {
    if (g.ipc_fd < 0) return;
    if (g.ipc_len >= g.ipc_buf.len) g.ipc_len = 0;
    const n = c.read(g.ipc_fd, g.ipc_buf[g.ipc_len..].ptr, g.ipc_buf.len - g.ipc_len);
    if (n <= 0) {
        g.running = false;
        return;
    }
    g.ipc_len += @intCast(n);

    while (true) {
        const slice = g.ipc_buf[0..g.ipc_len];
        const nl = std.mem.indexOfScalar(u8, slice, '\n') orelse break;
        const line = std.mem.trim(u8, slice[0..nl], " \r");
        handleIpcLine(line);
        const remain = g.ipc_len - (nl + 1);
        if (remain > 0) std.mem.copyForwards(u8, g.ipc_buf[0..remain], g.ipc_buf[nl + 1 .. g.ipc_len]);
        g.ipc_len = remain;
    }
}

fn connectIpc() bool {
    var path_buf: [256]u8 = undefined;
    var path: []const u8 = "";
    if (c.getenv("TESSA_IPC")) |p| {
        path = std.mem.span(p);
    } else if (c.getenv("XDG_RUNTIME_DIR")) |p| {
        path = std.fmt.bufPrint(&path_buf, "{s}/tessa.sock", .{std.mem.span(p)}) catch "";
    }
    if (path.len == 0 or path.len >= 100) return false;

    const fd = c.socket(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0);
    if (fd < 0) return false;

    var addr: c.sockaddr_un = std.mem.zeroes(c.sockaddr_un);
    addr.sun_family = c.AF_UNIX;
    @memcpy(addr.sun_path[0..path.len], path);
    addr.sun_path[path.len] = 0;

    const connect_addr: c.__CONST_SOCKADDR_ARG = .{ .__sockaddr_un__ = @ptrCast(&addr) };
    if (c.connect(fd, connect_addr, @intCast(@sizeOf(c.sockaddr_un))) < 0) {
        _ = c.close(fd);
        return false;
    }
    const flags = c.fcntl(fd, c.F_GETFL, @as(c_int, 0));
    _ = c.fcntl(fd, c.F_SETFL, @as(c_int, flags | c.O_NONBLOCK));
    const subscribe = "CMD subscribe all\n";
    _ = c.send(fd, subscribe.ptr, subscribe.len, c.MSG_NOSIGNAL);
    g.ipc_fd = fd;
    logMsg("connected to {s}", .{path});
    return true;
}

fn updateSystemAndLog() bool {
    const old_battery = g.battery_percent;
    const old_charging = g.battery_charging;
    const old_network = g.network_present;
    const old_wireless = g.network_wireless;
    const changed = m.updateSystemStatus();
    if (g.battery_percent >= 0 and
        (old_battery != g.battery_percent or old_charging != g.battery_charging))
    {
        logMsg("system: battery {d}%{s}", .{
            g.battery_percent,
            if (g.battery_charging) " charging" else "",
        });
    }
    if (g.network_present and
        (!old_network or old_wireless != g.network_wireless))
    {
        logMsg("system: network {s}", .{g.network_label[0..g.network_label_len]});
    }
    return changed;
}

fn updateTimers(now: i64) void {
    expireNotifications(now);
    if (now >= g.next_clock_ms) {
        if (m.updateClock()) g.bar.dirty = true;
        g.next_clock_ms = now + 1000;
    }
    if (now >= g.next_cpu_ms) {
        m.updateCpu();
        m.updateMem();
        g.bar.dirty = true;
        g.next_cpu_ms = now + 2000;
    }
    if (now >= g.next_system_ms) {
        if (updateSystemAndLog()) g.bar.dirty = true;
        g.next_system_ms = now + 5000;
    }
    if (g.launcher_open and now >= g.next_blink_ms) {
        if (g.overlay) |s| s.dirty = true;
        g.next_blink_ms = now + 500;
    }
}

fn pollTimeout(now: i64) c_int {
    if (g.bg.dirty or g.bar.dirty) return 0;
    if (g.toasts) |s| {
        if (s.dirty) return 0;
    }
    if (g.overlay) |s| {
        if (s.dirty) return 0;
        if (now - g.menu_anim_start < 180) return 16;
    }
    var next = g.next_clock_ms;
    if (g.next_cpu_ms < next) next = g.next_cpu_ms;
    if (g.next_system_ms < next) next = g.next_system_ms;
    if (g.launcher_open and g.next_blink_ms < next) next = g.next_blink_ms;
    var i: usize = 0;
    while (i < g.notification_count) : (i += 1) {
        const expire = g.notifications[i].expire_ms;
        if (expire > 0 and expire < next) next = expire;
    }
    const diff = next - now;
    if (diff <= 0) return 0;
    if (diff > 1000) return 1000;
    return @intCast(diff);
}

fn eventLoop() void {
    const display = g.display.?;
    const fd = c.wl_display_get_fd(display);

    while (g.running) {
        while (c.wl_display_prepare_read(display) != 0) {
            if (c.wl_display_dispatch_pending(display) < 0) {
                g.running = false;
                break;
            }
        }
        if (!g.running) break;
        _ = c.wl_display_flush(display);

        const now = m.nowMs();
        const timeout = pollTimeout(now);
        var fds = [_]c.pollfd{
            .{ .fd = fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = g.ipc_fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = g.clipboard_fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = g.notification_fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = g.media_fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = g.tray_fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = g.audio_fd, .events = c.POLLIN, .revents = 0 },
        };
        const nfds: c.nfds_t = if (g.audio_fd >= 0)
            7
        else if (g.tray_fd >= 0)
            6
        else if (g.media_fd >= 0)
            5
        else if (g.notification_fd >= 0)
            4
        else if (g.clipboard_fd >= 0)
            3
        else if (g.ipc_fd >= 0)
            2
        else
            1;
        const pr = c.poll(&fds, nfds, timeout);
        if (pr < 0) {
            _ = c.wl_display_cancel_read(display);
            continue;
        }

        if (pr > 0 and (fds[0].revents & c.POLLIN) != 0) {
            if (c.wl_display_read_events(display) < 0) {
                g.running = false;
                break;
            }
            if (c.wl_display_dispatch_pending(display) < 0) {
                g.running = false;
                break;
            }
        } else {
            _ = c.wl_display_cancel_read(display);
        }

        if (g.ipc_fd >= 0 and pr > 0 and (fds[1].revents & (c.POLLIN | c.POLLHUP)) != 0) {
            readIpc();
            if (!g.running) break;
        }
        if (g.clipboard_fd >= 0 and pr > 0 and
            (fds[2].revents & (c.POLLIN | c.POLLHUP | c.POLLERR)) != 0)
        {
            readClipboardPipe();
        }
        if (g.notification_fd >= 0 and pr > 0 and
            (fds[3].revents & (c.POLLIN | c.POLLHUP | c.POLLERR)) != 0)
        {
            readNotifications();
        }
        if (g.media_fd >= 0 and pr > 0 and
            (fds[4].revents & (c.POLLIN | c.POLLHUP | c.POLLERR)) != 0)
        {
            readMedia();
        }
        if (g.tray_fd >= 0 and pr > 0 and
            (fds[5].revents & (c.POLLIN | c.POLLHUP | c.POLLERR)) != 0)
        {
            readTray();
        }
        if (g.audio_fd >= 0 and pr > 0 and
            (fds[6].revents & (c.POLLIN | c.POLLHUP | c.POLLERR)) != 0)
        {
            readAudio();
        }

        const now2 = m.nowMs();
        updateTimers(now2);
        if (g.overlay != null) tickAnimation(now2);

        if (g.bg.dirty) draw.drawBackground(&g.bg);
        if (g.bar.dirty) draw.drawBar(&g.bar);
        if (g.toasts) |toasts| {
            if (toasts.dirty) draw.drawToasts(toasts);
        }
        if (g.overlay) |ov| {
            if (ov.dirty) draw.drawOverlay(ov);
        }
        _ = c.wl_display_flush(display);
    }
}

pub fn main() !void {
    g.* = std.mem.zeroes(m.Panel);
    g.running = true;
    g.active_ws = 1;
    g.scale = 1;
    g.ipc_fd = -1;
    g.clipboard_fd = -1;
    g.notification_fd = -1;
    g.media_fd = -1;
    g.tray_fd = -1;
    g.audio_fd = -1;
    _ = c.signal(c.SIGPIPE, c.SIG_IGN);
    if (c.getenv("TESSA_PANEL_OUTPUT")) |name| {
        m.copyTrunc(&g.target_name, &g.target_name_len, std.mem.span(name));
    }
    if (c.getenv("TESSA_PANEL_NOTIFY_OWNER")) |owner| {
        const value = std.mem.span(owner);
        g.notification_owner = !(value.len > 0 and value[0] == '0');
    }
    initListeners();
    m.loadConfig();
    apps.scan(&g.app_list);
    addCustomApps();
    logMsg("loaded {d} desktop entries", .{g.app_list.count});
    m.recomputeResults();
    _ = m.updateClock();
    m.updateCpu();
    m.updateMem();
    _ = updateSystemAndLog();

    g.xkb_ctx = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    if (g.xkb_ctx == null) logMsg("warning: no xkb context", .{});

    g.display = c.wl_display_connect(null) orelse {
        logMsg("cannot connect to Wayland display", .{});
        return error.WaylandConnectFailed;
    };

    g.registry = c.wl_display_get_registry(g.display.?) orelse {
        logMsg("cannot get registry", .{});
        return error.RegistryFailed;
    };
    _ = c.wl_registry_add_listener(g.registry.?, &registry_listener, null);
    _ = c.wl_display_roundtrip(g.display.?);
    _ = c.wl_display_roundtrip(g.display.?);
    selectTargetOutput();

    if (g.compositor == null or g.shm == null or g.layer_shell == null) {
        logMsg("missing required globals (compositor={} shm={} layer_shell={})", .{
            g.compositor != null,
            g.shm != null,
            g.layer_shell != null,
        });
        return error.MissingGlobals;
    }

    if (!connectIpc()) {
        logMsg("cannot connect to tessa IPC socket", .{});
        return error.IpcConnectFailed;
    }

    createChrome();
    if (g.notification_owner) startNotificationService();
    startMediaService();
    startTrayService();
    startAudioService();

    const now = m.nowMs();
    g.next_clock_ms = now + 1000;
    g.next_cpu_ms = now + 2000;
    g.next_system_ms = now + 5000;
    g.next_blink_ms = now + 500;

    eventLoop();

    tessa_notifications_stop();
    g.notification_fd = -1;
    clearNotifications();
    tessa_media_stop();
    g.media_fd = -1;
    tessa_tray_stop();
    g.tray_fd = -1;
    freeTraySurfaces();
    tessa_audio_stop();
    g.audio_fd = -1;
    freeScreenshot();
    resetClipboardRead();
    destroyToasts();
    if (g.data_offer) |offer| {
        c.zwlr_data_control_offer_v1_destroy(offer);
        g.data_offer = null;
    }
    if (g.clipboard_source) |source| {
        c.zwlr_data_control_source_v1_destroy(source);
        g.clipboard_source = null;
    }
    if (g.data_control_device) |device| {
        c.zwlr_data_control_device_v1_destroy(device);
        g.data_control_device = null;
    }
    if (g.overlay) |s| {
        draw.destroyBuffers(s);
        if (s.layer) |ls| c.zwlr_layer_surface_v1_destroy(ls);
        if (s.wl) |wl| c.wl_surface_destroy(wl);
        c.free(s);
        g.overlay = null;
    }
    draw.destroyBuffers(&g.bar);
    draw.destroyBuffers(&g.bg);
    if (g.bar.layer) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (g.bar.wl) |wl| c.wl_surface_destroy(wl);
    if (g.bg.layer) |ls| c.zwlr_layer_surface_v1_destroy(ls);
    if (g.bg.wl) |wl| c.wl_surface_destroy(wl);
    if (g.ipc_fd >= 0) _ = c.close(g.ipc_fd);
    if (g.xkb_state) |s| c.xkb_state_unref(s);
    if (g.xkb_keymap) |k| c.xkb_keymap_unref(k);
    if (g.xkb_ctx) |ctx| c.xkb_context_unref(ctx);
    c.wl_display_disconnect(g.display.?);
}
