const std = @import("std");
const c = @import("c.zig").c;
const m = @import("model.zig");
const apps = @import("apps.zig");

const g = &m.g;

const PI: f64 = 3.141592653589793;
const MONO = "JetBrains Mono";

const palette = [6][3]f64{
    .{ 0.84, 0.36, 0.29 },
    .{ 0.25, 0.52, 0.52 },
    .{ 0.38, 0.43, 0.68 },
    .{ 0.58, 0.40, 0.58 },
    .{ 0.60, 0.48, 0.30 },
    .{ 0.33, 0.56, 0.40 },
};

const TextSize = struct { w: f64 = 0, h: f64 = 0 };
const Draw = struct {
    b: *m.Buffer,
    cr: *c.cairo_t,
    img: *c.cairo_surface_t,
};

fn setColor(cr: *c.cairo_t, col: [4]f64) void {
    c.cairo_set_source_rgba(cr, col[0], col[1], col[2], col[3]);
}

fn roundRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
    const rr = @min(r, @min(w, h) / 2.0);
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - rr, y + rr, rr, -PI / 2.0, 0);
    c.cairo_arc(cr, x + w - rr, y + h - rr, rr, 0, PI / 2.0);
    c.cairo_arc(cr, x + rr, y + h - rr, rr, PI / 2.0, PI);
    c.cairo_arc(cr, x + rr, y + rr, rr, PI, PI * 1.5);
    c.cairo_close_path(cr);
}

fn fillRound(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64, col: [4]f64) void {
    roundRect(cr, x, y, w, h, r);
    setColor(cr, col);
    c.cairo_fill(cr);
}

fn strokeRound(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64, col: [4]f64, width: f64) void {
    roundRect(cr, x, y, w, h, r);
    setColor(cr, col);
    c.cairo_set_line_width(cr, width);
    c.cairo_stroke(cr);
}

fn fillCircle(cr: *c.cairo_t, cx: f64, cy: f64, r: f64, col: [4]f64) void {
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, cx, cy, r, 0, PI * 2.0);
    setColor(cr, col);
    c.cairo_fill(cr);
}

fn copyZBuf(comptime N: usize, dest: *[N:0]u8, src: []const u8) [*:0]const u8 {
    const n = @min(src.len, N - 1);
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
    return dest;
}

fn drawText(cr: *c.cairo_t, text: []const u8, x: f64, y: f64, family: []const u8, style: []const u8, size: f64, col: [4]f64, max_w: f64, spacing: f64) TextSize {
    if (text.len == 0) return .{};
    var fam_buf: [128:0]u8 = undefined;
    var style_buf: [64:0]u8 = undefined;
    const fam = copyZBuf(128, &fam_buf, family);
    const sty = copyZBuf(64, &style_buf, style);
    var h: f64 = 0;
    const w = c.tessa_text_draw(cr, text.ptr, @intCast(text.len), fam, sty, size, max_w, spacing, x, y, 0, col[0], col[1], col[2], col[3], &h);
    return .{ .w = w, .h = h };
}

fn drawTextCentered(cr: *c.cairo_t, text: []const u8, x: f64, cy: f64, family: []const u8, style: []const u8, size: f64, col: [4]f64, max_w: f64, spacing: f64) TextSize {
    if (text.len == 0) return .{};
    var fam_buf: [128:0]u8 = undefined;
    var style_buf: [64:0]u8 = undefined;
    const fam = copyZBuf(128, &fam_buf, family);
    const sty = copyZBuf(64, &style_buf, style);
    var h: f64 = 0;
    const w = c.tessa_text_draw(cr, text.ptr, @intCast(text.len), fam, sty, size, max_w, spacing, x, cy, 1, col[0], col[1], col[2], col[3], &h);
    return .{ .w = w, .h = h };
}

fn textWidth(cr: *c.cairo_t, text: []const u8, family: []const u8, style: []const u8, size: f64, spacing: f64) f64 {
    if (text.len == 0) return 0;
    var fam_buf: [128:0]u8 = undefined;
    var style_buf: [64:0]u8 = undefined;
    const fam = copyZBuf(128, &fam_buf, family);
    const sty = copyZBuf(64, &style_buf, style);
    var h: f64 = 0;
    return c.tessa_text_measure(cr, text.ptr, @intCast(text.len), fam, sty, size, spacing, &h);
}

fn drawPetal(cr: *c.cairo_t, cx: f64, cy: f64, r: f64, col: [4]f64) void {
    c.cairo_save(cr);
    c.cairo_translate(cr, cx, cy);
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        c.cairo_save(cr);
        c.cairo_rotate(cr, @as(f64, @floatFromInt(i)) * PI * 2.0 / 5.0);
        c.cairo_translate(cr, 0, -r * 0.42);
        c.cairo_scale(cr, 0.46, 0.88);
        c.cairo_new_sub_path(cr);
        c.cairo_arc(cr, 0, 0, r * 0.5, 0, PI * 2.0);
        setColor(cr, col);
        c.cairo_fill(cr);
        c.cairo_restore(cr);
    }
    c.cairo_restore(cr);
    fillCircle(cr, cx, cy, r * 0.18, col);
}

fn appColor(app: *const apps.App) [3]f64 {
    var h: u32 = 2166136261;
    for (app.id[0..app.id_len]) |ch| {
        h = (h ^ ch) *% 16777619;
    }
    return palette[h % palette.len];
}

fn firstGlyph(text: []const u8) []const u8 {
    if (text.len == 0) return "?";
    var n: usize = 1;
    while (n < text.len and (text[n] & 0xC0) == 0x80) n += 1;
    return text[0..n];
}

fn upperFirst(buf: []u8, text: []const u8) []const u8 {
    if (text.len == 0) return text;
    const n = @min(buf.len, text.len);
    @memcpy(buf[0..n], text[0..n]);
    if (buf[0] >= 'a' and buf[0] <= 'z') buf[0] -= 32;
    return buf[0..n];
}

pub fn destroyBuffers(s: *m.Surface) void {
    for (&s.buffers) |*b| {
        if (b.wl) |wl| c.wl_buffer_destroy(wl);
        if (b.data) |data| {
            _ = c.munmap(data, b.size);
        }
        b.wl = null;
        b.data = null;
        b.size = 0;
        b.busy = false;
    }
}

fn onBufferRelease(data: ?*anyopaque, buffer: ?*c.wl_buffer) callconv(.c) void {
    _ = buffer;
    const b: *m.Buffer = @ptrCast(@alignCast(data.?));
    b.busy = false;
}

fn createBuffer(s: *m.Surface, b: *m.Buffer, width: u32, height: u32) bool {
    const shm = g.shm orelse return false;
    const stride: usize = @as(usize, width) * 4;
    const size: usize = stride * @as(usize, height);
    if (size == 0) return false;

    const fd = c.memfd_create("tessa-panel", c.MFD_CLOEXEC);
    if (fd < 0) return false;
    if (c.ftruncate(fd, @intCast(size)) < 0) {
        _ = c.close(fd);
        return false;
    }
    const map = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
    if (map == null or @intFromPtr(map.?) == std.math.maxInt(usize)) {
        _ = c.close(fd);
        return false;
    }
    const pool = c.wl_shm_create_pool(shm, fd, @intCast(size)) orelse {
        _ = c.munmap(map, size);
        _ = c.close(fd);
        return false;
    };
    const wl_buf = c.wl_shm_pool_create_buffer(
        pool,
        0,
        @intCast(width),
        @intCast(height),
        @intCast(stride),
        @intCast(c.WL_SHM_FORMAT_ARGB8888),
    );
    c.wl_shm_pool_destroy(pool);
    _ = c.close(fd);

    if (wl_buf == null) {
        _ = c.munmap(map, size);
        return false;
    }

    b.wl = wl_buf;
    b.data = map;
    b.size = size;
    b.busy = false;
    b.owner = s;
    b.listener = std.mem.zeroes(c.wl_buffer_listener);
    b.listener.release = onBufferRelease;
    _ = c.wl_buffer_add_listener(wl_buf.?, &b.listener, b);
    return true;
}

fn ensureBuffers(s: *m.Surface) bool {
    if (s.width == 0 or s.height == 0) return false;
    const scale: usize = @intCast(@max(1, s.scale));
    const buf_w: u32 = s.width * @as(u32, @intCast(scale));
    const buf_h: u32 = s.height * @as(u32, @intCast(scale));
    const expected: usize = @as(usize, buf_w) * 4 * @as(usize, buf_h);
    if (s.buffers[0].wl != null and s.buffers[0].size == expected) return true;

    destroyBuffers(s);
    var i: usize = 0;
    while (i < s.buffers.len) : (i += 1) {
        if (!createBuffer(s, &s.buffers[i], buf_w, buf_h)) {
            destroyBuffers(s);
            return false;
        }
    }
    return true;
}

pub fn setSurfaceScale(s: *m.Surface, scale: i32) void {
    const scl = @max(1, scale);
    if (s.scale == scl) return;
    s.scale = scl;
    if (s.wl) |wl| c.wl_surface_set_buffer_scale(wl, scl);
    destroyBuffers(s);
    s.dirty = true;
}

pub fn configureSurface(s: *m.Surface, width: u32, height: u32) void {
    if (width == 0 or height == 0) return;
    if (s.configured and s.width == width and s.height == height) {
        s.dirty = true;
        return;
    }
    s.width = width;
    s.height = height;
    s.configured = true;
    destroyBuffers(s);
    _ = ensureBuffers(s);
    s.dirty = true;
}

fn acquire(s: *m.Surface) ?*m.Buffer {
    for (&s.buffers) |*b| {
        if (b.wl != null and !b.busy) return b;
    }
    return null;
}

fn begin(s: *m.Surface) ?Draw {
    if (!s.configured or s.wl == null) return null;
    if (!ensureBuffers(s)) return null;
    const b = acquire(s) orelse return null;

    const scale: f64 = @floatFromInt(@max(1, s.scale));
    const buf_w: u32 = s.width * @as(u32, @intCast(@max(1, s.scale)));
    const buf_h: u32 = s.height * @as(u32, @intCast(@max(1, s.scale)));
    const img = c.cairo_image_surface_create_for_data(
        @ptrCast(b.data.?),
        c.CAIRO_FORMAT_ARGB32,
        @intCast(buf_w),
        @intCast(buf_h),
        @intCast(@as(usize, buf_w) * 4),
    ) orelse return null;
    const cr = c.cairo_create(img) orelse {
        c.cairo_surface_destroy(img);
        return null;
    };
    c.cairo_scale(cr, scale, scale);

    const opts = c.cairo_font_options_create();
    c.cairo_font_options_set_antialias(opts, c.CAIRO_ANTIALIAS_GRAY);
    c.cairo_font_options_set_hint_style(opts, c.CAIRO_HINT_STYLE_SLIGHT);
    c.cairo_set_font_options(cr, opts);
    c.cairo_font_options_destroy(opts);
    c.cairo_set_antialias(cr, c.CAIRO_ANTIALIAS_BEST);

    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_rgba(cr, 0, 0, 0, 0);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    return .{ .b = b, .cr = cr, .img = img };
}

fn end(s: *m.Surface, d: Draw) void {
    c.cairo_destroy(d.cr);
    c.cairo_surface_flush(d.img);
    c.cairo_surface_destroy(d.img);

    c.wl_surface_attach(s.wl.?, d.b.wl.?, 0, 0);
    const scale: u32 = @intCast(@max(1, s.scale));
    const damage_w: i32 = @intCast(s.width * scale);
    const damage_h: i32 = @intCast(s.height * scale);
    c.wl_surface_damage_buffer(s.wl.?, 0, 0, damage_w, damage_h);
    c.wl_surface_commit(s.wl.?);
    d.b.busy = true;
    s.dirty = false;
}

fn linearGradient(cr: *c.cairo_t, x0: f64, y0: f64, x1: f64, y1: f64, c0: [4]f64, c1: [4]f64) void {
    const pat = c.cairo_pattern_create_linear(x0, y0, x1, y1);
    c.cairo_pattern_add_color_stop_rgba(pat, 0, c0[0], c0[1], c0[2], c0[3]);
    c.cairo_pattern_add_color_stop_rgba(pat, 1, c1[0], c1[1], c1[2], c1[3]);
    c.cairo_set_source(cr, pat);
    c.cairo_pattern_destroy(pat);
}

fn paintGradientRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, c0: [4]f64, c1: [4]f64) void {
    c.cairo_rectangle(cr, x, y, w, h);
    linearGradient(cr, x, y, x, y + h, c0, c1);
    c.cairo_fill(cr);
}

fn radialFill(cr: *c.cairo_t, cx: f64, cy: f64, r0: f64, r1: f64, c0: [4]f64, c1: [4]f64) void {
    const pat = c.cairo_pattern_create_radial(cx, cy, r0, cx, cy, r1);
    c.cairo_pattern_add_color_stop_rgba(pat, 0, c0[0], c0[1], c0[2], c0[3]);
    c.cairo_pattern_add_color_stop_rgba(pat, 1, c1[0], c1[1], c1[2], c1[3]);
    c.cairo_set_source(cr, pat);
    c.cairo_paint(cr);
    c.cairo_pattern_destroy(pat);
}

