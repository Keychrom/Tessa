const std = @import("std");
const c = @import("c.zig").c;
const m = @import("model.zig");
const gpu = @import("gpu.zig");
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

fn drawTextMarkup(cr: *c.cairo_t, text: []const u8, x: f64, y: f64, family: []const u8, style: []const u8, size: f64, col: [4]f64, max_w: f64, spacing: f64) TextSize {
    if (text.len == 0) return .{};
    var fam_buf: [128:0]u8 = undefined;
    var style_buf: [64:0]u8 = undefined;
    const fam = copyZBuf(128, &fam_buf, family);
    const sty = copyZBuf(64, &style_buf, style);
    var h: f64 = 0;
    const w = c.tessa_text_draw_markup(cr, text.ptr, @intCast(text.len), fam, sty, size, max_w, spacing, x, y, 0, col[0], col[1], col[2], col[3], &h);
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

/// Keep workspace pills compact: at most seven UTF-8 characters plus "..".
fn workspaceLabel(wi: usize, buf: *[32]u8) []const u8 {
    const name = g.ws_names[wi][0..g.ws_name_lens[wi]];
    if (name.len == 0) {
        return std.fmt.bufPrint(buf, "{d}", .{wi + 1}) catch "?";
    }
    var i: usize = 0;
    var chars: usize = 0;
    while (i < name.len and chars < 7) {
        const seq = std.unicode.utf8ByteSequenceLength(name[i]) catch 1;
        const n: usize = @intCast(seq);
        if (i + n > name.len) break;
        i += n;
        chars += 1;
    }
    if (i == name.len) {
        @memcpy(buf[0..i], name[0..i]);
        return buf[0..i];
    }
    @memcpy(buf[0..i], name[0..i]);
    buf[i] = '.';
    buf[i + 1] = '.';
    return buf[0 .. i + 2];
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
    if (s.kind == .background and m.g.panel_renderer == .gpu and s.configured) {
        const physical: u32 = @intCast(scl);
        if (gpu.configure(s, s.width * physical, s.height * physical)) {
            destroyBuffers(s);
            m.g.bg_base_dirty = true;
            m.g.mark_dirty = true;
            s.dirty = true;
            return;
        }
    }
    if (s.kind == .overlay and m.g.overlay_renderer == .gpu and s.configured) {
        const physical: u32 = @intCast(scl);
        if (gpu.configure(s, s.width * physical, s.height * physical)) {
            destroyBuffers(s);
            m.g.overlay_content_dirty = true;
            s.dirty = true;
            return;
        }
    }
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
    if (s.kind == .background and m.g.panel_renderer == .gpu) {
        const physical: u32 = @intCast(@max(1, s.scale));
        if (gpu.configure(s, width * physical, height * physical)) {
            destroyBuffers(s);
            m.g.bg_base_dirty = true;
            m.g.mark_dirty = true;
            s.dirty = true;
            return;
        }
    }
    if (s.kind == .overlay and m.g.overlay_renderer == .gpu) {
        const physical: u32 = @intCast(@max(1, s.scale));
        if (gpu.configure(s, width * physical, height * physical)) {
            destroyBuffers(s);
            m.g.overlay_content_dirty = true;
            s.dirty = true;
            return;
        }
    }
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

fn setCairoQuality(cr: *c.cairo_t) void {
    const opts = c.cairo_font_options_create();
    c.cairo_font_options_set_antialias(opts, c.CAIRO_ANTIALIAS_GRAY);
    c.cairo_font_options_set_hint_style(opts, c.CAIRO_HINT_STYLE_SLIGHT);
    c.cairo_set_font_options(cr, opts);
    c.cairo_font_options_destroy(opts);
    c.cairo_set_antialias(cr, c.CAIRO_ANTIALIAS_BEST);
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
    setCairoQuality(cr);

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

fn paintWallpaperImage(cr: *c.cairo_t, surface: *c.cairo_surface_t, w: f64, h: f64) bool {
    const iw_raw = c.cairo_image_surface_get_width(surface);
    const ih_raw = c.cairo_image_surface_get_height(surface);
    if (iw_raw <= 0 or ih_raw <= 0) return false;
    const iw: f64 = @floatFromInt(iw_raw);
    const ih: f64 = @floatFromInt(ih_raw);

    // Letterboxing and alpha need an opaque base.
    c.cairo_set_source_rgb(cr, g.bg_rgb[0], g.bg_rgb[1], g.bg_rgb[2]);
    c.cairo_paint(cr);

    var scale_x: f64 = w / iw;
    var scale_y: f64 = h / ih;
    switch (g.wallpaper_fit) {
        .cover => {
            const scale = @max(scale_x, scale_y);
            scale_x = scale;
            scale_y = scale;
        },
        .contain => {
            const scale = @min(scale_x, scale_y);
            scale_x = scale;
            scale_y = scale;
        },
        .stretch => {},
    }
    const draw_w = iw * scale_x;
    const draw_h = ih * scale_y;
    const x = (w - draw_w) / 2.0;
    const y = (h - draw_h) / 2.0;

    c.cairo_save(cr);
    c.cairo_rectangle(cr, 0, 0, w, h);
    c.cairo_clip(cr);
    c.cairo_translate(cr, x, y);
    c.cairo_scale(cr, scale_x, scale_y);
    c.cairo_set_source_surface(cr, surface, 0, 0);
    c.cairo_paint(cr);
    c.cairo_restore(cr);
    return true;
}

fn drawBackgroundArt(cr: *c.cairo_t, w: f64, h: f64) void {
    if (g.wallpaper_surface) |surface| {
        if (paintWallpaperImage(cr, surface, w, h)) return;
    }
    const bg = g.bg_rgb;
    const top = if (g.bg_top_set)
        [4]f64{ g.bg_top[0], g.bg_top[1], g.bg_top[2], 1.0 }
    else
        [4]f64{ bg[0] * 1.9 + 0.012, bg[1] * 1.9 + 0.018, bg[2] * 1.9 + 0.030, 1.0 };
    const bottom = if (g.bg_bottom_set)
        [4]f64{ g.bg_bottom[0], g.bg_bottom[1], g.bg_bottom[2], 1.0 }
    else
        [4]f64{ bg[0] * 0.55, bg[1] * 0.55, bg[2] * 0.6, 1.0 };
    paintGradientRect(cr, 0, 0, w, h, top, bottom);

    const accent = g.accent;
    if (g.wallpaper_art) {
        const art = std.math.clamp(g.wallpaper_art_opacity, 0.0, 1.0);
        // broad wash
        c.cairo_save(cr);
        c.cairo_translate(cr, w * 0.78, h * 0.24);
        c.cairo_scale(cr, 1.7, 1.0);
        radialFill(cr, 0, 0, 0, h * 0.44, .{ accent[0], accent[1], accent[2], 0.12 * art }, .{ accent[0], accent[1], accent[2], 0.0 });
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
            radialFill(cr, 0, 0, 0, h * b[2], .{ 0.10, 0.25, 0.28, b[3] * art }, .{ 0.10, 0.25, 0.28, 0.0 });
            c.cairo_restore(cr);
        }

        // sun
        const cx = w * 0.79;
        const cy = h * 0.235;
        const sr = h * 0.155;
        radialFill(cr, cx, cy, sr * 0.65, sr * 2.8, .{ accent[0], accent[1], accent[2], 0.18 * art }, .{ accent[0], accent[1], accent[2], 0.0 });

        c.cairo_save(cr);
        c.cairo_new_sub_path(cr);
        c.cairo_arc(cr, cx, cy, sr, 0, PI * 2.0);
        c.cairo_clip(cr);
        paintGradientRect(cr, cx - sr, cy - sr, sr * 2, sr * 2, .{ 0.93, 0.47, 0.35, 0.58 * art }, .{ 0.55, 0.15, 0.15, 0.26 * art });
        c.cairo_restore(cr);

        c.cairo_new_sub_path(cr);
        c.cairo_arc(cr, cx, cy, sr * 1.26, 0, PI * 2.0);
        setColor(cr, .{ accent[0], accent[1], accent[2], 0.18 * art });
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
            const tri_alpha: f64 = if (tri % 2 == 0) 0.010 else 0.004;
            setColor(cr, .{ 1.0, 1.0, 1.0, tri_alpha * art });
            c.cairo_fill(cr);
            setColor(cr, .{ 1.0, 1.0, 1.0, 0.012 * art });
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
            setColor(cr, .{ 1.0, 1.0, 1.0, (0.010 + 0.004 * @as(f64, @floatFromInt(k))) * art });
            c.cairo_set_line_width(cr, 0.8);
            c.cairo_stroke(cr);
        }
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
    _ = drawText(cr, "TESSA", w - 136, h - 36, m.popoverFont(), "Semi-Bold", 8, .{ 1, 1, 1, 0.20 }, 0, 2.4);
    _ = drawText(cr, "SUMI SHELL / 01", w - 136, h - 24, MONO, "Medium", 6.5, .{ 1, 1, 1, 0.10 }, 0, 1.2);
}

fn renderBackgroundBase(s: *m.Surface) ?*c.cairo_surface_t {
    const scale: u32 = @intCast(@max(1, s.scale));
    const buf_w = s.width * scale;
    const buf_h = s.height * scale;
    if (buf_w == 0 or buf_h == 0) return null;

    const img = c.cairo_image_surface_create(
        c.CAIRO_FORMAT_ARGB32,
        @intCast(buf_w),
        @intCast(buf_h),
    );
    if (img == null or c.cairo_surface_status(img) != c.CAIRO_STATUS_SUCCESS) {
        if (img) |surface| c.cairo_surface_destroy(surface);
        return null;
    }
    const cr = c.cairo_create(img) orelse {
        c.cairo_surface_destroy(img);
        return null;
    };
    const scl: f64 = @floatFromInt(scale);
    c.cairo_scale(cr, scl, scl);
    setCairoQuality(cr);
    drawBackgroundArt(cr, @floatFromInt(s.width), @floatFromInt(s.height));
    c.cairo_destroy(cr);
    c.cairo_surface_flush(img);
    return img;
}

fn renderBackgroundMark(s: *m.Surface) ?*c.cairo_surface_t {
    const scale: u32 = @intCast(@max(1, s.scale));
    const img = c.cairo_image_surface_create(
        c.CAIRO_FORMAT_ARGB32,
        @intCast(220 * scale),
        @intCast(60 * scale),
    );
    if (img == null or c.cairo_surface_status(img) != c.CAIRO_STATUS_SUCCESS) {
        if (img) |surface| c.cairo_surface_destroy(surface);
        return null;
    }
    const cr = c.cairo_create(img) orelse {
        c.cairo_surface_destroy(img);
        return null;
    };
    const scl: f64 = @floatFromInt(scale);
    c.cairo_scale(cr, scl, scl);
    setCairoQuality(cr);
    drawPetal(cr, 70, 30, 7, .{ 1, 1, 1, 0.16 });
    _ = drawText(cr, "TESSA", 84, 24, m.popoverFont(), "Semi-Bold", 8, .{ 1, 1, 1, 0.20 }, 0, 2.4);
    _ = drawText(cr, "SUMI SHELL / 01", 84, 36, MONO, "Medium", 6.5, .{ 1, 1, 1, 0.10 }, 0, 1.2);
    c.cairo_destroy(cr);
    c.cairo_surface_flush(img);
    return img;
}

fn backgroundPalette() gpu.Palette {
    const bg = m.g.bg_rgb;
    const top: [3]f64 = if (m.g.bg_top_set) m.g.bg_top else .{
        std.math.clamp(bg[0] * 1.9 + 0.012, 0, 1),
        std.math.clamp(bg[1] * 1.9 + 0.018, 0, 1),
        std.math.clamp(bg[2] * 1.9 + 0.030, 0, 1),
    };
    const bottom: [3]f64 = if (m.g.bg_bottom_set) m.g.bg_bottom else .{
        bg[0] * 0.55,
        bg[1] * 0.55,
        bg[2] * 0.6,
    };
    return .{
        .top = .{ @floatCast(top[0]), @floatCast(top[1]), @floatCast(top[2]) },
        .bottom = .{ @floatCast(bottom[0]), @floatCast(bottom[1]), @floatCast(bottom[2]) },
        .accent = .{ @floatCast(m.g.accent[0]), @floatCast(m.g.accent[1]), @floatCast(m.g.accent[2]) },
        .art = if (m.g.wallpaper_art)
            @floatCast(std.math.clamp(m.g.wallpaper_art_opacity, 0, 1))
        else
            0.0,
    };
}

fn drawBackgroundGpu(s: *m.Surface) bool {
    if (!gpu.ready()) return false;
    if (s.gpu == null) {
        const physical: u32 = @intCast(@max(1, s.scale));
        if (!gpu.configure(s, s.width * physical, s.height * physical)) return false;
        destroyBuffers(s);
    }
    const has_image = m.g.wallpaper_image_len > 0 or m.g.wallpaper_shader_len > 0;
    const procedural = m.g.wallpaper_engine == .procedural and !has_image;
    if (procedural) {
        if (m.g.mark_dirty) {
            if (renderBackgroundMark(s)) |mark| {
                defer c.cairo_surface_destroy(mark);
                _ = gpu.setMark(s, mark);
            }
            m.g.mark_dirty = false;
        }
    } else if (m.g.bg_base_dirty) {
        const base = renderBackgroundBase(s) orelse {
            gpu.fail("wallpaper base render failed");
            return false;
        };
        defer c.cairo_surface_destroy(base);
        if (!gpu.setBase(s, base)) return false;
        m.g.bg_base_dirty = false;
    }
    const animate = gpu.animationActive(m.nowMs());
    const time: f64 = if (animate)
        @as(f64, @floatFromInt(m.nowMs())) / 1000.0
    else
        0.0;
    const framed = if (animate) gpu.requestFrame(s) else false;
    if (!gpu.draw(s, backgroundPalette(), time, animate, procedural)) {
        gpu.cancelFrame();
        return false;
    }
    m.g.gpu_frame_pending = framed;
    s.dirty = false;
    return true;
}

pub fn drawBackground(s: *m.Surface) void {
    if (m.g.panel_renderer == .gpu) {
        if (m.g.gpu_frame_pending) {
            if (m.nowMs() - m.g.gpu_frame_ms < 250) return;
            gpu.cancelFrame();
        }
        if (drawBackgroundGpu(s)) return;
        gpu.destroySurface(s);
    }
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
    const tw = textWidth(cr, label, m.popoverFont(), "Medium", 8.2, 0.4);
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
    _ = drawTextCentered(cr, label, x + 20, cy + 0.3, m.popoverFont(), "Medium", 8.2, .{
        fg[0], fg[1], fg[2], 0.58,
    }, 0, 0.4);
    return x - 14;
}

fn drawControlsGlyph(cr: *c.cairo_t, x: f64, cy: f64, col: [4]f64) void {
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const y = cy - 5.0 + @as(f64, @floatFromInt(i)) * 5.0;
        fillRound(cr, x, y, 14.0, 1.5, 0.75, col);
        const knob_x = x + 3.0 + @as(f64, @floatFromInt((i * 5) % 9));
        fillCircle(cr, knob_x, y + 0.75, 2.2, col);
    }
}

fn drawBluetoothGlyph(cr: *c.cairo_t, cx: f64, cy: f64, size: f64, col: [4]f64) void {
    const h = size * 0.5;
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, cx, cy - h);
    c.cairo_line_to(cr, cx + h * 0.72, cy - h * 0.35);
    c.cairo_line_to(cr, cx - h * 0.55, cy + h * 0.35);
    c.cairo_line_to(cr, cx + h * 0.55, cy + h * 0.35);
    c.cairo_line_to(cr, cx, cy + h);
    c.cairo_line_to(cr, cx, cy - h);
    setColor(cr, col);
    c.cairo_set_line_width(cr, 1.4);
    c.cairo_stroke(cr);
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

fn paintNotificationIcon(cr: *c.cairo_t, n: *const m.NotificationEntry, x: f64, y: f64, size: f64) void {
    const accent = g.accent;
    var source: ?*c.cairo_surface_t = null;
    var temp = false;
    var iw: f64 = 0;
    var ih: f64 = 0;

    if (n.icon_len > 0 and n.icon_w > 0 and n.icon_h > 0) {
        iw = @floatFromInt(n.icon_w);
        ih = @floatFromInt(n.icon_h);
        const surf = c.cairo_image_surface_create_for_data(
            @ptrCast(@constCast(&n.icon_data)),
            c.CAIRO_FORMAT_ARGB32,
            @intCast(n.icon_w),
            @intCast(n.icon_h),
            @intCast(n.icon_w * 4),
        );
        if (c.cairo_surface_status(surf) == c.CAIRO_STATUS_SUCCESS) {
            source = surf;
            temp = true;
        } else {
            c.cairo_surface_destroy(surf);
        }
    } else if (n.icon_surface) |surf| {
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
        fillRound(cr, x, y, size, size, 9, .{ accent[0], accent[1], accent[2], 0.86 });
        const app = if (n.app_len > 0) n.app[0..n.app_len] else "Notification";
        var glyph_buf: [8]u8 = undefined;
        const glyph = upperFirst(&glyph_buf, firstGlyph(app));
        _ = drawTextCentered(cr, glyph, x + size / 2.0 - 2.8, y + size / 2.0 + 0.4, m.popoverFont(), "Semi-Bold", 10.5, .{
            1, 1, 1, 0.96,
        }, 0, 0);
    }
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
        _ = drawTextCentered(cr, glyph, x + size / 2.0 - 2.4, y + size / 2.0 + 0.3, m.popoverFont(), "Semi-Bold", 8.0, .{ 1, 1, 1, 0.95 }, 0, 0);
    }

    if (item.status == 2) {
        fillCircle(cr, x + size - 2.0, y + 2.0, 3.0, .{ accent[0], accent[1], accent[2], 1.0 });
    }
}

fn layoutLabel() []const u8 {
    const layout = g.active_layout[0..g.active_layout_len];
    if (std.mem.eql(u8, layout, "master")) return "MASTER";
    if (std.mem.eql(u8, layout, "mosaic")) return "MOSAIC";
    if (std.mem.eql(u8, layout, "grid")) return "GRID";
    if (std.mem.eql(u8, layout, "columns")) return "COLUMNS";
    if (std.mem.eql(u8, layout, "scrolling")) return "SCROLL";
    if (std.mem.eql(u8, layout, "monocle")) return "MONOCLE";
    if (std.mem.eql(u8, layout, "stacking")) return "STACK";
    return if (layout.len > 0) layout else "LAYOUT";
}

const GroupSummary = struct { count: u32 = 0, active: u32 = 0 };

fn groupSummary() GroupSummary {
    var ids: [m.MAX_WINDOWS]u32 = undefined;
    var count: u32 = 0;
    var summary = GroupSummary{};
    var wi: usize = 0;
    while (wi < g.window_count) : (wi += 1) {
        const w = &g.windows[wi];
        if (w.ws != g.active_ws or w.group_id == 0) continue;
        if (w.group_active) summary.active = w.group_id;
        var seen = false;
        var ii: usize = 0;
        while (ii < count) : (ii += 1) {
            if (ids[ii] == w.group_id) {
                seen = true;
                break;
            }
        }
        if (!seen and count < ids.len) {
            ids[count] = w.group_id;
            count += 1;
        }
    }
    summary.count = count;
    return summary;
}

fn drawContextPill(cr: *c.cairo_t, right: f64, cy: f64, label: []const u8, alpha: f64) f64 {
    const tw = textWidth(cr, label, MONO, "Medium", 8.2, 0.8);
    const pill_w = tw + 18.0;
    const x = right - pill_w;
    fillRound(cr, x, cy - 10, pill_w, 20, 6, .{
        g.accent[0], g.accent[1], g.accent[2], alpha,
    });
    strokeRound(cr, x + 0.5, cy - 9.5, pill_w - 1, 19, 5.5, .{
        g.accent[0], g.accent[1], g.accent[2], 0.22,
    }, 1.0);
    _ = drawTextCentered(cr, label, x + 9, cy + 0.3, MONO, "Medium", 8.2, .{
        g.accent[0], g.accent[1], g.accent[2], 0.96,
    }, tw + 2, 0.8);
    return x - 10.0;
}

