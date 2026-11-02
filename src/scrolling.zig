const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const rules = @import("rules.zig");
const motion = @import("motion.zig");

const Server = types.Server;
const Output = types.Output;
const Client = types.Client;
const ScrollColumn = types.ScrollColumn;
const ScrollWorkspace = types.ScrollWorkspace;
const ColumnWidth = types.ColumnWidth;

pub const Rect = struct {
    client: *Client,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

pub const Arrangement = struct {
    rects: [types.MAX_CLIENTS]Rect,
    count: usize,
};

pub const ColumnMove = enum { left, right, first, last };
pub const WindowMove = enum { up, down };

const Metrics = struct {
    vx: i32,
    vy: i32,
    vw: i32,
    vh: i32,
    content_width: i32,
};

fn emptyArrangement() Arrangement {
    return .{ .rects = undefined, .count = 0 };
}

pub fn init(server: *Server) void {
    for (&server.scroll_columns) |*column| {
        column.* = std.mem.zeroes(ScrollColumn);
    }
}

pub fn initOutput(out: *Output) void {
    for (&out.scroll_ws) |*workspace| {
        workspace.* = std.mem.zeroes(ScrollWorkspace);
    }
}

pub fn isScrolling(out: *Output) bool {
    return out.ws_layouts[out.active_ws - 1] == .scrolling;
}

fn activeWorkspace(out: *Output) *ScrollWorkspace {
    return &out.scroll_ws[out.active_ws - 1];
}

fn columnById(server: *Server, id: u16) ?*ScrollColumn {
    if (id == 0 or @as(usize, id) > server.scroll_columns.len) return null;
    const column = &server.scroll_columns[id - 1];
    if (!column.used) return null;
    return column;
}

fn allocColumn(server: *Server) ?u16 {
    var i: usize = 0;
    while (i < server.scroll_columns.len) : (i += 1) {
        if (!server.scroll_columns[i].used) {
            server.scroll_columns[i] = std.mem.zeroes(ScrollColumn);
            server.scroll_columns[i].used = true;
            const id: u16 = @intCast(i + 1);
            server.scroll_columns[i].id = id;
            server.scroll_columns[i].width = server.config.default_column_width;
            server.scroll_columns[i].restore = server.config.default_column_width;
            server.scroll_columns[i].preset_index = -1;
            return id;
        }
    }
    return null;
}

fn freeColumn(server: *Server, id: u16) void {
    if (id == 0 or @as(usize, id) > server.scroll_columns.len) return;
    server.scroll_columns[id - 1] = std.mem.zeroes(ScrollColumn);
}

fn clientEligible(client: *Client, out: *Output) bool {
    if (!client.mapped or client.output != out) return false;
    if (client.ws != out.active_ws) return false;
    if (client.floating or client.scratchpad or client.special_workspace_len > 0) return false;
    return types.clientVisible(client, out);
}

fn columnIndexOf(ws: *ScrollWorkspace, id: u16) ?usize {
    var i: usize = 0;
    while (i < ws.count) : (i += 1) {
        if (ws.columns[i] == id) return i;
    }
    return null;
}

fn insertColumnAt(ws: *ScrollWorkspace, index: usize, id: u16) void {
    if (ws.count >= ws.columns.len) return;
    const at = @min(index, ws.count);
    var i: usize = ws.count;
    while (i > at) : (i -= 1) {
        ws.columns[i] = ws.columns[i - 1];
    }
    ws.columns[at] = id;
    ws.count += 1;
}

fn removeColumnAt(server: *Server, ws: *ScrollWorkspace, index: usize) void {
    if (index >= ws.count) return;
    const id = ws.columns[index];
    var i: usize = index;
    while (i + 1 < ws.count) : (i += 1) {
        ws.columns[i] = ws.columns[i + 1];
    }
    ws.count -= 1;
    if (ws.count > 0 and ws.focus_index >= ws.count) ws.focus_index = ws.count - 1;
    freeColumn(server, id);
}

fn unlinkClient(client: *Client) void {
    const id = client.scroll_column;
    if (id == 0) return;
    const column = columnById(client.server, id) orelse {
        client.scroll_column = 0;
        client.scroll_prev = null;
        client.scroll_next = null;
        return;
    };
    if (client.scroll_prev) |prev| {
        prev.scroll_next = client.scroll_next;
    } else if (column.first == client) {
        column.first = client.scroll_next;
    }
    if (client.scroll_next) |next| {
        next.scroll_prev = client.scroll_prev;
    } else if (column.last == client) {
        column.last = client.scroll_prev;
    }
    if (column.active == client) column.active = null;
    if (column.count > 0) column.count -= 1;
    client.scroll_column = 0;
    client.scroll_prev = null;
    client.scroll_next = null;
}

fn appendClient(column: *ScrollColumn, client: *Client) void {
    client.scroll_column = column.id;
    client.scroll_prev = column.last;
    client.scroll_next = null;
    if (column.last) |last| {
        last.scroll_next = client;
    } else {
        column.first = client;
    }
    column.last = client;
    column.count += 1;
    if (column.active == null) column.active = client;
}

fn prependClient(column: *ScrollColumn, client: *Client) void {
    client.scroll_column = column.id;
    client.scroll_prev = null;
    client.scroll_next = column.first;
    if (column.first) |first| {
        first.scroll_prev = client;
    } else {
        column.last = client;
    }
    column.first = client;
    column.count += 1;
    if (column.active == null) column.active = client;
}

fn insertClientBefore(column: *ScrollColumn, before: ?*Client, client: *Client) void {
    const target = before orelse {
        appendClient(column, client);
        return;
    };
    client.scroll_column = column.id;
    client.scroll_next = target;
    client.scroll_prev = target.scroll_prev;
    if (target.scroll_prev) |prev| {
        prev.scroll_next = client;
    } else {
        column.first = client;
    }
    target.scroll_prev = client;
    column.count += 1;
    if (column.active == null) column.active = client;
}

fn createColumnFor(out: *Output, client: *Client, index: usize) bool {
    const server = out.server;
    const id = allocColumn(server) orelse return false;
    const column = columnById(server, id) orelse return false;
    appendClient(column, client);
    client.scroll_column = id;
    const ws = activeWorkspace(out);
    insertColumnAt(ws, index, id);
    return true;
}

fn defaultWidthFor(out: *Output) ColumnWidth {
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    return tuning.column_width;
}

fn insertNewClient(out: *Output, client: *Client) void {
    const ws = activeWorkspace(out);
    var index = ws.count;
    if (ws.count > 0 and ws.focus_index < ws.count) {
        index = @min(@as(usize, ws.focus_index) + 1, ws.count);
    }
    if (!createColumnFor(out, client, index)) return;
    if (client.scroll_column != 0) {
        const column = columnById(out.server, client.scroll_column) orelse return;
        column.width = defaultWidthFor(out);
        column.restore = column.width;
    }
    ws.focus_index = index;
    ws.prev_focus_index = ws.focus_index;
}

fn firstVisibleClient(column: *ScrollColumn, out: *Output) ?*Client {
    var current = column.first;
    while (current) |client| {
        if (types.clientVisible(client, out) and !client.fullscreen) return client;
        current = client.scroll_next;
    }
    return null;
}

fn activeClient(column: *ScrollColumn, out: *Output) ?*Client {
    if (column.active) |active| {
        if (active.scroll_column != 0 and types.clientVisible(active, out)) return active;
    }
    return firstVisibleClient(column, out);
}

fn measure(out: *Output, area: c.wlr_box, tuning: rules.Tuning, border: i32) Metrics {
    const outer = tuning.outer_gaps;
    const gap = tuning.gaps;
    const vx = area.x + outer;
    const vy = area.y + outer;
    const vw = @max(1, area.width - outer * 2);
    const vh = @max(1, area.height - outer * 2);
    const ws = activeWorkspace(out);
    const server = out.server;

    var content_width: i32 = 0;
    var i: usize = 0;
    while (i < ws.count) : (i += 1) {
        const id = ws.columns[i];
        const column = columnById(server, id) orelse continue;
        var width = columnWidthPx(column, vw, border);
        if (width < 2 * border + 160) width = 2 * border + 160;
        if (width > vw) width = vw;
        column.width_px = width;
        content_width += width;
        if (i + 1 < ws.count) content_width += gap;
    }

    return .{ .vx = vx, .vy = vy, .vw = vw, .vh = vh, .content_width = content_width };
}

fn columnWidthPx(column: *ScrollColumn, viewport_width: i32, border: i32) i32 {
    if (column.maximized) return viewport_width;
    return switch (column.width.kind) {
        .proportion => @intFromFloat(@round(@as(f32, @floatFromInt(viewport_width)) * column.width.value)),
        .fixed => @as(i32, @intFromFloat(@round(column.width.value))) + border * 2,
    };
}

fn clampView(ws: *ScrollWorkspace, viewport_width: i32, content_width: i32) void {
    const max_offset: f32 = @floatFromInt(@max(0, content_width - viewport_width));
    if (ws.view_offset < 0) ws.view_offset = 0;
    if (ws.view_offset > max_offset) ws.view_offset = max_offset;
    if (ws.view_target < 0) ws.view_target = 0;
    if (ws.view_target > max_offset) ws.view_target = max_offset;
}

fn columnLeft(server: *Server, ws: *ScrollWorkspace, index: usize, gap: i32) i32 {
    var x: i32 = 0;
    var i: usize = 0;
    while (i < index and i < ws.count) : (i += 1) {
        const column = columnById(server, ws.columns[i]) orelse continue;
        x += column.width_px + gap;
    }
    return x;
}

fn updateViewTarget(out: *Output, tuning: rules.Tuning, prev_index: usize) void {
    const ws = activeWorkspace(out);
    if (ws.count == 0) {
        ws.view_target = 0;
        return;
    }
    const border = out.server.config.border_width;
    const metrics = measure(out, out.usable, tuning, border);
    const index = @min(@as(usize, ws.focus_index), ws.count - 1);
    const column = columnById(out.server, ws.columns[index]) orelse return;
    const left = columnLeft(out.server, ws, index, tuning.gaps);
    const right = left + column.width_px;
    const viewport = metrics.vw;

    var target = ws.view_target;
    switch (tuning.center_focused_column) {
        .always => target = @floatFromInt(left + @divTrunc(column.width_px - viewport, 2)),
        .on_overflow => {
            if (prev_index != index and prev_index < ws.count) {
                const prev_column = columnById(out.server, ws.columns[prev_index]) orelse null;
                if (prev_column) |pc| {
                    const prev_left = columnLeft(out.server, ws, prev_index, tuning.gaps);
                    const prev_right = prev_left + pc.width_px;
                    const both_left = @min(prev_left, left);
                    const both_right = @max(prev_right, right);
                    if (both_right - both_left <= viewport) {
                        if (@as(f32, @floatFromInt(left)) < ws.view_offset) target = @floatFromInt(left);
                        if (@as(f32, @floatFromInt(right)) > ws.view_offset + @as(f32, @floatFromInt(viewport))) {
                            target = @floatFromInt(right - viewport);
                        }
                    } else {
                        target = @floatFromInt(left + @divTrunc(column.width_px - viewport, 2));
                    }
                }
            } else {
                if (@as(f32, @floatFromInt(left)) < ws.view_offset) target = @floatFromInt(left);
                if (@as(f32, @floatFromInt(right)) > ws.view_offset + @as(f32, @floatFromInt(viewport))) {
                    target = @floatFromInt(right - viewport);
                }
            }
        },
        .never => {
            if (@as(f32, @floatFromInt(left)) < ws.view_offset) target = @floatFromInt(left);
            if (@as(f32, @floatFromInt(right)) > ws.view_offset + @as(f32, @floatFromInt(viewport))) {
                target = @floatFromInt(right - viewport);
            }
        },
    }
    const max_offset: f32 = @floatFromInt(@max(0, metrics.content_width - viewport));
    if (target < 0) target = 0;
    if (target > max_offset) target = max_offset;
    ws.view_target = target;

    const animations = out.server.config.animations and !out.server.config.reduce_motion;
    const duration = out.server.config.animation_view_ms;
    if (!animations or duration <= 0) {
        ws.view_offset = target;
        ws.view_animating = false;
    } else if (@abs(ws.view_offset - target) < 0.5) {
        ws.view_offset = target;
        ws.view_animating = false;
    } else {
        ws.view_from = ws.view_offset;
        ws.view_start_ms = core.timeNowMs();
        ws.view_animating = true;
    }
}

pub fn ensure(out: *Output) void {
    if (!isScrolling(out)) {
        leave(out);
        return;
    }
    const ws = activeWorkspace(out);
    if (!ws.initialized) enter(out);
    reconcile(out);
}

pub fn enter(out: *Output) void {
    const ws = activeWorkspace(out);
    ws.* = std.mem.zeroes(ScrollWorkspace);
    ws.initialized = true;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    var i: usize = 0;
    while (i < out.server.clients.len) : (i += 1) {
        const client = out.server.clients[i] orelse continue;
        if (!clientEligible(client, out)) continue;
        if (client.scroll_column != 0) continue;
        if (createColumnFor(out, client, ws.count)) {
            if (columnById(out.server, client.scroll_column)) |column| {
                column.width = tuning.column_width;
                column.restore = tuning.column_width;
            }
        }
    }
    if (ws.count > 0) {
        if (out.server.focused) |focused| {
            if (focused.scroll_column != 0) {
                if (columnIndexOf(ws, focused.scroll_column)) |index| ws.focus_index = index;
            }
        }
    }
    updateViewTarget(out, tuning, ws.focus_index);
    ws.view_offset = ws.view_target;
    ws.view_animating = false;
}

fn flatten(out: *Output) void {
    const ws = activeWorkspace(out);
    if (!ws.initialized) return;
    const server = out.server;
    var order: [types.MAX_CLIENTS]?*Client = undefined;
    var order_count: usize = 0;
    var i: usize = 0;
    while (i < ws.count) : (i += 1) {
        const column = columnById(server, ws.columns[i]) orelse continue;
        var client = column.first;
        while (client) |cl| {
            const next = cl.scroll_next;
            if (cl.scroll_column == ws.columns[i] and order_count < order.len) {
                order[order_count] = cl;
                order_count += 1;
            }
            client = next;
        }
    }

    var slots: [types.MAX_CLIENTS]usize = undefined;
    var slot_count: usize = 0;
    i = 0;
    while (i < order_count) : (i += 1) {
        const cl = order[i] orelse continue;
        if (core.clientIndex(server, cl)) |idx| {
            slots[slot_count] = idx;
            slot_count += 1;
        }
    }
    if (slot_count == order_count) {
        // Overwrite the slots that held these clients in flattened order.
        // The slot list is sorted first: assigning to the original per-client
        // slots would preserve the old order rather than applying the new one.
        // Unrelated clients (other outputs/workspaces) keep their slots.
        std.mem.sort(usize, slots[0..slot_count], {}, std.sort.asc(usize));
        i = 0;
        while (i < slot_count) : (i += 1) {
            const cl = order[i] orelse continue;
            server.clients[slots[i]] = cl;
        }
    }

    i = 0;
    while (i < order_count) : (i += 1) {
        const cl = order[i] orelse continue;
        cl.scroll_column = 0;
        cl.scroll_prev = null;
        cl.scroll_next = null;
    }
    i = 0;
    while (i < ws.count) : (i += 1) {
        freeColumn(server, ws.columns[i]);
    }
    ws.* = std.mem.zeroes(ScrollWorkspace);
}

pub fn leave(out: *Output) void {
    flatten(out);
}

fn reconcile(out: *Output) void {
    const ws = activeWorkspace(out);
    var i: usize = 0;
    while (i < out.server.clients.len) : (i += 1) {
        const client = out.server.clients[i] orelse continue;
        if (client.output != out or client.ws != out.active_ws) continue;
        const eligible = clientEligible(client, out);
        if (eligible and client.scroll_column == 0) {
            _ = createColumnFor(out, client, ws.count);
        } else if (!eligible and client.scroll_column != 0) {
            detachClient(client);
        }
    }
    i = 0;
    while (i < ws.count) {
        const id = ws.columns[i];
        const column = columnById(out.server, id);
        if (column == null or column.?.count == 0) {
            removeColumnAt(out.server, ws, i);
            continue;
        }
        i += 1;
    }
    if (ws.focus_index >= ws.count and ws.count > 0) ws.focus_index = ws.count - 1;
}

pub fn onClientMapped(client: *Client) void {
    const out = client.output;
    if (!isScrolling(out)) return;
    ensure(out);
    if (!clientEligible(client, out)) return;
    if (client.scroll_column == 0) {
        insertNewClient(out, client);
        return;
    }
    // enter() may have appended the new window while building the workspace.
    // Niri inserts new windows next to the focused column, so move it there.
    const ws = activeWorkspace(out);
    const index = columnIndexOf(ws, client.scroll_column) orelse return;
    const desired = if (ws.count > 0) @min(@as(usize, ws.focus_index) + 1, ws.count) else 0;
    if (index + 1 == desired or index == desired) return;
    const id = ws.columns[index];
    var i: usize = index;
    while (i + 1 < ws.count) : (i += 1) ws.columns[i] = ws.columns[i + 1];
    ws.count -= 1;
    insertColumnAt(ws, desired, id);
}

pub fn onClientUnmapped(client: *Client) void {
    if (client.scroll_column != 0) detachClient(client);
}

pub fn detachClient(client: *Client) void {
    const out = client.output;
    const id = client.scroll_column;
    if (id == 0) return;
    if (client.ws == 0 or client.ws > out.scroll_ws.len) {
        client.scroll_column = 0;
        client.scroll_prev = null;
        client.scroll_next = null;
        return;
    }
    const ws = &out.scroll_ws[client.ws - 1];
    const index = columnIndexOf(ws, id);
    unlinkClient(client);
    if (index) |idx| {
        const column = columnById(client.server, id);
        if (column == null or column.?.count == 0) removeColumnAt(client.server, ws, idx);
    }
}

pub fn onFocus(client: *Client) void {
    const out = client.output;
    if (!isScrolling(out)) return;
    ensure(out);
    if (client.scroll_column == 0) {
        if (client.group_id != 0) replaceGroupClient(client) else return;
    }
    const ws = activeWorkspace(out);
    const index = columnIndexOf(ws, client.scroll_column) orelse return;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    const previous = ws.focus_index;
    ws.prev_focus_index = previous;
    ws.focus_index = index;
    const column = columnById(out.server, client.scroll_column) orelse return;
    column.active = client;
    updateViewTarget(out, tuning, previous);
}

fn replaceGroupClient(client: *Client) void {
    // When a tab in a group becomes active, keep the group's column position
    // rather than creating a new column at the end.
    const server = client.server;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const other = server.clients[i] orelse continue;
        if (other == client or other.group_id == 0 or other.group_id != client.group_id) continue;
        if (other.scroll_column == 0) continue;
        const column_id = other.scroll_column;
        const column = columnById(server, column_id) orelse continue;
        unlinkClient(other);
        appendClient(column, client);
        client.scroll_column = column_id;
        column.active = client;
        return;
    }
}

