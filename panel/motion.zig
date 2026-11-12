const std = @import("std");

pub fn clamp01(t: f64) f64 {
    return std.math.clamp(t, 0.0, 1.0);
}

pub fn lerp(a: f64, b: f64, t: f64) f64 {
    return a + (b - a) * t;
}

pub fn easeOutCubic(t: f64) f64 {
    const x = clamp01(t);
    return 1.0 - std.math.pow(f64, 1.0 - x, 3.0);
}

/// Accelerates and decelerates, so panel motion does not start at full speed.
pub fn easeInOutCubic(t: f64) f64 {
    const x = clamp01(t);
    if (x < 0.5) return 4.0 * x * x * x;
    return 1.0 - std.math.pow(f64, -2.0 * x + 2.0, 3.0) / 2.0;
}

pub fn easeOutQuint(t: f64) f64 {
    const x = clamp01(t);
    return 1.0 - std.math.pow(f64, 1.0 - x, 5.0);
}

pub fn smoothstep(t: f64) f64 {
    const x = clamp01(t);
    return x * x * (3.0 - 2.0 * x);
}

/// Normalized damped spring response. Overshoots for damping below 1 and
/// always reaches exactly 1 at t >= 1. Loosely follows src/motion.zig.
pub fn spring(t: f64, damping: f64, frequency: f64) f64 {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    const d = std.math.clamp(damping, 0.05, 2.0);
    const f = std.math.clamp(frequency, 0.25, 4.0);
    const k = 2.0 * std.math.pi * f;
    const decay = d * k;
    const denom = 1.0 - @exp(-decay);
    if (denom < 1e-9) return t;
    const raw = 1.0 - @exp(-decay * t) * @cos(k * t);
    return std.math.clamp(raw / denom, 0.0, 2.0);
}