/// Compact vertical bar used when bar_position is left or right.
fn drawBarVerticalModule(
    cr: *c.cairo_t,
    module: m.BarModule,
    y: f64,
    h: f64,
    W: f64,
    fg: [3]f64,
    accent: [3]f64,
) void {
    const cx = W / 2.0;
    switch (module) {
        .clock => {
            const time = std.mem.sliceTo(&g.clock_buf, 0);
            const time_w = textWidth(cr, time, MONO, "Medium", 8.6, 0);
            _ = drawTextCentered(cr, time, cx - time_w / 2.0, y + 15.0, MONO, "Medium", 8.6, .{
                fg[0], fg[1], fg[2], 0.95,
            }, W - 4.0, 0);
            const date_len = std.mem.indexOfScalar(u8, &g.date_buf, 0) orelse g.date_buf.len;
            const short = g.date_buf[0..@min(date_len, 6)];
            const date_w = textWidth(cr, short, m.barFont(), "Medium", 6.4, 0.3);
            _ = drawTextCentered(cr, short, cx - date_w / 2.0, y + 30.0, m.barFont(), "Medium", 6.4, .{
                0.66, 0.72, 0.82, 0.60,
            }, W - 4.0, 0.3);
            addBarHit(2, y, W - 4, h, .{ .kind = .clock });
        },
        .battery => {
            if (!g.show_battery or g.battery_percent < 0) return;
            const pct = std.math.clamp(@as(f64, @floatFromInt(g.battery_percent)) / 100.0, 0.0, 1.0);
            const col: [4]f64 = if (g.battery_charging)
                .{ accent[0], accent[1], accent[2], 0.95 }
            else
                .{ fg[0], fg[1], fg[2], 0.62 };
            const bx = cx - 10.0;
            const by = y + 4.0;
            strokeRound(cr, bx + 0.5, by + 0.5, 19, 10, 2.5, .{ 1, 1, 1, 0.28 }, 1);
            fillRound(cr, bx + 20, by + 3, 2, 4, 1, .{ 1, 1, 1, 0.25 });
            if (pct > 0.02) fillRound(cr, bx + 2.5, by + 2.5, 15.0 * pct, 5, 1.2, col);
            var buf: [16]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "{d}%", .{g.battery_percent}) catch "";
            const tw = textWidth(cr, text, MONO, "Medium", 6.6, 0);
            _ = drawTextCentered(cr, text, cx - tw / 2.0, y + 21.0, MONO, "Medium", 6.6, .{
                col[0], col[1], col[2], 0.88,
            }, W - 4.0, 0);
        },
        .network => {
            if (!g.show_network or !g.network_present) return;
            const bars = [_]f64{ 4.0, 7.0, 10.0 };
            var i: usize = 0;
            while (i < bars.len) : (i += 1) {
                const bh = bars[i];
                fillRound(cr, cx - 6.0 + @as(f64, @floatFromInt(i)) * 4.0, y + 12.0 - bh, 2.5, bh, 1, .{
                    accent[0], accent[1], accent[2], 0.78,
                });
            }
            const net_label = g.network_label[0..g.network_label_len];
            const net_w = textWidth(cr, net_label, m.barFont(), "Medium", 6.4, 0.3);
            _ = drawTextCentered(cr, net_label, cx - net_w / 2.0, y + 21.0, m.barFont(), "Medium", 6.4, .{
                fg[0], fg[1], fg[2], 0.62,
            }, W - 4.0, 0.3);
        },
        .volume => {
            if (!g.show_volume or g.volume_percent < 0) return;
            const col: [4]f64 = if (g.volume_muted)
                .{ fg[0], fg[1], fg[2], 0.38 }
            else
                .{ accent[0], accent[1], accent[2], 0.88 };
            const vx = cx - 9.0;
            const vy = y + 11.0;
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, vx + 1, vy - 3);
            c.cairo_line_to(cr, vx + 5, vy - 3);
            c.cairo_line_to(cr, vx + 10, vy - 7);
            c.cairo_line_to(cr, vx + 10, vy + 7);
            c.cairo_line_to(cr, vx + 5, vy + 3);
            c.cairo_line_to(cr, vx + 1, vy + 3);
            c.cairo_close_path(cr);
            setColor(cr, col);
            c.cairo_fill(cr);
            if (!g.volume_muted) {
                c.cairo_new_path(cr);
                c.cairo_arc(cr, vx + 10.5, vy, 4.5, -0.85, 0.85);
                setColor(cr, .{ col[0], col[1], col[2], 0.75 });
                c.cairo_set_line_width(cr, 1.3);
                c.cairo_stroke(cr);
            }
            var buf: [16]u8 = undefined;
            const text = if (g.volume_muted)
                "MUTE"
            else
                std.fmt.bufPrint(&buf, "{d}%", .{g.volume_percent}) catch "VOL";
            const tw = textWidth(cr, text, MONO, "Medium", 6.4, 0);
            _ = drawTextCentered(cr, text, cx - tw / 2.0, y + 22.0, MONO, "Medium", 6.4, .{
                col[0], col[1], col[2], 0.82,
            }, W - 4.0, 0);
            addBarHit(4, y, W - 8, h, .{ .kind = .volume });
        },
        .stats => {
            if (!g.show_stats) return;
            var cbuf: [32]u8 = undefined;
            var mbuf: [32]u8 = undefined;
            const cs = std.fmt.bufPrint(&cbuf, "CPU {d:.0}%", .{g.cpu_percent}) catch "CPU";
            const ms = std.fmt.bufPrint(&mbuf, "MEM {d:.0}%", .{g.mem_percent}) catch "MEM";
            const cw = textWidth(cr, cs, MONO, "Medium", 7.2, 0);
            const mw = textWidth(cr, ms, MONO, "Medium", 7.2, 0);
            _ = drawTextCentered(cr, cs, cx - cw / 2.0, y + 9.0, MONO, "Medium", 7.2, .{
                0.60, 0.67, 0.77, 0.60,
            }, W - 4.0, 0);
            _ = drawTextCentered(cr, ms, cx - mw / 2.0, y + 24.0, MONO, "Medium", 7.2, .{
                0.60, 0.67, 0.77, 0.60,
            }, W - 4.0, 0);
        },
        .media => {
            if (!g.show_media or (g.media_status != 1 and g.media_status != 2)) return;
            const my = y + h / 2.0;
            if (g.media_status == 1) {
                fillRound(cr, cx - 4, my - 5, 2.2, 10, 1, .{ accent[0], accent[1], accent[2], 0.95 });
                fillRound(cr, cx + 1, my - 5, 2.2, 10, 1, .{ accent[0], accent[1], accent[2], 0.95 });
            } else {
                c.cairo_new_path(cr);
                c.cairo_move_to(cr, cx - 4, my - 6);
                c.cairo_line_to(cr, cx + 6, my);
                c.cairo_line_to(cr, cx - 4, my + 6);
                c.cairo_close_path(cr);
                setColor(cr, .{ accent[0], accent[1], accent[2], 0.95 });
                c.cairo_fill(cr);
            }
            addBarHit(4, y, W - 8, h, .{ .kind = .media });
        },
        .tray => {
            if (!g.show_tray or g.tray_count == 0) return;
            const slot = 24.0;
            const icon_size = 18.0;
            var ti: usize = 0;
            while (ti < g.tray_count) : (ti += 1) {
                const item = &g.tray_items[ti];
                const iy = y + @as(f64, @floatFromInt(ti)) * slot;
                const hovered = g.hover.kind == .tray and g.hover.value == ti;
                if (hovered) {
                    fillRound(cr, 3, iy + 2, W - 6, 20, 6, .{
                        accent[0], accent[1], accent[2], 0.12,
                    });
                }
                paintTrayIcon(cr, item, (W - icon_size) / 2.0, iy + (slot - icon_size) / 2.0, icon_size);
                addBarHit(3, iy, W - 6, slot, .{ .kind = .tray, .value = ti });
            }
        },
        .status => {
            if (!g.show_status) return;
            var si: usize = 0;
            while (si < g.status_count) : (si += 1) {
                const st = &g.statuses[si];
                const row_y = y + @as(f64, @floatFromInt(si)) * 24.0;
                const hovered = g.hover.kind == .status and g.hover.value == si;
                fillRound(cr, 4, row_y + 1, W - 8, 22, 6, .{
                    1, 1, 1, if (hovered) 0.075 else 0.040,
                });
                strokeRound(cr, 4.5, row_y + 1.5, W - 9, 21, 5.5, .{
                    1, 1, 1, if (hovered) 0.10 else 0.045,
                }, 1.0);
                const icon = st.icon[0..st.icon_len];
                const text = st.text[0..st.text_len];
                const avail = W - 10.0;
                if (icon.len > 0) {
                    const iw = textWidth(cr, icon, m.barFont(), "Medium", 7.6, 0);
                    _ = drawTextCentered(cr, icon, cx - @min(iw, avail) / 2.0, row_y + 12.0, m.barFont(), "Medium", 7.6, .{
                        0.72, 0.78, 0.88, 0.92,
                    }, avail, 0);
                } else {
                    const tw = textWidth(cr, text, m.barFont(), "Medium", 6.6, 0);
                    _ = drawTextCentered(cr, text, cx - @min(tw, avail) / 2.0, row_y + 12.0, m.barFont(), "Medium", 6.6, .{
                        0.68, 0.74, 0.84, 0.88,
                    }, avail, 0);
                }
                addBarHit(4, row_y + 1, W - 8, 22, .{ .kind = .status, .value = si });
            }
        },
        .layout => {
            if (!g.show_layout) return;
            drawVerticalLabelPill(cr, y + 1, h - 2, W, layoutLabel(), 0.08);
        },
        .groups => {
            if (!g.show_groups) return;
            const summary = groupSummary();
            if (summary.count == 0) return;
            var buf: [32]u8 = undefined;
            const label = if (summary.active > 0)
                std.fmt.bufPrint(&buf, "G{d}/{d}", .{ summary.active, summary.count }) catch "G"
            else
                std.fmt.bufPrint(&buf, "G{d}", .{summary.count}) catch "G";
            drawVerticalLabelPill(cr, y + 1, h - 2, W, label, if (summary.active > 0) 0.14 else 0.07);
        },
        .mode => {
            if (!g.show_mode or g.input_mode_len == 0) return;
            const mode = g.input_mode[0..g.input_mode_len];
            if (std.mem.eql(u8, mode, "default")) return;
            var label_buf: [24]u8 = undefined;
            const label_len = @min(mode.len, label_buf.len);
            for (mode[0..label_len], 0..) |ch, i| {
                label_buf[i] = if (ch >= 'a' and ch <= 'z') ch - 32 else ch;
            }
            drawVerticalLabelPill(cr, y + 1, h - 2, W, label_buf[0..label_len], 0.14);
        },
        .effects => {
            if (!g.show_effects) return;
            drawVerticalLabelPill(cr, y + 1, h - 2, W, "FX", 0.055);
        },
        .logo, .workspaces, .chips => {},
    }
}

fn drawVerticalLabelPill(cr: *c.cairo_t, y: f64, h: f64, W: f64, label: []const u8, alpha: f64) void {
    const tw = textWidth(cr, label, MONO, "Medium", 7.4, 0.6);
    const pill_w = @min(W - 10.0, tw + 12.0);
    const x = (W - pill_w) / 2.0;
    fillRound(cr, x, y, pill_w, h, 6, .{
        g.accent[0], g.accent[1], g.accent[2], alpha,
    });
    strokeRound(cr, x + 0.5, y + 0.5, pill_w - 1, h - 1, 5.5, .{
        g.accent[0], g.accent[1], g.accent[2], 0.22,
    }, 1.0);
    _ = drawTextCentered(cr, label, (W - tw) / 2.0, y + h / 2.0 + 0.2, MONO, "Medium", 7.4, .{
        g.accent[0], g.accent[1], g.accent[2], 0.96,
    }, pill_w - 4.0, 0.6);
}

fn drawBarVertical(s: *m.Surface) void {
    const d = begin(s) orelse return;
    const cr = d.cr;
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    const accent = g.accent;
    const bg = g.bar_bg;
    const fg = g.bar_fg;
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
    linearGradient(cr, 0, 0, W, 0, bar_top, bar_bottom);
    c.cairo_fill(cr);

    c.cairo_save(cr);
    roundRect(cr, 0, 0, W, H, 18);
    c.cairo_clip(cr);
    c.cairo_translate(cr, W / 2.0, 46.0);
    c.cairo_scale(cr, 1.0, 3.2);
    radialFill(cr, 0, 0, 0, 62, .{ accent[0], accent[1], accent[2], 0.10 }, .{ accent[0], accent[1], accent[2], 0.0 });
    c.cairo_restore(cr);

    strokeRound(cr, 0.5, 0.5, W - 1, H - 1, 18, .{ 1, 1, 1, 0.075 }, 1.0);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, 0.7, 26);
    c.cairo_line_to(cr, 0.7, H - 26);
    setColor(cr, .{ 1, 1, 1, 0.10 });
    c.cairo_set_line_width(cr, 1.0);
    c.cairo_stroke(cr);

    var y: f64 = 8.0;
    if (g.show_logo) {
        const size = 28.0;
        const x = (W - size) / 2.0;
        const hovered = g.hover.kind == .menu;
        fillRound(cr, x, y, size, size, 9, .{ 1, 1, 1, if (hovered) 0.11 else 0.055 });
        strokeRound(cr, x + 0.5, y + 0.5, size - 1, size - 1, 9, .{
            accent[0], accent[1], accent[2], if (hovered) 0.55 else 0.30,
        }, 1.0);
        drawPetal(cr, W / 2.0, y + size / 2.0, 7.2, .{ accent[0], accent[1], accent[2], 1.0 });
        addBarHit(4, y, W - 8, size, .{ .kind = .menu });
        y += size + 7.0;
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, 10, y);
        c.cairo_line_to(cr, W - 10, y);
        setColor(cr, .{ 1, 1, 1, 0.07 });
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_stroke(cr);
        y += 7.0;
    }

    if (g.show_workspaces) {
        var label_storage: [m.WS_COUNT][32]u8 = undefined;
        var wi: usize = 0;
        while (wi < m.WS_COUNT) : (wi += 1) {
            const ws = wi + 1;
            const label = workspaceLabel(wi, &label_storage[wi]);
            const named = g.ws_name_lens[wi] > 0;
            const active = ws == g.active_ws;
            const occupied = g.occ[ws] > 0;
            const hovered = g.hover.kind == .workspace and g.hover.value == ws;
            const pill_w = W - 12.0;
            const pill_h = 18.0;
            const px = 6.0;
            if (active) {
                fillRound(cr, px, y, pill_w, pill_h, 9, .{ accent[0], accent[1], accent[2], 1.0 });
            } else {
                fillRound(cr, px, y, pill_w, pill_h, 9, .{
                    1, 1, 1, if (hovered) 0.115 else if (occupied) 0.070 else 0.030,
                });
                strokeRound(cr, px + 0.5, y + 0.5, pill_w - 1, pill_h - 1, 8.5, .{ 1, 1, 1, 0.045 }, 1.0);
            }
            const text_col: [4]f64 = if (active)
                .{ 0.055, 0.08, 0.11, 1.0 }
            else
                .{ 0.70, 0.76, 0.86, if (occupied) 0.95 else 0.55 };
            const family = if (named) m.barFont() else MONO;
            const font_size: f64 = if (named) 6.8 else 7.6;
            const tw = textWidth(cr, label, family, "Medium", font_size, 0);
            _ = drawTextCentered(cr, label, px + (pill_w - tw) / 2.0, y + pill_h / 2.0 + 0.3, family, "Medium", font_size, text_col, 0, 0);
            addBarHit(px, y, pill_w, pill_h, .{ .kind = .workspace, .value = ws });
            y += pill_h + 3.0;
        }
        y += 3.0;
    }

    if (g.show_chips) {
        var shown: usize = 0;
        var index: usize = 0;
        while (index < g.window_count) : (index += 1) {
            const w = &g.windows[index];
            if (!w.visible or w.ws != g.active_ws) continue;
            if (shown >= 5) break;
            const label = if (w.title_len > 0)
                w.title[0..w.title_len]
            else if (w.app_len > 0)
                w.app_id[0..w.app_len]
            else
                "untitled";
            const focused = w.id == g.focused_id;
            const hovered = g.hover.kind == .window and g.hover.value == w.id;
            const size = 26.0;
            const x = (W - size) / 2.0;
            if (focused) {
                fillRound(cr, x, y, size, size, 7, .{ accent[0], accent[1], accent[2], if (hovered) 0.22 else 0.15 });
                strokeRound(cr, x + 0.5, y + 0.5, size - 1, size - 1, 6.5, .{ accent[0], accent[1], accent[2], 0.42 }, 1.0);
            } else {
                fillRound(cr, x, y, size, size, 7, .{ 1, 1, 1, if (hovered) 0.075 else 0.040 });
                strokeRound(cr, x + 0.5, y + 0.5, size - 1, size - 1, 6.5, .{ 1, 1, 1, 0.040 }, 1.0);
            }
            const app_id = if (w.app_len > 0) w.app_id[0..w.app_len] else label;
            var hsh: u32 = 2166136261;
            for (app_id) |ch| hsh = (hsh ^ ch) *% 16777619;
            const col = palette[hsh % palette.len];
            fillRound(cr, x + 5, y + 5, 16, 16, 5, .{ col[0], col[1], col[2], 0.92 });
            var gbuf: [8]u8 = undefined;
            const glyph = upperFirst(&gbuf, firstGlyph(label));
            const gw = textWidth(cr, glyph, m.barFont(), "Semi-Bold", 7.4, 0);
            _ = drawTextCentered(cr, glyph, x + 5.0 + (16.0 - gw) / 2.0, y + 13.3, m.barFont(), "Semi-Bold", 7.4, .{ 1, 1, 1, 0.95 }, 0, 0);
            addBarHit(x, y, size, size, .{ .kind = .window, .value = w.id });
            y += size + 4.0;
            shown += 1;
        }
        if (shown > 0) y += 4.0;
    }

    const available = H - 8.0 - (y + 8.0);
    const plan = m.planBarVertical(available);
    g.bar_hidden = plan.hidden;
    g.bar_hidden_count = plan.hidden_count;

    var bottom = H - 8.0;
    if (plan.hidden_count > 0) {
        const more_h = 22.0;
        bottom -= more_h;
        const hovered = g.hover.kind == .bar_overflow;
        fillRound(cr, 5, bottom, W - 10, more_h, 6, if (hovered)
            .{ accent[0], accent[1], accent[2], 0.16 }
        else
            .{ 1, 1, 1, 0.040 });
        strokeRound(cr, 5.5, bottom + 0.5, W - 11, more_h - 1, 5.5, if (hovered)
            .{ accent[0], accent[1], accent[2], 0.28 }
        else
            .{ 1, 1, 1, 0.045 }, 1.0);
        var mbuf: [16]u8 = undefined;
        const more = std.fmt.bufPrint(&mbuf, "+{d}", .{plan.hidden_count}) catch "+";
        const more_w = textWidth(cr, more, MONO, "Medium", 7.6, 0);
        _ = drawTextCentered(cr, more, (W - more_w) / 2.0, bottom + more_h / 2.0 + 0.3, MONO, "Medium", 7.6, .{
            0.68, 0.74, 0.84, 0.88,
        }, W - 12.0, 0);
        addBarHit(5, bottom, W - 10, more_h, .{ .kind = .bar_overflow });
        bottom -= 6.0;
    }

    var mi: usize = 0;
    while (mi < g.bar_module_count) : (mi += 1) {
        const module = g.bar_modules[mi];
        if (plan.hidden[@intFromEnum(module)]) continue;
        const h = m.barModuleHeight(module);
        if (h <= 0 or bottom - h < y + 4.0) continue;
        bottom -= h;
        drawBarVerticalModule(cr, module, bottom, h, W, fg, accent);
        bottom -= 6.0;
    }

    end(s, d);
}

