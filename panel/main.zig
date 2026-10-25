const std = @import("std");
const c = @import("c.zig").c;
const m = @import("model.zig");
const draw = @import("draw.zig");
const apps = @import("apps.zig");

const g = &m.g;

var registry_listener: c.wl_registry_listener = undefined;
var seat_listener: c.wl_seat_listener = undefined;
var keyboard_listener: c.wl_keyboard_listener = undefined;
var pointer_listener: c.wl_pointer_listener = undefined;
var shm_listener: c.wl_shm_listener = undefined;

fn logMsg(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("tessa-panel: " ++ fmt ++ "\n", args);
}

fn surfaceFor(wl_surface: ?*c.wl_surface) ?*m.Surface {
    if (wl_surface == null) return null;
    if (g.bar.wl == wl_surface) return &g.bar;
    if (g.bg.wl == wl_surface) return &g.bg;
    if (g.overlay) |ov| {
        if (ov.wl == wl_surface) return ov;
    }
    return null;
}

fn onLayerConfigure(data: ?*anyopaque, layer: ?*c.zwlr_layer_surface_v1, serial: u32, width: u32, height: u32) callconv(.c) void {
    _ = layer;
    const s: *m.Surface = @ptrCast(@alignCast(data.?));
    if (s.layer) |ls| c.zwlr_layer_surface_v1_ack_configure(ls, serial);
    draw.configureSurface(s, width, height);
}

fn destroyOverlay() void {
    const s = g.overlay orelse return;
    g.overlay = null;
    g.launcher_open = false;
    g.menu_anim = 0;
    if (g.pointer_surface == s) g.pointer_surface = null;
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
    } else {
        g.running = false;
    }
}

