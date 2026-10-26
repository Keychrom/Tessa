const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const ime = @import("ime.zig");

const Server = types.Server;
const Client = types.Client;
const Output = types.Output;
const LayerSurface = types.LayerSurface;

const Dir = enum { left, right, up, down };

fn tBase(xdg: *c.wlr_xdg_toplevel) *c.wlr_xdg_surface {
    return @ptrCast(@alignCast(xdg.base));
}
fn tSurface(xdg: *c.wlr_xdg_toplevel) *c.wlr_surface {
    return @ptrCast(@alignCast(tBase(xdg).surface));
}

fn parseDir(arg: []const u8) ?Dir {
    if (std.mem.eql(u8, arg, "left")) return .left;
    if (std.mem.eql(u8, arg, "right")) return .right;
    if (std.mem.eql(u8, arg, "up")) return .up;
    if (std.mem.eql(u8, arg, "down")) return .down;
    return null;
}

fn keyboardEnter(server: *Server, surface: *c.wlr_surface) void {
    const kb_raw = c.wlr_seat_get_keyboard(server.seat) orelse {
        c.wlr_seat_keyboard_clear_focus(server.seat);
        return;
    };
    const kb: *c.wlr_keyboard = @ptrCast(@alignCast(kb_raw));
    c.wlr_seat_keyboard_notify_enter(
        server.seat,
        surface,
        &kb.keycodes[0],
        kb.num_keycodes,
        &kb.modifiers,
    );
}

fn keyboardClear(server: *Server) void {
    if (server.focused_layer == null) c.wlr_seat_keyboard_clear_focus(server.seat);
}

fn clientSurfaceOrigin(cl: *Client) struct { x: i32, y: i32 } {
    const geo = tBase(cl.xdg).geometry;
    const border: i32 = if (cl.fullscreen) 0 else cl.server.config.border_width;
    return .{
        .x = cl.frame.node.x + border - geo.x,
        .y = cl.frame.node.y + border - geo.y,
    };
}

pub fn raiseClient(client: *Client) void {
    const s = client.server;
    const tree: *c.wlr_scene_tree = if (client.fullscreen)
        s.tree_fullscreen
    else if (client.floating)
        s.tree_floating
    else
        s.tree_windows;

    const parent: ?*c.wlr_scene_tree = if (client.frame.node.parent) |p|
        @ptrCast(@alignCast(p))
    else
        null;
    if (parent != tree) {
        c.wlr_scene_node_reparent(&client.frame.node, tree);
    }
    c.wlr_scene_node_raise_to_top(&client.frame.node);
}

pub fn updateBorders(server: *Server) void {
    const accent = server.config.accent_rgb;
    const active = [4]f32{ accent[0], accent[1], accent[2], 1.0 };
    const inactive = [4]f32{ 0.16, 0.20, 0.28, 1.0 };

    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        const is_active = (cl == server.focused) and
            cl.mapped and
            cl.ws == server.active_ws and
            server.focused_layer == null;
        c.wlr_scene_rect_set_color(cl.border_rect, if (is_active) &active else &inactive);
    }
}

pub fn refreshKeyboardFocus(server: *Server) void {
    if (server.focused_layer) |layer| {
        c.wlr_seat_keyboard_clear_focus(server.seat);
        keyboardEnter(server, @ptrCast(@alignCast(layer.wlr.surface)));
    } else if (server.focused) |cl| {
        if (cl.mapped and cl.ws == server.active_ws) {
            c.wlr_seat_keyboard_clear_focus(server.seat);
            keyboardEnter(server, tSurface(cl.xdg));
        } else {
            keyboardClear(server);
        }
    } else {
        keyboardClear(server);
    }
}