pub fn drawBar(s: *m.Surface) void {
    if (!m.barHorizontal()) {
        drawBarVertical(s);
        return;
    }
    const d = begin(s) orelse return;
    const cr = d.cr;
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    const cy = H / 2.0;
    const accent = g.accent;
    const bg = g.bar_bg;
    const fg = g.bar_fg;
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

    var menu_end: f64 = 12.0;
    var div_x: f64 = 12.0;
    if (g.show_logo) {
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
        const word_w = textWidth(cr, word, m.barFont(), "Semi-Bold", 10.0, 1.8);
        _ = drawTextCentered(cr, word, mark_x + 38, cy + 0.5, m.barFont(), "Semi-Bold", 10.0, .{ fg[0], fg[1], fg[2], 0.92 }, 0, 1.8);

        menu_end = mark_x + 38 + word_w + 8;
        addBarHit(mark_x, 4, menu_end - mark_x, H - 8, .{ .kind = .menu });

        div_x = menu_end + 7;
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, div_x, cy - 9);
        c.cairo_line_to(cr, div_x, cy + 9);
        setColor(cr, .{ 1, 1, 1, 0.055 });
        c.cairo_set_line_width(cr, 1);
        c.cairo_stroke(cr);
    }

    // workspace pills
    const pill_h = 20.0;
    const pill_gap = 4.0;
    var label_storage: [m.WS_COUNT][32]u8 = undefined;
    var labels: [m.WS_COUNT][]const u8 = undefined;
    var pill_widths: [m.WS_COUNT]f64 = undefined;
    var ws_total: f64 = 0;
    var wi: usize = 0;
    while (wi < m.WS_COUNT) : (wi += 1) {
        labels[wi] = workspaceLabel(wi, &label_storage[wi]);
        const named = g.ws_name_lens[wi] > 0;
        const tw = textWidth(
            cr,
            labels[wi],
            if (named) m.barFont() else MONO,
            "Medium",
            if (named) 8.2 else 9.0,
            0,
        );
        pill_widths[wi] = std.math.clamp(tw + 12.0, 22.0, 56.0);
        ws_total += pill_widths[wi];
        if (wi + 1 < m.WS_COUNT) ws_total += pill_gap;
    }
    const ws_x0 = if (g.show_workspaces) W / 2.0 - ws_total / 2.0 else W / 2.0;
    const ws_y = cy - pill_h / 2.0;

    if (g.show_workspaces) {
        var pill_x = ws_x0;
        wi = 0;
        while (wi < m.WS_COUNT) : (wi += 1) {
            const ws = wi + 1;
            const pill_w = pill_widths[wi];
            const active = ws == g.active_ws;
            const occupied = g.occ[ws] > 0;
            const hovered = g.hover.kind == .workspace and g.hover.value == ws;
            const named = g.ws_name_lens[wi] > 0;

            if (active) {
                fillRound(cr, pill_x, ws_y, pill_w, pill_h, 10, .{ accent[0], accent[1], accent[2], 1.0 });
            } else {
                fillRound(cr, pill_x, ws_y, pill_w, pill_h, 10, .{
                    1, 1, 1, if (hovered) 0.115 else if (occupied) 0.070 else 0.030,
                });
                strokeRound(cr, pill_x + 0.5, ws_y + 0.5, pill_w - 1, pill_h - 1, 9.5, .{ 1, 1, 1, 0.045 }, 1.0);
            }
            const text_col: [4]f64 = if (active)
                .{ 0.055, 0.08, 0.11, 1.0 }
            else
                .{ 0.70, 0.76, 0.86, if (occupied) 0.95 else 0.55 };
            const family = if (named) m.barFont() else MONO;
            const tw = textWidth(cr, labels[wi], family, "Medium", if (named) 8.2 else 9.0, 0);
            _ = drawTextCentered(
                cr,
                labels[wi],
                pill_x + (pill_w - tw) / 2.0,
                cy + 0.5,
                family,
                "Medium",
                if (named) 8.2 else 9.0,
                text_col,
                0,
                0,
            );
            addBarHit(pill_x, ws_y - 2, pill_w, pill_h + 4, .{ .kind = .workspace, .value = ws });
            pill_x += pill_w + pill_gap;
        }
    }

    // window chips
    const chips_end = ws_x0 - 16.0;
    var cx = div_x + 12.0;
    var shown: usize = 0;
    var skipped: usize = 0;
    var index: usize = 0;
    if (g.show_chips) {
        while (index < g.window_count) : (index += 1) {
            const w = &g.windows[index];
            if (!w.visible) continue;
            if (w.ws != g.active_ws) continue;
            const label = if (w.title_len > 0)
                w.title[0..w.title_len]
            else if (w.app_len > 0)
                w.app_id[0..w.app_len]
            else
                "untitled";
            const tw = textWidth(cr, label, m.barFont(), "Medium", 9.6, 0);
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
            _ = drawTextCentered(cr, glyph, cx + 10.6, cy + 0.3, m.barFont(), "Semi-Bold", 8.2, .{ 1, 1, 1, 0.95 }, 0, 0);

            _ = drawTextCentered(cr, label, cx + 28, cy + 0.2, m.barFont(), "Medium", 9.6, if (focused) .{ 1, 1, 1, 0.96 } else .{ 0.68, 0.74, 0.84, 0.9 }, chip_w - 36, 0);
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
    }

    // right cluster, in configured module order from right to left
    var right = W - 16.0;
    var right_first = true;

    if (g.panel_style == .unified) {
        const button_w = 30.0;
        const button_x = right - button_w;
        const hovered = g.hover.kind == .controls;
        if (hovered) {
            fillRound(cr, button_x, cy - 13, button_w, 26, 9, .{
                accent[0], accent[1], accent[2], 0.12,
            });
        }
        drawControlsGlyph(cr, button_x + 8, cy + 0.5, .{
            fg[0], fg[1], fg[2], if (hovered) 0.95 else 0.66,
        });
        if (g.notification_count > 0) {
            fillCircle(cr, button_x + button_w - 5, cy - 8, 3.0, .{ accent[0], accent[1], accent[2], 0.95 });
        }
        addBarHit(button_x - 3, cy - 14, button_w + 6, 28, .{ .kind = .controls });
        right = button_x - 8.0;
        right_first = false;
    }
    const previous_hidden = g.bar_hidden_count;
    const bar_plan = m.planBar(W, right - (cx + 12.0));
    g.bar_hidden = bar_plan.hidden;
    g.bar_hidden_count = bar_plan.hidden_count;
    if (bar_plan.hidden_count != previous_hidden) {
        std.debug.print("tessa-panel: bar overflow +{d}\n", .{bar_plan.hidden_count});
    }
    var mi: usize = 0;
    while (mi < g.bar_module_count) : (mi += 1) {
        const module = g.bar_modules[mi];
        if (bar_plan.hidden[@intFromEnum(module)]) continue;
        switch (module) {
            .clock => {
                if (!g.show_clock) continue;
                const clock_right = right;
                const time = std.mem.sliceTo(&g.clock_buf, 0);
                const tw = textWidth(cr, time, MONO, "Medium", 12.0, 0);
                const time_x = clock_right - tw;
                const date = std.mem.sliceTo(&g.date_buf, 0);
                const dw = textWidth(cr, date, m.barFont(), "Medium", 8.2, 0.9);
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
                _ = drawTextCentered(cr, date, date_x, cy + 0.3, m.barFont(), "Medium", 8.2, .{
                    0.66, 0.72, 0.82, if (clock_hovered) 0.78 else 0.55,
                }, 0, 0.9);
                addBarHit(date_x - 9, cy - 13, clock_right + 8 - (date_x - 9), 26, .{ .kind = .clock });
                right = date_x - 12.0;

                if (right_first) {
                    c.cairo_new_path(cr);
                    c.cairo_move_to(cr, right, cy - 7);
                    c.cairo_line_to(cr, right, cy + 7);
                    setColor(cr, .{ 1, 1, 1, 0.06 });
                    c.cairo_set_line_width(cr, 1);
                    c.cairo_stroke(cr);
                    right -= 12.0;
                }
                right_first = false;
            },
            .battery => {
                if (!g.show_battery or g.battery_percent < 0 or W <= 900) continue;
                right = drawBatteryIndicator(cr, right, cy, fg);
                right_first = false;
            },
            .network => {
                if (!g.show_network or !g.network_present or W <= 1000) continue;
                const net_right = right;
                right = drawNetworkIndicator(cr, right, cy, fg);
                const net_left = right + 14.0;
                addBarHit(net_left, cy - 12, net_right - net_left, 24, .{ .kind = .wifi });
                if (g.bt_present and m.controlFeatureEnabled(.bluetooth)) {
                    const bx = right - 16.0;
                    drawBluetoothGlyph(cr, bx + 6, cy, 12.0, .{
                        accent[0], accent[1], accent[2], if (g.bt_powered) 0.82 else 0.38,
                    });
                    addBarHit(bx - 2, cy - 12, 18, 24, .{ .kind = .bluetooth });
                    right = bx - 8.0;
                }
                right_first = false;
            },
            .volume => {
                if (!g.show_volume or g.volume_percent < 0 or W <= 1080) continue;
                const vol_right = right;
                right = drawVolumeIndicator(cr, right, cy, fg);
                addBarHit(right + 14, cy - 12, vol_right - (right + 14), 24, .{ .kind = .volume });
                right_first = false;
            },
            .stats => {
                if (!g.show_stats or W <= 1180) continue;
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

                const spark_w = 42.0;
                drawSparkline(cr, right - spark_w, cy - 7, spark_w, 14);
                right -= spark_w + 12.0;
                right_first = false;
            },
            .media => {
                if (!g.show_media or (g.media_status != 1 and g.media_status != 2) or W <= 1250) continue;
                const title = if (g.media_title_len > 0)
                    g.media_title[0..g.media_title_len]
                else if (g.media_artist_len > 0)
                    g.media_artist[0..g.media_artist_len]
                else if (g.media_player_len > 0)
                    g.media_player[0..g.media_player_len]
                else
                    "Media";
                const media_tw = @min(textWidth(cr, title, m.barFont(), "Medium", 8.6, 0), 150.0);
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
                    _ = drawTextCentered(cr, title, chip_x + 27, cy + 0.3, m.barFont(), "Medium", 8.6, .{
                        fg[0], fg[1], fg[2], 0.84,
                    }, media_tw, 0);
                    addBarHit(chip_x, cy - chip_h / 2.0 - 1, chip_w, chip_h + 2, .{ .kind = .media });
                    right = chip_x - 14.0;
                    right_first = false;
                }
            },
            .tray => {
                if (!g.show_tray or g.tray_count == 0 or W <= 980) continue;
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
                    right_first = false;
                }
            },
            .status => {
                if (!g.show_status) continue;
                var order: [m.MAX_STATUS]usize = undefined;
                var order_count: usize = 0;
                var oi: usize = 0;
                while (oi < g.status_count) : (oi += 1) {
                    order[oi] = oi;
                    order_count += 1;
                }
                // Higher priority stays visible longer; insertion sort keeps
                // the declaration order for equal priorities.
                oi = 1;
                while (oi < order_count) : (oi += 1) {
                    const key = order[oi];
                    const key_priority = g.statuses[key].priority;
                    var j = oi;
                    while (j > 0 and g.statuses[order[j - 1]].priority < key_priority) : (j -= 1) {
                        order[j] = order[j - 1];
                    }
                    order[j] = key;
                }

                var status_widths: [m.MAX_STATUS]f64 = undefined;
                var status_fit: usize = 0;
                var status_total: f64 = 0;
                while (status_fit < order_count) : (status_fit += 1) {
                    const st = &g.statuses[order[status_fit]];
                    const text = st.text[0..st.text_len];
                    const icon = st.icon[0..st.icon_len];
                    const tw2 = @min(textWidth(cr, text, m.barFont(), "Medium", 8.4, 0), 112.0);
                    const icon_w = if (icon.len > 0) textWidth(cr, icon, m.barFont(), "Medium", 9.0, 0) + 5.0 else 0.0;
                    const status_pill = tw2 + icon_w + 20.0;
                    const gap2: f64 = if (status_fit == 0) 0 else 6.0;
                    if (right - status_total - status_pill - gap2 < cx + 12.0) break;
                    status_widths[status_fit] = status_pill;
                    status_total += status_pill + gap2;
                }

                if (status_fit > 0) {
                    var sx = right - status_total;
                    var si: usize = 0;
                    while (si < status_fit) : (si += 1) {
                        const st = &g.statuses[order[si]];
                        const status_w = status_widths[si];
                        const hovered = g.hover.kind == .status and g.hover.value == order[si];
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
                        var text_x = sx + 10.0;
                        const icon = st.icon[0..st.icon_len];
                        if (icon.len > 0) {
                            const icon_w = textWidth(cr, icon, m.barFont(), "Medium", 9.0, 0);
                            _ = drawTextCentered(cr, icon, sx + 9.0 + icon_w / 2.0, cy + 0.3, m.barFont(), "Medium", 9.0, col, icon_w + 2.0, 0);
                            text_x += icon_w + 5.0;
                        }
                        _ = drawTextCentered(cr, st.text[0..st.text_len], text_x, cy + 0.3, m.barFont(), "Medium", 8.4, col, status_w - (text_x - sx) - 10.0, 0);
                        addBarHit(sx, cy - 11, status_w, 22, .{ .kind = .status, .value = order[si] });
                        sx += status_w + 6.0;
                    }
                    right = right - status_total - 12.0;
                    right_first = false;

                    const hidden = order_count - status_fit;
                    if (hidden > 0) {
                        const more_w = 28.0;
                        const mx = right - more_w;
                        if (mx > cx + 12.0) {
                            fillRound(cr, mx, cy - 10, more_w, 20, 6, .{ 1, 1, 1, 0.040 });
                            var mbuf: [16]u8 = undefined;
                            const more = std.fmt.bufPrint(&mbuf, "+{d}", .{hidden}) catch "+";
                            _ = drawTextCentered(cr, more, mx + 7, cy + 0.3, MONO, "Medium", 8.2, .{
                                0.68, 0.74, 0.84, 0.88,
                            }, 0, 0);
                            right = mx - 8.0;
                        }
                    }
                }
            },
            .layout => {
                if (!g.show_layout) continue;
                if (right - 96.0 < cx + 12.0) continue;
                right = drawContextPill(cr, right, cy, layoutLabel(), 0.08);
                right_first = false;
            },
            .groups => {
                if (!g.show_groups) continue;
                const summary = groupSummary();
                if (summary.count == 0) continue;
                var buf: [32]u8 = undefined;
                const label = if (summary.active > 0)
                    std.fmt.bufPrint(&buf, "G{d}/{d}", .{ summary.active, summary.count }) catch "G"
                else
                    std.fmt.bufPrint(&buf, "G{d}", .{summary.count}) catch "G";
                if (right - 80.0 < cx + 12.0) continue;
                right = drawContextPill(cr, right, cy, label, if (summary.active > 0) 0.14 else 0.07);
                right_first = false;
            },
            .mode => {
                if (!g.show_mode or g.input_mode_len == 0) continue;
                const mode = g.input_mode[0..g.input_mode_len];
                if (std.mem.eql(u8, mode, "default")) continue;
                var label_buf: [24]u8 = undefined;
                const label_len = @min(mode.len, label_buf.len);
                for (mode[0..label_len], 0..) |ch, i| {
                    label_buf[i] = if (ch >= 'a' and ch <= 'z') ch - 32 else ch;
                }
                if (right - 96.0 < cx + 12.0) continue;
                right = drawContextPill(cr, right, cy, label_buf[0..label_len], 0.14);
                right_first = false;
            },
            .effects => {
                if (!g.show_effects) continue;
                const pill_w = 48.0;
                const x = right - pill_w;
                if (x < cx + 12.0) continue;
                fillRound(cr, x, cy - 10, pill_w, 20, 6, .{
                    g.accent[0], g.accent[1], g.accent[2], 0.055,
                });
                strokeRound(cr, x + 0.5, cy - 9.5, pill_w - 1, 19, 5.5, .{
                    g.accent[0], g.accent[1], g.accent[2], 0.18,
                }, 1.0);
                _ = drawTextCentered(cr, "FX", x + 8, cy + 0.3, MONO, "Medium", 8.0, .{
                    g.accent[0], g.accent[1], g.accent[2], 0.9,
                }, 18, 0.6);
                const states = [3]bool{ g.blur_enabled, g.shadows_enabled, g.animations_enabled };
                var di: usize = 0;
                while (di < states.len) : (di += 1) {
                    const alpha: f64 = if (states[di]) 0.92 else 0.16;
                    fillRound(cr, x + 24.0 + @as(f64, @floatFromInt(di)) * 6.0, cy - 1.5, 3, 3, 1, .{
                        g.accent[0], g.accent[1], g.accent[2], alpha,
                    });
                }
                right = x - 10.0;
                right_first = false;
            },
            else => {},
        }
    }

    if (bar_plan.hidden_count > 0) {
        const more_w = 28.0;
        const mx = right - more_w;
        if (mx > cx + 12.0) {
            const hovered = g.hover.kind == .bar_overflow;
            fillRound(cr, mx, cy - 10, more_w, 20, 6, if (hovered)
                .{ accent[0], accent[1], accent[2], 0.16 }
            else
                .{ 1, 1, 1, 0.040 });
            strokeRound(cr, mx + 0.5, cy - 9.5, more_w - 1, 19, 5.5, if (hovered)
                .{ accent[0], accent[1], accent[2], 0.28 }
            else
                .{ 1, 1, 1, 0.045 }, 1.0);
            var mbuf: [16]u8 = undefined;
            const more = std.fmt.bufPrint(&mbuf, "+{d}", .{bar_plan.hidden_count}) catch "+";
            _ = drawTextCentered(cr, more, mx + 7, cy + 0.3, MONO, "Medium", 8.2, .{
                0.68, 0.74, 0.84, 0.88,
            }, 0, 0);
            addBarHit(mx, cy - 11, more_w, 22, .{ .kind = .bar_overflow });
            right = mx - 8.0;
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

fn launcherRowReveal(row: usize, t: f64) f64 {
    const delay = 0.10 + @as(f64, @floatFromInt(row)) * 0.035;
    const span = @max(0.001, 1.0 - delay);
    const p = std.math.clamp((t - delay) / span, 0.0, 1.0);
    return 1.0 - std.math.pow(f64, 1.0 - p, 3.0);
}

/// Shared application list for the wide Wofi-style launcher and the compact
/// start menu. Hits use the unscaled row position so the reveal animation
/// cannot move the clickable target.
fn drawLauncherRows(
    cr: *c.cairo_t,
    row_x: f64,
    row_w: f64,
    row_y0: f64,
    row_h: f64,
    row_gap: f64,
    visible: usize,
    compact: bool,
    t: f64,
) void {
    const accent = g.accent;
    const fg = g.launcher_fg;
    const fam = m.launcherFont();
    const stride = row_h + row_gap;

    // The selection marker glides between rows when the keyboard moves.
    const sel_row = g.selected_anim - @as(f64, @floatFromInt(g.scroll));
    if (g.result_count > 0 and sel_row > -1.0 and
        sel_row < @as(f64, @floatFromInt(visible)))
    {
        const hy = row_y0 + sel_row * stride;
        fillRound(cr, row_x, hy, row_w, row_h, 10, .{ accent[0], accent[1], accent[2], 0.16 * t });
        strokeRound(cr, row_x + 0.5, hy + 0.5, row_w - 1, row_h - 1, 9.5, .{ accent[0], accent[1], accent[2], 0.22 * t }, 1.0);
        fillRound(cr, row_x + 1.5, hy + 12, 3, row_h - 24, 1.5, .{ accent[0], accent[1], accent[2], 0.95 * t });
    }

    var row: usize = 0;
    while (row < visible) : (row += 1) {
        const idx = g.scroll + row;
        if (idx >= g.result_count) break;
        const app_index = g.results[idx];
        if (app_index >= g.app_list.count) continue;
        const app = &g.app_list.apps[app_index];
        const base_y = row_y0 + @as(f64, @floatFromInt(row)) * stride;
        const reveal = launcherRowReveal(row, t);
        if (reveal <= 0.002) continue;
        const y = base_y + (1.0 - reveal) * 8.0;
        const selected = idx == g.selected;
        const hovered = row == g.overlay_row_hover;

        c.cairo_push_group(cr);
        if (hovered and selected == false) {
            fillRound(cr, row_x, y, row_w, row_h, 10, .{ 1, 1, 1, 0.045 });
        }

        const icon_size: f64 = if (compact) 28.0 else 32.0;
        const icon_inset: f64 = if (compact) 10.0 else 14.0;
        const text_gap: f64 = if (compact) 10.0 else 14.0;
        const glyph_inset: f64 = if (compact) 6.5 else 7.0;
        const icon_x = row_x + icon_inset;
        const icon_y = y + (row_h - icon_size) / 2.0;
        const col = appColor(app);
        fillRound(cr, icon_x, icon_y, icon_size, icon_size, if (compact) 8.0 else 9.0, .{ col[0], col[1], col[2], 0.9 });
        var gbuf: [8]u8 = undefined;
        const glyph = upperFirst(&gbuf, firstGlyph(app.name[0..app.name_len]));
        _ = drawTextCentered(cr, glyph, icon_x + glyph_inset, y + row_h / 2.0, fam, "Semi-Bold", if (compact) 10.5 else 11.5, .{ 1, 1, 1, 0.96 }, 0, 0);

        const text_x = icon_x + icon_size + text_gap;
        if (compact) {
            _ = drawText(cr, app.name[0..app.name_len], text_x, y + 9, fam, "Semi-Bold", 10.8, if (selected) .{ fg[0], fg[1], fg[2], 1 } else .{ fg[0], fg[1], fg[2], 0.9 }, row_w - (text_x - row_x) - 34, 0);
        } else {
            _ = drawText(cr, app.name[0..app.name_len], text_x, y + 10, fam, "Semi-Bold", 11.2, if (selected) .{ fg[0], fg[1], fg[2], 1 } else .{ fg[0], fg[1], fg[2], 0.9 }, row_w - (text_x - row_x) - 64, 0);
            _ = drawText(cr, app.comment[0..app.comment_len], text_x, y + 28, fam, "Regular", 8.7, .{ 0.62, 0.68, 0.77, 0.62 }, row_w - (text_x - row_x) - 64, 0);
        }

        if (app.terminal) {
            const tag_w: f64 = if (compact) 30.0 else 34.0;
            const tag_inset: f64 = if (compact) 8.0 else 10.0;
            const tag_x = row_x + row_w - tag_w - tag_inset;
            fillRound(cr, tag_x, y + (row_h - 16) / 2.0, tag_w, 16, 5, .{ 1, 1, 1, 0.05 });
            _ = drawTextCentered(cr, "TERM", tag_x + 3, y + row_h / 2.0, MONO, "Medium", 6.4, .{ 0.65, 0.71, 0.81, 0.6 }, 0, 0.7);
        }
        if (selected) {
            _ = drawTextCentered(cr, "\xe2\x86\xb5", row_x + row_w - 22, y + row_h / 2.0, MONO, "Medium", if (compact) 10.5 else 12.0, .{ accent[0], accent[1], accent[2], 0.95 }, 0, 0);
        }

        c.cairo_pop_group_to_source(cr);
        c.cairo_paint_with_alpha(cr, reveal);
        addOverlayHit(row_x, base_y, row_w, row_h, .{ .kind = .app, .value = app_index });
    }
}

fn drawLauncherPanel(cr: *c.cairo_t, px: f64, py: f64, pw: f64, ph: f64, t: f64) void {
    const accent = g.accent;
    const bg = g.launcher_bg;
    const fg = g.launcher_fg;
    const fam = m.launcherFont();

    c.cairo_push_group(cr);

    // shadow
    var i: usize = 0;
    while (i < 7) : (i += 1) {
        const expand = 8.0 + @as(f64, @floatFromInt(i)) * 5.0;
        fillRound(cr, px - expand, py - expand + 8, pw + expand * 2, ph + expand * 2, 28 + expand, .{ 0, 0, 0, 0.035 });
    }

    fillRound(cr, px, py, pw, ph, 24, .{ bg[0], bg[1], bg[2], 0.985 });
    roundRect(cr, px, py, pw, ph, 24);
    linearGradient(cr, px, py, px, py + ph, .{
        std.math.clamp(bg[0] * 1.55 + 0.01, 0, 1),
        std.math.clamp(bg[1] * 1.55 + 0.01, 0, 1),
        std.math.clamp(bg[2] * 1.55 + 0.01, 0, 1),
        0.99,
    }, .{ bg[0] * 0.58, bg[1] * 0.58, bg[2] * 0.64, 0.99 });
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
    _ = drawText(cr, "Tessa", px + 64, py + 26, fam, "Semi-Bold", 24, .{ fg[0], fg[1], fg[2], 0.98 }, 0, 0);
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
            const size = drawTextCentered(cr, query, cursor_x, sy + sh / 2.0, fam, "Regular", 12.2, .{ fg[0], fg[1], fg[2], 0.98 }, sw - 110, 0);
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
        drawLauncherRows(cr, row_x, row_w, row_y0, row_h, row_gap, visible, false, t);
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

fn drawStartMenu(cr: *c.cairo_t, px: f64, py: f64, pw: f64, ph: f64, t: f64) void {
    const accent = g.accent;
    const bg = g.launcher_bg;
    const fg = g.launcher_fg;
    const fam = m.launcherFont();

    c.cairo_push_group(cr);

    var i: usize = 0;
    while (i < 6) : (i += 1) {
        const expand = 6.0 + @as(f64, @floatFromInt(i)) * 5.0;
        fillRound(cr, px - expand, py - expand + 7, pw + expand * 2, ph + expand * 2, 22 + expand, .{ 0, 0, 0, 0.040 });
    }

    fillRound(cr, px, py, pw, ph, 22, .{ bg[0], bg[1], bg[2], 0.975 });
    roundRect(cr, px, py, pw, ph, 22);
    linearGradient(cr, px, py, px, py + ph, .{
        std.math.clamp(bg[0] * 1.45 + 0.008, 0, 1),
        std.math.clamp(bg[1] * 1.45 + 0.008, 0, 1),
        std.math.clamp(bg[2] * 1.45 + 0.008, 0, 1),
        0.98,
    }, .{ bg[0] * 0.62, bg[1] * 0.62, bg[2] * 0.68, 0.99 });
    c.cairo_fill(cr);
    strokeRound(cr, px + 0.5, py + 0.5, pw - 1, ph - 1, 21.5, .{ 1, 1, 1, 0.10 }, 1.0);

    const top_pat = c.cairo_pattern_create_linear(px + 28, 0, px + pw - 28, 0);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 0, accent[0], accent[1], accent[2], 0);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 0.5, accent[0], accent[1], accent[2], 0.68);
    c.cairo_pattern_add_color_stop_rgba(top_pat, 1, accent[0], accent[1], accent[2], 0);
    c.cairo_set_source(cr, top_pat);
    c.cairo_rectangle(cr, px + 18, py + 1, pw - 36, 1.2);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(top_pat);

    // Search field
    const sx = px + 20;
    const sy = py + 18;
    const sw = pw - 40;
    const sh = 46.0;
    fillRound(cr, sx, sy, sw, sh, 12, .{ 1, 1, 1, 0.050 });
    strokeRound(cr, sx + 0.5, sy + 0.5, sw - 1, sh - 1, 11.5, .{ 1, 1, 1, 0.085 }, 1.0);

    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, sx + 22, sy + 22, 5.2, 0, PI * 2.0);
    setColor(cr, .{ accent[0], accent[1], accent[2], 0.9 });
    c.cairo_set_line_width(cr, 1.4);
    c.cairo_stroke(cr);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, sx + 26, sy + 26.5);
    c.cairo_line_to(cr, sx + 31, sy + 31.5);
    c.cairo_stroke(cr);

    const query = g.query[0..g.query_len];
    const preedit = g.preedit[0..g.preedit_len];
    const text_x = sx + 42.0;
    if (query.len == 0 and preedit.len == 0) {
        _ = drawTextCentered(cr, "Search applications...", text_x, sy + sh / 2.0, fam, "Regular", 11.6, .{ 0.56, 0.61, 0.70, 0.78 }, sw - 104, 0);
    } else {
        var cursor_x = text_x;
        if (query.len > 0) {
            const size = drawTextCentered(cr, query, cursor_x, sy + sh / 2.0, fam, "Regular", 11.6, .{ fg[0], fg[1], fg[2], 0.98 }, sw - 104, 0);
            cursor_x += size.w;
        }
        if (preedit.len > 0) {
            const psize = drawTextCentered(cr, preedit, cursor_x, sy + sh / 2.0, fam, "Regular", 11.6, .{ accent[0], accent[1], accent[2], 0.98 }, sw - 104, 0);
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, cursor_x, sy + 31);
            c.cairo_line_to(cr, cursor_x + psize.w, sy + 31);
            setColor(cr, .{ accent[0], accent[1], accent[2], 0.55 });
            c.cairo_set_line_width(cr, 1.0);
            c.cairo_stroke(cr);
            cursor_x += psize.w;
        }
        if (@mod(m.nowMs(), 1000) < 520) {
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, cursor_x + 1.5, sy + 14);
            c.cairo_line_to(cr, cursor_x + 1.5, sy + 32);
            setColor(cr, .{ accent[0], accent[1], accent[2], 0.9 });
            c.cairo_set_line_width(cr, 1.4);
            c.cairo_stroke(cr);
        }
    }

    fillRound(cr, sx + sw - 42, sy + 14, 30, 18, 5, .{ 1, 1, 1, 0.045 });
    _ = drawTextCentered(cr, "ESC", sx + sw - 34.5, sy + 23, MONO, "Medium", 6.8, .{ 0.65, 0.71, 0.81, 0.55 }, 0, 0.8);

    // Section label
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, px + 20, py + 78);
    c.cairo_line_to(cr, px + pw - 20, py + 78);
    setColor(cr, .{ 1, 1, 1, 0.055 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const label = if (query.len == 0) "APPLICATIONS" else "RESULTS";
    _ = drawText(cr, label, px + 22, py + 90, fam, "Semi-Bold", 7.4, .{ 0.64, 0.70, 0.80, 0.42 }, 0, 1.6);
    var count_buf: [32]u8 = undefined;
    const count = std.fmt.bufPrint(&count_buf, "{d}", .{g.result_count}) catch "";
    const count_w = textWidth(cr, count, MONO, "Medium", 7.2, 0.8);
    _ = drawText(cr, count, px + pw - 22 - count_w, py + 90, MONO, "Medium", 7.2, .{ 0.60, 0.66, 0.76, 0.42 }, 0, 0.8);

    g.overlay_hit_count = 0;
    g.overlay_panel = .{ .x = px, .y = py, .w = pw, .h = ph };

    const row_x = px + 16;
    const row_w = pw - 32;
    const row_h = 42.0;
    const row_gap = 4.0;
    const row_y0 = py + 108;
    const visible: usize = 9;

    if (g.result_count == 0) {
        drawPetal(cr, px + pw / 2.0, py + 310, 16, .{ 1, 1, 1, 0.10 });
        _ = drawTextCentered(cr, "Nothing matches", px + pw / 2.0 - 64, py + 354, fam, "Semi-Bold", 12.0, .{ 0.86, 0.89, 0.94, 0.75 }, 128, 0);
    } else {
        drawLauncherRows(cr, row_x, row_w, row_y0, row_h, row_gap, visible, true, t);
    }

    // User / session footer
    const footer_y = py + ph - 82.0;
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, px + 18, footer_y);
    c.cairo_line_to(cr, px + pw - 18, footer_y);
    setColor(cr, .{ 1, 1, 1, 0.055 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const footer_t = std.math.clamp((t - 0.18) / 0.82, 0.0, 1.0);
    if (footer_t > 0.002) {
        c.cairo_push_group(cr);
        const avatar_x = px + 38;
        const avatar_y = py + ph - 42;
        fillCircle(cr, avatar_x, avatar_y, 18, .{ 1, 1, 1, 0.055 });
        c.cairo_new_sub_path(cr);
        c.cairo_arc(cr, avatar_x, avatar_y, 18, 0, PI * 2.0);
        setColor(cr, .{ accent[0], accent[1], accent[2], 0.42 });
        c.cairo_set_line_width(cr, 1.0);
        c.cairo_stroke(cr);
        drawPetal(cr, avatar_x, avatar_y, 8.5, .{ accent[0], accent[1], accent[2], 0.95 });

        const user: []const u8 = if (c.getenv("USER")) |u| std.mem.span(u) else "user";
        const host: []const u8 = if (c.getenv("HOSTNAME")) |h| std.mem.span(h) else "linux";
        _ = drawText(cr, user, px + 64, py + ph - 58, fam, "Semi-Bold", 10.8, .{ fg[0], fg[1], fg[2], 0.94 }, pw - 140, 0);
        _ = drawText(cr, host, px + 64, py + ph - 40, fam, "Regular", 8.0, .{ 0.62, 0.68, 0.77, 0.58 }, pw - 140, 0);

        const lock_cx = px + pw - 72;
        const power_cx = px + pw - 34;
        const icon_cy = py + ph - 42;
        c.cairo_new_path(cr);
        c.cairo_arc(cr, lock_cx, icon_cy - 3, 5.5, PI, 2.0 * PI);
        setColor(cr, .{ fg[0], fg[1], fg[2], 0.78 });
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);
        fillRound(cr, lock_cx - 7, icon_cy - 3, 14, 11, 3, .{ fg[0], fg[1], fg[2], 0.78 });
        addOverlayHit(lock_cx - 16, icon_cy - 16, 32, 32, .{ .kind = .launcher_lock });

        c.cairo_new_path(cr);
        c.cairo_arc(cr, power_cx, icon_cy, 7.5, -PI / 2.0 + 0.62, 3.0 * PI / 2.0 - 0.62);
        setColor(cr, .{ fg[0], fg[1], fg[2], 0.78 });
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_stroke(cr);
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, power_cx, icon_cy - 10);
        c.cairo_line_to(cr, power_cx, icon_cy - 2);
        c.cairo_stroke(cr);
        addOverlayHit(power_cx - 16, icon_cy - 16, 32, 32, .{ .kind = .launcher_power });

        c.cairo_pop_group_to_source(cr);
        c.cairo_paint_with_alpha(cr, footer_t);
    }

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
        .extensions => 460.0,
        .module => 360.0,
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
        .extensions => 128.0 + @as(f64, @floatFromInt(@min(g.extension_count, 6))) * 52.0,
        .module => 96.0 + @as(f64, @floatFromInt(g.module_popover.action_count)) * 40.0,
        else => 360.0,
    };
    const bar = m.barOutputRect(W, H);
    const gap = 8.0;
    const anchored_right = switch (g.bar_position) {
        .left => bar.x + bar.w + gap,
        .right => bar.x - gap - w,
        else => bar.x + bar.w - w,
    };
    const anchored_left = switch (g.bar_position) {
        .left => bar.x + bar.w + gap,
        .right => bar.x - gap - w,
        else => bar.x,
    };
    var x = switch (mode) {
        .calendar, .tray, .module => anchored_right,
        .clipboard, .media, .audio, .extensions => (W - w) / 2.0,
        else => anchored_left,
    };
    var y = switch (mode) {
        .clipboard, .media, .audio, .extensions => (H - h) / 2.0,
        else => switch (g.bar_position) {
            .bottom => bar.y - gap - h,
            .left, .right => bar.y,
            else => bar.y + bar.h + gap,
        },
    };
    x = std.math.clamp(x, 8.0, @max(8.0, W - w - 8.0));
    if (y + h > H - 8.0 or y < 8.0) y = std.math.clamp(y, 8.0, @max(8.0, H - h - 8.0));
    return .{ .x = x, .y = y, .w = w, .h = h };
}