pub fn build(out: *Output, area: c.wlr_box, tuning: rules.Tuning, border: i32) Arrangement {
    ensure(out);
    var result = emptyArrangement();
    const ws = activeWorkspace(out);
    if (!ws.initialized or ws.count == 0) {
        ws.content_width = 0;
        ws.viewport_width = 0;
        return result;
    }

    const metrics = measure(out, area, tuning, border);
    ws.content_width = metrics.content_width;
    ws.viewport_width = metrics.vw;
    clampView(ws, metrics.vw, metrics.content_width);

    const offset: i32 = @intFromFloat(@round(ws.view_offset));
    var content_x: i32 = 0;
    var index: usize = 0;
    while (index < ws.count) : (index += 1) {
        const column = columnById(out.server, ws.columns[index]) orelse continue;
        const screen_x = metrics.vx + content_x - offset;
        const column_width = column.width_px;

        var clients: [types.MAX_CLIENTS]?*Client = undefined;
        var count: usize = 0;
        var current = column.first;
        while (current) |client| {
            const next = client.scroll_next;
            if (types.clientVisible(client, out) and !client.fullscreen and count < clients.len) {
                clients[count] = client;
                count += 1;
            }
            current = next;
        }
        column.tabbed = count == 1 and clients[0] != null and clients[0].?.group_id != 0;

        if (count > 0) {
            var y = metrics.vy;
            var ci: usize = 0;
            while (ci < count) : (ci += 1) {
                const client = clients[ci].?;
                var height = metrics.vh;
                if (count > 1) {
                    height = @divTrunc(metrics.vh - tuning.gaps * @as(i32, @intCast(count - 1)), @as(i32, @intCast(count)));
                    if (ci + 1 == count) height = metrics.vy + metrics.vh - y;
                }
                if (height < 1) height = 1;
                const on_screen = screen_x < metrics.vx + metrics.vw and
                    screen_x + column_width > metrics.vx and
                    y < metrics.vy + metrics.vh and y + height > metrics.vy;
                client.on_screen = on_screen;
                if (result.count < result.rects.len) {
                    result.rects[result.count] = .{
                        .client = client,
                        .x = screen_x,
                        .y = y,
                        .w = column_width,
                        .h = height,
                    };
                    result.count += 1;
                }
                y += height + tuning.gaps;
            }
        }

        content_x += column_width + tuning.gaps;
    }

    if (ws.focus_index >= ws.count) ws.focus_index = ws.count - 1;
    return result;
}

