//! Shared Sumi geometry. Drawn rectangles and input clipping use these values.
const std = @import("std");

pub const accent = [3]f64{ 240.0 / 255.0, 141.0 / 255.0, 114.0 / 255.0 };
pub const background = [3]f64{ 16.0 / 255.0, 23.0 / 255.0, 28.0 / 255.0 };
pub const surface = [3]f64{ 26.0 / 255.0, 35.0 / 255.0, 41.0 / 255.0 };
pub const foreground = [3]f64{ 240.0 / 255.0, 238.0 / 255.0, 231.0 / 255.0 };
pub const border = [3]f64{ 54.0 / 255.0, 68.0 / 255.0, 75.0 / 255.0 };
pub const launcher_width = 620.0;
pub const launcher_height = 620.0;

pub const Rect = struct {
    x: f64 = 0,
    y: f64 = 0,
    w: f64 = 0,
    h: f64 = 0,

    pub fn intersect(a: Rect, b: Rect) ?Rect {
        const x = @max(a.x, b.x);
        const y = @max(a.y, b.y);
        const w = @min(a.x + a.w, b.x + b.w) - x;
        const h = @min(a.y + a.h, b.y + b.h) - y;
        if (w <= 0 or h <= 0) return null;
        return .{ .x = x, .y = y, .w = w, .h = h };
    }
};

pub const Edge = enum { top, bottom, left, right };

pub fn controlRect(w: f64, h: f64, position: Edge, margin: f64, thickness: f64, side: f64, desired_w: f64, desired_h: f64) Rect {
    // Work inside the free output rectangle for every bar orientation.
    var area = Rect{ .x = 8, .y = 8, .w = @max(0, w - 16), .h = @max(0, h - 16) };
    const reserve = @min(margin + thickness + 12, if (position == .top or position == .bottom) h else w);
    switch (position) {
        .top => {
            area.y = reserve;
            area.h = @max(0, h - reserve - 8);
        },
        .bottom => area.h = @max(0, h - reserve - 8),
        .left => {
            area.x = reserve;
            area.w = @max(0, w - reserve - 8);
        },
        .right => area.w = @max(0, w - reserve - 8),
    }
    const width = @min(desired_w, area.w);
    const height = @min(desired_h, area.h);
    const x = if (position == .left) area.x else std.math.clamp(w - @max(8, side) - width, area.x, area.x + area.w - width);
    const y = if (position == .bottom) area.y + area.h - height else if (position == .top) area.y else std.math.clamp(side, area.y, area.y + area.h - height);
    return .{ .x = x, .y = y, .w = width, .h = height };
}

pub const Section = enum { connectivity, volume, brightness, focus, profile, media, notifications, quick_actions };
pub const section_count = 8;
const heights = [section_count]f64{ 104, 60, 60, 58, 42, 112, 104, 58 };

pub const HomePlan = struct {
    viewport: Rect,
    footer: Rect,
    rows: [section_count]?Rect,
    scroll: f64,
    max_scroll: f64,
    pub fn row(self: HomePlan, section: Section) ?Rect {
        return self.rows[@backingInt(section)];
    }
};

pub fn homePlan(panel: Rect, enabled: [section_count]bool, requested_scroll: f64) HomePlan {
    const pad = @min(24.0, panel.w / 8);
    const viewport = Rect{ .x = panel.x + pad, .y = panel.y + 76, .w = @max(0, panel.w - pad * 2), .h = @max(0, panel.h - 140) };
    var content_h: f64 = 0;
    for (enabled, heights) |on, height| {
        if (on) content_h += height;
    }
    const max_scroll = @max(0, content_h - viewport.h);
    const scroll = std.math.clamp(requested_scroll, 0, max_scroll);
    var plan = HomePlan{ .viewport = viewport, .footer = .{ .x = viewport.x, .y = panel.y + panel.h - 54, .w = viewport.w, .h = 40 }, .rows = @splat(null), .scroll = scroll, .max_scroll = max_scroll };
    var y = viewport.y - scroll;
    for (enabled, heights, 0..) |on, height, i| {
        if (!on) continue;
        plan.rows[i] = .{ .x = viewport.x, .y = y, .w = viewport.w, .h = height };
        y += height;
    }
    return plan;
}

test "controls stay inside small, portrait and desktop outputs at every edge" {
    for ([_][2]f64{ .{ 360, 640 }, .{ 800, 480 }, .{ 1366, 768 }, .{ 1920, 1080 } }) |size| {
        for ([_]Edge{ .top, .bottom, .left, .right }) |edge| {
            const r = controlRect(size[0], size[1], edge, 16, 48, 20, 390, 760);
            try std.testing.expect(r.x >= 0 and r.y >= 0);
            try std.testing.expect(r.x + r.w <= size[0] and r.y + r.h <= size[1]);
        }
    }
}

test "last home action can be reached and clipped actions cannot steal footer clicks" {
    const panel = controlRect(1366, 768, .top, 16, 48, 20, 390, 760);
    const plan = homePlan(panel, @splat(true), 9999);
    const last = plan.row(.quick_actions).?;
    try std.testing.expect(plan.scroll == plan.max_scroll);
    try std.testing.expectApproxEqAbs(plan.viewport.y + plan.viewport.h, last.y + last.h, 0.001);
    try std.testing.expect(plan.viewport.intersect(plan.footer) == null);
    const first_visible = plan.row(.connectivity).?.intersect(plan.viewport).?;
    try std.testing.expect(first_visible.y == plan.viewport.y);
    const hidden = Rect{ .x = plan.viewport.x, .y = plan.viewport.y - 30, .w = 30, .h = 20 };
    try std.testing.expect(hidden.intersect(plan.viewport) == null);
    const crossing = Rect{ .x = plan.viewport.x, .y = plan.viewport.y - 10, .w = 30, .h = 25 };
    const hit = crossing.intersect(plan.viewport).?;
    try std.testing.expectEqual(@as(f64, 15), hit.h);
}

test "disabled features collapse without stale scroll or hits" {
    const panel = Rect{ .x = 10, .y = 80, .w = 390, .h = 650 };
    const plan = homePlan(panel, @splat(false), 100);
    try std.testing.expectEqual(@as(f64, 0), plan.scroll);
    try std.testing.expectEqual(@as(f64, 0), plan.max_scroll);
    for (plan.rows) |row| try std.testing.expect(row == null);
}