/// A compact audio mixer bar that opens next to the volume indicator.
fn audioBarLayout(W: f64, H: f64) PopoverLayout {
    const w = @min(452.0, @max(300.0, W - 16.0));
    const h = 80.0;
    const bar = m.barOutputRect(W, H);
    const gap = 8.0;
    var anchor_y = bar.y + bar.h / 2.0;

    var i: usize = 0;
    while (i < g.bar_hit_count) : (i += 1) {
        const rect = g.bar_hits[i];
        if (rect.hit.kind == .volume) {
            anchor_y = bar.y + rect.y + rect.h / 2.0;
            break;
        }
    }

    var x: f64 = undefined;
    var y: f64 = undefined;
    switch (g.bar_position) {
        .bottom => {
            x = bar.x + bar.w - w;
            y = bar.y - gap - h;
        },
        .left => {
            x = bar.x + bar.w + gap;
            y = anchor_y - h / 2.0;
        },
        .right => {
            x = bar.x - gap - w;
            y = anchor_y - h / 2.0;
        },
        else => {
            x = bar.x + bar.w - w;
            y = bar.y + bar.h + gap;
        },
    }
    x = std.math.clamp(x, 8.0, @max(8.0, W - w - 8.0));
    y = std.math.clamp(y, 8.0, @max(8.0, H - h - 8.0));
    return .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawPopoverCard(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64) void {
    const accent = g.accent;
    const bg = g.popover_bg;
    var i: usize = 0;
    while (i < 7) : (i += 1) {
        const expand = 6.0 + @as(f64, @floatFromInt(i)) * 4.0;
        fillRound(cr, x - expand, y - expand + 6, w + expand * 2, h + expand * 2, 22 + expand, .{
            0, 0, 0, 0.032,
        });
    }

    fillRound(cr, x, y, w, h, 18, .{ bg[0], bg[1], bg[2], 0.985 });
    roundRect(cr, x, y, w, h, 18);
    linearGradient(cr, x, y, x, y + h, .{
        std.math.clamp(bg[0] * 1.6 + 0.01, 0, 1),
        std.math.clamp(bg[1] * 1.6 + 0.01, 0, 1),
        std.math.clamp(bg[2] * 1.6 + 0.01, 0, 1),
        0.99,
    }, .{ bg[0] * 0.58, bg[1] * 0.58, bg[2] * 0.64, 0.99 });
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
    const fam = m.popoverFont();
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
        g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.98,
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
    const fam = m.popoverFont();
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
        g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.98,
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
            g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 1,
        } else .{ g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.9 }, row_w - 90, 0);
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
    const bg = g.toast_bg;
    const fg = g.toast_fg;
    const fam = m.toastFont();
    // Leave a clear gutter before the close button; long CJK bodies must
    // ellipsize instead of running into the card edge.
    const text_max = W - 110.0;
    g.toast_hit_count = 0;
    g.toast_action_hit_count = 0;

    var region: ?*c.wl_region = null;
    if (g.compositor) |compositor| region = c.wl_compositor_create_region(compositor);

    var y: f64 = 0;
    var shown_cards: usize = 0;
    var i: usize = 0;
    while (i < g.notification_count and shown_cards < m.MAX_TOASTS) : (i += 1) {
        const n = &g.notifications[i];
        if (!n.toast_visible) continue;
        shown_cards += 1;
        const th = m.toastHeight(n);
        const height: f64 = @floatFromInt(th);
        if (y >= H) break;
        const hovered = g.pointer_surface == s and
            g.pointer_x >= 0 and g.pointer_x < W and
            g.pointer_y >= y and g.pointer_y < y + height;

        fillRound(cr, 0, y, W, height, 14, .{ 0.016, 0.023, 0.038, 0.72 });
        roundRect(cr, 0, y, W, height, 14);
        linearGradient(cr, 0, y, 0, y + height, .{
            bg[0] * 1.7 + 0.01,
            bg[1] * 1.7 + 0.01,
            bg[2] * 1.7 + 0.02,
            if (hovered) 0.985 else 0.965,
        }, .{ bg[0] * 1.05, bg[1] * 1.05, bg[2] * 1.08, 0.965 });
        c.cairo_fill(cr);
        strokeRound(cr, 0.5, y + 0.5, W - 1, height - 1, 13.5, .{ 1, 1, 1, if (hovered) 0.16 else 0.09 }, 1);

        const top_pat = c.cairo_pattern_create_linear(16, 0, W - 16, 0);
        c.cairo_pattern_add_color_stop_rgba(top_pat, 0, accent[0], accent[1], accent[2], 0.65);
        c.cairo_pattern_add_color_stop_rgba(top_pat, 1, accent[0], accent[1], accent[2], 0.0);
        c.cairo_set_source(cr, top_pat);
        c.cairo_rectangle(cr, 16, y + 0.8, W - 32, 1.2);
        c.cairo_fill(cr);
        c.cairo_pattern_destroy(top_pat);

        // Keep text and actions inside the rounded card even when a client
        // sends an unusually long, unbreakable string.
        c.cairo_save(cr);
        roundRect(cr, 0, y, W, height, 14);
        c.cairo_clip(cr);

        paintNotificationIcon(cr, n, 16, y + 26, 28);

        var app_buf: [80]u8 = undefined;
        const app = if (n.app_len > 0) n.app[0..n.app_len] else "Notification";
        const app_line = toastLine(&app_buf, app);
        _ = drawText(cr, app_line, 54, y + 10, fam, "Medium", 7.2, .{
            0.68, 0.74, 0.84, 0.55,
        }, text_max, 0.9);

        var summary_buf: [180]u8 = undefined;
        const summary_text = if (n.summary_len > 0) n.summary[0..n.summary_len] else "Notification";
        const summary = toastLine(&summary_buf, summary_text);
        _ = drawText(cr, summary, 54, y + 23, fam, "Semi-Bold", 10.4, .{
            fg[0], fg[1], fg[2], 0.98,
        }, text_max, 0);

        if (n.body_len > 0) {
            var body_buf: [560]u8 = undefined;
            const body = toastLine(&body_buf, n.body[0..n.body_len]);
            _ = drawTextMarkup(cr, body, 54, y + 44, fam, "Regular", 8.3, .{
                0.68, 0.74, 0.83, 0.72,
            }, text_max, 0);
        }

        _ = drawTextCentered(cr, "\xc3\x97", W - 22, y + 20, fam, "Medium", 12.0, .{
            0.76, 0.81, 0.88, if (hovered) 0.9 else 0.45,
        }, 0, 0);

        const action_count = m.toastActionCount(n);
        if (action_count > 0) {
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, 16, y + 70);
            c.cairo_line_to(cr, W - 16, y + 70);
            setColor(cr, .{ 1, 1, 1, 0.055 });
            c.cairo_set_line_width(cr, 1);
            c.cairo_stroke(cr);

            const action_gap = 6.0;
            const available = W - 32.0 - action_gap * @as(f64, @floatFromInt(action_count - 1));
            const button_w = @min(168.0, available / @as(f64, @floatFromInt(action_count)));
            const button_h = 26.0;
            var shown: usize = 0;
            var ai: usize = 0;
            while (ai < n.action_count and ai < n.actions.len) : (ai += 1) {
                const action = &n.actions[ai];
                if (action.key_len == 0 or
                    std.mem.eql(u8, action.key[0..action.key_len], "default")) continue;
                if (shown >= action_count) break;
                const bx = 16.0 + @as(f64, @floatFromInt(shown)) * (button_w + action_gap);
                const action_hovered = g.pointer_surface == s and
                    g.pointer_x >= bx and g.pointer_x < bx + button_w and
                    g.pointer_y >= y + 76 and g.pointer_y < y + 76 + button_h;
                fillRound(cr, bx, y + 76, button_w, button_h, 8, if (action_hovered) .{
                    accent[0], accent[1], accent[2], 0.22,
                } else .{ 1, 1, 1, 0.065 });
                strokeRound(cr, bx + 0.5, y + 76.5, button_w - 1, button_h - 1, 7.5, .{
                    accent[0], accent[1], accent[2], if (action_hovered) 0.42 else 0.18,
                }, 1);
                const label = if (action.label_len > 0)
                    action.label[0..action.label_len]
                else
                    action.key[0..action.key_len];
                _ = drawTextCentered(cr, label, bx + button_w / 2.0, y + 76 + button_h / 2.0, fam, "Semi-Bold", 8.4, .{
                    0.88, 0.92, 0.97, 0.95,
                }, button_w - 12, 0);
                if (g.toast_action_hit_count < g.toast_action_hits.len) {
                    g.toast_action_hits[g.toast_action_hit_count] = .{
                        .x = bx,
                        .y = y + 76,
                        .w = button_w,
                        .h = button_h,
                        .id = n.id,
                        .action = ai,
                    };
                    g.toast_action_hit_count += 1;
                }
                shown += 1;
            }
        }

        c.cairo_restore(cr);

        if (g.toast_hit_count < g.toast_hits.len) {
            g.toast_hits[g.toast_hit_count] = .{
                .x = 0,
                .y = y,
                .w = W,
                .h = height,
                .hit = .{ .kind = .notification, .value = @intCast(n.id) },
            };
            g.toast_hit_count += 1;
        }
        if (region) |r| c.wl_region_add(r, 0, @intFromFloat(y), @intFromFloat(W), @intFromFloat(height));
        y += height + 8.0;
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
    const fam = m.popoverFont();
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
        g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.98,
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
                g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 1,
            } else .{ g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.88 }, row_w - 150, 0);

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
    const fam = m.popoverFont();

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
    const fam = m.popoverFont();
    const p = audioBarLayout(W, H);
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

    const ix = x + 24.0;
    const iy = y + h / 2.0 - 2.0;
    const icon_col: [4]f64 = if (available and !g.volume_muted)
        .{ accent[0], accent[1], accent[2], 0.92 }
    else
        .{ g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.42 };
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, ix, iy - 3);
    c.cairo_line_to(cr, ix + 5, iy - 3);
    c.cairo_line_to(cr, ix + 10, iy - 7);
    c.cairo_line_to(cr, ix + 10, iy + 7);
    c.cairo_line_to(cr, ix + 5, iy + 3);
    c.cairo_line_to(cr, ix, iy + 3);
    c.cairo_close_path(cr);
    setColor(cr, icon_col);
    c.cairo_fill(cr);
    if (available and !g.volume_muted) {
        c.cairo_new_path(cr);
        c.cairo_arc(cr, ix + 10.5, iy, 4.5, -0.85, 0.85);
        setColor(cr, .{ icon_col[0], icon_col[1], icon_col[2], 0.72 });
        c.cairo_set_line_width(cr, 1.3);
        c.cairo_stroke(cr);
    } else if (g.volume_muted) {
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, ix + 12, iy - 5);
        c.cairo_line_to(cr, ix + 16, iy + 5);
        setColor(cr, .{ 0.82, 0.87, 0.94, 0.55 });
        c.cairo_set_line_width(cr, 1.3);
        c.cairo_stroke(cr);
    }

    _ = drawText(cr, "AUDIO", x + 44, y + 11, fam, "Medium", 7.2, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.5);

    if (available) {
        var value_buf: [16]u8 = undefined;
        const value = std.fmt.bufPrint(&value_buf, "{d}", .{g.volume_percent}) catch "0";
        const value_col: [4]f64 = if (g.volume_muted)
            .{ 0.58, 0.63, 0.72, 0.55 }
        else
            .{ g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.98 };
        const vw = drawText(cr, value, x + 44, y + 25, fam, "Semi-Bold", 27.0, value_col, 60, 0).w;
        _ = drawText(cr, "%", x + 47 + vw, y + 39, fam, "Medium", 10.0, .{
            value_col[0], value_col[1], value_col[2], 0.62,
        }, 0, 0);
    } else {
        _ = drawText(cr, "No audio", x + 44, y + 30, fam, "Semi-Bold", 12.0, .{
            0.86, 0.90, 0.96, 0.84,
        }, 80, 0);
    }

    const mid_x = x + 116;
    const mid_w = @max(80.0, w - 276.0);
    const muted = available and g.volume_muted;
    _ = drawText(cr, if (muted) "MUTED" else "OUTPUT VOLUME", mid_x, y + 16, MONO, "Medium", 6.8, if (muted) .{
        accent[0], accent[1], accent[2], 0.9,
    } else .{
        0.58, 0.64, 0.74, 0.42,
    }, mid_w, 0.7);

    const bar_x = mid_x;
    const bar_y = y + 42;
    const bar_w = mid_w;
    fillRound(cr, bar_x, bar_y, bar_w, 8, 4, .{ 1, 1, 1, 0.07 });
    const pct = if (available)
        std.math.clamp(@as(f64, @floatFromInt(g.volume_percent)) / 100.0, 0.0, 1.0)
    else
        0.0;
    if (pct > 0.005) {
        const fill_col: [4]f64 = if (g.volume_muted)
            .{ 0.56, 0.61, 0.70, 0.42 }
        else
            .{ accent[0], accent[1], accent[2], 0.92 };
        fillRound(cr, bar_x, bar_y, bar_w * pct, 8, 4, fill_col);
    }
    if (available and !g.volume_muted) {
        fillCircle(cr, bar_x + bar_w * pct, bar_y + 4, 4.5, .{ 1, 1, 1, 0.92 });
    }
    var tick: usize = 1;
    while (tick < 4) : (tick += 1) {
        fillRound(cr, bar_x + bar_w * @as(f64, @floatFromInt(tick)) / 4.0, bar_y + 13, 1, 3, 0.5, .{ 1, 1, 1, 0.06 });
    }

    const source = g.volume_source[0..g.volume_source_len];
    if (source.len > 0) {
        _ = drawText(cr, source, mid_x, y + 62, MONO, "Medium", 6.6, .{
            0.60, 0.66, 0.76, 0.42,
        }, mid_w, 0.5);
    } else {
        _ = drawText(cr, if (available) "\xe2\x86\x91/\xe2\x86\x93 volume   m mute   esc close" else "Install wpctl, pactl, or amixer", mid_x, y + 62, if (available) fam else MONO, "Medium", 6.6, .{
            0.60, 0.66, 0.75, 0.38,
        }, mid_w, 0.3);
    }

    const labels = [_][]const u8{ "-", if (g.volume_muted) "UNMUTE" else "MUTE", "+" };
    const hits = [_]m.HitKind{ .audio_down, .audio_mute, .audio_up };
    const button_w = 38.0;
    const button_h = 36.0;
    const gap = 6.0;
    const total_w = button_w * 3.0 + gap * 2.0;
    const start_x = x + w - 18.0 - total_w;
    const button_y = y + 22.0;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const bx = start_x + @as(f64, @floatFromInt(i)) * (button_w + gap);
        const hovered = g.overlay_row_hover == i;
        const primary = i == 1;
        fillRound(cr, bx, button_y, button_w, button_h, 9, if (primary) .{
            accent[0], accent[1], accent[2], if (available) 0.88 else 0.25,
        } else .{
            1, 1, 1, if (hovered and available) 0.09 else 0.045,
        });
        if (!primary) {
            strokeRound(cr, bx + 0.5, button_y + 0.5, button_w - 1, button_h - 1, 8.5, .{
                1, 1, 1, 0.07,
            }, 1);
        }
        const label_col: [4]f64 = if (primary) .{
            0.055, 0.075, 0.105, if (available) 1.0 else 0.5,
        } else .{ 0.82, 0.87, 0.94, if (available) 0.9 else 0.4 };
        _ = drawTextCentered(cr, labels[i], bx + button_w / 2.0, button_y + button_h / 2.0, if (i == 1) MONO else fam, "Semi-Bold", if (i == 1) 6.4 else 15.0, label_col, 0, 0);
        addOverlayHit(bx - x, button_y - y, button_w, button_h, .{ .kind = hits[i] });
    }

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawExtensionsPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = m.popoverFont();
    const p = popoverLayout(.extensions, W, H);
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
    _ = drawText(cr, "EXTENSIONS", x + 46, y + 18, fam, "Medium", 7.4, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.6);
    var count_buf: [32]u8 = undefined;
    const count_text = std.fmt.bufPrint(&count_buf, "{d} TOTAL", .{g.extension_count}) catch "0";
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

    if (g.extension_count == 0) {
        _ = drawTextCentered(cr, "No extensions configured", x + w / 2.0, y + 100, fam, "Semi-Bold", 12.0, .{
            0.86, 0.90, 0.96, 0.82,
        }, w - 48, 0);
        _ = drawTextCentered(cr, "Add extension = id=...; command=...; state below.", x + w / 2.0, y + 124, fam, "Regular", 8.2, .{
            0.60, 0.66, 0.76, 0.55,
        }, w - 48, 0);
    } else {
        const max_visible: usize = 6;
        const first: usize = if (g.extension_selected >= max_visible)
            g.extension_selected - (max_visible - 1)
        else
            0;
        var row: usize = 0;
        while (row < max_visible and first + row < g.extension_count) : (row += 1) {
            const i = first + row;
            const ext = &g.extensions[i];
            const row_y = y + 60.0 + @as(f64, @floatFromInt(row)) * 52.0;
            const row_w = w - 40.0;
            const selected = g.extension_selected == i;
            const hovered = g.overlay_row_hover == i;
            if (selected) {
                fillRound(cr, x + 20, row_y, row_w, 46, 9, .{
                    accent[0], accent[1], accent[2], 0.16,
                });
                strokeRound(cr, x + 20.5, row_y + 0.5, row_w - 1, 45, 8.5, .{
                    accent[0], accent[1], accent[2], 0.34,
                }, 1);
            } else if (hovered) {
                fillRound(cr, x + 20, row_y, row_w, 46, 9, .{ 1, 1, 1, 0.055 });
            }

            const state = ext.state[0..ext.state_len];
            const failed = std.mem.eql(u8, state, "failed") or std.mem.eql(u8, state, "blocked");
            const ready = ext.ready or std.mem.eql(u8, state, "ready");
            const dot = if (failed)
                [4]f32{ 0.90, 0.36, 0.32, 0.95 }
            else if (ready)
                [4]f32{ 0.42, 0.82, 0.58, 0.95 }
            else
                [4]f32{ 0.58, 0.64, 0.74, 0.55 };
            c.cairo_set_source_rgba(cr, dot[0], dot[1], dot[2], dot[3]);
            c.cairo_arc(cr, x + 30, row_y + 21, 4.0, 0, 2.0 * std.math.pi);
            c.cairo_fill(cr);

            _ = drawText(cr, ext.id[0..ext.id_len], x + 44, row_y + 9, fam, "Medium", 10.4, .{
                g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.96,
            }, row_w - 100, 0);
            var detail_buf: [160]u8 = undefined;
            const detail = std.fmt.bufPrint(&detail_buf, "{s}  api {d}  {s}", .{
                state,
                ext.api,
                ext.permissions[0..ext.permissions_len],
            }) catch state;
            _ = drawText(cr, detail, x + 44, row_y + 26, MONO, "Medium", 7.0, .{
                0.62, 0.68, 0.78, 0.60,
            }, row_w - 100, 0.2);

            const enabled_text = if (ext.enabled) "ON" else "OFF";
            const enabled_w = textWidth(cr, enabled_text, MONO, "Medium", 6.8, 0.5);
            _ = drawText(cr, enabled_text, x + w - 32 - enabled_w, row_y + 15, MONO, "Medium", 6.8, if (ext.enabled) .{
                accent[0], accent[1], accent[2], 0.90,
            } else .{ 0.58, 0.64, 0.74, 0.45 }, 0, 0.5);
            addOverlayHit(20, row_y - y, row_w, 46, .{ .kind = .extension, .value = i });
        }
    }

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + h - 42);
    c.cairo_line_to(cr, x + w - 24, y + h - 42);
    setColor(cr, .{ 1, 1, 1, 0.045 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);
    _ = drawText(cr, "\xe2\x86\x91/\xe2\x86\x93  select      enter  enable/disable      esc  close", x + 24, y + h - 30, fam, "Medium", 7.4, .{
        0.60, 0.66, 0.75, 0.55,
    }, w - 48, 0.3);

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawTrayPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = m.popoverFont();
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
                g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.95,
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
    const fam = m.popoverFont();
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
        g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.98,
    } else .{ g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.8 }, w - 124, 0);
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