pub fn tick(out: *Output, now: i64) bool {
    if (!isScrolling(out)) return false;
    const ws = activeWorkspace(out);
    if (!ws.view_animating) return false;
    const duration = out.server.config.animation_view_ms;
    if (duration <= 0) {
        ws.view_offset = ws.view_target;
        ws.view_animating = false;
        return true;
    }
    const elapsed = now - ws.view_start_ms;
    const progress = std.math.clamp(
        @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(duration)),
        0.0,
        1.0,
    );
    const curve = motion.resolve(&out.server.config, out.server.config.animation_view_curve[0..out.server.config.animation_view_curve_len]) orelse motion.DEFAULT_OPEN;
    const eased: f32 = @floatCast(motion.evaluate(curve, @floatCast(progress)));
    ws.view_offset = ws.view_from + (ws.view_target - ws.view_from) * eased;
    if (progress >= 1.0) {
        ws.view_offset = ws.view_target;
        ws.view_animating = false;
    }
    return true;
}

pub fn snapWorkspace(out: *Output, ws_index: usize) void {
    if (ws_index >= out.scroll_ws.len) return;
    const ws = &out.scroll_ws[ws_index];
    ws.view_offset = ws.view_target;
    ws.view_animating = false;
}

pub fn clearAnimations(server: *Server) void {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        for (&out.scroll_ws) |*ws| {
            if (ws.view_animating) {
                ws.view_offset = ws.view_target;
                ws.view_animating = false;
            }
        }
    }
}