const Prng = struct {
    state: u64 = 0x9e3779b97f4a7c15,

    fn next(self: *Prng) f64 {
        self.state = self.state *% 6364136223846793005 +% 1442695040888963407;
        return @as(f64, @floatFromInt(self.state >> 11)) / 9007199254740992.0;
    }
};

fn drawBackgroundArt(cr: *c.cairo_t, w: f64, h: f64) void {
    const bg = g.bg_rgb;
    const top = [4]f64{ bg[0] * 1.9 + 0.012, bg[1] * 1.9 + 0.018, bg[2] * 1.9 + 0.030, 1.0 };
    const bottom = [4]f64{ bg[0] * 0.55, bg[1] * 0.55, bg[2] * 0.6, 1.0 };
    paintGradientRect(cr, 0, 0, w, h, top, bottom);

    const accent = g.accent;

    // broad wash
    c.cairo_save(cr);
    c.cairo_translate(cr, w * 0.78, h * 0.24);
    c.cairo_scale(cr, 1.7, 1.0);
    radialFill(cr, 0, 0, 0, h * 0.44, .{ accent[0], accent[1], accent[2], 0.12 }, .{ accent[0], accent[1], accent[2], 0.0 });
    c.cairo_restore(cr);

    // ink blots
    const blots = [_][4]f64{
        .{ 0.20, 0.72, 0.42, 0.030 },
        .{ 0.64, 0.78, 0.54, 0.022 },
        .{ 0.08, 0.30, 0.34, 0.020 },
        .{ 0.44, 0.14, 0.26, 0.018 },
        .{ 0.88, 0.62, 0.30, 0.026 },
    };
    for (blots) |b| {
        c.cairo_save(cr);
        c.cairo_translate(cr, w * b[0], h * b[1]);
        c.cairo_scale(cr, 1.5, 0.8);
        radialFill(cr, 0, 0, 0, h * b[2], .{ 0.10, 0.25, 0.28, b[3] }, .{ 0.10, 0.25, 0.28, 0.0 });
        c.cairo_restore(cr);
    }

    // sun
    const cx = w * 0.79;
    const cy = h * 0.235;
    const sr = h * 0.155;
    radialFill(cr, cx, cy, sr * 0.65, sr * 2.8, .{ accent[0], accent[1], accent[2], 0.18 }, .{ accent[0], accent[1], accent[2], 0.0 });

    c.cairo_save(cr);
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, cx, cy, sr, 0, PI * 2.0);
    c.cairo_clip(cr);
    paintGradientRect(cr, cx - sr, cy - sr, sr * 2, sr * 2, .{ 0.93, 0.47, 0.35, 0.58 }, .{ 0.55, 0.15, 0.15, 0.26 });
    c.cairo_restore(cr);

    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, cx, cy, sr * 1.26, 0, PI * 2.0);
    setColor(cr, .{ accent[0], accent[1], accent[2], 0.18 });
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);

    // faint tessellation
    c.cairo_save(cr);
    var tri: usize = 0;
    while (tri < 10) : (tri += 1) {
        const bx = w * (0.06 + 0.085 * @as(f64, @floatFromInt(tri % 5)));
        const by = h * (0.62 + 0.07 * @as(f64, @floatFromInt(tri / 5)));
        const size = h * 0.16;
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, bx, by);
        c.cairo_line_to(cr, bx + size, by + size * 0.55);
        c.cairo_line_to(cr, bx + size * 0.2, by + size);
        c.cairo_close_path(cr);
        setColor(cr, .{ 1.0, 1.0, 1.0, if (tri % 2 == 0) 0.010 else 0.004 });
        c.cairo_fill(cr);
        setColor(cr, .{ 1.0, 1.0, 1.0, 0.012 });
        c.cairo_set_line_width(cr, 0.8);
        c.cairo_stroke(cr);
    }
    c.cairo_restore(cr);

    // water lines
    var k: usize = 0;
    while (k < 6) : (k += 1) {
        const y = h * (0.80 + 0.028 * @as(f64, @floatFromInt(k)));
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, 0, y);
        c.cairo_curve_to(cr, w * 0.32, y - 10.0, w * 0.62, y + 8.0, w, y - 4.0);
        setColor(cr, .{ 1.0, 1.0, 1.0, 0.010 + 0.004 * @as(f64, @floatFromInt(k)) });
        c.cairo_set_line_width(cr, 0.8);
        c.cairo_stroke(cr);
    }

    // film grain
    var rng = Prng{};
    c.cairo_new_path(cr);
    var i: usize = 0;
    while (i < 3400) : (i += 1) {
        const x = rng.next() * w;
        const y = rng.next() * h;
        c.cairo_rectangle(cr, x, y, 1.0, 1.0);
    }
    setColor(cr, .{ 1.0, 1.0, 1.0, 0.016 });
    c.cairo_fill(cr);

    c.cairo_new_path(cr);
    i = 0;
    while (i < 900) : (i += 1) {
        const x = rng.next() * w;
        const y = rng.next() * h;
        c.cairo_rectangle(cr, x, y, 1.0, 1.0);
    }
    setColor(cr, .{ 0.0, 0.0, 0.0, 0.05 });
    c.cairo_fill(cr);

    // vignette
    const vp = c.cairo_pattern_create_radial(w * 0.5, h * 0.5, h * 0.1, w * 0.5, h * 0.5, h * 0.82);
    c.cairo_pattern_add_color_stop_rgba(vp, 0, 0, 0, 0, 0);
    c.cairo_pattern_add_color_stop_rgba(vp, 0.62, 0, 0, 0, 0);
    c.cairo_pattern_add_color_stop_rgba(vp, 1, 0, 0, 0, 0.38);
    c.cairo_set_source(cr, vp);
    c.cairo_paint(cr);
    c.cairo_pattern_destroy(vp);

    // signature
    drawPetal(cr, w - 150, h - 30, 7, .{ 1, 1, 1, 0.16 });
    _ = drawText(cr, "TESSA", w - 136, h - 36, g.font[0..g.font_len], "Semi-Bold", 8, .{ 1, 1, 1, 0.20 }, 0, 2.4);
    _ = drawText(cr, "SUMI SHELL / 01", w - 136, h - 24, MONO, "Medium", 6.5, .{ 1, 1, 1, 0.10 }, 0, 1.2);
}

pub fn drawBackground(s: *m.Surface) void {
    const d = begin(s) orelse return;
    const w: f64 = @floatFromInt(s.width);
    const h: f64 = @floatFromInt(s.height);
    drawBackgroundArt(d.cr, w, h);
    end(s, d);
}

fn addBarHit(x: f64, y: f64, w: f64, h: f64, hit: m.Hit) void {
    if (g.bar_hit_count >= g.bar_hits.len) return;
    g.bar_hits[g.bar_hit_count] = .{ .x = x, .y = y, .w = w, .h = h, .hit = hit };
    g.bar_hit_count += 1;
}

fn drawSparkline(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64) void {
    const n = g.cpu_hist.len;
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x, y + h);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const px = x + @as(f64, @floatFromInt(i)) * w / @as(f64, @floatFromInt(n - 1));
        const norm = std.math.clamp(@as(f64, g.cpu_hist[i]) / 100.0, 0.0, 1.0);
        const py = y + h - norm * h;
        c.cairo_line_to(cr, px, py);
    }
    c.cairo_line_to(cr, x + w, y + h);
    c.cairo_close_path(cr);
    const pat = c.cairo_pattern_create_linear(x, y, x, y + h);
    c.cairo_pattern_add_color_stop_rgba(pat, 0, g.accent[0], g.accent[1], g.accent[2], 0.28);
    c.cairo_pattern_add_color_stop_rgba(pat, 1, g.accent[0], g.accent[1], g.accent[2], 0.02);
    c.cairo_set_source(cr, pat);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(pat);

    c.cairo_new_path(cr);
    i = 0;
    while (i < n) : (i += 1) {
        const px = x + @as(f64, @floatFromInt(i)) * w / @as(f64, @floatFromInt(n - 1));
        const norm = std.math.clamp(@as(f64, g.cpu_hist[i]) / 100.0, 0.0, 1.0);
        const py = y + h - norm * h;
        if (i == 0) c.cairo_move_to(cr, px, py) else c.cairo_line_to(cr, px, py);
    }
    setColor(cr, .{ g.accent[0], g.accent[1], g.accent[2], 0.85 });
    c.cairo_set_line_width(cr, 1.1);
    c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);
    c.cairo_stroke(cr);
}

fn drawBatteryIndicator(cr: *c.cairo_t, right: f64, cy: f64, fg: [3]f64) f64 {
    var buf: [16]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}%", .{g.battery_percent}) catch "";
    const tw = textWidth(cr, text, MONO, "Medium", 8.2, 0);
    const group_w = 20.0 + 6.0 + tw;
    const x = right - group_w;
    const col: [4]f64 = if (g.battery_charging)
        .{ g.accent[0], g.accent[1], g.accent[2], 0.95 }
    else
        .{ fg[0], fg[1], fg[2], 0.62 };

    strokeRound(cr, x + 0.5, cy - 5.5, 19, 11, 2.5, .{ 1, 1, 1, 0.28 }, 1);
    fillRound(cr, x + 20, cy - 2, 2, 4, 1, .{ 1, 1, 1, 0.25 });
    const pct = std.math.clamp(@as(f64, @floatFromInt(g.battery_percent)) / 100.0, 0.0, 1.0);
    if (pct > 0.02) {
        fillRound(cr, x + 2.5, cy - 3.5, 15.0 * pct, 7, 1.2, col);
    }
    _ = drawTextCentered(cr, text, x + 22, cy + 0.3, MONO, "Medium", 8.2, .{
        col[0], col[1], col[2], 0.88,
    }, 0, 0);
    return x - 14;
}

fn drawNetworkIndicator(cr: *c.cairo_t, right: f64, cy: f64, fg: [3]f64) f64 {
    const label = g.network_label[0..g.network_label_len];
    const tw = textWidth(cr, label, g.font[0..g.font_len], "Medium", 8.2, 0.4);
    const group_w = 20.0 + tw;
    const x = right - group_w;
    const bars = [_]f64{ 4.0, 7.0, 10.0 };
    var i: usize = 0;
    while (i < bars.len) : (i += 1) {
        const h = bars[i];
        const bx = x + @as(f64, @floatFromInt(i)) * 4.0;
        fillRound(cr, bx, cy + 6.0 - h, 2.5, h, 1, .{
            g.accent[0], g.accent[1], g.accent[2], 0.78,
        });
    }
    _ = drawTextCentered(cr, label, x + 20, cy + 0.3, g.font[0..g.font_len], "Medium", 8.2, .{
        fg[0], fg[1], fg[2], 0.58,
    }, 0, 0.4);
    return x - 14;
}

fn drawVolumeIndicator(cr: *c.cairo_t, right: f64, cy: f64, fg: [3]f64) f64 {
    const accent = g.accent;
    var text_buf: [16]u8 = undefined;
    const text = if (g.volume_muted)
        "MUTE"
    else
        std.fmt.bufPrint(&text_buf, "{d}%", .{g.volume_percent}) catch "VOL";
    const tw = textWidth(cr, text, MONO, "Medium", 8.2, 0);
    const group_w = 18.0 + 6.0 + tw;
    const x = right - group_w;
    const col: [4]f64 = if (g.volume_muted)
        .{ fg[0], fg[1], fg[2], 0.38 }
    else
        .{ accent[0], accent[1], accent[2], 0.88 };

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 1, cy - 3);
    c.cairo_line_to(cr, x + 5, cy - 3);
    c.cairo_line_to(cr, x + 10, cy - 7);
    c.cairo_line_to(cr, x + 10, cy + 7);
    c.cairo_line_to(cr, x + 5, cy + 3);
    c.cairo_line_to(cr, x + 1, cy + 3);
    c.cairo_close_path(cr);
    setColor(cr, col);
    c.cairo_fill(cr);

    if (!g.volume_muted) {
        c.cairo_new_path(cr);
        c.cairo_arc(cr, x + 10.5, cy, 4.5, -0.85, 0.85);
        setColor(cr, .{ col[0], col[1], col[2], 0.75 });
        c.cairo_set_line_width(cr, 1.3);
        c.cairo_stroke(cr);
    } else {
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, x + 12, cy - 5);
        c.cairo_line_to(cr, x + 16, cy + 5);
        setColor(cr, .{ fg[0], fg[1], fg[2], 0.55 });
        c.cairo_set_line_width(cr, 1.3);
        c.cairo_stroke(cr);
    }

    _ = drawTextCentered(cr, text, x + 18, cy + 0.3, MONO, "Medium", 8.2, .{
        col[0], col[1], col[2], 0.82,
    }, 0, 0);
    return x - 14;
}