fn drawModulePopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const accent = g.accent;
    const fam = m.popoverFont();
    const p = popoverLayout(.module, W, H);
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

    _ = drawText(cr, "MODULE", x + 24, y + 18, fam, "Medium", 7.6, .{
        0.64, 0.70, 0.80, 0.45,
    }, 0, 1.7);
    const title = g.module_popover.title[0..g.module_popover.title_len];
    _ = drawText(cr, if (title.len > 0) title else "Widget", x + 24, y + 35, fam, "Semi-Bold", 18.5, .{
        g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.98,
    }, w - 96, 0);
    _ = drawText(cr, "ESC", x + w - 48, y + 18, MONO, "Medium", 7.2, .{
        0.64, 0.70, 0.80, 0.4,
    }, 0, 0.8);

    const body = g.module_popover.body[0..g.module_popover.body_len];
    if (body.len > 0) {
        _ = drawText(cr, body, x + 24, y + 58, fam, "Regular", 10.0, .{
            g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], 0.62,
        }, w - 48, 0);
    }

    c.cairo_new_path(cr);
    c.cairo_move_to(cr, x + 24, y + 76);
    c.cairo_line_to(cr, x + w - 24, y + 76);
    setColor(cr, .{ 1, 1, 1, 0.06 });
    c.cairo_set_line_width(cr, 1);
    c.cairo_stroke(cr);

    const row_w = w - 32.0;
    const row_h = 36.0;
    const row_y0 = y + 84.0;
    var i: usize = 0;
    while (i < g.module_popover.action_count) : (i += 1) {
        const action = &g.module_popover.actions[i];
        const row_y = row_y0 + @as(f64, @floatFromInt(i)) * 40.0;
        const selected = i == g.module_selected;
        const hovered = i == g.overlay_row_hover;
        if (selected) {
            fillRound(cr, x + 16, row_y, row_w, row_h, 10, .{
                accent[0], accent[1], accent[2], 0.14,
            });
            strokeRound(cr, x + 16.5, row_y + 0.5, row_w - 1, row_h - 1, 9.5, .{
                accent[0], accent[1], accent[2], 0.24,
            }, 1);
            fillRound(cr, x + 17.5, row_y + 8, 3, 20, 1.5, .{
                accent[0], accent[1], accent[2], 0.95,
            });
        } else if (hovered) {
            fillRound(cr, x + 16, row_y, row_w, row_h, 10, .{ 1, 1, 1, 0.035 });
        }

        _ = drawText(cr, action.label[0..action.label_len], x + 30, row_y + 9, fam, "Medium", 10.4, .{
            g.popover_fg[0], g.popover_fg[1], g.popover_fg[2], if (selected) 1.0 else 0.88,
        }, row_w - 78, 0);
        if (action.command_len > 0) {
            _ = drawTextCentered(cr, "\xe2\x86\xb5", x + w - 32, row_y + row_h / 2.0, MONO, "Medium", 11.0, .{
                accent[0], accent[1], accent[2], if (selected) 0.9 else 0.55,
            }, 0, 0);
        } else {
            _ = drawText(cr, "INFO", x + w - 64, row_y + row_h / 2.0 - 4, MONO, "Medium", 6.4, .{
                0.60, 0.66, 0.76, 0.4,
            }, 0, 0.8);
        }
        addOverlayHit(16, row_y - y, row_w, row_h, .{ .kind = .module_action, .value = i });
    }

    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);

    g.overlay_panel = .{ .x = x, .y = y, .w = w, .h = h };
}

fn drawWifiGlyph(cr: *c.cairo_t, cx: f64, cy: f64, size: f64, col: [4]f64) void {
    const r = size * 0.5;
    setColor(cr, col);
    c.cairo_set_line_width(cr, 1.5);
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const rr = r * (0.35 + @as(f64, @floatFromInt(i)) * 0.32);
        c.cairo_new_path(cr);
        c.cairo_arc(cr, cx, cy + r * 0.55, rr, -2.45, -0.69);
        c.cairo_stroke(cr);
    }
    fillCircle(cr, cx, cy + r * 0.52, 1.4, col);
}

fn drawMoonGlyph(cr: *c.cairo_t, cx: f64, cy: f64, size: f64, col: [4]f64) void {
    const r = size * 0.5;
    c.cairo_new_path(cr);
    c.cairo_arc(cr, cx, cy, r, 0.65, 5.63);
    c.cairo_arc_negative(cr, cx + r * 0.48, cy - r * 0.15, r * 0.86, 5.1, 1.2);
    c.cairo_close_path(cr);
    setColor(cr, col);
    c.cairo_fill(cr);
}

fn drawSunGlyph(cr: *c.cairo_t, cx: f64, cy: f64, size: f64, col: [4]f64) void {
    const r = size * 0.28;
    fillCircle(cr, cx, cy, r, col);
    setColor(cr, col);
    c.cairo_set_line_width(cr, 1.3);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const a = @as(f64, @floatFromInt(i)) * std.math.pi / 4.0;
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, cx + @cos(a) * r * 1.55, cy + @sin(a) * r * 1.55);
        c.cairo_line_to(cr, cx + @cos(a) * r * 2.15, cy + @sin(a) * r * 2.15);
        c.cairo_stroke(cr);
    }
}

fn drawBellGlyph(cr: *c.cairo_t, cx: f64, cy: f64, size: f64, col: [4]f64) void {
    const r = size * 0.5;
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, cx - r * 0.75, cy + r * 0.45);
    c.cairo_curve_to(cr, cx - r * 0.5, cy - r * 0.1, cx - r * 0.55, cy - r * 0.75, cx, cy - r * 0.75);
    c.cairo_curve_to(cr, cx + r * 0.55, cy - r * 0.75, cx + r * 0.5, cy - r * 0.1, cx + r * 0.75, cy + r * 0.45);
    c.cairo_close_path(cr);
    setColor(cr, col);
    c.cairo_fill(cr);
    fillCircle(cr, cx, cy + r * 0.72, r * 0.18, col);
}

fn drawChevron(cr: *c.cairo_t, cx: f64, cy: f64, size: f64, col: [4]f64) void {
    setColor(cr, col);
    c.cairo_set_line_width(cr, 1.4);
    c.cairo_new_path(cr);
    c.cairo_move_to(cr, cx - size * 0.25, cy - size * 0.5);
    c.cairo_line_to(cr, cx + size * 0.25, cy);
    c.cairo_line_to(cr, cx - size * 0.25, cy + size * 0.5);
    c.cairo_stroke(cr);
}

fn drawLockGlyph(cr: *c.cairo_t, cx: f64, cy: f64, size: f64, col: [4]f64) void {
    const r = size * 0.5;
    setColor(cr, col);
    c.cairo_set_line_width(cr, 1.4);
    c.cairo_new_path(cr);
    c.cairo_arc(cr, cx, cy - r * 0.15, r * 0.42, std.math.pi, 2.0 * std.math.pi);
    c.cairo_stroke(cr);
    fillRound(cr, cx - r * 0.65, cy - r * 0.05, r * 1.3, r * 0.85, 2.0, col);
}

fn drawGearGlyph(cr: *c.cairo_t, cx: f64, cy: f64, size: f64, col: [4]f64) void {
    const r = size * 0.5;
    fillCircle(cr, cx, cy, r * 0.42, col);
    setColor(cr, col);
    c.cairo_set_line_width(cr, 1.5);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const a = @as(f64, @floatFromInt(i)) * std.math.pi / 4.0;
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, cx + @cos(a) * r * 0.62, cy + @sin(a) * r * 0.62);
        c.cairo_line_to(cr, cx + @cos(a) * r, cy + @sin(a) * r);
        c.cairo_stroke(cr);
    }
}