pub fn scrollBy(out: *Output, delta: f32) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (!ws.initialized) return;
    ws.view_target += delta;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    const border = out.server.config.border_width;
    const metrics = measure(out, out.usable, tuning, border);
    clampView(ws, metrics.vw, metrics.content_width);
    if (!out.server.config.animations or out.server.config.reduce_motion) {
        ws.view_offset = ws.view_target;
        ws.view_animating = false;
    } else {
        ws.view_from = ws.view_offset;
        ws.view_start_ms = core.timeNowMs();
        ws.view_animating = @abs(ws.view_offset - ws.view_target) >= 0.5;
    }
}

pub fn centerFocused(out: *Output) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return;
    const index = @min(@as(usize, ws.focus_index), ws.count - 1);
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    const border = out.server.config.border_width;
    const metrics = measure(out, out.usable, tuning, border);
    const column = columnById(out.server, ws.columns[index]) orelse return;
    const left = columnLeft(out.server, ws, index, tuning.gaps);
    ws.view_target = @floatFromInt(left + @divTrunc(column.width_px - metrics.vw, 2));
    clampView(ws, metrics.vw, metrics.content_width);
    if (!out.server.config.animations or out.server.config.reduce_motion) {
        ws.view_offset = ws.view_target;
        ws.view_animating = false;
    } else {
        ws.view_from = ws.view_offset;
        ws.view_start_ms = core.timeNowMs();
        ws.view_animating = @abs(ws.view_offset - ws.view_target) >= 0.5;
    }
}