pub fn focusClient(server: *Server, target: ?*Client) void {
    if (server.focused_layer != null) {
        server.focused_layer = null;
    }

    if (target) |cl| {
        if (!cl.mapped or cl.ws != server.active_ws) return;
        if (server.focused == cl) {
            raiseClient(cl);
            return;
        }
        if (server.focused) |prev| {
            if (prev != cl) _ = c.wlr_xdg_toplevel_set_activated(prev.xdg, false);
        }
        server.focused = cl;
        server.last_focused[cl.ws] = cl;
        _ = c.wlr_xdg_toplevel_set_activated(cl.xdg, true);
        raiseClient(cl);
        keyboardEnter(server, tSurface(cl.xdg));
        const origin = clientSurfaceOrigin(cl);
        ime.focusSurface(server, tSurface(cl.xdg), origin.x, origin.y);
        updateBorders(server);
        core.markDirty(server);
        return;
    }

    if (server.focused) |prev| {
        _ = c.wlr_xdg_toplevel_set_activated(prev.xdg, false);
    }
    server.focused = null;
    keyboardClear(server);
    ime.focusSurface(server, null, 0, 0);
    updateBorders(server);
    core.markDirty(server);
}

pub fn focusLayer(server: *Server, layer: *LayerSurface) void {
    if (server.focused) |cl| {
        _ = c.wlr_xdg_toplevel_set_activated(cl.xdg, false);
    }
    server.focused_layer = layer;
    keyboardEnter(server, @ptrCast(@alignCast(layer.wlr.surface)));
    const layer_tree: *c.wlr_scene_tree = @ptrCast(@alignCast(layer.scene_layer.tree));
    ime.focusSurface(
        server,
        @ptrCast(@alignCast(layer.wlr.surface)),
        layer.output.full.x + layer_tree.node.x,
        layer.output.full.y + layer_tree.node.y,
    );
    updateBorders(server);
    core.markDirty(server);
}

pub fn restoreFocusAfterLayer(server: *Server, layer: *LayerSurface) void {
    if (server.focused_layer != layer) return;
    server.focused_layer = null;
    if (server.focused) |cl| {
        if (cl.mapped and cl.ws == server.active_ws) {
            _ = c.wlr_xdg_toplevel_set_activated(cl.xdg, true);
            keyboardEnter(server, tSurface(cl.xdg));
            const origin = clientSurfaceOrigin(cl);
            ime.focusSurface(server, tSurface(cl.xdg), origin.x, origin.y);
            updateBorders(server);
            core.markDirty(server);
            return;
        }
    }
    keyboardClear(server);
    ime.focusSurface(server, null, 0, 0);
    updateBorders(server);
    core.markDirty(server);
}

fn applyFrame(client: *Client, x: i32, y: i32, w: i32, h: i32, border: i32, enabled_border: bool) void {
    client.x = x;
    client.y = y;
    client.w = @max(1, w);
    client.h = @max(1, h);

    c.wlr_scene_node_set_position(&client.frame.node, x, y);

    if (enabled_border and border > 0) {
        c.wlr_scene_node_set_enabled(&client.border_rect.node, true);
        c.wlr_scene_node_set_position(&client.border_rect.node, 0, 0);
        c.wlr_scene_rect_set_size(client.border_rect, client.w, client.h);
    } else {
        c.wlr_scene_node_set_enabled(&client.border_rect.node, false);
    }

    const geo = tBase(client.xdg).geometry;
    const gx = geo.x;
    const gy = geo.y;
    const b = if (enabled_border) border else 0;
    c.wlr_scene_node_set_position(&client.surface_tree.node, b - gx, b - gy);

    const cw = @max(1, client.w - b * 2);
    const ch = @max(1, client.h - b * 2);
    if (cw != client.xdg.current.width or ch != client.xdg.current.height) {
        _ = c.wlr_xdg_toplevel_set_size(client.xdg, cw, ch);
    }
}

fn initFloatRect(client: *Client, out: *Output) void {
    const area = if (out.usable.width > 100) out.usable else out.full;
    var fw: i32 = @intFromFloat(@as(f32, @floatFromInt(area.width)) * 0.55);
    var fh: i32 = @intFromFloat(@as(f32, @floatFromInt(area.height)) * 0.60);
    fw = std.math.clamp(fw, 480, 1100);
    fh = std.math.clamp(fh, 320, 760);
    client.float_w = fw;
    client.float_h = fh;
    client.float_x = area.x + @divTrunc(area.width - fw, 2);
    client.float_y = area.y + @divTrunc(area.height - fh, 2);
}