fn drawSignalBars(cr: *c.cairo_t, x: f64, cy: f64, signal: u8, col: [4]f64) void {
    const pct = std.math.clamp(@as(f64, @floatFromInt(signal)) / 100.0, 0.0, 1.0);
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const h = 4.0 + @as(f64, @floatFromInt(i)) * 2.4;
        const on = pct >= @as(f64, @floatFromInt(i + 1)) / 4.0 - 0.12;
        fillRound(cr, x + @as(f64, @floatFromInt(i)) * 3.6, cy + 6.0 - h, 2.2, h, 1.0, .{
            col[0], col[1], col[2], if (on) col[3] else col[3] * 0.22,
        });
    }
}

fn controlCard(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64) void {
    const bg = g.popover_bg;
    const accent = g.accent;
    fillRound(cr, x, y, w, h, 16, .{ bg[0] * 1.25 + 0.008, bg[1] * 1.25 + 0.008, bg[2] * 1.3 + 0.012, 0.94 });
    roundRect(cr, x, y, w, h, 16);
    linearGradient(cr, x, y, x, y + h, .{
        1, 1, 1, 0.055,
    }, .{ 0, 0, 0, 0.10 });
    c.cairo_fill(cr);
    strokeRound(cr, x + 0.5, y + 0.5, w - 1, h - 1, 15.5, .{ 1, 1, 1, 0.075 }, 1.0);
    const pat = c.cairo_pattern_create_linear(x + 16, 0, x + w - 16, 0);
    c.cairo_pattern_add_color_stop_rgba(pat, 0, accent[0], accent[1], accent[2], 0.55);
    c.cairo_pattern_add_color_stop_rgba(pat, 1, accent[0], accent[1], accent[2], 0.0);
    c.cairo_set_source(cr, pat);
    c.cairo_rectangle(cr, x + 16, y + 0.8, w - 32, 1.1);
    c.cairo_fill(cr);
    c.cairo_pattern_destroy(pat);
}

fn controlSection(cr: *c.cairo_t, text: []const u8, x: f64, y: f64, w: f64) void {
    _ = w;
    _ = drawText(cr, text, x, y, MONO, "Medium", 6.6, .{
        0.64, 0.70, 0.80, 0.42,
    }, 0, 1.4);
}

fn controlPill(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, on: bool) void {
    const accent = g.accent;
    fillRound(cr, x, y, w, h, h * 0.5, if (on) .{
        accent[0], accent[1], accent[2], 0.85,
    } else .{ 1, 1, 1, 0.075 });
    fillCircle(cr, if (on) x + w - h * 0.5 else x + h * 0.5, y + h * 0.5, h * 0.32, if (on) .{
        0.055, 0.075, 0.105, 0.95,
    } else .{
        0.78, 0.83, 0.90, 0.75,
    });
}

fn controlSlider(cr: *c.cairo_t, x: f64, y: f64, w: f64, pct: f64, kind: m.DragTarget) void {
    const accent = g.accent;
    const track_h = 8.0;
    fillRound(cr, x, y, w, track_h, 4, .{ 1, 1, 1, 0.075 });
    const clamped = std.math.clamp(pct, 0.0, 1.0);
    if (clamped > 0.005) {
        fillRound(cr, x, y, w * clamped, track_h, 4, .{ accent[0], accent[1], accent[2], 0.88 });
    }
    fillCircle(cr, x + w * clamped, y + track_h / 2.0, 5.0, .{ 1, 1, 1, 0.94 });
    const hit = m.HitRect{ .x = x - 4, .y = y - 7, .w = w + 8, .h = track_h + 14 };
    addOverlayHit(hit.x, hit.y, hit.w, hit.h, .{ .kind = .control_slider, .value = @intFromEnum(kind) });
    switch (kind) {
        .volume => g.control_volume_slider = hit,
        .brightness => g.control_brightness_slider = hit,
        .seek => g.control_seek_slider = hit,
        else => {},
    }
}

fn drawControlHeader(cr: *c.cairo_t, x: f64, y: f64, w: f64, title: []const u8, back: bool) void {
    const accent = g.accent;
    const fg = g.popover_fg;
    if (back) {
        drawChevron(cr, x + 2, y + 12, 10.0, .{ fg[0], fg[1], fg[2], 0.62 });
        addOverlayHit(x - 10, y - 2, 28, 28, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.back) });
        _ = drawText(cr, title, x + 24, y + 5, m.popoverFont(), "Semi-Bold", 13.0, .{
            fg[0], fg[1], fg[2], 0.96,
        }, w - 24, 0);
    } else {
        _ = drawText(cr, title, x, y + 5, MONO, "Medium", 7.0, .{
            0.64, 0.70, 0.80, 0.48,
        }, 0, 1.6);
        const clock = std.mem.sliceTo(&g.clock_buf, 0);
        const cw = textWidth(cr, clock, MONO, "Medium", 9.0, 0);
        _ = drawText(cr, clock, x + w - cw, y + 4, MONO, "Medium", 9.0, .{
            fg[0], fg[1], fg[2], 0.72,
        }, 0, 0);
        _ = drawText(cr, "CLICK OUTSIDE OR ESC TO CLOSE", x + w - 206, y + 21, MONO, "Medium", 5.8, .{
            accent[0], accent[1], accent[2], 0.42,
        }, 200, 0.4);
    }
}

fn controlHome(cr: *c.cairo_t, l: m.ControlLayout) void {
    const accent = g.accent;
    const fg = g.popover_fg;
    const fam = m.popoverFont();
    const pad = 18.0;
    const top = l.y + 48.0;
    const content_w = l.w - pad * 2.0;
    const col_gap = 14.0;
    const two = l.columns == 2;
    const col_w = if (two) (content_w - col_gap) / 2.0 else content_w;
    const left_x = l.x + pad;
    const right_x = if (two) left_x + col_w + col_gap else left_x;
    var left_y = top;
    var right_y = top;

    drawControlHeader(cr, left_x, l.y + 14, content_w, "CONTROL", false);

    // Connectivity card.
    const conn_h = 116.0;
    controlCard(cr, left_x, left_y, col_w, conn_h);
    controlSection(cr, "CONNECTIVITY", left_x + 16, left_y + 13, col_w - 32);
    var row_y = left_y + 30.0;
    if (m.controlFeatureEnabled(.wifi)) {
        const active = g.wifi_ssid_len > 0 and g.wifi_enabled;
        drawWifiGlyph(cr, left_x + 27, row_y + 13, 18.0, if (active) .{
            accent[0], accent[1], accent[2], 0.9,
        } else .{
            fg[0], fg[1], fg[2], 0.42,
        });
        _ = drawText(cr, "Wi-Fi", left_x + 48, row_y + 5, fam, "Semi-Bold", 10.0, .{
            fg[0], fg[1], fg[2], 0.94,
        }, col_w - 90, 0);
        const wifi_status = if (!g.wifi_present) "Unavailable" else if (!g.wifi_enabled) "Off" else if (g.wifi_ssid_len > 0) g.wifi_ssid[0..g.wifi_ssid_len] else "Not connected";
        _ = drawText(cr, wifi_status, left_x + 48, row_y + 19, fam, "Regular", 7.6, .{
            0.64, 0.70, 0.80, 0.55,
        }, col_w - 96, 0);
        drawChevron(cr, left_x + col_w - 20, row_y + 14, 9.0, .{ fg[0], fg[1], fg[2], 0.35 });
        registerControlNav(left_x + 8, row_y, col_w - 16, 32, .wifi);
        row_y += 42.0;
    }
    if (m.controlFeatureEnabled(.bluetooth)) {
        drawBluetoothGlyph(cr, left_x + 27, row_y + 13, 17.0, if (g.bt_powered) .{
            accent[0], accent[1], accent[2], 0.9,
        } else .{
            fg[0], fg[1], fg[2], 0.42,
        });
        _ = drawText(cr, "Bluetooth", left_x + 48, row_y + 5, fam, "Semi-Bold", 10.0, .{
            fg[0], fg[1], fg[2], 0.94,
        }, col_w - 90, 0);
        const bt_status = if (!g.bt_present) "Unavailable" else if (!g.bt_powered) "Off" else if (g.bt_count > 0 and (g.bt_devices[0].flags & m.BT_DEVICE_CONNECTED) != 0) g.bt_devices[0].name[0..g.bt_devices[0].name_len] else "On";
        _ = drawText(cr, bt_status, left_x + 48, row_y + 19, fam, "Regular", 7.6, .{
            0.64, 0.70, 0.80, 0.55,
        }, col_w - 96, 0);
        drawChevron(cr, left_x + col_w - 20, row_y + 14, 9.0, .{ fg[0], fg[1], fg[2], 0.35 });
        registerControlNav(left_x + 8, row_y, col_w - 16, 32, .bluetooth);
        row_y += 42.0;
    }
    left_y += conn_h + 12.0;

    const show_focus = m.controlFeatureEnabled(.focus);
    const show_ppd = m.controlFeatureEnabled(.power_profile) and g.ppd_available;
    if (show_focus or show_ppd) {
        var focus_h: f64 = 0.0;
        if (show_focus) focus_h += 50.0;
        if (show_ppd) focus_h += 44.0;
        controlCard(cr, left_x, left_y, col_w, focus_h);
        if (show_focus) {
            drawMoonGlyph(cr, left_x + 28, left_y + 25, 16.0, .{
                accent[0], accent[1], accent[2], 0.85,
            });
            _ = drawText(cr, "Focus", left_x + 48, left_y + 14, fam, "Semi-Bold", 10.0, .{
                fg[0], fg[1], fg[2], 0.94,
            }, col_w - 120, 0);
            _ = drawText(cr, if (g.dnd) "Notifications silenced" else "Notifications allowed", left_x + 48, left_y + 29, fam, "Regular", 7.2, .{
                0.64, 0.70, 0.80, 0.52,
            }, col_w - 120, 0);
            controlPill(cr, left_x + col_w - 62, left_y + 16, 42, 20, g.dnd);
            addOverlayHit(left_x + 8, left_y + 6, col_w - 16, 38, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.dnd) });
        }
        if (show_ppd) {
            var py: f64 = left_y + 10.0;
            if (show_focus) py = left_y + 50.0;
            _ = drawText(cr, "POWER PROFILE", left_x + 16, py, MONO, "Medium", 6.2, .{
                0.64, 0.70, 0.80, 0.42,
            }, 100, 0.8);
            const gap = 5.0;
            const bw = (col_w - 32.0 - gap * 2.0) / 3.0;
            var pi: usize = 0;
            while (pi < g.ppd_profile_count and pi < 3) : (pi += 1) {
                const name = g.ppd_profiles[pi][0..g.ppd_profile_lens[pi]];
                const active = name.len == g.ppd_profile_len and
                    std.mem.eql(u8, name, g.ppd_profile[0..g.ppd_profile_len]);
                const bx = left_x + 16.0 + @as(f64, @floatFromInt(pi)) * (bw + gap);
                drawControlButton(cr, name, bx, py + 12, bw, 20, active);
                addOverlayHit(bx, py + 12, bw, 20, .{ .kind = .control_profile, .value = pi });
            }
        }
        left_y += focus_h + 12.0;
    }

    if (m.controlFeatureEnabled(.battery) or m.controlFeatureEnabled(.power)) {
        const sys_h = 96.0;
        controlCard(cr, left_x, left_y, col_w, sys_h);
        controlSection(cr, "SYSTEM", left_x + 16, left_y + 13, col_w - 32);
        const bx = left_x + 16;
        const by = left_y + 30;
        if (m.controlFeatureEnabled(.battery) and g.battery_percent >= 0) {
            var bbuf: [32]u8 = undefined;
            const btext = std.fmt.bufPrint(&bbuf, "{d}%", .{g.battery_percent}) catch "?";
            _ = drawText(cr, btext, bx, by + 2, MONO, "Medium", 12.0, .{
                fg[0], fg[1], fg[2], 0.9,
            }, 80, 0);
            _ = drawText(cr, if (g.battery_charging) "CHARGING" else "BATTERY", bx, by + 20, MONO, "Medium", 6.4, .{
                0.64, 0.70, 0.80, 0.45,
            }, 90, 0.6);
        }
        if (m.controlFeatureEnabled(.power)) {
            drawPowerButtons(cr, left_x + 16, left_y + 54, col_w - 32);
        }
        left_y += sys_h + 12.0;
    }

    if (m.controlFeatureEnabled(.quick_actions)) {
        drawQuickActions(cr, left_x, left_y, col_w);
        left_y += 62.0;
    }

    // Right column: sliders, media, notifications. On narrow/vertical bars
    // the right column becomes a continuation of the single column.
    if (!two) right_y = left_y;
    if (m.controlFeatureEnabled(.volume) or m.controlFeatureEnabled(.brightness)) {
        const sh = 136.0;
        controlCard(cr, right_x, right_y, col_w, sh);
        var sy = right_y + 16.0;
        if (m.controlFeatureEnabled(.volume)) {
            controlSection(cr, "SOUND", right_x + 16, sy, col_w - 32);
            var vbuf: [16]u8 = undefined;
            const vtext = if (g.volume_muted) "MUTE" else std.fmt.bufPrint(&vbuf, "{d}%", .{@max(0, g.volume_percent)}) catch "0%";
            const vw = textWidth(cr, vtext, MONO, "Medium", 8.0, 0);
            _ = drawText(cr, vtext, right_x + col_w - 16 - vw, sy, MONO, "Medium", 8.0, .{
                fg[0], fg[1], fg[2], 0.62,
            }, 0, 0);
            const pct = if (g.volume_percent >= 0) @as(f64, @floatFromInt(g.volume_percent)) / 100.0 else 0.0;
            controlSlider(cr, right_x + 16, sy + 22, col_w - 32, pct, .volume);
            sy += 52.0;
        }
        if (m.controlFeatureEnabled(.brightness)) {
            controlSection(cr, "DISPLAY", right_x + 16, sy, col_w - 32);
            if (g.brightness_percent >= 0) {
                var sbuf: [16]u8 = undefined;
                const stext = std.fmt.bufPrint(&sbuf, "{d}%", .{g.brightness_percent}) catch "0%";
                const sw = textWidth(cr, stext, MONO, "Medium", 8.0, 0);
                _ = drawText(cr, stext, right_x + col_w - 16 - sw, sy, MONO, "Medium", 8.0, .{
                    fg[0], fg[1], fg[2], 0.62,
                }, 0, 0);
                controlSlider(cr, right_x + 16, sy + 22, col_w - 32, @as(f64, @floatFromInt(g.brightness_percent)) / 100.0, .brightness);
            } else {
                _ = drawText(cr, "No backlight", right_x + 16, sy + 24, fam, "Regular", 8.0, .{
                    0.64, 0.70, 0.80, 0.42,
                }, col_w - 32, 0);
            }
        }
        right_y += sh + 12.0;
    }

    if (m.controlFeatureEnabled(.media)) {
        const mh = 154.0;
        controlCard(cr, right_x, right_y, col_w, mh);
        controlSection(cr, "MEDIA", right_x + 16, right_y + 13, col_w - 32);
        const art_x = right_x + 16;
        const art_y = right_y + 28;
        drawMediaArt(cr, art_x, art_y, 54.0);
        const title = if (g.media_title_len > 0) g.media_title[0..g.media_title_len] else "No media";
        const artist = if (g.media_artist_len > 0) g.media_artist[0..g.media_artist_len] else if (g.media_status > 0) g.media_player[0..g.media_player_len] else "Open a player";
        _ = drawText(cr, title, art_x + 66, art_y + 4, fam, "Semi-Bold", 10.0, .{
            fg[0], fg[1], fg[2], 0.96,
        }, col_w - 92, 0);
        _ = drawText(cr, artist, art_x + 66, art_y + 22, fam, "Regular", 7.6, .{
            0.64, 0.70, 0.80, 0.55,
        }, col_w - 92, 0);
        const pct = if (g.media_length_us > 0)
            std.math.clamp(@as(f64, @floatFromInt(g.media_position_us)) / @as(f64, @floatFromInt(g.media_length_us)), 0.0, 1.0)
        else
            0.0;
        fillRound(cr, right_x + 16, right_y + 102, col_w - 32, 5, 2.5, .{ 1, 1, 1, 0.07 });
        if (pct > 0.005) fillRound(cr, right_x + 16, right_y + 102, (col_w - 32) * pct, 5, 2.5, .{
            accent[0], accent[1], accent[2], 0.82,
        });
        addOverlayHit(right_x + 16, right_y + 96, col_w - 32, 17, .{ .kind = .control_slider, .value = @intFromEnum(m.DragTarget.seek) });
        g.control_seek_slider = .{ .x = right_x + 16, .y = right_y + 96, .w = col_w - 32, .h = 17 };
        const buttons = [_]struct { label: []const u8, action: m.ControlAction }{
            .{ .label = "prev", .action = .back },
            .{ .label = if (g.media_status == 1) "pause" else "play", .action = .power_lock },
            .{ .label = "next", .action = .power_quit },
        };
        _ = buttons;
        drawMediaButtons(cr, right_x + col_w - 16, right_y + 118, fg);
        right_y += mh + 12.0;
    }

    if (m.controlFeatureEnabled(.notifications)) {
        const nh = @min(200.0, l.y + l.h - right_y - pad);
        if (nh > 70.0) {
            controlCard(cr, right_x, right_y, col_w, nh);
            controlSection(cr, "NOTIFICATIONS", right_x + 16, right_y + 13, col_w - 140);
            var count_buf: [24]u8 = undefined;
            const count_text = std.fmt.bufPrint(&count_buf, "{d}", .{g.notification_count}) catch "0";
            _ = drawText(cr, count_text, right_x + col_w - 16 - textWidth(cr, count_text, MONO, "Medium", 7.2, 0), right_y + 12, MONO, "Medium", 7.2, .{
                0.64, 0.70, 0.80, 0.48,
            }, 0, 0);
            drawControlButton(cr, "SILENT", right_x + col_w - 116, right_y + 8, 46, 18, g.dnd);
            addOverlayHit(right_x + col_w - 118, right_y + 6, 50, 22, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.dnd) });
            drawControlButton(cr, "CLEAR", right_x + col_w - 64, right_y + 8, 46, 18, false);
            addOverlayHit(right_x + col_w - 66, right_y + 6, 50, 22, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.clear_notifications) });
            var ny = right_y + 34.0;
            const row_h = 38.0;
            var shown: usize = 0;
            var ni: usize = 0;
            while (ni < g.notification_count and shown < 3 and ny + row_h < right_y + nh - 6) : (ni += 1) {
                const n = &g.notifications[ni];
                paintNotificationIcon(cr, n, right_x + 16, ny + 8, 18);
                const summary = if (n.summary_len > 0) n.summary[0..n.summary_len] else "Notification";
                _ = drawText(cr, summary, right_x + 42, ny + 2, fam, "Medium", 8.6, .{
                    fg[0], fg[1], fg[2], 0.88,
                }, col_w - 62, 0);
                const app = if (n.app_len > 0) n.app[0..n.app_len] else "App";
                _ = drawText(cr, app, right_x + 42, ny + 17, fam, "Regular", 7.0, .{
                    0.64, 0.70, 0.80, 0.45,
                }, col_w - 62, 0);
                addOverlayHit(right_x + 8, ny, col_w - 16, row_h - 4, .{ .kind = .control_notification, .value = ni });
                if (shown + 1 < 3 and ni + 1 < g.notification_count) {
                    c.cairo_new_path(cr);
                    c.cairo_move_to(cr, right_x + 42, ny + row_h - 3);
                    c.cairo_line_to(cr, right_x + col_w - 16, ny + row_h - 3);
                    setColor(cr, .{ 1, 1, 1, 0.045 });
                    c.cairo_set_line_width(cr, 1);
                    c.cairo_stroke(cr);
                }
                ny += row_h;
                shown += 1;
            }
            if (g.notification_count == 0) {
                _ = drawText(cr, "No notifications", right_x + 16, right_y + 48, fam, "Regular", 8.2, .{
                    0.64, 0.70, 0.80, 0.42,
                }, col_w - 32, 0);
            } else if (g.notification_count > shown) {
                _ = drawText(cr, "View all", right_x + col_w - 62, right_y + nh - 22, fam, "Medium", 7.2, .{
                    accent[0], accent[1], accent[2], 0.7,
                }, 60, 0);
                addOverlayHit(right_x + col_w - 70, right_y + nh - 30, 66, 24, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.view_notifications) });
            }
        }
    }
}

fn registerControlNav(x: f64, y: f64, w: f64, h: f64, view: m.ControlView) void {
    addOverlayHit(x, y, w, h, .{ .kind = .control_view, .value = @intFromEnum(view) });
}