fn paintTrayIcon(cr: *c.cairo_t, item: *const m.TrayItem, x: f64, y: f64, size: f64) void {
    const accent = g.accent;
    var source: ?*c.cairo_surface_t = null;
    var temp = false;
    var iw: f64 = 0;
    var ih: f64 = 0;

    if (item.icon_len > 0 and item.icon_w > 0 and item.icon_h > 0) {
        iw = @floatFromInt(item.icon_w);
        ih = @floatFromInt(item.icon_h);
        const surf = c.cairo_image_surface_create_for_data(
            @ptrCast(@constCast(&item.icon_data)),
            c.CAIRO_FORMAT_ARGB32,
            @intCast(item.icon_w),
            @intCast(item.icon_h),
            @intCast(item.icon_w * 4),
        );
        if (c.cairo_surface_status(surf) == c.CAIRO_STATUS_SUCCESS) {
            source = surf;
            temp = true;
        } else {
            c.cairo_surface_destroy(surf);
        }
    } else if (item.icon_surface) |surf| {
        iw = @floatFromInt(c.cairo_image_surface_get_width(surf));
        ih = @floatFromInt(c.cairo_image_surface_get_height(surf));
        if (iw > 0 and ih > 0) source = surf;
    }

    if (source) |surf| {
        const scale = @min(size / iw, size / ih);
        c.cairo_save(cr);
        c.cairo_translate(cr, x + size / 2.0, y + size / 2.0);
        c.cairo_scale(cr, scale, scale);
        c.cairo_set_source_surface(cr, surf, -iw / 2.0, -ih / 2.0);
        c.cairo_paint(cr);
        c.cairo_restore(cr);
        if (temp) c.cairo_surface_destroy(surf);
    } else {
        const label = if (item.title_len > 0) item.title[0..item.title_len] else item.icon_name[0..item.icon_name_len];
        var hsh: u32 = 2166136261;
        for (label) |ch| hsh = (hsh ^ ch) *% 16777619;
        const col = palette[hsh % palette.len];
        fillRound(cr, x, y, size, size, 6, .{ col[0], col[1], col[2], 0.92 });
        var gbuf: [8]u8 = undefined;
        const glyph = upperFirst(&gbuf, firstGlyph(if (label.len > 0) label else "T"));
        _ = drawTextCentered(cr, glyph, x + size / 2.0 - 2.4, y + size / 2.0 + 0.3, g.font[0..g.font_len], "Semi-Bold", 8.0, .{ 1, 1, 1, 0.95 }, 0, 0);
    }

    if (item.status == 2) {
        fillCircle(cr, x + size - 2.0, y + 2.0, 3.0, .{ accent[0], accent[1], accent[2], 1.0 });
    }
}