fn applyFloating(client: *Client, out: *Output) void {
    if (client.float_w <= 0 or client.float_h <= 0) initFloatRect(client, out);
    const border = client.server.config.border_width;

    const full = out.full;
    if (full.width > 0 and full.height > 0) {
        const max_x = full.x + full.width - client.float_w;
        const max_y = full.y + full.height - client.float_h;
        client.float_x = std.math.clamp(client.float_x, full.x, @max(full.x, max_x));
        client.float_y = std.math.clamp(client.float_y, full.y, @max(full.y, max_y));
    }

    applyFrame(client, client.float_x, client.float_y, client.float_w, client.float_h, border, true);
}

fn applyFullscreen(client: *Client, out: *Output) void {
    var full = out.full;
    if (full.width <= 0 or full.height <= 0) {
        c.wlr_output_layout_get_box(out.server.output_layout, out.wlr, &full);
    }
    applyFrame(client, full.x, full.y, full.width, full.height, 0, false);
}

pub fn arrangeOutput(server: *Server, out: *Output) void {
    var area = out.usable;
    if (area.width < 50 or area.height < 50) area = out.full;

    var tiles: [types.MAX_CLIENTS]?*Client = undefined;
    var tile_count: usize = 0;

    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.output != out) continue;

        const visible = cl.mapped and cl.ws == server.active_ws;
        c.wlr_scene_node_set_enabled(&cl.frame.node, visible);
        if (!visible) continue;

        if (cl.fullscreen) {
            applyFullscreen(cl, out);
            raiseClient(cl);
        } else if (cl.floating) {
            applyFloating(cl, out);
        } else if (tile_count < tiles.len) {
            tiles[tile_count] = cl;
            tile_count += 1;
        }
    }

    if (tile_count > 0) {
        const cfg = &server.config;
        const border = cfg.border_width;
        const outer = cfg.outer_gaps;
        const gap = cfg.gaps;

        const ux = area.x + outer;
        const uy = area.y + outer;
        const uw = area.width - outer * 2;
        const uh = area.height - outer * 2;

        if (uw > 20 and uh > 20) {
            if (tile_count == 1) {
                applyFrame(tiles[0].?, ux, uy, uw, uh, border, true);
            } else if (cfg.layout_mode == .mosaic and tile_count <= 8) {
                var rx = ux;
                var ry = uy;
                var rw = uw;
                var rh = uh;
                var dir: u2 = 0;
                var mi: usize = 0;
                while (mi < tile_count) : (mi += 1) {
                    if (mi == tile_count - 1 or rw < 160 or rh < 160) {
                        applyFrame(tiles[mi].?, rx, ry, rw, rh, border, true);
                        mi += 1;
                        while (mi < tile_count) : (mi += 1) {
                            applyFrame(tiles[mi].?, rx, ry, rw, rh, border, true);
                        }
                        break;
                    }
                    if (dir == 0 or dir == 2) {
                        const slice = @max(120, @as(i32, @intFromFloat(
                            @as(f32, @floatFromInt(rw - gap)) * 0.62,
                        )));
                        if (dir == 0) {
                            applyFrame(tiles[mi].?, rx, ry, slice, rh, border, true);
                            rx += slice + gap;
                            rw -= slice + gap;
                        } else {
                            applyFrame(tiles[mi].?, rx + rw - slice, ry, slice, rh, border, true);
                            rw -= slice + gap;
                        }
                    } else {
                        const slice = @max(120, @as(i32, @intFromFloat(
                            @as(f32, @floatFromInt(rh - gap)) * 0.62,
                        )));
                        if (dir == 1) {
                            applyFrame(tiles[mi].?, rx, ry, rw, slice, border, true);
                            ry += slice + gap;
                            rh -= slice + gap;
                        } else {
                            applyFrame(tiles[mi].?, rx, ry + rh - slice, rw, slice, border, true);
                            rh -= slice + gap;
                        }
                    }
                    dir = @intCast((@as(u32, dir) + 1) % 4);
                }
            } else {
                const gap_total = gap;
                var master_w: i32 = 0;
                if (uw > gap_total + 160) {
                    master_w = @intFromFloat(@round(
                        @as(f32, @floatFromInt(uw - gap_total)) * cfg.master_ratio,
                    ));
                    if (master_w < 100) master_w = 100;
                    if (uw - gap_total - master_w < 100)
                        master_w = @divTrunc(uw - gap_total, 2);
                } else {
                    master_w = @divTrunc(uw - gap_total, 2);
                }
                const stack_x = ux + master_w + gap_total;
                const stack_w = @max(1, uw - master_w - gap_total);
                const stack_n = tile_count - 1;

                applyFrame(tiles[0].?, ux, uy, master_w, uh, border, true);

                const stack_total = uh - gap * @as(i32, @intCast(stack_n - 1));
                const each: i32 = @divTrunc(stack_total, @as(i32, @intCast(stack_n)));
                var sy = uy;
                var j: usize = 1;
                while (j < tile_count) : (j += 1) {
                    const is_last = (j == tile_count - 1);
                    var h = each;
                    if (is_last) h = uy + uh - sy;
                    if (h < 1) h = 1;
                    applyFrame(tiles[j].?, stack_x, sy, stack_w, h, border, true);
                    sy += h + gap;
                }
            }
        }
    }

    if (server.focused) |fc| {
        if (fc.output == out and fc.mapped and fc.ws == server.active_ws) {
            raiseClient(fc);
        }
    }

    updateBorders(server);
}