fn drawControlButton(cr: *c.cairo_t, label: []const u8, x: f64, y: f64, w: f64, h: f64, active: bool) void {
    const accent = g.accent;
    fillRound(cr, x, y, w, h, 7, if (active) .{
        accent[0], accent[1], accent[2], 0.20,
    } else .{ 1, 1, 1, 0.055 });
    strokeRound(cr, x + 0.5, y + 0.5, w - 1, h - 1, 6.5, .{
        accent[0], accent[1], accent[2], if (active) 0.38 else 0.10,
    }, 1);
    _ = drawTextCentered(cr, label, x + w / 2.0, y + h / 2.0, MONO, "Medium", 6.2, .{
        0.78, 0.84, 0.92, if (active) 0.95 else 0.62,
    }, w - 4, 0.5);
}

fn drawMediaArt(cr: *c.cairo_t, x: f64, y: f64, size: f64) void {
    const accent = g.accent;
    if (g.media_art_surface) |surface| {
        c.cairo_save(cr);
        roundRect(cr, x, y, size, size, 10);
        c.cairo_clip(cr);
        const sw: f64 = @floatFromInt(c.cairo_image_surface_get_width(surface));
        const sh: f64 = @floatFromInt(c.cairo_image_surface_get_height(surface));
        const scale = @max(size / sw, size / sh);
        c.cairo_translate(cr, x + (size - sw * scale) / 2.0, y + (size - sh * scale) / 2.0);
        c.cairo_scale(cr, scale, scale);
        c.cairo_set_source_surface(cr, surface, 0, 0);
        c.cairo_paint(cr);
        c.cairo_restore(cr);
        return;
    }
    fillRound(cr, x, y, size, size, 10, .{ accent[0] * 0.55, accent[1] * 0.55, accent[2] * 0.6, 0.75 });
    const glyph = if (g.media_title_len > 0) g.media_title[0..1] else "M";
    _ = drawTextCentered(cr, glyph, x + size / 2.0, y + size / 2.0, m.popoverFont(), "Semi-Bold", 20.0, .{
        1, 1, 1, 0.72,
    }, 0, 0);
}

fn drawMediaButtons(cr: *c.cairo_t, right: f64, cy: f64, fg: [3]f64) void {
    const accent = g.accent;
    const button = 26.0;
    var x = right - button;
    const labels = [_]m.HitKind{ .media_next, .media_toggle, .media_prev };
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const primary = i == 1;
        fillRound(cr, x, cy - button / 2.0, button, button, 8, if (primary) .{
            accent[0], accent[1], accent[2], 0.82,
        } else .{ 1, 1, 1, 0.055 });
        const col: [4]f64 = if (primary) .{ 0.055, 0.075, 0.105, 1.0 } else .{ fg[0], fg[1], fg[2], 0.75 };
        if (i == 1) {
            if (g.media_status == 1) {
                fillRound(cr, x + 9, cy - 5, 2.2, 10, 1, col);
                fillRound(cr, x + 15, cy - 5, 2.2, 10, 1, col);
            } else {
                c.cairo_new_path(cr);
                c.cairo_move_to(cr, x + 10, cy - 6);
                c.cairo_line_to(cr, x + 18, cy);
                c.cairo_line_to(cr, x + 10, cy + 6);
                c.cairo_close_path(cr);
                setColor(cr, col);
                c.cairo_fill(cr);
            }
        } else {
            const dir: f64 = if (i == 0) 1.0 else -1.0;
            c.cairo_new_path(cr);
            c.cairo_move_to(cr, x + 13 - dir * 3, cy - 6);
            c.cairo_line_to(cr, x + 13 + dir * 3, cy);
            c.cairo_line_to(cr, x + 13 - dir * 3, cy + 6);
            c.cairo_close_path(cr);
            setColor(cr, col);
            c.cairo_fill(cr);
        }
        addOverlayHit(x, cy - button / 2.0, button, button, .{ .kind = labels[i] });
        x -= button + 5.0;
    }
}

fn drawPowerButtons(cr: *c.cairo_t, x: f64, y: f64, w: f64) void {
    const actions = [_]struct { label: []const u8, action: m.ControlAction }{
        .{ .label = "LOCK", .action = .power_lock },
        .{ .label = "SUSPEND", .action = .power_suspend },
        .{ .label = "REBOOT", .action = .power_reboot },
        .{ .label = "OFF", .action = .power_off },
    };
    const gap = 5.0;
    const bw = (w - gap * 3.0) / 4.0;
    for (actions, 0..) |item, i| {
        const bx = x + @as(f64, @floatFromInt(i)) * (bw + gap);
        drawControlButton(cr, item.label, bx, y, bw, 24.0, false);
        addOverlayHit(bx, y, bw, 24.0, .{ .kind = .control_action, .value = @intFromEnum(item.action) });
    }
}

fn drawQuickActions(cr: *c.cairo_t, x: f64, y: f64, w: f64) void {
    const accent = g.accent;
    const fg = g.popover_fg;
    const actions = [_]struct { label: []const u8, action: m.ControlAction }{
        .{ .label = "SHOT", .action = .quick_screenshot },
        .{ .label = "CLIP", .action = .quick_clipboard },
        .{ .label = "SETTINGS", .action = .quick_settings },
        .{ .label = "LOCK", .action = .quick_lock },
    };
    controlCard(cr, x, y, w, 50.0);
    const gap = 6.0;
    const bw = (w - 24.0 - gap * 3.0) / 4.0;
    for (actions, 0..) |item, i| {
        const bx = x + 12.0 + @as(f64, @floatFromInt(i)) * (bw + gap);
        drawControlButton(cr, item.label, bx, y + 13, bw, 24, false);
        addOverlayHit(bx, y + 13, bw, 24, .{ .kind = .control_action, .value = @intFromEnum(item.action) });
    }
    _ = accent;
    _ = fg;
}

fn drawControlCenter(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {


    const l = m.controlCenterLayout(W, H);
    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1.0;
    g.overlay_hit_x = 0;
    g.overlay_hit_y = 0;
    g.control_panel_rect = .{ .x = l.x, .y = l.y, .w = l.w, .h = l.h };
    g.overlay_panel = g.control_panel_rect;

    c.cairo_push_group(cr);
    controlCard(cr, l.x, l.y, l.w, l.h);
    c.cairo_save(cr);
    roundRect(cr, l.x, l.y, l.w, l.h, 18);
    c.cairo_clip(cr);
    switch (g.control_view) {
        .home => controlHome(cr, l),
        .wifi => drawControlWifi(cr, l, true, t),
        .bluetooth => drawControlBluetooth(cr, l, true, t),
        .notifications => drawControlNotifications(cr, l),
        .calendar => drawControlCalendar(cr, l),
        .tray => drawControlTray(cr, l),
        .power => drawControlPower(cr, l),
    }
    c.cairo_restore(cr);
    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
}

fn drawControlWifi(cr: *c.cairo_t, l: m.ControlLayout, in_panel: bool, t: f64) void {
    _ = t;
    const accent = g.accent;
    const fg = g.popover_fg;
    const fam = m.popoverFont();
    const pad = 18.0;
    const x = l.x + pad;
    const top = l.y + 14;
    const w = l.w - pad * 2.0;
    drawControlHeader(cr, x, top, w, "WI-FI", in_panel);
    // Toggle and scan controls.
    controlPill(cr, x + w - 58, top + 3, 42, 20, g.wifi_enabled);
    addOverlayHit(x + w - 60, top, 46, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.wifi_toggle) });
    drawControlButton(cr, "SCAN", x + w - 112, top + 3, 46, 20, false);
    addOverlayHit(x + w - 114, top, 50, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.wifi_scan) });
    const status = if (!g.wifi_present) "Wi-Fi adapter not found" else if (!g.wifi_enabled) "Wi-Fi is off" else if (g.wifi_scanning) "Scanning..." else if (g.wifi_ssid_len > 0) g.wifi_ssid[0..g.wifi_ssid_len] else "Not connected";
    _ = drawText(cr, status, x, top + 32, fam, "Regular", 8.4, .{
        fg[0], fg[1], fg[2], 0.58,
    }, w - 20, 0);
    if (g.wifi_error_len > 0) {
        _ = drawText(cr, g.wifi_error[0..g.wifi_error_len], x, top + 48, fam, "Regular", 7.2, .{
            accent[0], accent[1], accent[2], 0.75,
        }, w, 0);
    }
    var y = top + 62;
    const row_h = 42.0;
    var shown: usize = 0;
    var i = g.wifi_scroll;
    while (i < g.wifi_ap_count and y + row_h < l.y + l.h - 44 and shown < 9) : (i += 1) {
        const ap = &g.wifi_aps[i];
        const active = (ap.flags & m.WIFI_AP_ACTIVE) != 0;
        const secured = (ap.flags & m.WIFI_AP_SECURED) != 0;
        const saved = (ap.flags & m.WIFI_AP_SAVED) != 0;
        if (active) fillRound(cr, x - 6, y - 2, w + 12, row_h - 4, 10, .{
            accent[0], accent[1], accent[2], 0.10,
        });
        drawWifiGlyph(cr, x + 10, y + 15, 15.0, if (active) .{
            accent[0], accent[1], accent[2], 0.92,
        } else .{
            fg[0], fg[1], fg[2], 0.5,
        });
        _ = drawText(cr, ap.ssid[0..ap.ssid_len], x + 28, y + 5, fam, "Medium", 9.0, .{
            fg[0], fg[1], fg[2], if (active) 0.98 else 0.88,
        }, w - 112, 0);
        const detail = if (active) "Connected" else if (saved) "Saved" else if (secured) "Secured" else "Open";
        _ = drawText(cr, detail, x + 28, y + 20, fam, "Regular", 7.0, .{
            0.64, 0.70, 0.80, 0.5,
        }, w - 120, 0);
        drawSignalBars(cr, x + w - 36, y + 16, ap.signal, .{ fg[0], fg[1], fg[2], 0.72 });
        if (secured) drawLockGlyph(cr, x + w - 18, y + 15, 9.0, .{ fg[0], fg[1], fg[2], 0.4 });
        addOverlayHit(x - 4, y - 2, w + 8, row_h - 4, .{ .kind = .control_ap, .value = i });
        y += row_h;
        shown += 1;
    }
    if (g.wifi_ap_count == 0) {
        _ = drawText(cr, if (g.wifi_enabled) "No networks found" else "Turn Wi-Fi on to scan", x + 4, y + 12, fam, "Regular", 8.2, .{
            0.64, 0.70, 0.80, 0.42,
        }, w, 0);
    }
    // Bottom actions.
    if (g.wifi_ssid_len > 0) {
        drawControlButton(cr, "DISCONNECT", x, l.y + l.h - 36, 94, 22, false);
        addOverlayHit(x, l.y + l.h - 36, 94, 22, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.wifi_disconnect) });
    }
    drawControlButton(cr, "OTHER NETWORK", x + w - 112, l.y + l.h - 36, 112, 22, false);
    addOverlayHit(x + w - 112, l.y + l.h - 36, 112, 22, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.wifi_hidden) });
    if (g.wifi_modal != .none) drawControlModal(cr, l);
}

fn btFind(path: []const u8) ?usize {
    var i: usize = 0;
    while (i < g.bt_count) : (i += 1) {
        const d = &g.bt_devices[i];
        if (d.path_len == path.len and std.mem.eql(u8, d.path[0..d.path_len], path)) return i;
    }
    return null;
}

fn drawControlBluetooth(cr: *c.cairo_t, l: m.ControlLayout, in_panel: bool, t: f64) void {
    _ = t;
    const accent = g.accent;
    const fg = g.popover_fg;
    const fam = m.popoverFont();
    const pad = 18.0;
    const x = l.x + pad;
    const top = l.y + 14;
    const w = l.w - pad * 2.0;
    drawControlHeader(cr, x, top, w, "BLUETOOTH", in_panel);
    controlPill(cr, x + w - 58, top + 3, 42, 20, g.bt_powered);
    addOverlayHit(x + w - 60, top, 46, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.bt_toggle) });
    drawControlButton(cr, if (g.bt_discovering) "STOP" else "SCAN", x + w - 112, top + 3, 46, 20, false);
    addOverlayHit(x + w - 114, top, 50, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.bt_scan) });
    const status = if (!g.bt_present) "Bluetooth adapter not found" else if (!g.bt_powered) "Bluetooth is off" else if (g.bt_discovering) "Scanning..." else "On";
    _ = drawText(cr, status, x, top + 32, fam, "Regular", 8.4, .{
        fg[0], fg[1], fg[2], 0.58,
    }, w - 20, 0);
    if (!g.system_owner and g.bt_present) {
        _ = drawText(cr, "Pairing is available on the primary display.", x, top + 46, fam, "Regular", 7.0, .{
            accent[0], accent[1], accent[2], 0.62,
        }, w, 0);
    }
    var y = top + 66;
    const row_h = 46.0;
    var shown: usize = 0;
    var i = g.bt_scroll;
    while (i < g.bt_count and y + row_h < l.y + l.h - 24 and shown < 9) : (i += 1) {
        const d = &g.bt_devices[i];
        const connected = (d.flags & m.BT_DEVICE_CONNECTED) != 0;
        const paired = (d.flags & m.BT_DEVICE_PAIRED) != 0;
        if (connected) fillRound(cr, x - 6, y - 2, w + 12, row_h - 6, 10, .{
            accent[0], accent[1], accent[2], 0.10,
        });
        drawBluetoothGlyph(cr, x + 10, y + 16, 15.0, if (connected) .{
            accent[0], accent[1], accent[2], 0.9,
        } else .{
            fg[0], fg[1], fg[2], 0.45,
        });
        const name_max: f64 = if (paired) 150.0 else 80.0;
        _ = drawText(cr, if (d.name_len > 0) d.name[0..d.name_len] else "Unknown device", x + 30, y + 5, fam, "Medium", 9.0, .{
            fg[0], fg[1], fg[2], 0.9,
        }, w - name_max, 0);
        const detail = if (connected) "Connected" else if (paired) "Paired" else "Available";
        _ = drawText(cr, detail, x + 30, y + 21, fam, "Regular", 7.0, .{
            0.64, 0.70, 0.80, 0.5,
        }, w - 150, 0);
        if (d.battery >= 0) {
            var bb: [16]u8 = undefined;
            const bt = std.fmt.bufPrint(&bb, "{d}%", .{d.battery}) catch "";
            const battery_x: f64 = if (paired) 150.0 else 38.0;
            _ = drawText(cr, bt, x + w - battery_x, y + 10, MONO, "Medium", 7.4, .{
                accent[0], accent[1], accent[2], 0.7,
            }, 0, 0);
        }
        if (paired) {
            drawControlButton(cr, "FORGET", x + w - 62, y + 10, 58, 22, false);
            addOverlayHit(x + w - 62, y + 10, 58, 22, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.bt_forget) + @as(usize, i) * 1000 });
        }
        addOverlayHit(x - 4, y - 2, w + 8, row_h - 6, .{ .kind = .control_bt_device, .value = i });
        y += row_h;
        shown += 1;
    }
    if (g.bt_count == 0) {
        _ = drawText(cr, if (g.bt_powered) "No devices found" else "Turn Bluetooth on to scan", x + 4, y + 12, fam, "Regular", 8.2, .{
            0.64, 0.70, 0.80, 0.42,
        }, w, 0);
    }
    if (g.bt_agent != .none) drawControlModal(cr, l);
}

fn drawControlNotifications(cr: *c.cairo_t, l: m.ControlLayout) void {
    const fg = g.popover_fg;
    const fam = m.popoverFont();
    const pad = 18.0;
    const x = l.x + pad;
    const top = l.y + 14;
    const w = l.w - pad * 2.0;
    drawControlHeader(cr, x, top, w, "NOTIFICATIONS", true);
    drawControlButton(cr, if (g.dnd) "SILENT ON" else "SILENT", x + w - 150, top + 3, 66, 20, g.dnd);
    addOverlayHit(x + w - 152, top, 70, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.dnd) });
    drawControlButton(cr, "CLEAR", x + w - 76, top + 3, 66, 20, false);
    addOverlayHit(x + w - 78, top, 70, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.clear_notifications) });
    var y = top + 38;
    const row_h = 48.0;
    var i: usize = 0;
    while (i < g.notification_count and y + row_h < l.y + l.h - 12) : (i += 1) {
        const n = &g.notifications[i];
        paintNotificationIcon(cr, n, x + 2, y + 10, 22);
        const summary = if (n.summary_len > 0) n.summary[0..n.summary_len] else "Notification";
        _ = drawText(cr, summary, x + 32, y + 4, fam, "Semi-Bold", 9.2, .{
            fg[0], fg[1], fg[2], 0.94,
        }, w - 46, 0);
        const app = if (n.app_len > 0) n.app[0..n.app_len] else "App";
        _ = drawText(cr, app, x + 32, y + 20, fam, "Regular", 7.2, .{
            0.64, 0.70, 0.80, 0.48,
        }, w - 46, 0);
        if (n.body_len > 0) {
            _ = drawText(cr, n.body[0..n.body_len], x + 32, y + 32, fam, "Regular", 7.0, .{
                0.64, 0.70, 0.80, 0.38,
            }, w - 46, 0);
        }
        addOverlayHit(x, y, w, row_h - 2, .{ .kind = .control_notification, .value = i });
        c.cairo_new_path(cr);
        c.cairo_move_to(cr, x + 32, y + row_h - 4);
        c.cairo_line_to(cr, x + w, y + row_h - 4);
        setColor(cr, .{ 1, 1, 1, 0.045 });
        c.cairo_set_line_width(cr, 1);
        c.cairo_stroke(cr);
        y += row_h;
    }
    if (g.notification_count == 0) {
        _ = drawText(cr, "No notifications", x + 4, y + 12, fam, "Regular", 9.0, .{
            0.64, 0.70, 0.80, 0.42,
        }, w, 0);
    }
}

fn drawControlCalendar(cr: *c.cairo_t, l: m.ControlLayout) void {
    const accent = g.accent;
    const fg = g.popover_fg;
    const fam = m.popoverFont();
    const pad = 18.0;
    const x = l.x + pad;
    const top = l.y + 14;
    const w = l.w - pad * 2.0;
    drawControlHeader(cr, x, top, w, "CALENDAR", true);

    var now_t: c.time_t = c.time(null);
    var now_tm: c.tm = undefined;
    _ = c.localtime_r(&now_t, &now_tm);
    const today_year = @as(i32, @intCast(now_tm.tm_year)) + 1900;
    const today_month = @as(i32, @intCast(now_tm.tm_mon)) + 1;
    const today_day = @as(i32, @intCast(now_tm.tm_mday));

    var month_buf: [32]u8 = undefined;
    const month_text = std.fmt.bufPrint(&month_buf, "{s} {d}", .{
        m.month_names[@intCast(@mod(g.calendar_month - 1, 12))],
        g.calendar_year,
    }) catch "Calendar";
    _ = drawText(cr, month_text, x + 32, top + 36, fam, "Semi-Bold", 15.0, .{
        fg[0], fg[1], fg[2], 0.96,
    }, w - 100, 0);
    c.cairo_save(cr);
    c.cairo_translate(cr, x + 10, top + 48);
    c.cairo_rotate(cr, std.math.pi);
    drawChevron(cr, 0, 0, 9.0, .{ fg[0], fg[1], fg[2], 0.55 });
    c.cairo_restore(cr);
    addOverlayHit(x - 4, top + 34, 28, 28, .{ .kind = .calendar_prev });
    drawChevron(cr, x + w - 10, top + 48, 9.0, .{ fg[0], fg[1], fg[2], 0.55 });
    addOverlayHit(x + w - 22, top + 34, 28, 28, .{ .kind = .calendar_next });

    const grid_x = x + 4;
    const grid_w = w - 8;
    const cell_w = grid_w / 7.0;
    const weekdays = [_][]const u8{ "S", "M", "T", "W", "T", "F", "S" };
    var wi: usize = 0;
    while (wi < 7) : (wi += 1) {
        _ = drawTextCentered(cr, weekdays[wi], grid_x + cell_w * (@as(f64, @floatFromInt(wi)) + 0.5), top + 74, MONO, "Medium", 7.0, .{
            0.64, 0.70, 0.80, 0.42,
        }, 0, 0);
    }
    const days = m.daysInMonth(g.calendar_year, g.calendar_month);
    const first = m.firstWeekday(g.calendar_year, g.calendar_month);
    const grid_y = top + 88.0;
    const cell_h = 34.0;
    var day: i32 = 1;
    while (day <= days) : (day += 1) {
        const cell_index = first + day - 1;
        const row = @divTrunc(cell_index, 7);
        if (row > 5) break;
        const col_i: usize = @intCast(@mod(cell_index, 7));
        const cx = grid_x + @as(f64, @floatFromInt(col_i)) * cell_w + cell_w / 2.0;
        const cy = grid_y + @as(f64, @floatFromInt(row)) * cell_h + cell_h / 2.0;
        const is_today = g.calendar_year == today_year and g.calendar_month == today_month and day == today_day;
        if (is_today) fillCircle(cr, cx, cy, 13.0, .{ accent[0], accent[1], accent[2], 0.95 });
        var day_buf: [4]u8 = undefined;
        const day_text = std.fmt.bufPrint(&day_buf, "{d}", .{day}) catch "";
        _ = drawTextCentered(cr, day_text, cx, cy + 0.3, MONO, "Medium", 9.2, if (is_today) .{
            0.055, 0.075, 0.105, 1.0,
        } else .{ 0.79, 0.84, 0.91, 0.9 }, 0, 0);
    }
    const today_label = m.weekday_names[@intCast(@mod(now_tm.tm_wday, 7))];
    var today_buf: [80]u8 = undefined;
    const today_text = std.fmt.bufPrint(&today_buf, "{s}, {s} {d}", .{
        today_label,
        m.month_names[@intCast(@mod(today_month - 1, 12))],
        today_day,
    }) catch "Today";
    _ = drawText(cr, today_text, x, l.y + l.h - 34, fam, "Medium", 8.4, .{
        0.82, 0.87, 0.94, 0.8,
    }, w - 100, 0);
    drawControlButton(cr, "TODAY", x + w - 66, l.y + l.h - 40, 66, 24, false);
    addOverlayHit(x + w - 66, l.y + l.h - 40, 66, 24, .{ .kind = .calendar_today });
}