pub fn drawBar(s: *m.Surface) void {
    const d = begin(s) orelse return;
    const cr = d.cr;
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    const cy = H / 2.0;
    const accent = g.accent;
    const bg = g.panel_bg;
    const fg = g.panel_fg;
    const bar_top = [4]f64{
        std.math.clamp(bg[0] + 0.030, 0, 1),
        std.math.clamp(bg[1] + 0.040, 0, 1),
        std.math.clamp(bg[2] + 0.055, 0, 1),
        0.97,
    };
    const bar_bottom = [4]f64{ bg[0] * 0.62, bg[1] * 0.65, bg[2] * 0.70, 0.97 };

    g.bar_hit_count = 0;

    fillRound(cr, 0, 0, W, H, 18, .{ bg[0], bg[1], bg[2], 0.96 });
    roundRect(cr, 0, 0, W, H, 18);
    linearGradient(cr, 0, 0, 0, H, bar_top, bar_bottom);
    c.cairo_fill(cr);

    c.cairo_save(cr);
    roundRect(cr, 0, 0, W, H, 18);
    c.cairo_clip(cr);
    c.cairo_translate(cr, 46, cy);
    c.cairo_scale(cr, 3.2, 1.0);
    radialFill(cr, 0, 0, 0, 62, .{ accent[0], accent[1], accent[2], 0.10 }, .{ accent[0], accent[1], accent[2], 0.0 });
    c.cairo_restore(cr);

    strokeRound(cr, 0.5, 0.5, W - 1, H - 1, 18, .{ 1, 1, 1, 0.075 }, 1.0);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, 26, 0.7);
    c.cairo_line_to(cr, W - 26, 0.7);
    setColor(cr, .{ 1, 1, 1, 0.10 });
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);

    // menu mark
    const mark_x = 14.0;
    const mark_y = cy - 14.0;
    const hover_menu = g.hover.kind == .menu;
    fillRound(cr, mark_x, mark_y, 28, 28, 9, .{
        1, 1, 1, if (hover_menu) 0.11 else 0.055,
    });
    strokeRound(cr, mark_x + 0.5, mark_y + 0.5, 27, 27, 9, .{
        accent[0], accent[1], accent[2], if (hover_menu) 0.55 else 0.30,
    }, 1.0);
    drawPetal(cr, mark_x + 14, cy, 7.2, .{ accent[0], accent[1], accent[2], 1.0 });

    const word = "TESSA";
    const word_w = textWidth(cr, word, g.font[0..g.font_len], "Semi-Bold", 10.0, 1.8);
    _ = drawTextCentered(cr, word, mark_x + 38, cy + 0.5, g.font[0..g.font_len], "Semi-Bold", 10.0, .{ fg[0], fg[1], fg[2], 0.92 }, 0, 1.8);

    const menu_end = mark_x + 38 + word_w + 8;
    addBarHit(mark_x, 4, menu_end - mark_x, H - 8, .{ .kind = .menu });

    const div_x = menu_end + 7;
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, div_x, cy - 9);
    c.cairo_line_to(cr, div_x, cy + 9);
    setColor(cr, .{ 1, 1, 1, 0.055 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    // workspace pills
    const pill_w = 22.0;
    const pill_h = 20.0;
    const pill_gap = 4.0;
    const ws_total = 9.0 * pill_w + 8.0 * pill_gap;
    const ws_x0 = W / 2.0 - ws_total / 2.0;
    const ws_y = cy - pill_h / 2.0;

    var wi: usize = 0;
    while (wi < 9) : (wi += 1) {
        const ws = wi + 1;
        const active = ws == g.active_ws;
        const occupied = g.occ[ws] > 0;
        const hovered = g.hover.kind == .workspace and g.hover.value == ws;
        const x = ws_x0 + @as(f64, @floatFromInt(wi)) * (pill_w + pill_gap);

        if (active) {
            fillRound(cr, x, ws_y, pill_w, pill_h, 10, .{ accent[0], accent[1], accent[2], 1.0 });
        } else {
            fillRound(cr, x, ws_y, pill_w, pill_h, 10, .{
                1, 1, 1, if (hovered) 0.115 else if (occupied) 0.070 else 0.030,
            });
            strokeRound(cr, x + 0.5, ws_y + 0.5, pill_w - 1, pill_h - 1, 9.5, .{ 1, 1, 1, 0.045 }, 1.0);
        }
        var nbuf: [2]u8 = undefined;
        const ns = std.fmt.bufPrint(&nbuf, "{d}", .{ws}) catch "?";
        const text_col: [4]f64 = if (active)
            .{ 0.055, 0.08, 0.11, 1.0 }
        else
            .{ 0.70, 0.76, 0.86, if (occupied) 0.95 else 0.55 };
        _ = drawTextCentered(cr, ns, x + pill_w / 2.0 - 3.2, cy + 0.5, MONO, "Medium", 9.0, text_col, 0, 0);
        addBarHit(x, ws_y - 2, pill_w, pill_h + 4, .{ .kind = .workspace, .value = ws });
    }

    // window chips
    const chips_end = ws_x0 - 16.0;
    var cx = div_x + 12.0;
    var shown: usize = 0;
    var skipped: usize = 0;
    var index: usize = 0;
    while (index < g.window_count) : (index += 1) {
        const w = &g.windows[index];
        if (w.ws != g.active_ws) continue;
        const label = if (w.title_len > 0)
            w.title[0..w.title_len]
        else if (w.app_len > 0)
            w.app_id[0..w.app_len]
        else
            "untitled";
        const tw = textWidth(cr, label, g.font[0..g.font_len], "Medium", 9.6, 0);
        var chip_w = tw + 50.0;
        chip_w = std.math.clamp(chip_w, 92.0, 190.0);
        if (cx + chip_w > chips_end) {
            skipped += 1;
            continue;
        }
        const chip_h = 26.0;
        const chip_y = cy - chip_h / 2.0;
        const focused = w.id == g.focused_id;
        const hovered = g.hover.kind == .window and g.hover.value == w.id;

        if (focused) {
            fillRound(cr, cx, chip_y, chip_w, chip_h, 8, .{ accent[0], accent[1], accent[2], if (hovered) 0.22 else 0.15 });
            strokeRound(cr, cx + 0.5, chip_y + 0.5, chip_w - 1, chip_h - 1, 7.5, .{ accent[0], accent[1], accent[2], 0.42 }, 1.0);
        } else {
            fillRound(cr, cx, chip_y, chip_w, chip_h, 8, .{ 1, 1, 1, if (hovered) 0.075 else 0.040 });
            strokeRound(cr, cx + 0.5, chip_y + 0.5, chip_w - 1, chip_h - 1, 7.5, .{ 1, 1, 1, 0.040 }, 1.0);
        }

        const app_id = if (w.app_len > 0) w.app_id[0..w.app_len] else label;
        var hsh: u32 = 2166136261;
        for (app_id) |ch| hsh = (hsh ^ ch) *% 16777619;
        const col = palette[hsh % palette.len];

        fillRound(cr, cx + 6, cy - 8, 16, 16, 5, .{ col[0], col[1], col[2], 0.92 });
        var gbuf: [8]u8 = undefined;
        const glyph = upperFirst(&gbuf, firstGlyph(label));
        _ = drawTextCentered(cr, glyph, cx + 10.6, cy + 0.3, g.font[0..g.font_len], "Semi-Bold", 8.2, .{ 1, 1, 1, 0.95 }, 0, 0);

        _ = drawTextCentered(cr, label, cx + 28, cy + 0.2, g.font[0..g.font_len], "Medium", 9.6, if (focused) .{ 1, 1, 1, 0.96 } else .{ 0.68, 0.74, 0.84, 0.9 }, chip_w - 36, 0);
        addBarHit(cx, chip_y, chip_w, chip_h, .{ .kind = .window, .value = w.id });
        cx += chip_w + 6;
        shown += 1;
        if (shown >= 6) break;
    }
    if (skipped > 0 and cx + 34 < chips_end) {
        fillRound(cr, cx, cy - 11, 32, 22, 7, .{ 1, 1, 1, 0.045 });
        var sbuf: [16]u8 = undefined;
        const extra = std.fmt.bufPrint(&sbuf, "+{d}", .{skipped}) catch "+";
        _ = drawTextCentered(cr, extra, cx + 8, cy + 0.5, MONO, "Medium", 8.5, .{ 0.65, 0.71, 0.81, 0.8 }, 0, 0);
    }

    // right cluster
    const clock_right = W - 16.0;
    const time = std.mem.sliceTo(&g.clock_buf, 0);
    const tw = textWidth(cr, time, MONO, "Medium", 12.0, 0);
    const time_x = clock_right - tw;
    const date = std.mem.sliceTo(&g.date_buf, 0);
    const dw = textWidth(cr, date, g.font[0..g.font_len], "Medium", 8.2, 0.9);
    const date_x = time_x - 12.0 - dw;
    const clock_hovered = g.hover.kind == .clock;

    if (clock_hovered) {
        fillRound(cr, date_x - 9, cy - 13, clock_right + 8 - (date_x - 9), 26, 9, .{
            accent[0], accent[1], accent[2], 0.10,
        });
    }
    _ = drawTextCentered(cr, time, time_x, cy + 0.3, MONO, "Medium", 12.0, .{
        fg[0], fg[1], fg[2], 0.95,
    }, 0, 0);
    _ = drawTextCentered(cr, date, date_x, cy + 0.3, g.font[0..g.font_len], "Medium", 8.2, .{
        0.66, 0.72, 0.82, if (clock_hovered) 0.78 else 0.55,
    }, 0, 0.9);
    addBarHit(date_x - 9, cy - 13, clock_right + 8 - (date_x - 9), 26, .{ .kind = .clock });
    var right = date_x - 12.0;

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, right, cy - 7);
    c.cairo_line_to(cr, right, cy + 7);
    setColor(cr, .{ 1, 1, 1, 0.06 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);
    right -= 12.0;

    if (g.battery_percent >= 0 and W > 900) {
        right = drawBatteryIndicator(cr, right, cy, fg);
    }
    if (g.network_present and W > 1000) {
        right = drawNetworkIndicator(cr, right, cy, fg);
    }
    if (g.volume_percent >= 0 and W > 1080) {
        const vol_right = right;
        right = drawVolumeIndicator(cr, right, cy, fg);
        addBarHit(right + 14, cy - 12, vol_right - (right + 14), 24, .{ .kind = .volume });
    }

    if (W > 1180) {
        var mbuf: [32]u8 = undefined;
        const ms = std.fmt.bufPrint(&mbuf, "MEM {d:.0}%", .{g.mem_percent}) catch "MEM";
        const mw = textWidth(cr, ms, MONO, "Medium", 8.2, 0);
        _ = drawTextCentered(cr, ms, right - mw, cy + 0.3, MONO, "Medium", 8.2, .{ 0.60, 0.67, 0.77, 0.55 }, 0, 0);
        right -= mw + 12.0;

        var cbuf: [32]u8 = undefined;
        const cs = std.fmt.bufPrint(&cbuf, "CPU {d:.0}%", .{g.cpu_percent}) catch "CPU";
        const cw = textWidth(cr, cs, MONO, "Medium", 8.2, 0);
        _ = drawTextCentered(cr, cs, right - cw, cy + 0.3, MONO, "Medium", 8.2, .{ 0.60, 0.67, 0.77, 0.55 }, 0, 0);
        right -= cw + 10.0;

        drawSparkline(cr, right - 42, cy - 7, 42, 14);
    }

    if ((g.media_status == 1 or g.media_status == 2) and W > 1250) {
        const title = if (g.media_title_len > 0)
            g.media_title[0..g.media_title_len]
        else if (g.media_artist_len > 0)
            g.media_artist[0..g.media_artist_len]
        else if (g.media_player_len > 0)
            g.media_player[0..g.media_player_len]
        else
            "Media";
        const media_tw = @min(textWidth(cr, title, g.font[0..g.font_len], "Medium", 8.6, 0), 150.0);
        const chip_w = media_tw + 46.0;
        const chip_h = 24.0;
        const chip_x = right - chip_w;
        if (chip_x > cx + 12.0) {
            const hovered = g.hover.kind == .media;
            fillRound(cr, chip_x, cy - chip_h / 2.0, chip_w, chip_h, 8, .{
                accent[0], accent[1], accent[2], if (hovered) 0.16 else 0.10,
            });
            strokeRound(cr, chip_x + 0.5, cy - chip_h / 2.0 + 0.5, chip_w - 1, chip_h - 1, 7.5, .{
                accent[0], accent[1], accent[2], 0.22,
            }, 1);
            if (g.media_status == 1) {
                fillRound(cr, chip_x + 11, cy - 4.5, 2.2, 9, 1, .{ accent[0], accent[1], accent[2], 0.95 });
                fillRound(cr, chip_x + 15, cy - 4.5, 2.2, 9, 1, .{ accent[0], accent[1], accent[2], 0.95 });
            } else {
                c.cairo_new_path(cr);
                c.cairo_move_to(cr, chip_x + 11, cy - 5);
                c.cairo_line_to(cr, chip_x + 18, cy);
                c.cairo_line_to(cr, chip_x + 11, cy + 5);
                c.cairo_close_path(cr);
                setColor(cr, .{ accent[0], accent[1], accent[2], 0.95 });
                c.cairo_fill(cr);
            }
            _ = drawTextCentered(cr, title, chip_x + 27, cy + 0.3, g.font[0..g.font_len], "Medium", 8.6, .{
                fg[0], fg[1], fg[2], 0.84,
            }, media_tw, 0);
            addBarHit(chip_x, cy - chip_h / 2.0 - 1, chip_w, chip_h + 2, .{ .kind = .media });
            right = chip_x - 14.0;
        }
    }

    if (g.tray_count > 0 and W > 980) {
        const slot = 24.0;
        const icon_size = 18.0;
        const tray_w = @as(f64, @floatFromInt(g.tray_count)) * slot;
        const tray_x = right - tray_w;
        if (tray_x > cx + 12.0) {
            var ti: usize = 0;
            while (ti < g.tray_count) : (ti += 1) {
                const item = &g.tray_items[ti];
                const ix = tray_x + @as(f64, @floatFromInt(ti)) * slot;
                const hovered = g.hover.kind == .tray and g.hover.value == ti;
                if (hovered) {
                    fillRound(cr, ix + 1, cy - 12, slot - 2, 24, 7, .{
                        accent[0], accent[1], accent[2], 0.12,
                    });
                }
                paintTrayIcon(cr, item, ix + (slot - icon_size) / 2.0, cy - icon_size / 2.0, icon_size);
                addBarHit(ix, cy - 12, slot, 24, .{ .kind = .tray, .value = ti });
            }
            right = tray_x - 10.0;
        }
    }

    // Extension status entries. They are right-aligned next to the built-in
    // cluster and only drawn when they fit between the window chips and it.
    var status_widths: [m.MAX_STATUS]f64 = undefined;
    var status_fit: usize = 0;
    var status_total: f64 = 0;
    while (status_fit < g.status_count) : (status_fit += 1) {
        const st = &g.statuses[status_fit];
        const text = st.text[0..st.text_len];
        const tw2 = @min(textWidth(cr, text, g.font[0..g.font_len], "Medium", 8.4, 0), 112.0);
        const status_pill = tw2 + 20.0;
        const gap2: f64 = if (status_fit == 0) 0 else 6.0;
        if (right - status_total - status_pill - gap2 < cx + 12.0) break;
        status_widths[status_fit] = status_pill;
        status_total += status_pill + gap2;
    }

    if (status_fit > 0) {
        var sx = right - status_total;
        var si: usize = 0;
        while (si < status_fit) : (si += 1) {
            const st = &g.statuses[si];
            const status_w = status_widths[si];
            const hovered = g.hover.kind == .status and g.hover.value == si;
            fillRound(cr, sx, cy - 10, status_w, 20, 6, .{
                1, 1, 1, if (hovered) 0.075 else 0.040,
            });
            strokeRound(cr, sx + 0.5, cy - 9.5, status_w - 1, 19, 5.5, .{
                1, 1, 1, if (hovered) 0.10 else 0.045,
            }, 1.0);
            const col: [4]f64 = if (hovered)
                .{ 0.92, 0.95, 0.99, 0.98 }
            else
                .{ 0.68, 0.74, 0.84, 0.88 };
            _ = drawTextCentered(cr, st.text[0..st.text_len], sx + 10, cy + 0.3, g.font[0..g.font_len], "Medium", 8.4, col, status_w - 20, 0);
            addBarHit(sx, cy - 11, status_w, 22, .{ .kind = .status, .value = si });
            sx += status_w + 6.0;
        }
    }

    end(s, d);
}

fn addOverlayHit(x: f64, y: f64, w: f64, h: f64, hit: m.Hit) void {
    if (g.overlay_hit_count >= g.overlay_hits.len) return;
    g.overlay_hits[g.overlay_hit_count] = .{
        .x = g.overlay_hit_x + x * g.overlay_hit_scale,
        .y = g.overlay_hit_y + y * g.overlay_hit_scale,
        .w = w * g.overlay_hit_scale,
        .h = h * g.overlay_hit_scale,
        .hit = hit,
    };
    g.overlay_hit_count += 1;
}

fn drawLauncherPanel(cr: *c.cairo_t, px: f64, py: f64, pw: f64, ph: f64, t: f64) void {
    const accent = g.accent;
    const fam = g.font[0..g.font_len];

    c.cairo_push_group(cr);

    // shadow
    var i: usize = 0;
    while (i < 7) : (i += 1) {
        const expand = 8.0 + @as(f64, @floatFromInt(i)) * 5.0;
        fillRound(cr, px - expand, py - expand + 8, pw + expand * 2, ph + expand * 2, 28 + expand, .{ 0, 0, 0, 0.035 });
    }

    fillRound(cr, px, py, pw, ph, 24, .{ 0.055, 0.072, 0.105, 0.985 });
    roundRect(cr, px, py, pw, ph, 24);
    linearGradient(cr, px, py, px, py + ph, .{ 0.085, 0.105, 0.15, 0.99 }, .{ 0.032, 0.043, 0.068, 0.99 });
    c.cairo_fill(cr);
    strokeRound(cr, px + 0.5, py + 0.5, pw - 1, ph - 1, 23.5, .{ 1, 1, 1, 0.11 }, 1.0);

    const top_pat = c.cairo_pattern_create_linear(px + 40, 0, px + pw - 40, 0);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 0, accent[0], accent[1], accent[2], 0);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 0.5, accent[0], accent[1], accent[2], 0.75);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 1, accent[0], accent[1], accent[2], 0);
    c.cairo_set_source(cr, top_pat);
    c.cairo_rectangle(cr, px + 28, py + 1, pw - 56, 1.4);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(top_pat);

    // header
    drawPetal(cr, px + 44, py + 44, 10.0, .{ accent[0], accent[1], accent[2], 1.0 });
    _ = drawText(cr, "Tessa", px + 64, py + 26, fam, "Semi-Bold", 24, .{ 0.94, 0.96, 0.99, 0.98 }, 0, 0);
    _ = drawText(cr, "SUMI SHELL  /  LAUNCHER", px + 66, py + 60, fam, "Medium", 7.8, .{ 0.64, 0.70, 0.80, 0.42 }, 0, 1.8);

    // search box
    const sx = px + 32;
    const sy = py + 90;
    const sw = pw - 64;
    const sh = 50.0;
    fillRound(cr, sx, sy, sw, sh, 14, .{ 1, 1, 1, 0.045 });
    strokeRound(cr, sx + 0.5, sy + 0.5, sw - 1, sh - 1, 13.5, .{ 1, 1, 1, 0.075 }, 1.0);

    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, sx + 25, sy + 24, 5.5, 0, PI * 2.0);
    setColor(cr, .{ accent[0], accent[1], accent[2], 0.9 });
    c.cairo_set_line_width(cr, 1.4);
    c.cairo_stroke(cr);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, sx + 29, sy + 28.5);
    c.cairo_line_to(cr, sx + 34, sy + 33.5);
    c.cairo_stroke(cr);

    const query = g.query[0..g.query_len];
    const preedit = g.preedit[0..g.preedit_len];
    const text_x = sx + 46.0;
    if (query.len == 0 and preedit.len == 0) {
        _ = drawTextCentered(cr, "Search applications...", text_x, sy + sh / 2.0, fam, "Regular", 12.2, .{ 0.56, 0.61, 0.70, 0.78 }, sw - 110, 0);
    } else {
        var cursor_x = text_x;
        if (query.len > 0) {
            const size = drawTextCentered(cr, query, cursor_x, sy + sh / 2.0, fam, "Regular", 12.2, .{ 0.94, 0.96, 0.99, 0.98 }, sw - 110, 0);
            cursor_x += size.w;
        }
        if (preedit.len > 0) {
            const psize = drawTextCentered(cr, preedit, cursor_x, sy + sh / 2.0, fam, "Regular", 12.2, .{ accent[0], accent[1], accent[2], 0.98 }, sw - 110, 0);
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, cursor_x, sy + 37);
            c.cairo_line_to(cr, cursor_x + psize.w, sy + 37);
            setColor(cr, .{ accent[0], accent[1], accent[2], 0.55 });
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);
            cursor_x += psize.w;
        }
        if (@mod(m.nowMs(), 1000) < 520) {
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, cursor_x + 1.5, sy + 16);
            c.cairo_line_to(cr, cursor_x + 1.5, sy + 34);
            setColor(cr, .{ accent[0], accent[1], accent[2], 0.9 });
            c.cairo_set_line_width(cr, 1.4);
            c.cairo_stroke(cr);
        }
    }

    fillRound(cr, sx + sw - 48, sy + 15, 34, 20, 6, .{ 1, 1, 1, 0.045 });
    _ = drawTextCentered(cr, "ESC", sx + sw - 40.5, sy + 25.5, MONO, "Medium", 7.2, .{ 0.65, 0.71, 0.81, 0.55 }, 0, 0.8);

    // divider
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, px + 32, py + 158);
    c.cairo_line_to(cr, px + pw - 32, py + 158);
    setColor(cr, .{ 1, 1, 1, 0.055 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const label = if (query.len == 0) "APPLICATIONS" else "RESULTS";
    _ = drawText(cr, label, px + 34, py + 170, fam, "Semi-Bold", 7.8, .{ 0.64, 0.70, 0.80, 0.40 }, 0, 1.6);
    var count_buf: [32]u8 = undefined;
    const count = std.fmt.bufPrint(&count_buf, "{d} {s}", .{
        g.result_count,
        if (query.len == 0) "APPS" else "MATCHES",
    }) catch "";
    const count_w = textWidth(cr, count, MONO, "Medium", 7.4, 0.8);
    _ = drawText(cr, count, px + pw - 34 - count_w, py + 170, MONO, "Medium", 7.4, .{ 0.60, 0.66, 0.76, 0.40 }, 0, 0.8);

    g.overlay_hit_count = 0;
    g.overlay_panel = .{ .x = px, .y = py, .w = pw, .h = ph };

    const row_x = px + 28;
    const row_w = pw - 56;
    const row_h = 48.0;
    const row_gap = 4.0;
    const row_y0 = py + 188;
    const visible: usize = 7;

    if (g.result_count == 0) {
        drawPetal(cr, px + pw / 2.0, py + 320, 18, .{ 1, 1, 1, 0.10 });
        _ = drawTextCentered(cr, "Nothing matches", px + pw / 2.0 - 70, py + 370, fam, "Semi-Bold", 13.0, .{ 0.86, 0.89, 0.94, 0.75 }, 140, 0);
        _ = drawTextCentered(cr, "Try another word, or open a terminal.", px + pw / 2.0 - 110, py + 392, fam, "Regular", 9.2, .{ 0.60, 0.66, 0.75, 0.55 }, 220, 0);
    } else {
        var row: usize = 0;
        while (row < visible) : (row += 1) {
            const idx = g.scroll + row;
            if (idx >= g.result_count) break;
            const app_index = g.results[idx];
            if (app_index >= g.app_list.count) continue;
            const app = &g.app_list.apps[app_index];
            const y = row_y0 + @as(f64, @floatFromInt(row)) * (row_h + row_gap);
            const selected = idx == g.selected;
            const hovered = row == g.overlay_row_hover;

            if (selected) {
                fillRound(cr, row_x, y, row_w, row_h, 10, .{ accent[0], accent[1], accent[2], 0.14 });
                strokeRound(cr, row_x + 0.5, y + 0.5, row_w - 1, row_h - 1, 9.5, .{ accent[0], accent[1], accent[2], 0.20 }, 1.0);
                fillRound(cr, row_x + 1.5, y + 13, 3, 22, 1.5, .{ accent[0], accent[1], accent[2], 0.95 });
            } else if (hovered) {
                fillRound(cr, row_x, y, row_w, row_h, 10, .{ 1, 1, 1, 0.035 });
            }

            const col = appColor(app);
            fillRound(cr, row_x + 14, y + 8, 32, 32, 9, .{ col[0], col[1], col[2], 0.9 });
            var gbuf: [8]u8 = undefined;
            const glyph = upperFirst(&gbuf, firstGlyph(app.name[0..app.name_len]));
            _ = drawTextCentered(cr, glyph, row_x + 21, y + 24, fam, "Semi-Bold", 11.5, .{ 1, 1, 1, 0.96 }, 0, 0);

            _ = drawText(cr, app.name[0..app.name_len], row_x + 60, y + 10, fam, "Semi-Bold", 11.2, if (selected) .{ 0.97, 0.98, 1, 1 } else .{ 0.86, 0.90, 0.95, 0.9 }, row_w - 130, 0);
            _ = drawText(cr, app.comment[0..app.comment_len], row_x + 60, y + 28, fam, "Regular", 8.7, .{ 0.62, 0.68, 0.77, 0.62 }, row_w - 130, 0);

            if (app.terminal) {
                fillRound(cr, row_x + row_w - 78, y + 16, 34, 16, 5, .{ 1, 1, 1, 0.05 });
                _ = drawTextCentered(cr, "TERM", row_x + row_w - 72, y + 24.5, MONO, "Medium", 6.4, .{ 0.65, 0.71, 0.81, 0.6 }, 0, 0.7);
            }
            if (selected) {
                const arrow = "\xe2\x86\xb5";
                _ = drawTextCentered(cr, arrow, row_x + row_w - 27, y + 24, MONO, "Medium", 12.0, .{ accent[0], accent[1], accent[2], 0.95 }, 0, 0);
            }

            addOverlayHit(row_x, y, row_w, row_h, .{ .kind = .app, .value = app_index });
        }
    }

    // footer
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, px + 32, py + ph - 52);
    c.cairo_line_to(cr, px + pw - 32, py + ph - 52);
    setColor(cr, .{ 1, 1, 1, 0.045 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    _ = drawText(cr, "\xe2\x86\x91\xe2\x86\x93  navigate      \xe2\x86\xb5  open      esc  close", px + 34, py + ph - 38, fam, "Medium", 8.2, .{ 0.60, 0.66, 0.75, 0.55 }, 0, 0.6);
    drawPetal(cr, px + pw - 96, py + ph - 33, 5, .{ 1, 1, 1, 0.18 });
    _ = drawText(cr, "TESSA", px + pw - 86, py + ph - 38, fam, "Semi-Bold", 7.2, .{ 1, 1, 1, 0.22 }, 0, 1.4);

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
}

const PopoverLayout = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
};

fn popoverLayout(mode: m.OverlayMode, W: f64, H: f64) PopoverLayout {
    const w: f64 = switch (mode) {
        .calendar => 376.0,
        .clipboard => 560.0,
        .media => 380.0,
        .tray => 400.0,
        .audio => 380.0,
        else => 336.0,
    };
    const h: f64 = switch (mode) {
        .calendar => 400.0,
        .clipboard => if (g.clipboard_count == 0)
            300.0
        else
            130.0 + @as(f64, @floatFromInt(g.clipboard_count)) * 50.0,
        .media => 260.0,
        .audio => 270.0,
        .tray => if (g.tray_count == 0)
            210.0
        else
            92.0 + @as(f64, @floatFromInt(g.tray_count)) * 46.0,
        else => 360.0,
    };
    const margin: f64 = @floatFromInt(g.bar_side_margin);
    const bar_bottom: f64 = @floatFromInt(g.bar_top_margin + g.bar_height);
    var x = switch (mode) {
        .calendar, .tray => W - margin - w,
        .clipboard, .media, .audio => (W - w) / 2.0,
        else => margin,
    };
    var y = switch (mode) {
        .clipboard, .media, .audio => (H - h) / 2.0,
        else => bar_bottom + 8.0,
    };
    x = std.math.clamp(x, 8.0, @max(8.0, W - w - 8.0));
    if (y + h > H - 8.0 or y < 8.0) y = std.math.clamp(y, 8.0, @max(8.0, H - h - 8.0));
    return .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawPopoverCard(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64) void {
    const accent = g.accent;
    var i: usize = 0;
    while (i < 7) : (i += 1) {
        const expand = 6.0 + @as(f64, @floatFromInt(i)) * 4.0;
        fillRound(cr, x - expand, y - expand + 6, w + expand * 2, h + expand * 2, 22 + expand, .{
            0, 0, 0, 0.032,
        });
    }

    fillRound(cr, x, y, w, h, 18, .{ 0.055, 0.072, 0.105, 0.985 });
    roundRect(cr, x, y, w, h, 18);
    linearGradient(cr, x, y, x, y + h, .{ 0.088, 0.108, 0.152, 0.99 }, .{
        0.032, 0.043, 0.068, 0.99,
    });
    c.cairo_fill(cr);
    strokeRound(cr, x + 0.5, y + 0.5, w - 1, h - 1, 17.5, .{ 1, 1, 1, 0.11 }, 1.0);

    const top_pat = c.cairo_pattern_create_linear(x + 32, 0, x + w - 32, 0);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 0, accent[0], accent[1], accent[2], 0);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 0.5, accent[0], accent[1], accent[2], 0.75);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 1, accent[0], accent[1], accent[2], 0);
    c.cairo_set_source(cr, top_pat);
    c.cairo_rectangle(cr, x + 24, y + 1, w - 48, 1.4);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(top_pat);
}

