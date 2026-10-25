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
    const expected: usize = @as(usize, s.width) * 4 * @as(usize, s.height);
    if (s.buffers[0].wl != null and s.buffers[0].size == expected) return true;

    destroyBuffers(s);
    var i: usize = 0;
    while (i < s.buffers.len) : (i += 1) {
        if (!createBuffer(s, &s.buffers[i], s.width, s.height)) {
            destroyBuffers(s);
            return false;
        }
    }
    return true;
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

    const img = c.cairo_image_surface_create_for_data(
        @ptrCast(b.data.?),
        c.CAIRO_FORMAT_ARGB32,
        @intCast(s.width),
        @intCast(s.height),
        @intCast(@as(usize, s.width) * 4),
    ) orelse return null;
    const cr = c.cairo_create(img) orelse {
        c.cairo_surface_destroy(img);
        return null;
    };

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
    c.wl_surface_damage_buffer(s.wl.?, 0, 0, @intCast(s.width), @intCast(s.height));
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

pub fn drawBar(s: *m.Surface) void {
    const d = begin(s) orelse return;
    const cr = d.cr;
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    const cy = H / 2.0;
    const accent = g.accent;

    g.bar_hit_count = 0;

    fillRound(cr, 0, 0, W, H, 18, .{ 0.055, 0.075, 0.115, 0.96 });
    roundRect(cr, 0, 0, W, H, 18);
    linearGradient(cr, 0, 0, 0, H, .{ 0.085, 0.115, 0.17, 0.97 }, .{ 0.035, 0.05, 0.08, 0.97 });
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
    _ = drawTextCentered(cr, word, mark_x + 38, cy + 0.5, g.font[0..g.font_len], "Semi-Bold", 10.0, .{ 0.93, 0.95, 0.98, 0.92 }, 0, 1.8);

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
    var right = W - 16.0;
    const time = std.mem.sliceTo(&g.clock_buf, 0);
    const tw = textWidth(cr, time, MONO, "Medium", 12.0, 0);
    _ = drawTextCentered(cr, time, right - tw, cy + 0.3, MONO, "Medium", 12.0, .{ 0.94, 0.96, 0.99, 0.95 }, 0, 0);
    right -= tw + 12.0;

    const date = std.mem.sliceTo(&g.date_buf, 0);
    const dw = textWidth(cr, date, g.font[0..g.font_len], "Medium", 8.2, 0.9);
    _ = drawTextCentered(cr, date, right - dw, cy + 0.3, g.font[0..g.font_len], "Medium", 8.2, .{ 0.66, 0.72, 0.82, 0.55 }, 0, 0.9);
    right -= dw + 12.0;

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, right, cy - 7);
    c.cairo_line_to(cr, right, cy + 7);
    setColor(cr, .{ 1, 1, 1, 0.06 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);
    right -= 12.0;

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

    end(s, d);
}

fn addOverlayHit(x: f64, y: f64, w: f64, h: f64, hit: m.Hit) void {
    if (g.overlay_hit_count >= g.overlay_hits.len) return;
    g.overlay_hits[g.overlay_hit_count] = .{ .x = x, .y = y, .w = w, .h = h, .hit = hit };
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
    const text_x = sx + 46.0;
    if (query.len == 0) {
        _ = drawTextCentered(cr, "Search applications...", text_x, sy + sh / 2.0, fam, "Regular", 12.2, .{ 0.56, 0.61, 0.70, 0.78 }, sw - 110, 0);
    } else {
        const size = drawTextCentered(cr, query, text_x, sy + sh / 2.0, fam, "Regular", 12.2, .{ 0.94, 0.96, 0.99, 0.98 }, sw - 110, 0);
        if (@mod(m.nowMs(), 1000) < 520) {
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, text_x + size.w + 1.5, sy + 16);
            c.cairo_line_to(cr, text_x + size.w + 1.5, sy + 34);
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

pub fn drawOverlay(s: *m.Surface) void {
    const d = begin(s) orelse return;
    const cr = d.cr;
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    const t = std.math.clamp(g.menu_anim, 0.0, 1.0);

    fillRound(cr, 0, 0, W, H, 0, .{ 0.012, 0.018, 0.030, 0.52 * t });
    const vp = c.cairo_pattern_create_radial(W / 2, H / 2, H * 0.12, W / 2, H / 2, H * 0.8);
    c.cairo_pattern_add_color_stop_rgba(vp, 0, 0, 0, 0, 0);
    c.cairo_pattern_add_color_stop_rgba(vp, 1, 0, 0, 0, 0.42 * t);
    c.cairo_set_source(cr, vp);
    c.cairo_paint(cr);
    c.cairo_pattern_destroy(vp);

    const pw = @min(760.0, W - 80.0);
    const ph = @min(620.0, H - 80.0);
    const px = (W - pw) / 2.0;
    const py = (H - ph) / 2.0 - 14.0;

    const sc = 0.984 + 0.016 * t;
    c.cairo_save(cr);
    c.cairo_translate(cr, px + pw / 2.0, py + ph / 2.0);
    c.cairo_scale(cr, sc, sc);
    c.cairo_translate(cr, -(px + pw / 2.0), -(py + ph / 2.0));
    drawLauncherPanel(cr, px, py, pw, ph, t);
    c.cairo_restore(cr);

    end(s, d);
}
