const std = @import("std");
const types = @import("types.zig");

const Curve = types.Curve;

pub const DEFAULT_OPEN: Curve = .{};
pub const DEFAULT_CLOSE: Curve = .{
    .kind = .bezier,
    .points = .{ 0.65, 0.0, 0.35, 1.0 },
};

fn spring(damping: f32, frequency: f32) Curve {
    return .{ .kind = .spring, .damping = damping, .frequency = frequency };
}

fn builtin(name: []const u8) ?Curve {
    if (std.mem.eql(u8, name, "linear")) return .{ .points = .{ 0.0, 0.0, 1.0, 1.0 } };
    if (std.mem.eql(u8, name, "ease-out-cubic")) return DEFAULT_OPEN;
    if (std.mem.eql(u8, name, "ease-in-out-cubic")) return .{ .points = .{ 0.65, 0.0, 0.35, 1.0 } };
    if (std.mem.eql(u8, name, "ease-out-quint")) return .{ .points = .{ 0.22, 1.0, 0.36, 1.0 } };
    if (std.mem.eql(u8, name, "ease-in-out-quint")) return .{ .points = .{ 0.83, 0.0, 0.17, 1.0 } };
    if (std.mem.eql(u8, name, "smoothstep")) return DEFAULT_CLOSE;
    if (std.mem.eql(u8, name, "overshoot")) return .{ .points = .{ 0.34, 1.56, 0.64, 1.0 } };
    if (std.mem.eql(u8, name, "spring")) return spring(0.55, 1.6);
    if (std.mem.eql(u8, name, "spring-soft")) return spring(0.9, 0.9);
    if (std.mem.eql(u8, name, "spring-bouncy")) return spring(0.3, 2.0);
    return null;
}

pub fn resolve(cfg: *const types.Config, name: []const u8) ?Curve {
    if (name.len == 0) return null;
    var i: usize = 0;
    while (i < cfg.curve_count) : (i += 1) {
        const curve = &cfg.curves[i];
        if (std.mem.eql(u8, curve.name[0..curve.name_len], name)) return curve.curve;
    }
    if (builtin(name)) |curve| return curve;
    return null;
}

pub fn isKnown(cfg: *const types.Config, name: []const u8) bool {
    return resolve(cfg, name) != null;
}

pub fn open(cfg: *const types.Config) Curve {
    const name = if (cfg.animation_open_curve_len > 0)
        cfg.animation_open_curve[0..cfg.animation_open_curve_len]
    else
        cfg.animation_curve[0..cfg.animation_curve_len];
    return resolve(cfg, name) orelse DEFAULT_OPEN;
}

pub fn workspace(cfg: *const types.Config) Curve {
    const name = if (cfg.animation_workspace_curve_len > 0)
        cfg.animation_workspace_curve[0..cfg.animation_workspace_curve_len]
    else
        cfg.animation_curve[0..cfg.animation_curve_len];
    return resolve(cfg, name) orelse DEFAULT_OPEN;
}

pub fn close(cfg: *const types.Config) Curve {
    const name = if (cfg.animation_close_curve_len > 0)
        cfg.animation_close_curve[0..cfg.animation_close_curve_len]
    else
        "smoothstep";
    return resolve(cfg, name) orelse DEFAULT_CLOSE;
}

pub fn openFor(cfg: *const types.Config, override: types.AnimationOverride) Curve {
    if (override.open_curve_len > 0) {
        if (resolve(cfg, override.open_curve[0..override.open_curve_len])) |curve| return curve;
    }
    if (override.curve_len > 0) {
        if (resolve(cfg, override.curve[0..override.curve_len])) |curve| return curve;
    }
    return open(cfg);
}

pub fn workspaceFor(cfg: *const types.Config, override: types.AnimationOverride) Curve {
    if (override.workspace_curve_len > 0) {
        if (resolve(cfg, override.workspace_curve[0..override.workspace_curve_len])) |curve| return curve;
    }
    if (override.curve_len > 0) {
        if (resolve(cfg, override.curve[0..override.curve_len])) |curve| return curve;
    }
    return workspace(cfg);
}

pub fn closeFor(cfg: *const types.Config, override: types.AnimationOverride) Curve {
    if (override.close_curve_len > 0) {
        if (resolve(cfg, override.close_curve[0..override.close_curve_len])) |curve| return curve;
    }
    return close(cfg);
}

fn component(u: f64, p0: f64, p1: f64, p2: f64, p3: f64) f64 {
    const v = 1.0 - u;
    return v * v * v * p0 +
        3.0 * v * v * u * p1 +
        3.0 * v * u * u * p2 +
        u * u * u * p3;
}

/// Evaluate a cubic-bezier timing function with x1, y1, x2, y2.
fn evaluateBezier(points: [4]f32, t: f64) f64 {
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

/// Normalized damped spring response. `t` is the animation duration fraction;
/// the curve always ends at 1 and overshoots for damping below 1.
fn evaluateSpring(curve: Curve, t: f64) f64 {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    const damping = std.math.clamp(@as(f64, @floatCast(curve.damping)), 0.05, 2.0);
    const frequency = std.math.clamp(@as(f64, @floatCast(curve.frequency)), 0.25, 4.0);
    const k = 2.0 * std.math.pi * frequency;
    const decay = damping * k;
    const denom = 1.0 - @exp(-decay);
    if (denom < 1e-9) return t;
    const raw = 1.0 - @exp(-decay * t) * @cos(k * t);
    return std.math.clamp(raw / denom, 0.0, 2.0);
}

pub fn evaluate(curve: Curve, t: f64) f64 {
    return switch (curve.kind) {
        .bezier => evaluateBezier(curve.points, t),
        .spring => evaluateSpring(curve, t),
    };
}

pub fn kindName(curve: Curve) []const u8 {
    return switch (curve.kind) {
        .bezier => "bezier",
        .spring => "spring",
    };
}