pub fn focusColumnIndex(out: *Output, index: usize) ?*Client {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return null;
    const target_index = @min(index, ws.count - 1);
    const column = columnById(out.server, ws.columns[target_index]) orelse return null;
    const client = activeClient(column, out) orelse firstVisibleClient(column, out) orelse return null;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    ws.prev_focus_index = ws.focus_index;
    ws.focus_index = target_index;
    column.active = client;
    updateViewTarget(out, tuning, ws.prev_focus_index);
    return client;
}

pub fn focusColumnStep(out: *Output, move: ColumnMove) ?*Client {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return null;
    const current = @min(@as(usize, ws.focus_index), ws.count - 1);
    const index = switch (move) {
        .left => if (current > 0) current - 1 else 0,
        .right => @min(current + 1, ws.count - 1),
        .first => 0,
        .last => ws.count - 1,
    };
    return focusColumnIndex(out, index);
}

pub fn focusWindow(out: *Output, move: WindowMove) ?*Client {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return null;
    const index = @min(@as(usize, ws.focus_index), ws.count - 1);
    const column = columnById(out.server, ws.columns[index]) orelse return null;
    const active = column.active orelse activeClient(column, out) orelse return null;
    var candidate = active.scroll_prev;
    if (move == .down) candidate = active.scroll_next;
    while (candidate) |cl| {
        if (types.clientVisible(cl, out) and !cl.fullscreen) {
            column.active = cl;
            return cl;
        }
        candidate = if (move == .up) cl.scroll_prev else cl.scroll_next;
    }
    return null;
}