fn drawCalendarPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = g.font[0..g.font_len];
    const p = popoverLayout(.calendar, W, H);
    const x = p.x;
    const y = p.y;
    const w = p.w;
    const h = p.h;

    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1;
    g.overlay_hit_x = x;
    g.overlay_hit_y = y;

    c.cairo_push_group(cr);
    drawPopoverCard(cr, x, y, w, h);

    const month_i = @mod(g.calendar_month - 1, 12);
    const month_name = m.month_names[@intCast(month_i)];
    _ = drawText(cr, "CALENDAR", x + 24, y + 18, fam, "Medium", 7.6, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.7);
    var title_buf: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "{s} {d}", .{ month_name, g.calendar_year }) catch month_name;
    _ = drawText(cr, title, x + 24, y + 34, fam, "Semi-Bold", 19.5, .{
        0.95, 0.97, 0.99, 0.98,
    }, w - 140, 0);

    const nav_y = y + 20;
    const prev_x = x + w - 24 - 32 - 8 - 32;
    const next_x = x + w - 24 - 32;
    const prev_hover = g.overlay_row_hover == 0;
    const next_hover = g.overlay_row_hover == 1;
    if (prev_hover) fillRound(cr, prev_x, nav_y, 32, 32, 9, .{ 1, 1, 1, 0.075 });
    if (next_hover) fillRound(cr, next_x, nav_y, 32, 32, 9, .{ 1, 1, 1, 0.075 });
    strokeRound(cr, prev_x + 0.5, nav_y + 0.5, 31, 31, 8.5, .{ 1, 1, 1, 0.07 }, 1);
    strokeRound(cr, next_x + 0.5, nav_y + 0.5, 31, 31, 8.5, .{ 1, 1, 1, 0.07 }, 1);
    _ = drawTextCentered(cr, "<", prev_x + 16, nav_y + 16, MONO, "Medium", 12.0, .{
        0.74, 0.80, 0.89, 0.85,
    }, 0, 0);
    _ = drawTextCentered(cr, ">", next_x + 16, nav_y + 16, MONO, "Medium", 12.0, .{
        0.74, 0.80, 0.89, 0.85,
    }, 0, 0);
    addOverlayHit(prev_x - x, nav_y - y, 32, 32, .{ .kind = .calendar_prev });
    addOverlayHit(next_x - x, nav_y - y, 32, 32, .{ .kind = .calendar_next });

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + 72);
    c.cairo_line_to(cr, x + w - 24, y + 72);
    setColor(cr, .{ 1, 1, 1, 0.06 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const grid_x = x + 24.0;
    const cell_w = (w - 48.0) / 7.0;
    const weekday_short = [_][]const u8{ "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" };
    var col: usize = 0;
    while (col < 7) : (col += 1) {
        const cx = grid_x + @as(f64, @floatFromInt(col)) * cell_w + cell_w / 2.0;
        _ = drawTextCentered(cr, weekday_short[col], cx, y + 88, MONO, "Medium", 7.1, .{
            0.58, 0.64, 0.74, 0.55,
        }, 0, 0.8);
    }

    var now_t: c.time_t = c.time(null);
    var now_tm: c.tm = undefined;
    _ = c.localtime_r(&now_t, &now_tm);
    const today_year = @as(i32, @intCast(now_tm.tm_year)) + 1900;
    const today_month = @as(i32, @intCast(now_tm.tm_mon)) + 1;
    const today_day = @as(i32, @intCast(now_tm.tm_mday));

    const days = m.daysInMonth(g.calendar_year, g.calendar_month);
    const first = m.firstWeekday(g.calendar_year, g.calendar_month);
    const grid_y = y + 102.0;
    const cell_h = 38.0;

    var day: i32 = 1;
    while (day <= days) : (day += 1) {
        const cell_index = first + day - 1;
        const row = @divTrunc(cell_index, 7);
        if (row > 5) break;
        const col_i: usize = @intCast(@mod(cell_index, 7));
        const cx = grid_x + @as(f64, @floatFromInt(col_i)) * cell_w + cell_w / 2.0;
        const cy = grid_y + @as(f64, @floatFromInt(row)) * cell_h + cell_h / 2.0;
        const is_today = g.calendar_year == today_year and
            g.calendar_month == today_month and day == today_day;
        if (is_today) {
            fillCircle(cr, cx, cy, 14.5, .{ accent[0], accent[1], accent[2], 0.95 });
        }
        var day_buf: [4]u8 = undefined;
        const day_text = std.fmt.bufPrint(&day_buf, "{d}", .{day}) catch "";
        _ = drawTextCentered(cr, day_text, cx, cy + 0.3, MONO, "Medium", 9.6, if (is_today) .{
            0.055, 0.075, 0.105, 1.0,
        } else .{ 0.79, 0.84, 0.91, 0.92 }, 0, 0);
    }

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + h - 48);
    c.cairo_line_to(cr, x + w - 24, y + h - 48);
    setColor(cr, .{ 1, 1, 1, 0.05 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const today_label = m.weekday_names[@intCast(@mod(now_tm.tm_wday, 7))];
    var today_buf: [64]u8 = undefined;
    const today_text = std.fmt.bufPrint(&today_buf, "{s}, {s} {d}", .{
        today_label,
        m.month_names[@intCast(@mod(today_month - 1, 12))],
        today_day,
    }) catch "Today";
    _ = drawText(cr, "TODAY", x + 24, y + h - 40, fam, "Medium", 7.2, .{
        0.64, 0.70, 0.80, 0.42,
    }, 0, 1.4);
    _ = drawText(cr, today_text, x + 24, y + h - 27, fam, "Medium", 8.8, .{
        0.82, 0.87, 0.94, 0.85,
    }, w - 120, 0);

    const today_x = x + w - 24 - 56;
    const today_y = y + h - 38;
    const today_hover = g.overlay_row_hover == 2;
    fillRound(cr, today_x, today_y, 56, 24, 7, .{
        1, 1, 1, if (today_hover) 0.09 else 0.045,
    });
    _ = drawTextCentered(cr, "TODAY", today_x + 28, today_y + 12, MONO, "Medium", 6.8, .{
        0.72, 0.78, 0.87, 0.72,
    }, 0, 0.6);
    addOverlayHit(today_x - x, today_y - y, 56, 24, .{ .kind = .calendar_today });

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);

    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawPowerPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = g.font[0..g.font_len];
    const p = popoverLayout(.power, W, H);
    const x = p.x;
    const y = p.y;
    const w = p.w;
    const h = p.h;

    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1;
    g.overlay_hit_x = x;
    g.overlay_hit_y = y;

    c.cairo_push_group(cr);
    drawPopoverCard(cr, x, y, w, h);

    drawPetal(cr, x + 31, y + 33, 7.5, .{ accent[0], accent[1], accent[2], 0.95 });
    _ = drawText(cr, "SYSTEM", x + 48, y + 19, fam, "Medium", 7.4, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.6);
    _ = drawText(cr, "Power", x + 48, y + 33, fam, "Semi-Bold", 21.0, .{
        0.95, 0.97, 0.99, 0.98,
    }, w - 72, 0);

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + 70);
    c.cairo_line_to(cr, x + w - 24, y + 70);
    setColor(cr, .{ 1, 1, 1, 0.06 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const row_w = w - 32.0;
    const row_h = 44.0;
    const row_gap = 4.0;
    const row_y0 = y + 78.0;
    var i: usize = 0;
    while (i < m.POWER_ACTION_COUNT) : (i += 1) {
        const row_y = row_y0 + @as(f64, @floatFromInt(i)) * (row_h + row_gap);
        const selected = i == g.power_selected;
        const hovered = i == g.overlay_row_hover;
        if (selected) {
            fillRound(cr, x + 16, row_y, row_w, row_h, 10, .{
                accent[0], accent[1], accent[2], 0.14,
            });
            strokeRound(cr, x + 16.5, row_y + 0.5, row_w - 1, row_h - 1, 9.5, .{
                accent[0], accent[1], accent[2], 0.24,
            }, 1);
            fillRound(cr, x + 17.5, row_y + 12, 3, 20, 1.5, .{
                accent[0], accent[1], accent[2], 0.95,
            });
        } else if (hovered) {
            fillRound(cr, x + 16, row_y, row_w, row_h, 10, .{ 1, 1, 1, 0.035 });
        }

        const col: [3]f64 = if (i == m.POWER_ACTION_COUNT - 1)
            .{ accent[0], accent[1], accent[2] }
        else
            palette[i % palette.len];
        fillRound(cr, x + 30, row_y + 9, 26, 26, 8, .{ col[0], col[1], col[2], 0.88 });
        const label = m.power_labels[i];
        _ = drawTextCentered(cr, label[0..1], x + 43, row_y + 22.3, fam, "Semi-Bold", 9.8, .{
            1, 1, 1, 0.96,
        }, 0, 0);
        _ = drawText(cr, label, x + 66, row_y + 7, fam, "Semi-Bold", 10.6, if (selected) .{
            0.98, 0.99, 1, 1,
        } else .{ 0.84, 0.89, 0.95, 0.9 }, row_w - 90, 0);
        _ = drawText(cr, m.power_details[i], x + 66, row_y + 24, fam, "Regular", 8.0, .{
            0.60, 0.66, 0.76, 0.58,
        }, row_w - 90, 0);
        if (selected) {
            _ = drawTextCentered(cr, "\xe2\x86\xb5", x + w - 38, row_y + row_h / 2.0, MONO, "Medium", 11.0, .{
                accent[0], accent[1], accent[2], 0.9,
            }, 0, 0);
        }
        addOverlayHit(16, row_y - y, row_w, row_h, .{ .kind = .power, .value = i });
    }

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + h - 34);
    c.cairo_line_to(cr, x + w - 24, y + h - 34);
    setColor(cr, .{ 1, 1, 1, 0.045 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);
    _ = drawText(cr, "\xe2\x86\x91\xe2\x86\x93  select      \xe2\x86\xb5  run      esc  close", x + 24, y + h - 24, fam, "Medium", 7.4, .{
        0.60, 0.66, 0.75, 0.55,
    }, w - 48, 0.4);

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);

    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

fn toastLine(buf: []u8, text: []const u8) []const u8 {
    const line_end = std.mem.indexOfAny(u8, text, "\r\n") orelse text.len;
    var len: usize = 0;
    m.copyTrunc(buf, &len, text[0..line_end]);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (buf[i] < 0x20) buf[i] = ' ';
    }
    return buf[0..len];
}

pub fn drawToasts(s: *m.Surface) void {
    const d = begin(s) orelse return;
    const cr = d.cr;
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    const accent = g.accent;
    const bg = g.panel_bg;
    const fg = g.panel_fg;
    const fam = g.font[0..g.font_len];
    g.toast_hit_count = 0;

    var region: ?*c.wl_region = null;
    if (g.compositor) |compositor| region = c.wl_compositor_create_region(compositor);

    var i: usize = 0;
    while (i < g.notification_count) : (i += 1) {
        const n = &g.notifications[i];
        const y = @as(f64, @floatFromInt(i)) * 90.0;
        if (y >= H) break;
        const hovered = g.pointer_surface == s and
            g.pointer_x >= 0 and g.pointer_x < W and
            g.pointer_y >= y and g.pointer_y < y + 82.0;

        fillRound(cr, 0, y, W, 82, 14, .{ 0.016, 0.023, 0.038, 0.72 });
        roundRect(cr, 0, y, W, 82, 14);
        linearGradient(cr, 0, y, 0, y + 82, .{
            bg[0] * 1.7 + 0.01,
            bg[1] * 1.7 + 0.01,
            bg[2] * 1.7 + 0.02,
            if (hovered) 0.985 else 0.965,
        }, .{ bg[0] * 1.05, bg[1] * 1.05, bg[2] * 1.08, 0.965 });
        c.cairo_fill(cr);
        strokeRound(cr, 0.5, y + 0.5, W - 1, 81, 13.5, .{ 1, 1, 1, if (hovered) 0.16 else 0.09 }, 1);

        const top_pat = c.cairo_pattern_create_linear(16, 0, W - 16, 0);
        c.cairo_pattern_add_color_stop_rgba(top_pat, 0, accent[0], accent[1], accent[2], 0.65);
        c.cairo_pattern_add_color_stop_rgba(top_pat, 1, accent[0], accent[1], accent[2], 0.0);
        c.cairo_set_source(cr, top_pat);
        c.cairo_rectangle(cr, 16, y + 0.8, W - 32, 1.2);
        c.cairo_fill(cr);
        c.cairo_pattern_destroy(top_pat);

        fillRound(cr, 16, y + 26, 28, 28, 9, .{ accent[0], accent[1], accent[2], 0.86 });
        var glyph_buf: [8]u8 = undefined;
        const app = if (n.app_len > 0) n.app[0..n.app_len] else "Notification";
        const glyph = upperFirst(&glyph_buf, firstGlyph(app));
        _ = drawTextCentered(cr, glyph, 25, y + 40, fam, "Semi-Bold", 10.5, .{
            1, 1, 1, 0.96,
        }, 0, 0);

        var app_buf: [80]u8 = undefined;
        const app_line = toastLine(&app_buf, app);
        _ = drawText(cr, app_line, 54, y + 10, fam, "Medium", 7.2, .{
            0.68, 0.74, 0.84, 0.55,
        }, W - 96, 0.9);

        var summary_buf: [180]u8 = undefined;
        const summary_text = if (n.summary_len > 0) n.summary[0..n.summary_len] else "Notification";
        const summary = toastLine(&summary_buf, summary_text);
        _ = drawText(cr, summary, 54, y + 23, fam, "Semi-Bold", 10.4, .{
            fg[0], fg[1], fg[2], 0.98,
        }, W - 96, 0);

        if (n.body_len > 0) {
            var body_buf: [560]u8 = undefined;
            const body = toastLine(&body_buf, n.body[0..n.body_len]);
            _ = drawText(cr, body, 54, y + 44, fam, "Regular", 8.3, .{
                0.68, 0.74, 0.83, 0.72,
            }, W - 96, 0);
        }

        _ = drawTextCentered(cr, "\xc3\x97", W - 22, y + 20, fam, "Medium", 12.0, .{
            0.76, 0.81, 0.88, if (hovered) 0.9 else 0.45,
        }, 0, 0);

        if (g.toast_hit_count < g.toast_hits.len) {
            g.toast_hits[g.toast_hit_count] = .{
                .x = 0,
                .y = y,
                .w = W,
                .h = 82,
                .hit = .{ .kind = .notification, .value = @intCast(n.id) },
            };
            g.toast_hit_count += 1;
        }
        if (region) |r| c.wl_region_add(r, 0, @intFromFloat(y), @intFromFloat(W), 82);
    }

    if (region) |r| {
        c.wl_surface_set_input_region(s.wl.?, r);
        c.wl_region_destroy(r);
    }

    // The input region contains only the cards, not the transparent gaps.
    end(s, d);
}

fn clipboardPreview(buf: []u8, text: []const u8) []const u8 {
    const line_end = std.mem.indexOfAny(u8, text, "\r\n") orelse text.len;
    var len: usize = 0;
    m.copyTrunc(buf, &len, text[0..line_end]);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (buf[i] < 0x20 and buf[i] != '\t') buf[i] = ' ';
    }
    if (len == 0) {
        const blank = "(blank)";
        @memcpy(buf[0..blank.len], blank);
        return buf[0..blank.len];
    }
    return buf[0..len];
}