pub fn arrangeAll(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        if (server.outputs[i]) |out| arrangeOutput(server, out);
    }
}

pub fn setProvisionalSize(client: *Client) void {
    const out = client.output;
    var area = out.usable;
    if (area.width < 50 or area.height < 50) area = out.full;
    const cfg = &client.server.config;
    const b = cfg.border_width;
    const outer = cfg.outer_gaps;
    const w = @max(1, area.width - outer * 2 - b * 2);
    const h = @max(1, area.height - outer * 2 - b * 2);
    _ = c.wlr_xdg_toplevel_set_size(client.xdg, w, h);
}

fn visibleClientsOnOutput(server: *Server, out: *Output, out_list: []?*Client) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.mapped and cl.ws == server.active_ws and cl.output == out) {
            if (n < out_list.len) {
                out_list[n] = cl;
                n += 1;
            }
        }
    }
    return n;
}

fn centerX(cl: *Client) i32 {
    return cl.x + @divTrunc(cl.w, 2);
}
fn centerY(cl: *Client) i32 {
    return cl.y + @divTrunc(cl.h, 2);
}

fn findDirectional(server: *Server, from: *Client, dir: Dir, same_output: bool) ?*Client {
    var list: [types.MAX_CLIENTS]?*Client = undefined;
    const n = visibleClientsOnOutput(server, from.output, &list);
    const fx = centerX(from);
    const fy = centerY(from);

    var best: ?*Client = null;
    var best_score: f64 = std.math.floatMax(f64);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const cl = list[i].?;
        if (cl == from) continue;
        if (same_output and cl.output != from.output) continue;
        const dx = centerX(cl) - fx;
        const dy = centerY(cl) - fy;

        var primary: f64 = 0;
        var secondary: f64 = 0;
        switch (dir) {
            .left => {
                if (dx >= -8) continue;
                primary = -dx;
                secondary = @abs(@as(f64, @floatFromInt(dy)));
            },
            .right => {
                if (dx <= 8) continue;
                primary = dx;
                secondary = @abs(@as(f64, @floatFromInt(dy)));
            },
            .up => {
                if (dy >= -8) continue;
                primary = -dy;
                secondary = @abs(@as(f64, @floatFromInt(dx)));
            },
            .down => {
                if (dy <= 8) continue;
                primary = dy;
                secondary = @abs(@as(f64, @floatFromInt(dx)));
            },
        }
        const score = primary + secondary * 0.45;
        if (score < best_score) {
            best_score = score;
            best = cl;
        }
    }
    return best;
}