pub fn nextVisible(out: *Output, current: ?*Client, step: i32) ?*Client {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return null;
    var list: [types.MAX_CLIENTS]?*Client = undefined;
    var count: usize = 0;
    var i: usize = 0;
    while (i < ws.count) : (i += 1) {
        const column = columnById(out.server, ws.columns[i]) orelse continue;
        var client = column.first;
        while (client) |cl| {
            if (types.clientVisible(cl, out) and !cl.fullscreen and count < list.len) {
                list[count] = cl;
                count += 1;
            }
            client = cl.scroll_next;
        }
    }
    if (count == 0) return null;
    var index: usize = 0;
    if (current) |cur| {
        var k: usize = 0;
        while (k < count) : (k += 1) {
            if (list[k] == cur) {
                index = k;
                break;
            }
        }
    }
    const next: i32 = @as(i32, @intCast(index)) + step;
    const wrapped: usize = @intCast(@mod(next, @as(i32, @intCast(count))));
    return list[wrapped];
}

pub fn moveColumn(out: *Output, move: ColumnMove) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count < 2) return;
    const current = @min(@as(usize, ws.focus_index), ws.count - 1);
    const target = switch (move) {
        .left => if (current > 0) current - 1 else 0,
        .right => @min(current + 1, ws.count - 1),
        .first => 0,
        .last => ws.count - 1,
    };
    if (target == current) return;
    moveColumnTo(out, target);
}