fn drawControlTray(cr: *c.cairo_t, l: m.ControlLayout) void {
    const fg = g.popover_fg;
    const fam = m.popoverFont();
    const pad = 18.0;
    const x = l.x + pad;
    const top = l.y + 14;
    const w = l.w - pad * 2.0;
    drawControlHeader(cr, x, top, w, "TRAY", true);
    var y = top + 40;
    const row_h = 44.0;
    var i: usize = 0;
    while (i < g.tray_count and y + row_h < l.y + l.h - 12) : (i += 1) {
        const item = &g.tray_items[i];
        paintTrayIcon(cr, item, x + 2, y + 8, 22);
        _ = drawText(cr, item.title[0..item.title_len], x + 32, y + 8, fam, "Medium", 9.0, .{
            fg[0], fg[1], fg[2], 0.9,
        }, w - 46, 0);
        _ = drawText(cr, if (item.status == 2) "Needs attention" else "Tray item", x + 32, y + 24, fam, "Regular", 7.0, .{
            0.64, 0.70, 0.80, 0.45,
        }, w - 46, 0);
        addOverlayHit(x, y, w, row_h - 2, .{ .kind = .tray_entry, .value = i });
        y += row_h;
    }
    if (g.tray_count == 0) {
        _ = drawText(cr, "No tray items", x + 4, y + 12, fam, "Regular", 8.4, .{
            0.64, 0.70, 0.80, 0.42,
        }, w, 0);
    }
}

fn drawControlPower(cr: *c.cairo_t, l: m.ControlLayout) void {
    const accent = g.accent;
    const fg = g.popover_fg;
    const fam = m.popoverFont();
    const pad = 18.0;
    const x = l.x + pad;
    const top = l.y + 14;
    const w = l.w - pad * 2.0;
    drawControlHeader(cr, x, top, w, "POWER", true);
    const actions = [_]m.ControlAction{ .power_lock, .power_suspend, .power_reboot, .power_off, .power_quit };
    const row_h = 50.0;
    var y = top + 34;
    var i: usize = 0;
    while (i < actions.len) : (i += 1) {
        const selected = i == g.power_selected;
        if (selected) fillRound(cr, x - 4, y - 2, w + 8, row_h - 4, 10, .{
            accent[0], accent[1], accent[2], 0.12,
        });
        fillRound(cr, x, y + 4, 30, 30, 9, .{ accent[0], accent[1], accent[2], 0.78 });
        _ = drawTextCentered(cr, m.power_labels[i][0..1], x + 15, y + 19, fam, "Semi-Bold", 11.0, .{
            0.055, 0.075, 0.105, 1.0,
        }, 0, 0);
        _ = drawText(cr, m.power_labels[i], x + 42, y + 4, fam, "Semi-Bold", 10.4, .{
            fg[0], fg[1], fg[2], 0.94,
        }, w - 50, 0);
        _ = drawText(cr, m.power_details[i], x + 42, y + 20, fam, "Regular", 7.2, .{
            0.64, 0.70, 0.80, 0.48,
        }, w - 50, 0);
        addOverlayHit(x - 4, y - 2, w + 8, row_h - 4, .{ .kind = .control_power, .value = i });
        y += row_h;
    }
}

fn drawControlModal(cr: *c.cairo_t, l: m.ControlLayout) void {
    const accent = g.accent;
    const fg = g.popover_fg;
    const fam = m.popoverFont();
    g.overlay_hit_count = 0;
    fillRound(cr, l.x, l.y, l.w, l.h, 18, .{ 0.008, 0.012, 0.020, 0.55 });
    const mw = @min(360.0, l.w - 40.0);
    const mh: f64 = if (g.bt_agent == .display_passkey) 190.0 else 210.0;
    const mx = l.x + (l.w - mw) / 2.0;
    const my = l.y + (l.h - mh) / 2.0;
    controlCard(cr, mx, my, mw, mh);

    var title_buf: [112]u8 = undefined;
    var title: []const u8 = "Connect";
    if (g.wifi_modal == .wifi_hidden) {
        title = "Other network";
    } else if (g.wifi_modal == .wifi_password) {
        if (g.wifi_modal_ap < g.wifi_ap_count) {
            const ap = &g.wifi_aps[g.wifi_modal_ap];
            title = std.fmt.bufPrint(&title_buf, "Connect to {s}", .{ap.ssid[0..ap.ssid_len]}) catch "Connect";
        }
    } else if (g.bt_agent != .none) {
        title = "Bluetooth pairing";
    }
    _ = drawText(cr, title, mx + 18, my + 16, fam, "Semi-Bold", 12.0, .{
        fg[0], fg[1], fg[2], 0.96,
    }, mw - 36, 0);

    if (g.bt_agent != .none) {
        const name = if (g.bt_agent_name_len > 0) g.bt_agent_name[0..g.bt_agent_name_len] else "Bluetooth device";
        _ = drawText(cr, name, mx + 18, my + 44, fam, "Regular", 8.4, .{
            0.64, 0.70, 0.80, 0.62,
        }, mw - 36, 0);
        if (g.bt_agent == .confirm) {
            _ = drawText(cr, "Confirm the pairing code on both devices.", mx + 18, my + 68, fam, "Regular", 7.6, .{
                0.64, 0.70, 0.80, 0.55,
            }, mw - 36, 0);
            if (g.bt_agent_passkey_len > 0) {
                _ = drawTextCentered(cr, g.bt_agent_passkey[0..g.bt_agent_passkey_len], mx + mw / 2.0, my + 102, MONO, "Semi-Bold", 22.0, .{
                    accent[0], accent[1], accent[2], 0.95,
                }, 0, 0);
            }
        } else if (g.bt_agent == .display_passkey) {
            _ = drawText(cr, "Enter this code on the device:", mx + 18, my + 68, fam, "Regular", 7.6, .{
                0.64, 0.70, 0.80, 0.55,
            }, mw - 36, 0);
            _ = drawTextCentered(cr, g.bt_agent_passkey[0..g.bt_agent_passkey_len], mx + mw / 2.0, my + 102, MONO, "Semi-Bold", 22.0, .{
                accent[0], accent[1], accent[2], 0.95,
            }, 0, 0);
        } else {
            _ = drawText(cr, "Enter the PIN or passkey.", mx + 18, my + 66, fam, "Regular", 7.6, .{
                0.64, 0.70, 0.80, 0.55,
            }, mw - 36, 0);
            fillRound(cr, mx + 18, my + 84, mw - 36, 30, 8, .{ 1, 1, 1, 0.055 });
            var masked: [m.MAX_CONTROL_INPUT]u8 = @splat('*');
            const plen = @min(g.control_input_len, masked.len);
            _ = drawText(cr, if (g.bt_agent == .passkey) masked[0..plen] else g.control_input[0..g.control_input_len], mx + 28, my + 93, MONO, "Medium", 11.0, .{
                fg[0], fg[1], fg[2], 0.9,
            }, mw - 56, 0);
            addOverlayHit(mx + 18, my + 84, mw - 36, 30, .{ .kind = .control_input, .value = 0 });
        }
        drawControlButton(cr, "CANCEL", mx + mw - 170, my + mh - 42, 72, 26, false);
        addOverlayHit(mx + mw - 170, my + mh - 42, 72, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.modal_cancel) });
        drawControlButton(cr, if (g.bt_agent == .display_passkey) "DONE" else "PAIR", mx + mw - 90, my + mh - 42, 72, 26, true);
        addOverlayHit(mx + mw - 90, my + mh - 42, 72, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.modal_confirm) });
        return;
    }

    if (g.wifi_modal == .wifi_hidden) {
        _ = drawText(cr, "NETWORK NAME", mx + 18, my + 44, MONO, "Medium", 6.2, .{
            0.64, 0.70, 0.80, 0.45,
        }, 0, 1.0);
        fillRound(cr, mx + 18, my + 54, mw - 36, 28, 7, .{ 1, 1, 1, if (g.control_field == 0) 0.10 else 0.045 });
        _ = drawText(cr, g.control_ssid[0..g.control_ssid_len], mx + 27, my + 62, fam, "Medium", 9.0, .{
            fg[0], fg[1], fg[2], 0.9,
        }, mw - 54, 0);
        addOverlayHit(mx + 18, my + 54, mw - 36, 28, .{ .kind = .control_input, .value = 0 });
        _ = drawText(cr, "PASSWORD", mx + 18, my + 94, MONO, "Medium", 6.2, .{
            0.64, 0.70, 0.80, 0.45,
        }, 0, 1.0);
        fillRound(cr, mx + 18, my + 104, mw - 36, 28, 7, .{ 1, 1, 1, if (g.control_field == 1) 0.10 else 0.045 });
        var masked: [m.MAX_CONTROL_INPUT]u8 = @splat('*');
        const plen = @min(g.control_input_len, masked.len);
        _ = drawText(cr, masked[0..plen], mx + 27, my + 112, MONO, "Medium", 9.0, .{
            fg[0], fg[1], fg[2], 0.9,
        }, mw - 54, 0);
        addOverlayHit(mx + 18, my + 104, mw - 36, 28, .{ .kind = .control_input, .value = 1 });
    } else {
        _ = drawText(cr, "PASSWORD", mx + 18, my + 48, MONO, "Medium", 6.2, .{
            0.64, 0.70, 0.80, 0.45,
        }, 0, 1.0);
        fillRound(cr, mx + 18, my + 58, mw - 36, 30, 7, .{ 1, 1, 1, 0.08 });
        var masked: [m.MAX_CONTROL_INPUT]u8 = @splat('*');
        const plen = @min(g.control_input_len, masked.len);
        _ = drawText(cr, masked[0..plen], mx + 27, my + 67, MONO, "Medium", 10.0, .{
            fg[0], fg[1], fg[2], 0.9,
        }, mw - 54, 0);
        addOverlayHit(mx + 18, my + 58, mw - 36, 30, .{ .kind = .control_input, .value = 0 });
    }
    drawControlButton(cr, "CANCEL", mx + mw - 170, my + mh - 42, 72, 26, false);
    addOverlayHit(mx + mw - 170, my + mh - 42, 72, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.modal_cancel) });
    drawControlButton(cr, "CONNECT", mx + mw - 90, my + mh - 42, 72, 26, true);
    addOverlayHit(mx + mw - 90, my + mh - 42, 72, 26, .{ .kind = .control_action, .value = @intFromEnum(m.ControlAction.modal_confirm) });

    const field_y: f64 = if (g.wifi_modal == .wifi_hidden) 104.0 else 58.0;
    g.control_input_rect = .{
        @intFromFloat(mx * @as(f64, @floatFromInt(g.scale))),
        @intFromFloat((my + field_y) * @as(f64, @floatFromInt(g.scale))),
        @intFromFloat((mw - 36.0) * @as(f64, @floatFromInt(g.scale))),
        @intFromFloat(30.0 * @as(f64, @floatFromInt(g.scale))),
    };
}

fn controlPopoverLayout(W: f64, H: f64) m.ControlLayout {
    var l = m.controlCenterLayout(W, H);
    l.w = @min(l.w, 520.0);
    l.h = @min(l.h, 620.0);
    l.columns = 1;
    l.x = W - l.w - 16.0;
    if (l.x < 8.0) l.x = 8.0;
    if (l.y + l.h > H - 8.0) l.y = @max(8.0, H - l.h - 8.0);
    return l;
}

fn drawWifiPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const l = controlPopoverLayout(W, H);
    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1;
    g.overlay_hit_x = 0;
    g.overlay_hit_y = 0;
    g.overlay_panel = .{ .x = l.x, .y = l.y, .w = l.w, .h = l.h };
    c.cairo_push_group(cr);
    controlCard(cr, l.x, l.y, l.w, l.h);
    c.cairo_save(cr);
    roundRect(cr, l.x, l.y, l.w, l.h, 18);
    c.cairo_clip(cr);
    drawControlWifi(cr, l, false, t);
    c.cairo_restore(cr);
    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
}

fn drawBluetoothPopover(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    const l = controlPopoverLayout(W, H);
    g.overlay_hit_count = 0;
    g.overlay_hit_scale = 1;
    g.overlay_hit_x = 0;
    g.overlay_hit_y = 0;
    g.overlay_panel = .{ .x = l.x, .y = l.y, .w = l.w, .h = l.h };
    c.cairo_push_group(cr);
    controlCard(cr, l.x, l.y, l.w, l.h);
    c.cairo_save(cr);
    roundRect(cr, l.x, l.y, l.w, l.h, 18);
    c.cairo_clip(cr);
    drawControlBluetooth(cr, l, false, t);
    c.cairo_restore(cr);
    c.cairo_pop_group_to_source(cr);
    c.cairo_paint_with_alpha(cr, t);
}

fn drawOverlayCore(cr: *c.cairo_t, W: f64, H: f64, t: f64) void {
    if (g.overlay_mode == .launcher) {
        const start_style = g.launcher_open_style == .start;
        const l = if (start_style) m.startMenuLayout(W, H) else m.launcherLayout(W, H);
        g.overlay_hit_scale = l.scale;
        g.overlay_hit_x = l.x;
        g.overlay_hit_y = l.y;

        c.cairo_save(cr);
        c.cairo_translate(cr, l.x, l.y);
        c.cairo_scale(cr, l.scale, l.scale);
        if (start_style) {
            // The start menu grows away from the bar edge, like a native
            // desktop start menu, instead of scaling around its center.
            const slide = m.startMenuSlide();
            const drop = 1.0 - t;
            const anim = 0.985 + 0.015 * t;
            c.cairo_translate(cr, slide.x * drop, slide.y * drop);
            c.cairo_scale(cr, anim, anim);
            drawStartMenu(cr, 0, 0, 360, 620, t);
            g.overlay_panel = .{
                .x = l.x,
                .y = l.y,
                .w = 360.0 * l.scale,
                .h = 620.0 * l.scale,
            };
        } else {
            const anim = 0.97 + 0.03 * t;
            c.cairo_translate(cr, 380.0, 310.0);
            c.cairo_scale(cr, anim, anim);
            c.cairo_translate(cr, -380.0, -310.0);
            c.cairo_translate(cr, 0, (1.0 - t) * 8.0);
            drawLauncherPanel(cr, 0, 0, 760, 620, t);
            g.overlay_panel = .{
                .x = l.x,
                .y = l.y,
                .w = 760.0 * l.scale,
                .h = 620.0 * l.scale,
            };
        }
        c.cairo_restore(cr);
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
    } else if (g.overlay_mode == .extensions) {
        drawExtensionsPopover(cr, W, H, t);
    } else if (g.overlay_mode == .module) {
        drawModulePopover(cr, W, H, t);
    } else if (g.overlay_mode == .control) {
        drawControlCenter(cr, W, H, t);
    } else if (g.overlay_mode == .wifi) {
        drawWifiPopover(cr, W, H, t);
    } else if (g.overlay_mode == .bluetooth) {
        drawBluetoothPopover(cr, W, H, t);
    }

}

fn renderOverlayBase(s: *m.Surface) ?*c.cairo_surface_t {
    const scale: u32 = @intCast(@max(1, s.scale));
    const buf_w = s.width * scale;
    const buf_h = s.height * scale;
    if (buf_w == 0 or buf_h == 0) return null;
    const img = c.cairo_image_surface_create(
        c.CAIRO_FORMAT_ARGB32,
        @intCast(buf_w),
        @intCast(buf_h),
    );
    if (img == null or c.cairo_surface_status(img) != c.CAIRO_STATUS_SUCCESS) {
        if (img) |surface| c.cairo_surface_destroy(surface);
        return null;
    }
    const cr = c.cairo_create(img) orelse {
        c.cairo_surface_destroy(img);
        return null;
    };
    const scl: f64 = @floatFromInt(scale);
    c.cairo_scale(cr, scl, scl);
    setCairoQuality(cr);
    const old_selected = m.g.selected_anim;
    m.g.selected_anim = @floatFromInt(m.g.selected);
    drawOverlayCore(cr, @floatFromInt(s.width), @floatFromInt(s.height), 1.0);
    m.g.selected_anim = old_selected;
    c.cairo_destroy(cr);
    c.cairo_surface_flush(img);
    return img;
}

fn overlayMatrix(s: *m.Surface, t: f64) [9]f32 {
    const W: f64 = @floatFromInt(s.width);
    const H: f64 = @floatFromInt(s.height);
    var scale: f64 = 1.0;
    var offset_x: f64 = 0.0;
    var offset_y: f64 = 0.0;
    var pivot_x: f64 = W / 2.0;
    var pivot_y: f64 = H / 2.0;
    if (m.g.overlay_mode == .launcher) {
        const l = if (m.g.launcher_open_style == .start)
            m.startMenuLayout(W, H)
        else
            m.launcherLayout(W, H);
        if (m.g.launcher_open_style == .start) {
            const slide = m.startMenuSlide();
            scale = 0.985 + 0.015 * t;
            offset_x = slide.x * (1.0 - t);
            offset_y = slide.y * (1.0 - t);
            pivot_x = l.x;
            pivot_y = l.y;
        } else {
            scale = 0.97 + 0.03 * t;
            offset_y = (1.0 - t) * 8.0;
            pivot_x = l.x + 380.0;
            pivot_y = l.y + 310.0;
        }
    }
    const px = (pivot_x / W) * 2.0 - 1.0;
    const py = 1.0 - (pivot_y / H) * 2.0;
    const ox = px * (1.0 - scale) + (offset_x / W) * 2.0;
    const oy = py * (1.0 - scale) - (offset_y / H) * 2.0;
    return .{
        @floatCast(scale), 0.0, 0.0,
        0.0, @floatCast(scale), 0.0,
        @floatCast(ox), @floatCast(oy), 1.0,
    };
}

fn drawOverlayGpu(s: *m.Surface) bool {
    if (g.overlay_mode == .screenshot) return false;
    if (!gpu.ready()) return false;
    if (s.gpu == null) {
        const physical: u32 = @intCast(@max(1, s.scale));
        if (!gpu.configure(s, s.width * physical, s.height * physical)) return false;
        destroyBuffers(s);
    }
    if (g.overlay_content_dirty) {
        const base = renderOverlayBase(s) orelse {
            gpu.fail("overlay base render failed");
            return false;
        };
        defer c.cairo_surface_destroy(base);
        if (!gpu.setBase(s, base)) return false;
        g.overlay_content_dirty = false;
    }
    const t = std.math.clamp(m.g.menu_anim, 0.0, 1.0);
    const dim: f64 = if (m.g.overlay_mode == .audio)
        0.0
    else if (m.g.overlay_mode == .launcher)
        0.52
    else
        0.30;
    if (!gpu.drawOverlay(s, @floatCast(t), @floatCast(dim * t), overlayMatrix(s, t))) {
        return false;
    }
    s.dirty = false;
    return true;
}

pub fn drawOverlay(s: *m.Surface) void {
    if (m.g.overlay_renderer == .gpu) {
        if (drawOverlayGpu(s)) return;
        gpu.destroySurface(s);
    }
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

    if (g.overlay_mode != .audio) {
        fillRound(cr, 0, 0, W, H, 0, .{ 0.012, 0.018, 0.030, dim * t });
        const vp = c.cairo_pattern_create_radial(W / 2, H / 2, H * 0.12, W / 2, H / 2, H * 0.8);
        c.cairo_pattern_add_color_stop_rgba(vp, 0, 0, 0, 0, 0);
        c.cairo_pattern_add_color_stop_rgba(vp, 1, 0, 0, 0, 0.42 * t);
        c.cairo_set_source(cr, vp);
        c.cairo_paint(cr);
        c.cairo_pattern_destroy(vp);
    }

    drawOverlayCore(cr, W, H, t);
    end(s, d);
}
