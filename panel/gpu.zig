const std = @import("std");
const c = @import("c.zig").c;
const m = @import("model.zig");
const build_options = @import("build_options");

pub const enabled = build_options.gpu;

var gpu: ?*c.TessaGpu = null;
var failed = false;
var logged = false;

fn logUnavailable(reason: []const u8) void {
    if (logged) return;
    logged = true;
    std.debug.print("tessa-panel: gpu: {s}; using Cairo\n", .{reason});
}

pub fn ensure() bool {
    if (!enabled) {
        logUnavailable("disabled at build time");
        return false;
    }
    if (c.getenv("TESSA_GPU_DISABLE")) |raw| {
        const value = std.mem.span(raw);
        if (value.len > 0 and value[0] != '0') {
            failed = true;
            logUnavailable("disabled by TESSA_GPU_DISABLE");
            return false;
        }
    }
    if (gpu) |g| return c.tessa_gpu_ready(g) != 0;
    if (failed) return false;
    const display = m.g.display orelse return false;

    const created = c.tessa_gpu_create(display);
    if (created == null) {
        failed = true;
        logUnavailable("cannot create EGL display");
        return false;
    }
    if (c.tessa_gpu_ready(created) == 0) {
        logUnavailable(std.mem.span(c.tessa_gpu_error(created)));
        c.tessa_gpu_destroy(created);
        failed = true;
        return false;
    }
    gpu = created;
    return true;
}

pub fn ready() bool {
    if (!enabled or failed) return false;
    const g = gpu orelse return false;
    return c.tessa_gpu_ready(g) != 0;
}

var frame_listener: c.wl_callback_listener = undefined;
var frame_listener_ready = false;

fn onFrame(data: ?*anyopaque, callback: ?*c.wl_callback, time: u32) callconv(.c) void {
    _ = data;
    _ = time;
    m.g.gpu_frame_callback = null;
    m.g.gpu_frame_pending = false;
    m.g.gpu_frame_ms = 0;
    if (callback) |cb| c.wl_callback_destroy(cb);
    const now = m.nowMs();
    if (animationActive(now) and
        (m.g.next_wallpaper_ms == 0 or now >= m.g.next_wallpaper_ms))
    {
        m.g.bg.dirty = true;
    }
}

/// Ask the compositor for the next presentation callback. It is requested
/// before eglSwapBuffers so the swap's commit carries it.
pub fn requestFrame(s: *m.Surface) bool {
    const surface = s.wl orelse return false;
    cancelFrame();
    if (!frame_listener_ready) {
        frame_listener = std.mem.zeroes(c.wl_callback_listener);
        frame_listener.done = onFrame;
        frame_listener_ready = true;
    }
    const callback = c.wl_surface_frame(surface);
    if (callback == null) return false;
    m.g.gpu_frame_callback = callback;
    m.g.gpu_frame_ms = m.nowMs();
    _ = c.wl_callback_add_listener(callback, &frame_listener, null);
    return true;
}

pub fn cancelFrame() void {
    if (m.g.gpu_frame_callback) |callback| c.wl_callback_destroy(callback);
    m.g.gpu_frame_callback = null;
    m.g.gpu_frame_pending = false;
    m.g.gpu_frame_ms = 0;
}

fn fullscreenVisible() bool {
    for (m.g.windows[0..m.g.window_count]) |*window| {
        if (window.fullscreen and window.visible and window.ws == m.g.active_ws) return true;
    }
    return false;
}

pub fn animationActive(now: i64) bool {
    if (m.g.panel_renderer != .gpu or !ready()) return false;
    if (m.g.wallpaper_animation == .off) return false;
    if (!m.g.animations_enabled or m.g.reduce_motion) return false;
    if (m.g.overlay != null or fullscreenVisible()) return false;
    if (m.g.wallpaper_animation == .auto) {
        if (m.g.battery_percent >= 0 and !m.g.battery_charging) return false;
        const pause_seconds: i64 = @intCast(m.g.wallpaper_idle_pause);
        if (pause_seconds > 0 and m.g.last_input_ms > 0) {
            if (now - m.g.last_input_ms >= pause_seconds * 1000) return false;
        }
    }
    const bg = &m.g.bg;
    return bg.configured and bg.width > 0 and bg.height > 0;
}

pub fn configure(s: *m.Surface, width: u32, height: u32) bool {
    if (!ensure() or s.wl == null or width == 0 or height == 0) return false;
    if (s.gpu) |surface| {
        if (c.tessa_gpu_surface_resize(surface, @intCast(width), @intCast(height)) != 0) return true;
        destroySurface(s);
        disable("EGL surface resize failed");
        return false;
    }
    s.gpu = c.tessa_gpu_surface_create(
        gpu.?,
        s.wl.?,
        @intCast(width),
        @intCast(height),
    );
    if (s.gpu == null) {
        disable("cannot create EGL window surface");
        return false;
    }
    return true;
}

pub fn setBase(s: *m.Surface, image: *c.cairo_surface_t) bool {
    const surface = s.gpu orelse return false;
    if (c.cairo_surface_get_type(image) != c.CAIRO_SURFACE_TYPE_IMAGE) return false;
    c.cairo_surface_flush(image);
    const data = c.cairo_image_surface_get_data(image) orelse return false;
    const width = c.cairo_image_surface_get_width(image);
    const height = c.cairo_image_surface_get_height(image);
    const stride = c.cairo_image_surface_get_stride(image);
    if (c.tessa_gpu_set_base(surface, data, width, height, stride) == 0) {
        disable("wallpaper texture upload failed");
        return false;
    }
    return true;
}

pub fn draw(s: *m.Surface, time: f64, animate: bool) bool {
    const surface = s.gpu orelse return false;
    if (c.tessa_gpu_draw(surface, @floatCast(time), if (animate) 1 else 0) == 0) {
        disable("background draw failed");
        return false;
    }
    return true;
}

pub fn destroySurface(s: *m.Surface) void {
    if (s == &m.g.bg) cancelFrame();
    if (s.gpu) |surface| {
        c.tessa_gpu_surface_destroy(surface);
        s.gpu = null;
    }
}

fn disable(reason: []const u8) void {
    failed = true;
    logUnavailable(reason);
}

pub fn fail(reason: []const u8) void {
    disable(reason);
}

/// Drop the GPU context after a config change so a fixed renderer setting can
/// be retried without restarting the panel.
pub fn reset() void {
    cancelFrame();
    if (gpu) |g| c.tessa_gpu_destroy(g);
    gpu = null;
    failed = false;
    logged = false;
}

pub fn shutdown() void {
    cancelFrame();
    if (gpu) |g| c.tessa_gpu_destroy(g);
    gpu = null;
}