pub fn moveColumnTo(out: *Output, target_index: usize) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count < 2) return;
    const current = @min(@as(usize, ws.focus_index), ws.count - 1);
    const target = @min(target_index, ws.count - 1);
    if (current == target) return;
    const id = ws.columns[current];
    var i: usize = current;
    while (i + 1 < ws.count) : (i += 1) ws.columns[i] = ws.columns[i + 1];
    ws.count -= 1;
    insertColumnAt(ws, target, id);
    ws.prev_focus_index = ws.focus_index;
    ws.focus_index = target;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    updateViewTarget(out, tuning, ws.prev_focus_index);
}

pub fn clientAtIndex(out: *Output, index: usize) ?*Client {
    ensure(out);
    const ws = activeWorkspace(out);
    if (index >= ws.count) return null;
    const column = columnById(out.server, ws.columns[index]) orelse return null;
    return activeClient(column, out) orelse firstVisibleClient(column, out);
}

pub fn tileIndex(client: *Client) usize {
    const id = client.scroll_column;
    if (id == 0) return 0;
    const column = columnById(client.server, id) orelse return 0;
    var index: usize = 0;
    var current = column.first;
    while (current) |cl| {
        if (cl == client) return index;
        index += 1;
        current = cl.scroll_next;
    }
    return 0;
}

pub fn columnX(out: *Output, index: usize) ?i32 {
    ensure(out);
    const ws = activeWorkspace(out);
    if (index >= ws.count) return null;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    const metrics = measure(out, out.usable, tuning, out.server.config.border_width);
    const left = columnLeft(out.server, ws, index, tuning.gaps);
    return metrics.vx + left - @as(i32, @intFromFloat(@round(ws.view_offset)));
}

pub fn dropIndex(out: *Output, screen_x: f64) usize {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return 0;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    const border = out.server.config.border_width;
    const metrics = measure(out, out.usable, tuning, border);
    var x = metrics.vx - @as(i32, @intFromFloat(@round(ws.view_offset)));
    var i: usize = 0;
    while (i < ws.count) : (i += 1) {
        const column = columnById(out.server, ws.columns[i]) orelse continue;
        const center = @as(f64, @floatFromInt(x + @divTrunc(column.width_px, 2)));
        if (screen_x < center) return i;
        x += column.width_px + tuning.gaps;
    }
    return ws.count;
}

pub fn moveWindow(out: *Output, move: WindowMove) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return;
    const index = @min(@as(usize, ws.focus_index), ws.count - 1);
    const id = ws.columns[index];
    const column = columnById(out.server, id) orelse return;
    const active = column.active orelse activeClient(column, out) orelse return;
    if (move == .up) {
        if (active.scroll_prev) |prev| {
            unlinkClient(active);
            insertClientBefore(column, prev, active);
        }
    } else {
        if (active.scroll_next) |next| {
            const after = next.scroll_next;
            unlinkClient(active);
            insertClientBefore(column, after, active);
        }
    }
    column.active = active;
}

fn hasGroupMember(column: *ScrollColumn) bool {
    var client = column.first;
    while (client) |cl| {
        if (cl.group_id != 0) return true;
        client = cl.scroll_next;
    }
    return false;
}

pub fn consumeFocused(out: *Output) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count < 2) return;
    const index = @min(@as(usize, ws.focus_index), ws.count - 1);
    if (index + 1 >= ws.count) return;
    const left = columnById(out.server, ws.columns[index]) orelse return;
    const right = columnById(out.server, ws.columns[index + 1]) orelse return;
    if (hasGroupMember(left) or hasGroupMember(right)) return;
    const client = activeClient(right, out) orelse firstVisibleClient(right, out) orelse return;
    unlinkClient(client);
    appendClient(left, client);
    left.active = client;
    if (right.count == 0) removeColumnAt(out.server, ws, index + 1);
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    updateViewTarget(out, tuning, ws.focus_index);
}