fn drawClipboardPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = g.font[0..g.font_len];
    const p = popoverLayout(.clipboard, W, H);
    const x = p.x;
    const y = p.y;
    const w = p.w;
    const h = p.h;

    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1;
    g.overlay_hit_x = x;
    g.overlay_hit_y = y;

    c.cairo_push_group(cr);
    drawPopoverCard(cr, x, y, w, h);

    drawPetal(cr, x + 31, y + 33, 7.5, .{ accent[0], accent[1], accent[2], 0.95 });
    _ = drawText(cr, "CLIPBOARD", x + 48, y + 19, fam, "Medium", 7.4, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.6);
    _ = drawText(cr, "History", x + 48, y + 33, fam, "Semi-Bold", 21.0, .{
        0.95, 0.97, 0.99, 0.98,
    }, w - 72, 0);

    var count_buf: [48]u8 = undefined;
    const count = std.fmt.bufPrint(&count_buf, "{d} ITEMS  /  MEMORY ONLY", .{g.clipboard_count}) catch "";
    const count_w = textWidth(cr, count, MONO, "Medium", 7.1, 0.7);
    _ = drawText(cr, count, x + w - 24 - count_w, y + 34, MONO, "Medium", 7.1, .{
        0.60, 0.66, 0.76, 0.42,
    }, 0, 0.7);

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + 70);
    c.cairo_line_to(cr, x + w - 24, y + 70);
    setColor(cr, .{ 1, 1, 1, 0.06 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const row_x = x + 20.0;
    const row_w = w - 40.0;
    const row_h = 46.0;
    const row_gap = 4.0;
    const row_y0 = y + 82.0;

    if (g.clipboard_count == 0) {
        drawPetal(cr, x + w / 2.0, y + 150, 17, .{ 1, 1, 1, 0.10 });
        _ = drawTextCentered(cr, "Clipboard history is empty", x + w / 2.0 - 130, y + 188, fam, "Semi-Bold", 12.5, .{
            0.86, 0.89, 0.94, 0.75,
        }, 260, 0);
        _ = drawTextCentered(cr, "Copy text in any application, then open this again.", x + w / 2.0 - 190, y + 210, fam, "Regular", 9.0, .{
            0.60, 0.66, 0.75, 0.55,
        }, 380, 0);
    } else {
        var i: usize = 0;
        while (i < g.clipboard_count) : (i += 1) {
            const entry = &g.clipboard_entries[i];
            const row_y = row_y0 + @as(f64, @floatFromInt(i)) * (row_h + row_gap);
            const selected = i == g.clipboard_selected;
            const hovered = i == g.overlay_row_hover;
            if (selected) {
                fillRound(cr, row_x, row_y, row_w, row_h, 10, .{
                    accent[0], accent[1], accent[2], 0.14,
                });
                strokeRound(cr, row_x + 0.5, row_y + 0.5, row_w - 1, row_h - 1, 9.5, .{
                    accent[0], accent[1], accent[2], 0.22,
                }, 1);
                fillRound(cr, row_x + 1.5, row_y + 13, 3, 20, 1.5, .{
                    accent[0], accent[1], accent[2], 0.95,
                });
            } else if (hovered) {
                fillRound(cr, row_x, row_y, row_w, row_h, 10, .{ 1, 1, 1, 0.035 });
            }

            var num_buf: [8]u8 = undefined;
            const num = std.fmt.bufPrint(&num_buf, "{d}", .{i + 1}) catch "?";
            _ = drawTextCentered(cr, num, row_x + 21, row_y + row_h / 2.0, MONO, "Medium", 8.0, .{
                0.58, 0.64, 0.74, if (selected) 0.9 else 0.55,
            }, 0, 0);

            var preview_buf: [160]u8 = undefined;
            const preview = clipboardPreview(&preview_buf, entry.text[0..entry.len]);
            _ = drawTextCentered(cr, preview, row_x + 44, row_y + row_h / 2.0, fam, "Medium", 10.0, if (selected) .{
                0.97, 0.98, 1, 1,
            } else .{ 0.82, 0.87, 0.94, 0.88 }, row_w - 150, 0);

            var size_buf: [24]u8 = undefined;
            const size = std.fmt.bufPrint(&size_buf, "{d} B", .{entry.len}) catch "";
            const size_w = textWidth(cr, size, MONO, "Medium", 7.0, 0);
            _ = drawTextCentered(cr, size, row_x + row_w - 32 - size_w, row_y + row_h / 2.0, MONO, "Medium", 7.0, .{
                0.58, 0.64, 0.74, 0.42,
            }, 0, 0);
            if (selected) {
                _ = drawTextCentered(cr, "\xe2\x86\xb5", row_x + row_w - 18, row_y + row_h / 2.0, MONO, "Medium", 10.0, .{
                    accent[0], accent[1], accent[2], 0.9,
                }, 0, 0);
            }
            addOverlayHit(row_x - x, row_y - y, row_w, row_h, .{ .kind = .clipboard_entry, .value = i });
        }
    }

    const footer_divider = y + h - 44;
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, footer_divider);
    c.cairo_line_to(cr, x + w - 24, footer_divider);
    setColor(cr, .{ 1, 1, 1, 0.05 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    _ = drawText(cr, "\xe2\x86\x91\xe2\x86\x93  select      \xe2\x86\xb5  copy      esc  close", x + 24, y + h - 33, fam, "Medium", 7.5, .{
        0.60, 0.66, 0.75, 0.55,
    }, w - 140, 0.4);

    const clear_x = x + w - 24 - 62;
    const clear_y = y + h - 40;
    const clear_hover = g.overlay_row_hover == g.clipboard_count;
    fillRound(cr, clear_x, clear_y, 62, 24, 7, .{
        1, 1, 1, if (clear_hover and g.clipboard_count > 0) 0.09 else 0.045,
    });
    _ = drawTextCentered(cr, "CLEAR", clear_x + 31, clear_y + 12, MONO, "Medium", 6.8, .{
        0.72, 0.78, 0.87, if (g.clipboard_count > 0) 0.72 else 0.28,
    }, 0, 0.6);
    addOverlayHit(clear_x - x, clear_y - y, 62, 24, .{ .kind = .clipboard_clear });

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);

    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawScreenshotOverlay(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = g.font[0..g.font_len];

    fillRound(cr, 0, 0, W, H, 0, .{ 0.008, 0.012, 0.020, 0.38 * t });
    g.overlay_hit_count = 0;
    g.overlay_panel = .{ .x = 0, .y = 0, .w = W, .h = H };

    const sx = std.math.clamp(@min(g.screenshot_start_x, g.screenshot_end_x), 0, W);
    const sy = std.math.clamp(@min(g.screenshot_start_y, g.screenshot_end_y), 0, H);
    const ex = std.math.clamp(@max(g.screenshot_start_x, g.screenshot_end_x), 0, W);
    const ey = std.math.clamp(@max(g.screenshot_start_y, g.screenshot_end_y), 0, H);
    const select_w = ex - sx;
    const select_h = ey - sy;
    const has_selection = select_w > 0.5 and select_h > 0.5;

    if (has_selection) {
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_CLEAR);
        c.cairo_new_path(cr);
        c.cairo_rectangle(cr, sx, sy, select_w, select_h);
        c.cairo_fill(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        c.cairo_new_path(cr);
        c.cairo_rectangle(cr, sx + 0.75, sy + 0.75, @max(0.0, select_w - 1.5), @max(0.0, select_h - 1.5));
        setColor(cr, .{ accent[0], accent[1], accent[2], 0.95 * t });
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);

        const handle = 7.0;
        const corners = [_][2]f64{
            .{ sx, sy }, .{ ex, sy }, .{ sx, ey }, .{ ex, ey },
        };
        for (corners) |corner| {
            fillRound(cr, corner[0] - handle / 2.0, corner[1] - handle / 2.0, handle, handle, 2, .{
                accent[0], accent[1], accent[2], 0.95 * t,
            });
        }

        var size_buf: [48]u8 = undefined;
        const size_text = std.fmt.bufPrint(&size_buf, "{d} \xc3\x97 {d}", .{
            @as(i32, @intFromFloat(@round(select_w * @as(f64, @floatFromInt(@max(1, g.scale)))))),
            @as(i32, @intFromFloat(@round(select_h * @as(f64, @floatFromInt(@max(1, g.scale)))))),
        }) catch "";
        const tw = textWidth(cr, size_text, MONO, "Medium", 8.0, 0);
        var label_x = sx + 8;
        var label_y = ey + 8;
        if (label_y + 24 > H - 8) label_y = ey - 30;
        if (label_x + tw + 16 > W - 8) label_x = W - 8 - tw - 16;
        fillRound(cr, label_x, label_y, tw + 16, 22, 6, .{ 0.025, 0.035, 0.055, 0.82 * t });
        _ = drawTextCentered(cr, size_text, label_x + 8, label_y + 11, MONO, "Medium", 8.0, .{
            0.92, 0.95, 0.99, 0.9 * t,
        }, 0, 0);
    } else if (g.pointer_surface == g.overlay) {
        const px = g.pointer_x;
        const py = g.pointer_y;
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, 0, py + 0.5);
        c.cairo_line_to(cr, px - 14, py + 0.5);
        c.cairo_move_to(cr, px + 14, py + 0.5);
        c.cairo_line_to(cr, W, py + 0.5);
        c.cairo_move_to(cr, px + 0.5, 0);
        c.cairo_line_to(cr, px + 0.5, py - 14);
        c.cairo_move_to(cr, px + 0.5, py + 14);
        c.cairo_line_to(cr, px + 0.5, H);
        setColor(cr, .{ 1, 1, 1, 0.26 * t });
        c.cairo_set_line_width(cr, 1);
        c.cairo_stroke(cr);
        strokeRound(cr, px - 9, py - 9, 18, 18, 9, .{ 1, 1, 1, 0.30 * t }, 1);
    }

    const hint_w = 500.0;
    const hint_h = 34.0;
    const hint_x = (W - hint_w) / 2.0;
    const hint_y = H - hint_h - 28.0;
    fillRound(cr, hint_x, hint_y, hint_w, hint_h, 11, .{ 0.025, 0.035, 0.055, 0.88 * t });
    strokeRound(cr, hint_x + 0.5, hint_y + 0.5, hint_w - 1, hint_h - 1, 10.5, .{ 1, 1, 1, 0.10 * t }, 1);
    _ = drawTextCentered(cr, "SCREENSHOT", hint_x + 18, hint_y + hint_h / 2.0, MONO, "Medium", 7.4, .{
        accent[0], accent[1], accent[2], 0.95 * t,
    }, 0, 0.8);
    _ = drawTextCentered(cr, "drag to select      \xe2\x86\xb5  full screen      esc  cancel", hint_x + 104, hint_y + hint_h / 2.0, fam, "Medium", 8.0, .{
        0.76, 0.82, 0.90, 0.90 * t,
    }, hint_w - 120, 0.25);
}