fn createLayerSurface(
    s: *m.Surface,
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
    c.wl_surface_set_buffer_scale(wl, 1);

    const ls = c.zwlr_layer_shell_v1_get_layer_surface(shell, wl, null, layer, namespace) orelse {
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

fn createChrome() void {
    _ = createLayerSurface(
        &g.bg,
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

    _ = createLayerSurface(
        &g.bar,
        .bar,
        @intCast(c.ZWLR_LAYER_SHELL_V1_LAYER_TOP),
        @intCast(c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT),
        0,
        @intCast(m.BAR_HEIGHT),
        12,
        16,
        0,
        16,
        @intCast(m.BAR_HEIGHT),
        0,
        "tessa-bar",
    );
}

fn openLauncher(query_arg: []const u8) void {
    if (g.overlay != null and g.launcher_open) {
        if (query_arg.len == 0) {
            closeLauncher();
            return;
        }
        m.setQuery(query_arg);
        g.overlay.?.dirty = true;
        return;
    }

    if (g.overlay == null) {
        const s = @as(*m.Surface, @ptrCast(@alignCast(c.calloc(1, @sizeOf(m.Surface)).?)));
        s.* = std.mem.zeroes(m.Surface);
        if (!createLayerSurface(
            s,
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
            "tessa-launcher",
        )) {
            c.free(s);
            return;
        }
        g.overlay = s;
    }

    g.launcher_open = true;
    g.hover = .{};
    g.overlay_row_hover = 999;
    g.menu_from = g.menu_anim;
    g.menu_target = 1;
    g.menu_anim_start = m.nowMs();
    g.next_blink_ms = m.nowMs() + 500;

    m.setQuery(query_arg);
    g.overlay.?.dirty = true;
    g.bar.dirty = true;
}

fn closeLauncher() void {
    if (g.overlay == null or !g.launcher_open) return;
    g.launcher_open = false;
    g.menu_from = g.menu_anim;
    g.menu_target = 0;
    g.menu_anim_start = m.nowMs();
    g.overlay.?.dirty = true;
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
    closeLauncher();
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
    g.next_blink_ms = m.nowMs() + 500;
}

fn onKeyboardKeymap(data: ?*anyopaque, keyboard: ?*c.wl_keyboard, format: u32, fd: c_int, size: u32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    defer _ = c.close(fd);
    if (format != 1 or size == 0) return;
    const map = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (map == null or @intFromPtr(map.?) == std.math.maxInt(usize)) return;
    defer _ = c.munmap(map, size);

    const ctx = g.xkb_ctx orelse return;
    const keymap = c.xkb_keymap_new_from_string(
        ctx,
        @ptrCast(map.?),
        c.XKB_KEYMAP_FORMAT_TEXT_V1,
        @intCast(size),
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
    if (state != 1 or !g.launcher_open) return;
    const xstate = g.xkb_state orelse return;
    const keycode: c.xkb_keycode_t = key + 8;
    const sym = c.xkb_state_key_get_one_sym(xstate, keycode);

    if (sym == c.XKB_KEY_Escape) {
        closeLauncher();
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

fn onSeatCapabilities(data: ?*anyopaque, seat: ?*c.wl_seat, caps: u32) callconv(.c) void {
    _ = data;
    if (seat == null) return;
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
    updateHover();
}

fn onPointerLeave(data: ?*anyopaque, pointer: ?*c.wl_pointer, serial: u32, surface: ?*c.wl_surface) callconv(.c) void {
    _ = data;
    _ = pointer;
    _ = serial;
    const s = surfaceFor(surface) orelse return;
    if (g.pointer_surface == s) g.pointer_surface = null;
    updateHover();
}

fn onPointerMotion(data: ?*anyopaque, pointer: ?*c.wl_pointer, time: u32, sx: c.wl_fixed_t, sy: c.wl_fixed_t) callconv(.c) void {
    _ = data;
    _ = pointer;
    _ = time;
    if (g.pointer_surface == null) return;
    g.pointer_x = c.wl_fixed_to_double(sx);
    g.pointer_y = c.wl_fixed_to_double(sy);
    updateHover();
}

fn onPointerButton(data: ?*anyopaque, pointer: ?*c.wl_pointer, serial: u32, time: u32, button: u32, state: u32) callconv(.c) void {
    _ = data;
    _ = pointer;
    _ = serial;
    _ = time;
    if (state != 1) return;
    const s = g.pointer_surface orelse return;

    if (s == &g.bar) {
        const h = hitBar(g.pointer_x, g.pointer_y);
        switch (h.kind) {
            .menu => openLauncher(""),
            .workspace => {
                if (button == 0x110) sendCmd("CMD workspace {d}\n", .{h.value});
            },
            .window => {
                if (button == 0x110) {
                    sendCmd("CMD focus {d}\n", .{h.value});
                } else if (button == 0x111) {
                    sendCmd("CMD close {d}\n", .{h.value});
                }
            },
            else => {},
        }
    } else if (g.overlay) |ov| {
        if (s != ov) return;
        if (button == 0x111) {
            closeLauncher();
            return;
        }
        if (!hitIn(&g.overlay_panel, g.pointer_x, g.pointer_y)) {
            closeLauncher();
            return;
        }
        const h = hitOverlay(g.pointer_x, g.pointer_y);
        if (h.kind == .app) {
            launchApp(h.value);
        }
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
        sendCmd("CMD workspace {d}\n", .{ws});
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
}

fn handleStateLine(line: []const u8) void {
    if (std.mem.eql(u8, line, "STATE")) {
        g.window_count = 0;
        g.occ = [_]u32{0} ** 10;
        g.focused_id = 0;
        g.ipc_in_state = true;
        return;
    }
    if (std.mem.eql(u8, line, "END")) {
        g.ipc_in_state = false;
        g.bar.dirty = true;
        if (c.getenv("TESSA_PANEL_DEBUG") != null) {
            logMsg("state: ws={d} windows={d}", .{ g.active_ws, g.window_count });
        }
        return;
    }
    if (!g.ipc_in_state) return;

    if (std.mem.startsWith(u8, line, "WIN\t")) {
        var fields: [8][]const u8 = undefined;
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
        if (count < 8) return;
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
        g.window_count += 1;
        return;
    }

    var it = std.mem.tokenizeAny(u8, line, " \t");
    const cmd = it.next() orelse return;
    if (std.mem.eql(u8, cmd, "ACTIVE")) {
        const s = it.next() orelse return;
        const v = std.fmt.parseInt(usize, s, 10) catch return;
        if (v >= 1 and v <= 9) g.active_ws = v;
    } else if (std.mem.eql(u8, cmd, "OCC")) {
        const ws_s = it.next() orelse return;
        const n_s = it.next() orelse return;
        const ws = std.fmt.parseInt(usize, ws_s, 10) catch return;
        const n = std.fmt.parseInt(u32, n_s, 10) catch return;
        if (ws >= 1 and ws <= 9) g.occ[ws] = n;
    } else if (std.mem.eql(u8, cmd, "FOCUSED")) {
        const s = it.next() orelse return;
        g.focused_id = std.fmt.parseInt(u64, s, 10) catch 0;
    }
}

fn onEvent(line: []const u8) void {
    var it = std.mem.tokenizeAny(u8, line, " \t");
    const tag = it.next() orelse return;
    if (!std.mem.eql(u8, tag, "EVENT")) return;
    const name = it.next() orelse return;
    if (std.mem.eql(u8, name, "launcher")) {
        const rest = it.rest();
        openLauncher(std.mem.trim(u8, rest, " \t"));
    }
}

fn handleIpcLine(line: []const u8) void {
    if (line.len == 0) return;
    if (std.mem.startsWith(u8, line, "EVENT ")) {
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
    g.ipc_fd = fd;
    logMsg("connected to {s}", .{path});
    return true;
}

fn updateTimers(now: i64) void {
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
    if (g.launcher_open and now >= g.next_blink_ms) {
        if (g.overlay) |s| s.dirty = true;
        g.next_blink_ms = now + 500;
    }
}

fn pollTimeout(now: i64) c_int {
    if (g.bg.dirty or g.bar.dirty) return 0;
    if (g.overlay) |s| {
        if (s.dirty) return 0;
        if (now - g.menu_anim_start < 180) return 16;
    }
    var next = g.next_clock_ms;
    if (g.next_cpu_ms < next) next = g.next_cpu_ms;
    if (g.launcher_open and g.next_blink_ms < next) next = g.next_blink_ms;
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
        };
        const nfds: c.nfds_t = if (g.ipc_fd >= 0) 2 else 1;
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

        const now2 = m.nowMs();
        updateTimers(now2);
        if (g.overlay != null) tickAnimation(now2);

        if (g.bg.dirty) draw.drawBackground(&g.bg);
        if (g.bar.dirty) draw.drawBar(&g.bar);
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
    initListeners();
    m.loadConfig();
    apps.scan(&g.app_list);
    logMsg("loaded {d} desktop entries", .{g.app_list.count});
    m.recomputeResults();
    _ = m.updateClock();
    m.updateCpu();
    m.updateMem();

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

    const now = m.nowMs();
    g.next_clock_ms = now + 1000;
    g.next_cpu_ms = now + 2000;
    g.next_blink_ms = now + 500;

    eventLoop();

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