pub fn expelFocused(out: *Output) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return;
    const index = @min(@as(usize, ws.focus_index), ws.count - 1);
    const column = columnById(out.server, ws.columns[index]) orelse return;
    if (column.count <= 1 or hasGroupMember(column)) return;
    var visible_count: usize = 0;
    var bottom: ?*Client = null;
    var current = column.first;
    while (current) |cl| {
        if (types.clientVisible(cl, out) and !cl.fullscreen) {
            visible_count += 1;
            bottom = cl;
        }
        current = cl.scroll_next;
    }
    if (visible_count <= 1) return;
    const expelled = bottom orelse return;
    unlinkClient(expelled);
    const new_index = @min(index + 1, ws.count);
    if (!createColumnFor(out, expelled, new_index)) return;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    updateViewTarget(out, tuning, ws.focus_index);
}

pub fn cycleWidth(out: *Output, back: bool) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return;
    const column = columnById(out.server, ws.columns[@min(@as(usize, ws.focus_index), ws.count - 1)]) orelse return;
    const cfg = &out.server.config;
    if (cfg.column_width_preset_count == 0) return;
    var next: i32 = column.preset_index;
    if (next < 0) {
        next = if (back) @as(i32, @intCast(cfg.column_width_preset_count)) - 1 else 0;
    } else {
        const count: i32 = @intCast(cfg.column_width_preset_count);
        const step: i32 = if (back) -1 else 1;
        next = @mod(next + step, count);
    }
    column.preset_index = @intCast(next);
    column.width = cfg.column_width_presets[@intCast(next)];
    column.maximized = false;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    updateViewTarget(out, tuning, ws.focus_index);
}

pub fn setWidth(out: *Output, width: ColumnWidth) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return;
    const column = columnById(out.server, ws.columns[@min(@as(usize, ws.focus_index), ws.count - 1)]) orelse return;
    column.width = width;
    column.maximized = false;
    column.preset_index = -1;
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    updateViewTarget(out, tuning, ws.focus_index);
}

pub fn toggleMaximize(out: *Output) void {
    ensure(out);
    const ws = activeWorkspace(out);
    if (ws.count == 0) return;
    const column = columnById(out.server, ws.columns[@min(@as(usize, ws.focus_index), ws.count - 1)]) orelse return;
    if (column.maximized) {
        column.maximized = false;
        column.width = column.restore;
    } else {
        column.restore = column.width;
        column.maximized = true;
    }
    const tuning = rules.tuningFor(out.server, out, out.active_ws);
    updateViewTarget(out, tuning, ws.focus_index);
}

pub fn onGroupChanged(out: *Output) void {
    if (!isScrolling(out)) return;
    // Group changes can add or hide windows; rebuild the active workspace from
    // the flat order. Multi-window consume columns are intentionally reset.
    leave(out);
    enter(out);
}

pub fn discardWorkspace(out: *Output, ws_index: usize) void {
    if (ws_index >= out.scroll_ws.len) return;
    const ws = &out.scroll_ws[ws_index];
    var i: usize = 0;
    while (i < ws.count) : (i += 1) {
        const column = columnById(out.server, ws.columns[i]);
        if (column) |col| {
            var current = col.first;
            while (current) |client| {
                const next = client.scroll_next;
                if (client.scroll_column == ws.columns[i]) {
                    client.scroll_column = 0;
                    client.scroll_prev = null;
                    client.scroll_next = null;
                }
                current = next;
            }
        }
        freeColumn(out.server, ws.columns[i]);
    }
    ws.* = std.mem.zeroes(ScrollWorkspace);
}

pub fn deinitOutput(out: *Output) void {
    var i: usize = 0;
    while (i < out.scroll_ws.len) : (i += 1) {
        const ws = &out.scroll_ws[i];
        var k: usize = 0;
        while (k < ws.count) : (k += 1) {
            const column = columnById(out.server, ws.columns[k]);
            if (column) |col| {
                var current = col.first;
                while (current) |client| {
                    const next = client.scroll_next;
                    if (client.scroll_column == ws.columns[k]) {
                        client.scroll_column = 0;
                        client.scroll_prev = null;
                        client.scroll_next = null;
                    }
                    current = next;
                }
            }
            freeColumn(out.server, ws.columns[k]);
        }
        ws.* = std.mem.zeroes(ScrollWorkspace);
    }
}