fn drawAudioPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = g.font[0..g.font_len];
    const p = popoverLayout(.audio, W, H);
    const x = p.x;
    const y = p.y;
    const w = p.w;
    const h = p.h;
    const available = g.volume_percent >= 0;

    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1;
    g.overlay_hit_x = x;
    g.overlay_hit_y = y;

    c.cairo_push_group(cr);
    drawPopoverCard(cr, x, y, w, h);

    drawPetal(cr, x + 30, y + 32, 7.0, .{ accent[0], accent[1], accent[2], 0.95 });
    _ = drawText(cr, "AUDIO", x + 46, y + 18, fam, "Medium", 7.4, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.6);
    const source = g.volume_source[0..g.volume_source_len];
    if (source.len > 0) {
        const sw = textWidth(cr, source, MONO, "Medium", 7.0, 0.6);
        _ = drawText(cr, source, x + w - 24 - sw, y + 18, MONO, "Medium", 7.0, .{
            0.60, 0.66, 0.76, 0.45,
        }, 0, 0.6);
    }

    if (available) {
        var value_buf: [16]u8 = undefined;
        const value = std.fmt.bufPrint(&value_buf, "{d}", .{g.volume_percent}) catch "0";
        const value_col: [4]f64 = if (g.volume_muted)
            .{ 0.58, 0.63, 0.72, 0.55 }
        else
            .{ 0.96, 0.98, 1.0, 0.98 };
        const vw = drawText(cr, value, x + 24, y + 50, fam, "Semi-Bold", 46.0, value_col, w - 120, 0).w;
        _ = drawText(cr, "%", x + 28 + vw, y + 76, fam, "Medium", 15.0, .{
            value_col[0], value_col[1], value_col[2], 0.62,
        }, 0, 0);
        if (g.volume_muted) {
            const muted_w = textWidth(cr, "MUTED", MONO, "Medium", 7.2, 1.0);
            _ = drawText(cr, "MUTED", x + w - 24 - muted_w, y + 54, MONO, "Medium", 7.2, .{
                accent[0], accent[1], accent[2], 0.92,
            }, 0, 1.0);
        } else {
            const status_w = textWidth(cr, "OUTPUT VOLUME", MONO, "Medium", 7.0, 0.7);
            _ = drawText(cr, "OUTPUT VOLUME", x + w - 24 - status_w, y + 54, MONO, "Medium", 7.0, .{
                0.58, 0.64, 0.74, 0.42,
            }, 0, 0.7);
        }

        const bar_x = x + 24;
        const bar_y = y + 112;
        const bar_w = w - 48;
        fillRound(cr, bar_x, bar_y, bar_w, 8, 4, .{ 1, 1, 1, 0.07 });
        const pct = std.math.clamp(@as(f64, @floatFromInt(g.volume_percent)) / 100.0, 0.0, 1.0);
        if (pct > 0.005) {
            const fill_col: [4]f64 = if (g.volume_muted)
                .{ 0.56, 0.61, 0.70, 0.42 }
            else
                .{ accent[0], accent[1], accent[2], 0.92 };
            fillRound(cr, bar_x, bar_y, bar_w * pct, 8, 4, fill_col);
        }
        if (!g.volume_muted) {
            fillCircle(cr, bar_x + bar_w * pct, bar_y + 4, 4.5, .{ 1, 1, 1, 0.92 });
        }
        var tick: usize = 1;
        while (tick < 4) : (tick += 1) {
            fillRound(cr, bar_x + bar_w * @as(f64, @floatFromInt(tick)) / 4.0, bar_y + 13, 1, 3, 0.5, .{ 1, 1, 1, 0.06 });
        }
    } else {
        _ = drawText(cr, "No audio mixer found", x + 24, y + 58, fam, "Semi-Bold", 17.0, .{
            0.86, 0.90, 0.96, 0.84,
        }, w - 48, 0);
        _ = drawText(cr, "Install wpctl (PipeWire), pactl (PulseAudio), or amixer.", x + 24, y + 86, fam, "Regular", 8.6, .{
            0.60, 0.66, 0.76, 0.58,
        }, w - 48, 0);
        fillRound(cr, x + 24, y + 112, w - 48, 8, 4, .{ 1, 1, 1, 0.055 });
    }

    const labels = [_][]const u8{ "Vol -", if (g.volume_muted) "Unmute" else "Mute", "Vol +" };
    const hits = [_]m.HitKind{ .audio_down, .audio_mute, .audio_up };
    const button_w = 100.0;
    const button_h = 40.0;
    const gap = 10.0;
    const total_w = button_w * 3.0 + gap * 2.0;
    const start_x = x + (w - total_w) / 2.0;
    const button_y = y + 142;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const bx = start_x + @as(f64, @floatFromInt(i)) * (button_w + gap);
        const hovered = g.overlay_row_hover == i;
        const primary = i == 1;
        fillRound(cr, bx, button_y, button_w, button_h, 10, if (primary) .{
            accent[0], accent[1], accent[2], if (available) 0.88 else 0.25,
        } else .{
            1, 1, 1, if (hovered and available) 0.09 else 0.045,
        });
        if (!primary) {
            strokeRound(cr, bx + 0.5, button_y + 0.5, button_w - 1, button_h - 1, 9.5, .{
                1, 1, 1, 0.07,
            }, 1);
        }
        _ = drawTextCentered(cr, labels[i], bx + button_w / 2.0, button_y + button_h / 2.0, fam, "Semi-Bold", 9.6, if (primary) .{
            0.055, 0.075, 0.105, if (available) 1.0 else 0.5,
        } else .{ 0.82, 0.87, 0.94, if (available) 0.9 else 0.4 }, 0, 0);
        addOverlayHit(bx - x, button_y - y, button_w, button_h, .{ .kind = hits[i] });
    }

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + h - 46);
    c.cairo_line_to(cr, x + w - 24, y + h - 46);
    setColor(cr, .{ 1, 1, 1, 0.045 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);
    _ = drawText(cr, "\xe2\x86\x91/\xe2\x86\x93  volume      m  mute      esc  close", x + 24, y + h - 32, fam, "Medium", 7.4, .{
        0.60, 0.66, 0.75, 0.55,
    }, w - 48, 0.3);

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawTrayPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = g.font[0..g.font_len];
    const p = popoverLayout(.tray, W, H);
    const x = p.x;
    const y = p.y;
    const w = p.w;
    const h = p.h;

    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1;
    g.overlay_hit_x = x;
    g.overlay_hit_y = y;

    c.cairo_push_group(cr);
    drawPopoverCard(cr, x, y, w, h);

    drawPetal(cr, x + 30, y + 32, 7.0, .{ accent[0], accent[1], accent[2], 0.95 });
    _ = drawText(cr, "TRAY", x + 46, y + 18, fam, "Medium", 7.4, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.6);
    var count_buf: [32]u8 = undefined;
    const count_text = std.fmt.bufPrint(&count_buf, "{d} ITEM{s}", .{
        g.tray_count,
        if (g.tray_count == 1) "" else "S",
    }) catch "ITEMS";
    const count_w = textWidth(cr, count_text, MONO, "Medium", 7.0, 0.6);
    _ = drawText(cr, count_text, x + w - 24 - count_w, y + 18, MONO, "Medium", 7.0, .{
        0.60, 0.66, 0.76, 0.42,
    }, 0, 0.6);

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + 52);
    c.cairo_line_to(cr, x + w - 24, y + 52);
    setColor(cr, .{ 1, 1, 1, 0.06 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    if (g.tray_count == 0) {
        _ = drawTextCentered(cr, "No StatusNotifier items", x + w / 2.0, y + 104, fam, "Semi-Bold", 12.0, .{
            0.86, 0.90, 0.96, 0.82,
        }, w - 48, 0);
        _ = drawTextCentered(cr, "Tray applications register with org.kde.StatusNotifierWatcher.", x + w / 2.0, y + 128, fam, "Regular", 8.2, .{
            0.60, 0.66, 0.76, 0.55,
        }, w - 48, 0);
    } else {
        var i: usize = 0;
        while (i < g.tray_count) : (i += 1) {
            const item = &g.tray_items[i];
            const row_y = y + 60.0 + @as(f64, @floatFromInt(i)) * 46.0;
            const row_w = w - 40.0;
            const selected = g.tray_selected == i;
            const hovered = g.overlay_row_hover == i;
            if (selected) {
                fillRound(cr, x + 20, row_y, row_w, 40, 9, .{
                    accent[0], accent[1], accent[2], 0.16,
                });
                strokeRound(cr, x + 20.5, row_y + 0.5, row_w - 1, 39, 8.5, .{
                    accent[0], accent[1], accent[2], 0.34,
                }, 1);
            } else if (hovered) {
                fillRound(cr, x + 20, row_y, row_w, 40, 9, .{ 1, 1, 1, 0.055 });
            }
            paintTrayIcon(cr, item, x + 28, row_y + 8, 24);
            const title = if (item.title_len > 0) item.title[0..item.title_len] else "Tray item";
            _ = drawText(cr, title, x + 62, row_y + 9, fam, "Medium", 10.0, .{
                0.92, 0.95, 0.99, 0.95,
            }, row_w - 140, 0);
            const status_text = switch (item.status) {
                1 => "ACTIVE",
                2 => "ATTENTION",
                else => "PASSIVE",
            };
            const status_w = textWidth(cr, status_text, MONO, "Medium", 6.8, 0.5);
            _ = drawText(cr, status_text, x + w - 32 - status_w, row_y + 15, MONO, "Medium", 6.8, if (item.status == 2) .{
                accent[0], accent[1], accent[2], 0.95,
            } else .{ 0.58, 0.64, 0.74, 0.48 }, 0, 0.5);
            addOverlayHit(x + 20 - x, row_y - y, row_w, 40, .{ .kind = .tray_entry, .value = i });
        }
    }

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + h - 42);
    c.cairo_line_to(cr, x + w - 24, y + h - 42);
    setColor(cr, .{ 1, 1, 1, 0.045 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);
    _ = drawText(cr, "\xe2\x86\x91/\xe2\x86\x93  select      enter  activate      esc  close", x + 24, y + h - 30, fam, "Medium", 7.4, .{
        0.60, 0.66, 0.75, 0.55,
    }, w - 48, 0.3);

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawMediaPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = g.font[0..g.font_len];
    const p = popoverLayout(.media, W, H);
    const x = p.x;
    const y = p.y;
    const w = p.w;
    const h = p.h;
    const active = g.media_status == 1 or g.media_status == 2;

    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1;
    g.overlay_hit_x = x;
    g.overlay_hit_y = y;

    c.cairo_push_group(cr);
    drawPopoverCard(cr, x, y, w, h);

    drawPetal(cr, x + 30, y + 32, 7.0, .{ accent[0], accent[1], accent[2], 0.95 });
    _ = drawText(cr, "MEDIA", x + 46, y + 18, fam, "Medium", 7.4, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.6);
    var status_buf: [32]u8 = undefined;
    const status_text = switch (g.media_status) {
        1 => "PLAYING",
        2 => "PAUSED",
        3 => "STOPPED",
        else => "IDLE",
    };
    const player = g.media_player[0..g.media_player_len];
    const player_text = std.fmt.bufPrint(&status_buf, "{s}  /  {s}", .{
        if (player.len > 0) player else "MPRIS",
        status_text,
    }) catch status_text;
    const player_w = textWidth(cr, player_text, MONO, "Medium", 7.0, 0.6);
    _ = drawText(cr, player_text, x + w - 24 - player_w, y + 18, MONO, "Medium", 7.0, .{
        0.60, 0.66, 0.76, 0.42,
    }, 0, 0.6);

    const title = if (g.media_title_len > 0) g.media_title[0..g.media_title_len] else if (active) "Unknown title" else "No active player";
    const artist = if (g.media_artist_len > 0) g.media_artist[0..g.media_artist_len] else if (active) "MPRIS media" else "Start a media player to control it here.";
    const art_x = x + 24;
    const art_y = y + 42;
    const art_pat = c.cairo_pattern_create_linear(art_x, art_y, art_x + 60, art_y + 60);
    c.cairo_pattern_add_color_stop_rgba(art_pat, 0, accent[0], accent[1], accent[2], 0.9);
    c.cairo_pattern_add_color_stop_rgba(art_pat, 1, accent[0] * 0.35, accent[1] * 0.35, accent[2] * 0.5, 0.85);
    roundRect(cr, art_x, art_y, 60, 60, 14);
    c.cairo_set_source(cr, art_pat);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(art_pat);
    var glyph_buf: [8]u8 = undefined;
    const glyph = upperFirst(&glyph_buf, firstGlyph(if (title.len > 0) title else "M"));
    _ = drawTextCentered(cr, glyph, art_x + 21, art_y + 30, fam, "Semi-Bold", 20.0, .{
        1, 1, 1, 0.95,
    }, 0, 0);

    _ = drawText(cr, title, x + 100, y + 43, fam, "Semi-Bold", 16.0, if (active) .{
        0.96, 0.98, 1, 0.98,
    } else .{ 0.85, 0.89, 0.95, 0.8 }, w - 124, 0);
    _ = drawText(cr, artist, x + 100, y + 66, fam, "Regular", 9.2, .{
        0.66, 0.72, 0.81, 0.70,
    }, w - 124, 0);

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + 114);
    c.cairo_line_to(cr, x + w - 24, y + 114);
    setColor(cr, .{ 1, 1, 1, 0.06 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const labels = [_][]const u8{ "Prev", if (g.media_status == 1) "Pause" else "Play", "Next" };
    const hits = [_]m.HitKind{ .media_prev, .media_toggle, .media_next };
    const button_w = 96.0;
    const button_h = 40.0;
    const gap = 8.0;
    const total_w = button_w * 3.0 + gap * 2.0;
    const start_x = x + (w - total_w) / 2.0;
    const button_y = y + 130;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const bx = start_x + @as(f64, @floatFromInt(i)) * (button_w + gap);
        const hovered = g.overlay_row_hover == i;
        const primary = i == 1;
        fillRound(cr, bx, button_y, button_w, button_h, 10, if (primary) .{
            accent[0], accent[1], accent[2], if (active) 0.88 else 0.30,
        } else .{
            1, 1, 1, if (hovered and active) 0.09 else 0.045,
        });
        if (!primary) {
            strokeRound(cr, bx + 0.5, button_y + 0.5, button_w - 1, button_h - 1, 9.5, .{
                1, 1, 1, 0.07,
            }, 1);
        }
        _ = drawTextCentered(cr, labels[i], bx + 20, button_y + button_h / 2.0, fam, "Semi-Bold", 9.4, if (primary) .{
            0.055, 0.075, 0.105, if (active) 1.0 else 0.6,
        } else .{ 0.82, 0.87, 0.94, if (active) 0.9 else 0.4 }, 0, 0);
        addOverlayHit(bx - x, button_y - y, button_w, button_h, .{ .kind = hits[i] });
    }

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + h - 46);
    c.cairo_line_to(cr, x + w - 24, y + h - 46);
    setColor(cr, .{ 1, 1, 1, 0.045 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);
    _ = drawText(cr, "space  play/pause      \xe2\x86\x90/\xe2\x86\x92  previous/next      esc  close", x + 24, y + h - 34, fam, "Medium", 7.4, .{
        0.60, 0.66, 0.75, 0.55,
    }, w - 48, 0.3);

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

pub fn drawOverlay(s: *m.Surface) void {
    const d = begin(s) orelse return;
    const cr = d.cr;
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    const t = std.math.clamp(g.menu_anim, 0.0, 1.0);

    if (g.overlay_mode == .screenshot) {
        drawScreenshotOverlay(cr, W, H, t);
        end(s, d);
        return;
    }

    const dim: f64 = if (g.overlay_mode == .launcher) 0.52 else 0.30;

    fillRound(cr, 0, 0, W, H, 0, .{ 0.012, 0.018, 0.030, dim * t });
    const vp = c.cairo_pattern_create_radial(W / 2, H / 2, H * 0.12, W / 2, H / 2, H * 0.8);
    c.cairo_pattern_add_color_stop_rgba(vp, 0, 0, 0, 0, 0);
    c.cairo_pattern_add_color_stop_rgba(vp, 1, 0, 0, 0, 0.42 * t);
    c.cairo_set_source(cr, vp);
    c.cairo_paint(cr);
    c.cairo_pattern_destroy(vp);

    if (g.overlay_mode == .launcher) {
        const l = m.launcherLayout(W, H);
        g.overlay_hit_scale = l.scale;
        g.overlay_hit_x = l.x;
        g.overlay_hit_y = l.y;

        const anim = 0.984 + 0.016 * t;
        c.cairo_save(cr);
        c.cairo_translate(cr, l.x, l.y);
        c.cairo_scale(cr, l.scale, l.scale);
        c.cairo_translate(cr, 380.0, 310.0);
        c.cairo_scale(cr, anim, anim);
        c.cairo_translate(cr, -380.0, -310.0);
        drawLauncherPanel(cr, 0, 0, 760, 620, t);
        c.cairo_restore(cr);

        g.overlay_panel = .{
            .x = l.x,
            .y = l.y,
            .w = 760.0 * l.scale,
            .h = 620.0 * l.scale,
        };
    } else if (g.overlay_mode == .calendar) {
        drawCalendarPopover(cr, W, H, t);
    } else if (g.overlay_mode == .power) {
        drawPowerPopover(cr, W, H, t);
    } else if (g.overlay_mode == .clipboard) {
        drawClipboardPopover(cr, W, H, t);
    } else if (g.overlay_mode == .media) {
        drawMediaPopover(cr, W, H, t);
    } else if (g.overlay_mode == .tray) {
        drawTrayPopover(cr, W, H, t);
    } else if (g.overlay_mode == .audio) {
        drawAudioPopover(cr, W, H, t);
    }

    end(s, d);
}