pub fn focusDirection(server: *Server, arg: []const u8) void {
    const dir = parseDir(arg) orelse return;
    const cur = server.focused orelse {
        focusFirst(server);
        return;
    };
    if (findDirectional(server, cur, dir, true)) |target| {
        focusClient(server, target);
    }
}

pub fn moveDirection(server: *Server, arg: []const u8) void {
    const dir = parseDir(arg) orelse return;
    const cur = server.focused orelse return;

    if (cur.floating) {
        const step: i32 = 30;
        switch (dir) {
            .left => cur.float_x -= step,
            .right => cur.float_x += step,
            .up => cur.float_y -= step,
            .down => cur.float_y += step,
        }
        arrangeOutput(server, cur.output);
        core.markDirty(server);
        return;
    }

    const target = findDirectional(server, cur, dir, true) orelse return;
    if (target == cur) return;

    const i = core.clientIndex(server, cur) orelse return;
    const j = core.clientIndex(server, target) orelse return;
    server.clients[i] = target;
    server.clients[j] = cur;
    arrangeAll(server);
    focusClient(server, cur);
    core.markDirty(server);
}

pub fn focusNext(server: *Server, step: i32) void {
    var list: [types.MAX_CLIENTS]?*Client = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.mapped and cl.ws == server.active_ws) {
            list[n] = cl;
            n += 1;
        }
    }
    if (n == 0) return;

    var cur_idx: ?usize = null;
    if (server.focused) |fc| {
        var k: usize = 0;
        while (k < n) : (k += 1) {
            if (list[k] == fc) {
                cur_idx = k;
                break;
            }
        }
    }
    var next: usize = 0;
    if (cur_idx) |ci| {
        const nn: i32 = @as(i32, @intCast(ci)) + step;
        next = @intCast(@mod(nn, @as(i32, @intCast(n))));
    }
    focusClient(server, list[next]);
}

pub fn focusFirst(server: *Server) void {
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const cl = server.clients[i] orelse continue;
        if (cl.mapped and cl.ws == server.active_ws) {
            focusClient(server, cl);
            return;
        }
    }
    focusClient(server, null);
}

pub fn switchWorkspace(server: *Server, ws: usize) void {
    if (ws < 1 or ws > types.WS_COUNT) return;
    server.active_ws = ws;
    arrangeAll(server);

    var target: ?*Client = null;
    if (server.last_focused[ws]) |cl| {
        if (cl.mapped and cl.ws == ws) target = cl;
    }
    if (target == null) {
        var i: usize = 0;
        while (i < server.clients.len) : (i += 1) {
            const cl = server.clients[i] orelse continue;
            if (cl.mapped and cl.ws == ws) {
                target = cl;
                break;
            }
        }
    }
    focusClient(server, target);
    core.markDirty(server);
}

pub fn moveToWorkspace(server: *Server, ws: usize) void {
    if (ws < 1 or ws > types.WS_COUNT) return;
    const cl = server.focused orelse return;
    const old_ws = cl.ws;
    cl.ws = ws;
    server.last_focused[ws] = cl;
    if (old_ws != ws) {
        if (server.last_focused[old_ws] == cl) server.last_focused[old_ws] = null;
        var next: ?*Client = null;
        var i: usize = 0;
        while (i < server.clients.len) : (i += 1) {
            const other = server.clients[i] orelse continue;
            if (other != cl and other.mapped and other.ws == old_ws) {
                next = other;
                break;
            }
        }
        focusClient(server, next);
    }
    arrangeAll(server);
    core.markDirty(server);
}

pub fn toggleFloat(server: *Server) void {
    const cl = server.focused orelse return;
    cl.floating = !cl.floating;
    arrangeOutput(server, cl.output);
    focusClient(server, cl);
    core.markDirty(server);
}

pub fn toggleFullscreen(server: *Server) void {
    const cl = server.focused orelse return;
    cl.fullscreen = !cl.fullscreen;
    _ = c.wlr_xdg_toplevel_set_fullscreen(cl.xdg, cl.fullscreen);
    arrangeOutput(server, cl.output);
    focusClient(server, cl);
    core.markDirty(server);
}

