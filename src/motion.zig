const std = @import("std");
const types = @import("types.zig");

pub const DEFAULT_OPEN = [4]f32{ 0.33, 1.0, 0.68, 1.0 };
pub const DEFAULT_CLOSE = [4]f32{ 0.65, 0.0, 0.35, 1.0 };

fn builtin(name: []const u8) ?[4]f32 {
    if (std.mem.eql(u8, name, "linear")) return .{ 0.0, 0.0, 1.0, 1.0 };
    if (std.mem.eql(u8, name, "ease-out-cubic")) return DEFAULT_OPEN;
    if (std.mem.eql(u8, name, "ease-in-out-cubic")) return .{ 0.65, 0.0, 0.35, 1.0 };
    if (std.mem.eql(u8, name, "ease-out-quint")) return .{ 0.22, 1.0, 0.36, 1.0 };
    if (std.mem.eql(u8, name, "ease-in-out-quint")) return .{ 0.83, 0.0, 0.17, 1.0 };
    if (std.mem.eql(u8, name, "smoothstep")) return DEFAULT_CLOSE;
    if (std.mem.eql(u8, name, "overshoot")) return .{ 0.34, 1.56, 0.64, 1.0 };
    return null;
}

pub fn resolve(cfg: *const types.Config, name: []const u8) ?[4]f32 {
    if (name.len == 0) return null;
    var i: usize = 0;
    while (i < cfg.curve_count) : (i += 1) {
        const curve = &cfg.curves[i];
        if (std.mem.eql(u8, curve.name[0..curve.name_len], name)) return curve.points;
    }
    if (builtin(name)) |points| return points;
    return null;
}

pub fn isKnown(cfg: *const types.Config, name: []const u8) bool {
    return resolve(cfg, name) != null;
}

pub fn open(cfg: *const types.Config) [4]f32 {
    const name = if (cfg.animation_open_curve_len > 0)
        cfg.animation_open_curve[0..cfg.animation_open_curve_len]
    else
        cfg.animation_curve[0..cfg.animation_curve_len];
    return resolve(cfg, name) orelse DEFAULT_OPEN;
}

pub fn workspace(cfg: *const types.Config) [4]f32 {
    const name = if (cfg.animation_workspace_curve_len > 0)
        cfg.animation_workspace_curve[0..cfg.animation_workspace_curve_len]
    else
        cfg.animation_curve[0..cfg.animation_curve_len];
    return resolve(cfg, name) orelse DEFAULT_OPEN;
}

pub fn close(cfg: *const types.Config) [4]f32 {
    const name = if (cfg.animation_close_curve_len > 0)
        cfg.animation_close_curve[0..cfg.animation_close_curve_len]
    else
        "smoothstep";
    return resolve(cfg, name) orelse DEFAULT_CLOSE;
}

fn component(u: f64, p0: f64, p1: f64, p2: f64, p3: f64) f64 {
    const v = 1.0 - u;
    return v * v * v * p0 +
        3.0 * v * v * u * p1 +
        3.0 * v * u * u * p2 +
        u * u * u * p3;
}

/// Evaluate a cubic-bezier timing function with x1, y1, x2, y2.
pub fn evaluate(points: [4]f32, t: f64) f64 {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    var lo: f64 = 0.0;
    var hi: f64 = 1.0;
    var i: usize = 0;
    while (i < 24) : (i += 1) {
        const mid = (lo + hi) / 2.0;
        const x = component(mid, 0.0, @floatCast(points[0]), @floatCast(points[2]), 1.0);
        if (x < t) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    const u = (lo + hi) / 2.0;
    return component(u, 0.0, @floatCast(points[1]), @floatCast(points[3]), 1.0);
}