pub fn closeFocused(server: *Server) void {
    const cl = server.focused orelse return;
    c.wlr_xdg_toplevel_send_close(cl.xdg);
}

pub fn toggleLayout(server: *Server) void {
    server.config.layout_mode = if (server.config.layout_mode == .master) .mosaic else .master;
    arrangeAll(server);
    core.markDirty(server);
    core.logInfo("layout: {s}", .{@tagName(server.config.layout_mode)});
}

pub fn adjustRatio(server: *Server, delta: f32) void {
    server.config.master_ratio = std.math.clamp(server.config.master_ratio + delta, 0.15, 0.9);
    arrangeAll(server);
    core.markDirty(server);
}

pub fn beginInteractive(client: *Client, mode: types.CursorMode, edges: u32) void {
    const s = client.server;
    s.grabbed = client;
    s.cursor_mode = mode;
    if (mode == .move) {
        s.grab_x = s.cursor.x - @as(f64, @floatFromInt(client.frame.node.x));
        s.grab_y = s.cursor.y - @as(f64, @floatFromInt(client.frame.node.y));
    } else {
        const g = tBase(client.xdg).geometry;
        const border = s.config.border_width;
        const bx = @as(f64, @floatFromInt(client.x + border + g.x)) +
            (if (edges & c.WLR_EDGE_RIGHT != 0) @as(f64, @floatFromInt(g.width)) else 0);
        const by = @as(f64, @floatFromInt(client.y + border + g.y)) +
            (if (edges & c.WLR_EDGE_BOTTOM != 0) @as(f64, @floatFromInt(g.height)) else 0);
        s.grab_x = s.cursor.x - bx;
        s.grab_y = s.cursor.y - by;
        s.grab_box = .{
            .x = client.x,
            .y = client.y,
            .width = client.w,
            .height = client.h,
        };
        s.resize_edges = edges;
    }
}

pub fn resetInteractive(server: *Server) void {
    server.grabbed = null;
    server.cursor_mode = .passthrough;
}

pub fn updateInteractiveMove(server: *Server) void {
    const cl = server.grabbed orelse return;
    cl.float_x = @intFromFloat(@round(server.cursor.x - server.grab_x));
    cl.float_y = @intFromFloat(@round(server.cursor.y - server.grab_y));
    c.wlr_scene_node_set_position(&cl.frame.node, cl.float_x, cl.float_y);
    cl.x = cl.float_x;
    cl.y = cl.float_y;
}

pub fn updateInteractiveResize(server: *Server) void {
    const cl = server.grabbed orelse return;
    const bx: i32 = @intFromFloat(@round(server.cursor.x - server.grab_x));
    const by: i32 = @intFromFloat(@round(server.cursor.y - server.grab_y));

    var left = server.grab_box.x;
    var right = server.grab_box.x + server.grab_box.width;
    var top = server.grab_box.y;
    var bottom = server.grab_box.y + server.grab_box.height;

    if (server.resize_edges & c.WLR_EDGE_TOP != 0) top = by;
    if (server.resize_edges & c.WLR_EDGE_BOTTOM != 0) bottom = by;
    if (server.resize_edges & c.WLR_EDGE_LEFT != 0) left = bx;
    if (server.resize_edges & c.WLR_EDGE_RIGHT != 0) right = bx;

    const min: i32 = 200;
    if (right - left < min) {
        if (server.resize_edges & c.WLR_EDGE_LEFT != 0) {
            left = right - min;
        } else {
            right = left + min;
        }
    }
    if (bottom - top < min) {
        if (server.resize_edges & c.WLR_EDGE_TOP != 0) {
            top = bottom - min;
        } else {
            bottom = top + min;
        }
    }

    cl.float_x = left;
    cl.float_y = top;
    cl.float_w = right - left;
    cl.float_h = bottom - top;
    applyFrame(cl, cl.float_x, cl.float_y, cl.float_w, cl.float_h, server.config.border_width, true);
}
