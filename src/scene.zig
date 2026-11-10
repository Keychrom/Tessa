const std = @import("std");
const c = @import("c.zig").c;
const types = @import("types.zig");
const core = @import("core.zig");
const config = @import("config.zig");
const layout = @import("layout.zig");
const rules = @import("rules.zig");
const events = @import("events.zig");
const event_names = @import("event_names.zig");

const Server = types.Server;
const Client = types.Client;
const Output = types.Output;
const Scene = types.Scene;
const SceneApp = types.SceneApp;

const MAX_LINE = 2048;
const RESTORE_TIMEOUT_MS: i64 = 15_000;

const Section = enum { scene, theme, wallpaper, app };

fn validHexColor(value: []const u8) bool {
    var hex = value;
    if (hex.len > 0 and hex[0] == '#') hex = hex[1..];
    if (hex.len != 6) return false;
    for (hex) |ch| {
        if (!std.ascii.isHex(ch)) return false;
    }
    return true;
}

fn parseOptionalColor(value: []const u8, out: *?[3]f32) void {
    if (!validHexColor(value)) return;
    var rgb: [3]f32 = .{ 0, 0, 0 };
    core.parseHexColor(value, &rgb);
    out.* = rgb;
}

fn parseWallpaperFit(value: []const u8) ?types.WallpaperFit {
    if (std.ascii.eqlIgnoreCase(value, "cover")) return .cover;
    if (std.ascii.eqlIgnoreCase(value, "contain")) return .contain;
    if (std.ascii.eqlIgnoreCase(value, "stretch")) return .stretch;
    return null;
}

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > types.MAX_SCENE_NAME - 1) return false;
    if (name[0] == '.') return false;
    for (name) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '-' and ch != '_' and ch != '.') return false;
    }
    return true;
}

fn copyZ(dest: []u8, text: []const u8) bool {
    if (text.len >= dest.len) return false;
    @memcpy(dest[0..text.len], text);
    dest[text.len] = 0;
    return true;
}

fn openDir(server: *Server) ?*c.DIR {
    if (server.scene_dir_len == 0 or server.scene_dir_len >= server.scene_dir.len) return null;
    var zpath: [512:0]u8 = undefined;
    @memcpy(zpath[0..server.scene_dir_len], server.scene_dir[0..server.scene_dir_len]);
    zpath[server.scene_dir_len] = 0;
    return c.opendir(&zpath);
}

fn scenePath(server: *Server, name: []const u8, buf: []u8) []const u8 {
    if (!validName(name) or server.scene_dir_len == 0) return "";
    return std.fmt.bufPrint(buf, "{s}/{s}.scene", .{
        server.scene_dir[0..server.scene_dir_len],
        name,
    }) catch "";
}

fn resolveDir(server: *Server) void {
    server.scene_dir_len = 0;
    if (c.getenv("TESSA_SCENE_DIR")) |value| {
        const text = std.mem.span(value);
        core.copyString(&server.scene_dir, &server.scene_dir_len, text);
        return;
    }

    var path_buf: [512]u8 = undefined;
    const config_path = config.resolvePath(&path_buf);
    var dir_buf: [512]u8 = undefined;
    const dir = if (config_path.len > 0)
        (std.fs.path.dirname(config_path) orelse ".")
    else if (c.getenv("XDG_CONFIG_HOME")) |value|
        std.fmt.bufPrint(&dir_buf, "{s}/tessa", .{core.cstr(value)}) catch ""
    else if (c.getenv("HOME")) |value|
        std.fmt.bufPrint(&dir_buf, "{s}/.config/tessa", .{core.cstr(value)}) catch ""
    else
        "";

    if (dir.len == 0) return;
    var final_buf: [512]u8 = undefined;
    const final = std.fmt.bufPrint(&final_buf, "{s}/scenes", .{dir}) catch return;
    core.copyString(&server.scene_dir, &server.scene_dir_len, final);
}

pub fn init(server: *Server) void {
    resolveDir(server);
    reload(server);
}

fn ensureDir(server: *Server) bool {
    if (server.scene_dir_len == 0 or server.scene_dir_len >= server.scene_dir.len) return false;
    var zpath: [512:0]u8 = undefined;
    @memcpy(zpath[0..server.scene_dir_len], server.scene_dir[0..server.scene_dir_len]);
    zpath[server.scene_dir_len] = 0;
    if (c.access(&zpath, c.F_OK) == 0) return true;
    if (c.mkdir(&zpath, 0o700) == 0) return true;
    return c.access(&zpath, c.F_OK) == 0;
}

fn parseColumnWidth(text: []const u8) ?types.ColumnWidth {
    return config.parseColumnWidth(text);
}

fn parseCenterFocused(text: []const u8) ?types.CenterFocusedColumn {
    if (std.ascii.eqlIgnoreCase(text, "never") or
        std.ascii.eqlIgnoreCase(text, "off") or
        std.ascii.eqlIgnoreCase(text, "false")) return .never;
    if (std.ascii.eqlIgnoreCase(text, "always") or
        std.ascii.eqlIgnoreCase(text, "on") or
        std.ascii.eqlIgnoreCase(text, "true")) return .always;
    if (std.ascii.eqlIgnoreCase(text, "on-overflow") or
        std.ascii.eqlIgnoreCase(text, "on_overflow") or
        std.ascii.eqlIgnoreCase(text, "overflow")) return .on_overflow;
    return null;
}

fn parseBool(text: []const u8) bool {
    return std.mem.eql(u8, text, "1") or
        std.ascii.eqlIgnoreCase(text, "true") or
        std.ascii.eqlIgnoreCase(text, "yes") or
        std.ascii.eqlIgnoreCase(text, "on");
}

fn parseFile(path: []const u8, scene: *Scene) bool {
    var zpath: [512:0]u8 = undefined;
    if (!copyZ(&zpath, path)) return false;
    const file = c.fopen(&zpath, "r") orelse return false;
    defer _ = c.fclose(file);

    scene.* = .{};
    var current: ?*SceneApp = null;
    var section: Section = .scene;
    var line: [MAX_LINE]u8 = undefined;
    while (c.fgets(&line, @intCast(line.len), file)) |_| {
        const raw = std.mem.span(@as([*:0]const u8, @ptrCast(&line)));
        const text = trim(raw);
        if (text.len == 0 or text[0] == '#') continue;
        if (std.mem.eql(u8, text, "[app]")) {
            section = .app;
            if (scene.app_count < scene.apps.len) {
                current = &scene.apps[scene.app_count];
                scene.app_count += 1;
            } else {
                current = null;
            }
            continue;
        }
        if (std.mem.eql(u8, text, "[theme]")) {
            section = .theme;
            current = null;
            continue;
        }
        if (std.mem.eql(u8, text, "[wallpaper]")) {
            section = .wallpaper;
            current = null;
            continue;
        }
        if (std.mem.eql(u8, text, "[scene]")) {
            section = .scene;
            current = null;
            continue;
        }
        if (text[0] == '[') {
            section = .scene;
            current = null;
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, text, '=') orelse continue;
        const key = trim(text[0..eq]);
        const value = trim(text[eq + 1 ..]);

        if (std.ascii.eqlIgnoreCase(key, "name")) {
            core.copyString(&scene.name, &scene.name_len, value);
        } else if (std.ascii.eqlIgnoreCase(key, "workspace")) {
            scene.workspace = std.fmt.parseInt(usize, value, 10) catch scene.workspace;
            if (scene.workspace > types.WS_COUNT) scene.workspace = 0;
        } else if (std.ascii.eqlIgnoreCase(key, "layout")) {
            scene.layout = types.layoutFromName(value) orelse scene.layout;
        } else if (std.ascii.eqlIgnoreCase(key, "gaps")) {
            scene.tuning.gaps = std.fmt.parseInt(i32, value, 10) catch scene.tuning.gaps;
        } else if (std.ascii.eqlIgnoreCase(key, "outer_gaps") or std.ascii.eqlIgnoreCase(key, "outer-gaps")) {
            scene.tuning.outer_gaps = std.fmt.parseInt(i32, value, 10) catch scene.tuning.outer_gaps;
        } else if (std.ascii.eqlIgnoreCase(key, "master_ratio") or std.ascii.eqlIgnoreCase(key, "master-ratio")) {
            scene.tuning.master_ratio = std.fmt.parseFloat(f32, value) catch scene.tuning.master_ratio;
        } else if (std.ascii.eqlIgnoreCase(key, "master_count") or std.ascii.eqlIgnoreCase(key, "master-count")) {
            scene.tuning.master_count = std.fmt.parseInt(usize, value, 10) catch scene.tuning.master_count;
        } else if (std.ascii.eqlIgnoreCase(key, "mosaic_ratio") or std.ascii.eqlIgnoreCase(key, "mosaic-ratio")) {
            scene.tuning.mosaic_ratio = std.fmt.parseFloat(f32, value) catch scene.tuning.mosaic_ratio;
        } else if (std.ascii.eqlIgnoreCase(key, "mosaic_min_size") or std.ascii.eqlIgnoreCase(key, "mosaic-min-size")) {
            scene.tuning.mosaic_min_size = std.fmt.parseInt(i32, value, 10) catch scene.tuning.mosaic_min_size;
        } else if (std.ascii.eqlIgnoreCase(key, "grid_columns") or std.ascii.eqlIgnoreCase(key, "grid-columns")) {
            scene.tuning.grid_columns = std.fmt.parseInt(usize, value, 10) catch scene.tuning.grid_columns;
        } else if (std.ascii.eqlIgnoreCase(key, "column_width") or std.ascii.eqlIgnoreCase(key, "column-width")) {
            scene.tuning.column_width = parseColumnWidth(value) orelse scene.tuning.column_width;
        } else if (std.ascii.eqlIgnoreCase(key, "center_focused_column") or std.ascii.eqlIgnoreCase(key, "center-focused-column")) {
            scene.tuning.center_focused_column = parseCenterFocused(value) orelse scene.tuning.center_focused_column;
        } else if (section == .theme) {
            if (std.ascii.eqlIgnoreCase(key, "accent")) {
                parseOptionalColor(value, &scene.theme.accent);
            } else if (std.ascii.eqlIgnoreCase(key, "bg") or std.ascii.eqlIgnoreCase(key, "background")) {
                parseOptionalColor(value, &scene.theme.bg);
            } else if (std.ascii.eqlIgnoreCase(key, "border_active") or std.ascii.eqlIgnoreCase(key, "border-active")) {
                parseOptionalColor(value, &scene.theme.border_active);
            } else if (std.ascii.eqlIgnoreCase(key, "border_inactive") or std.ascii.eqlIgnoreCase(key, "border-inactive")) {
                parseOptionalColor(value, &scene.theme.border_inactive);
            } else if (std.ascii.eqlIgnoreCase(key, "panel_bg") or std.ascii.eqlIgnoreCase(key, "panel-bg")) {
                parseOptionalColor(value, &scene.theme.panel_bg);
            } else if (std.ascii.eqlIgnoreCase(key, "panel_fg") or std.ascii.eqlIgnoreCase(key, "panel-fg")) {
                parseOptionalColor(value, &scene.theme.panel_fg);
            } else if (std.ascii.eqlIgnoreCase(key, "bg_top") or std.ascii.eqlIgnoreCase(key, "bg-top")) {
                parseOptionalColor(value, &scene.theme.bg_top);
            } else if (std.ascii.eqlIgnoreCase(key, "bg_bottom") or std.ascii.eqlIgnoreCase(key, "bg-bottom")) {
                parseOptionalColor(value, &scene.theme.bg_bottom);
            }
        } else if (section == .wallpaper) {
            if (std.ascii.eqlIgnoreCase(key, "image") or std.ascii.eqlIgnoreCase(key, "wallpaper_image")) {
                core.copyString(&scene.wallpaper.image, &scene.wallpaper.image_len, value);
            } else if (std.ascii.eqlIgnoreCase(key, "fit")) {
                scene.wallpaper.fit = parseWallpaperFit(value) orelse scene.wallpaper.fit;
            } else if (std.ascii.eqlIgnoreCase(key, "art")) {
                scene.wallpaper.art = parseBool(value);
            } else if (std.ascii.eqlIgnoreCase(key, "art_opacity") or std.ascii.eqlIgnoreCase(key, "art-opacity")) {
                const opacity = std.fmt.parseFloat(f32, value) catch continue;
                scene.wallpaper.art_opacity = std.math.clamp(opacity, 0.0, 1.0);
            }
        } else if (current) |app| {
            if (std.ascii.eqlIgnoreCase(key, "app_id") or std.ascii.eqlIgnoreCase(key, "app-id")) {
                core.copyString(&app.app_id, &app.app_id_len, value);
            } else if (std.ascii.eqlIgnoreCase(key, "title")) {
                core.copyString(&app.title, &app.title_len, value);
            } else if (std.ascii.eqlIgnoreCase(key, "command")) {
                core.copyString(&app.command, &app.command_len, value);
            } else if (std.ascii.eqlIgnoreCase(key, "floating")) {
                app.floating = parseBool(value);
            } else if (std.ascii.eqlIgnoreCase(key, "x")) {
                app.x = std.fmt.parseInt(i32, value, 10) catch app.x;
            } else if (std.ascii.eqlIgnoreCase(key, "y")) {
                app.y = std.fmt.parseInt(i32, value, 10) catch app.y;
            } else if (std.ascii.eqlIgnoreCase(key, "width") or std.ascii.eqlIgnoreCase(key, "w")) {
                app.w = std.fmt.parseInt(i32, value, 10) catch app.w;
            } else if (std.ascii.eqlIgnoreCase(key, "height") or std.ascii.eqlIgnoreCase(key, "h")) {
                app.h = std.fmt.parseInt(i32, value, 10) catch app.h;
            }
        }
    }

    scene.tuning.gaps = std.math.clamp(scene.tuning.gaps, 0, 64);
    scene.tuning.outer_gaps = std.math.clamp(scene.tuning.outer_gaps, 0, 128);
    scene.tuning.master_ratio = std.math.clamp(scene.tuning.master_ratio, 0.15, 0.9);
    scene.tuning.master_count = std.math.clamp(scene.tuning.master_count, 1, 8);
    scene.tuning.mosaic_ratio = std.math.clamp(scene.tuning.mosaic_ratio, 0.25, 0.85);
    scene.tuning.mosaic_min_size = std.math.clamp(scene.tuning.mosaic_min_size, 80, 600);
    return true;
}

fn validSceneApp(app: *const SceneApp) bool {
    return app.app_id_len > 0 or app.title_len > 0;
}

fn parseNamed(server: *Server, name: []const u8, scene: *Scene) bool {
    var path_buf: [512]u8 = undefined;
    const path = scenePath(server, name, &path_buf);
    if (path.len == 0 or !parseFile(path, scene)) return false;
    core.copyString(&scene.name, &scene.name_len, name);
    return true;
}

fn writeRaw(file: *c.FILE, text: []const u8) void {
    var offset: usize = 0;
    while (offset < text.len) {
        var chunk: [1]u8 = .{text[offset]};
        if (chunk[0] == '\n' or chunk[0] == '\r') chunk[0] = ' ';
        _ = c.fwrite(&chunk, 1, 1, file);
        offset += 1;
    }
}

fn writeFmt(file: *c.FILE, comptime fmt: []const u8, args: anytype) void {
    var buf: [MAX_LINE]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = c.fwrite(text.ptr, 1, text.len, file);
}

fn hexColor(buf: *[7]u8, rgb: [3]f32) []const u8 {
    const digits = "0123456789abcdef";
    buf[0] = '#';
    for (rgb, 0..) |channel, i| {
        const value: u8 = @intFromFloat(std.math.clamp(channel, 0.0, 1.0) * 255.0 + 0.5);
        buf[1 + i * 2] = digits[@as(usize, value >> 4)];
        buf[2 + i * 2] = digits[@as(usize, value & 0x0f)];
    }
    return buf[0..7];
}

fn writeSceneFile(server: *Server, scene: *const Scene) bool {
    if (!ensureDir(server)) return false;
    var path_buf: [512]u8 = undefined;
    const path = scenePath(server, scene.name[0..scene.name_len], &path_buf);
    if (path.len == 0) return false;
    var temp_buf: [512]u8 = undefined;
    const temp = std.fmt.bufPrint(&temp_buf, "{s}.tmp", .{path}) catch return false;

    var zpath: [512:0]u8 = undefined;
    if (!copyZ(&zpath, temp)) return false;
    const file = c.fopen(&zpath, "w") orelse {
        core.logInfo("scene: cannot write {s}", .{temp});
        return false;
    };
    writeFmt(file, "# Tessa scene v1\n", .{});
    writeFmt(file, "name = {s}\n", .{scene.name[0..scene.name_len]});
    writeFmt(file, "workspace = {d}\n", .{scene.workspace});
    writeFmt(file, "layout = {s}\n", .{types.layoutName(scene.layout)});
    writeFmt(file, "gaps = {d}\n", .{scene.tuning.gaps});
    writeFmt(file, "outer_gaps = {d}\n", .{scene.tuning.outer_gaps});
    writeFmt(file, "master_ratio = {d:.4}\n", .{scene.tuning.master_ratio});
    writeFmt(file, "master_count = {d}\n", .{scene.tuning.master_count});
    writeFmt(file, "mosaic_ratio = {d:.4}\n", .{scene.tuning.mosaic_ratio});
    writeFmt(file, "mosaic_min_size = {d}\n", .{scene.tuning.mosaic_min_size});
    writeFmt(file, "grid_columns = {d}\n", .{scene.tuning.grid_columns});
    switch (scene.tuning.column_width.kind) {
        .proportion => writeFmt(file, "column_width = {d:.1}%\n", .{scene.tuning.column_width.value * 100.0}),
        .fixed => writeFmt(file, "column_width = {d:.0}\n", .{scene.tuning.column_width.value}),
    }
    writeFmt(file, "center_focused_column = {s}\n", .{@tagName(scene.tuning.center_focused_column)});

    const has_theme = scene.theme.accent != null or scene.theme.bg != null or
        scene.theme.border_active != null or scene.theme.border_inactive != null or
        scene.theme.panel_bg != null or scene.theme.panel_fg != null or
        scene.theme.bg_top != null or scene.theme.bg_bottom != null;
    if (has_theme) {
        writeFmt(file, "\n[theme]\n", .{});
        var hex_buf: [7]u8 = undefined;
        if (scene.theme.accent) |rgb| writeFmt(file, "accent = {s}\n", .{hexColor(&hex_buf, rgb)});
        if (scene.theme.bg) |rgb| writeFmt(file, "bg = {s}\n", .{hexColor(&hex_buf, rgb)});
        if (scene.theme.border_active) |rgb| writeFmt(file, "border_active = {s}\n", .{hexColor(&hex_buf, rgb)});
        if (scene.theme.border_inactive) |rgb| writeFmt(file, "border_inactive = {s}\n", .{hexColor(&hex_buf, rgb)});
        if (scene.theme.panel_bg) |rgb| writeFmt(file, "panel_bg = {s}\n", .{hexColor(&hex_buf, rgb)});
        if (scene.theme.panel_fg) |rgb| writeFmt(file, "panel_fg = {s}\n", .{hexColor(&hex_buf, rgb)});
        if (scene.theme.bg_top) |rgb| writeFmt(file, "bg_top = {s}\n", .{hexColor(&hex_buf, rgb)});
        if (scene.theme.bg_bottom) |rgb| writeFmt(file, "bg_bottom = {s}\n", .{hexColor(&hex_buf, rgb)});
    }

    const has_wallpaper = scene.wallpaper.image_len > 0 or scene.wallpaper.fit != null or
        scene.wallpaper.art != null or scene.wallpaper.art_opacity != null;
    if (has_wallpaper) {
        writeFmt(file, "\n[wallpaper]\n", .{});
        if (scene.wallpaper.image_len > 0) writeFmt(file, "image = {s}\n", .{scene.wallpaper.image[0..scene.wallpaper.image_len]});
        if (scene.wallpaper.fit) |fit| writeFmt(file, "fit = {s}\n", .{@tagName(fit)});
        if (scene.wallpaper.art) |art| writeFmt(file, "art = {}\n", .{art});
        if (scene.wallpaper.art_opacity) |opacity| writeFmt(file, "art_opacity = {d:.3}\n", .{opacity});
    }

    var i: usize = 0;
    while (i < scene.app_count) : (i += 1) {
        const app = &scene.apps[i];
        writeFmt(file, "\n[app]\n", .{});
        if (app.command_len > 0) writeFmt(file, "command = {s}\n", .{app.command[0..app.command_len]});
        if (app.app_id_len > 0) writeFmt(file, "app_id = {s}\n", .{app.app_id[0..app.app_id_len]});
        if (app.title_len > 0) writeFmt(file, "title = {s}\n", .{app.title[0..app.title_len]});
        writeFmt(file, "floating = {}\n", .{app.floating});
        if (app.floating) {
            writeFmt(file, "x = {d}\n", .{app.x});
            writeFmt(file, "y = {d}\n", .{app.y});
            writeFmt(file, "width = {d}\n", .{app.w});
            writeFmt(file, "height = {d}\n", .{app.h});
        }
    }

    const closed = c.fclose(file);
    if (closed != 0) {
        _ = c.unlink(&zpath);
        return false;
    }

    var zfinal: [512:0]u8 = undefined;
    if (!copyZ(&zfinal, path)) {
        _ = c.unlink(&zpath);
        return false;
    }
    if (c.rename(&zpath, &zfinal) != 0) {
        core.logInfo("scene: cannot replace {s}", .{path});
        _ = c.unlink(&zpath);
        return false;
    }
    _ = c.chmod(&zfinal, 0o600);
    return true;
}

fn appendShellArg(out: []u8, len: *usize, arg: []const u8) bool {
    if (arg.len == 0) return true;
    var simple = true;
    for (arg) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and
            ch != '_' and ch != '@' and ch != '%' and ch != '+' and ch != '=' and
            ch != ':' and ch != ',' and ch != '.' and ch != '/' and ch != '-')
        {
            simple = false;
            break;
        }
    }
    if (len.* + arg.len + 4 >= out.len) return false;
    if (simple) {
        @memcpy(out[len.* .. len.* + arg.len], arg);
        len.* += arg.len;
        return true;
    }
    out[len.*] = '\'';
    len.* += 1;
    for (arg) |ch| {
        if (ch == '\'') {
            if (len.* + 4 >= out.len) return false;
            @memcpy(out[len.* .. len.* + 4], "'\\''");
            len.* += 4;
        } else {
            if (len.* >= out.len) return false;
            out[len.*] = ch;
            len.* += 1;
        }
    }
    out[len.*] = '\'';
    len.* += 1;
    return true;
}

fn processNameIsXwayland(pid: c.pid_t) bool {
    var path_buf: [64:0]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/proc/{d}/comm", .{pid}) catch return false;
    path_buf[path.len] = 0;
    const file = c.fopen(&path_buf, "r") orelse return false;
    defer _ = c.fclose(file);
    var line: [128]u8 = undefined;
    if (c.fgets(&line, @intCast(line.len), file)) |_| {
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&line)));
        if (std.mem.indexOf(u8, name, "xwayland") != null or
            std.mem.indexOf(u8, name, "Xwayland") != null) return true;
    }
    return false;
}

fn commandForClient(client: *Client, buf: []u8) []const u8 {
    if (client.pid <= 0 or processNameIsXwayland(client.pid)) return "";
    var path_buf: [64:0]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/proc/{d}/cmdline", .{client.pid}) catch return "";
    path_buf[path.len] = 0;
    const file = c.fopen(&path_buf, "rb") orelse return "";
    defer _ = c.fclose(file);
    var raw: [4096]u8 = undefined;
    const n = c.fread(&raw, 1, raw.len, file);
    if (n == 0) return "";

    var out_len: usize = 0;
    var start: usize = 0;
    while (start < n) {
        var end = start;
        while (end < n and raw[end] != 0) : (end += 1) {}
        if (end > start) {
            if (out_len > 0) {
                if (out_len >= buf.len) return "";
                buf[out_len] = ' ';
                out_len += 1;
            }
            if (!appendShellArg(buf, &out_len, raw[start..end])) return "";
        }
        start = end + 1;
    }
    return buf[0..out_len];
}

fn rgb3(value: [4]f32) [3]f32 {
    return .{ value[0], value[1], value[2] };
}

fn themeRoleColor(cfg: *const types.Config, name: []const u8) ?[3]f32 {
    var i: usize = 0;
    while (i < cfg.theme_role_count) : (i += 1) {
        const role = &cfg.theme_roles[i];
        if (std.mem.eql(u8, role.name[0..role.name_len], name)) return role.rgb;
    }
    return null;
}

fn configColor(text: []const u8) ?[3]f32 {
    if (!validHexColor(text)) return null;
    var rgb: [3]f32 = .{ 0, 0, 0 };
    core.parseHexColor(text, &rgb);
    return rgb;
}

fn captureTheme(server: *Server, out: *Output, ws: usize) types.SceneTheme {
    const cfg = &server.config;
    const active = if (out.scene_theme_set[ws - 1]) out.scene_theme[ws - 1] else types.SceneTheme{};
    const active_accent: ?[3]f32 = if (out.theme_accent) |color| rgb3(color) else cfg.accent_rgb;
    const active_border: ?[3]f32 = if (cfg.border_active_len > 0) cfg.border_active_rgb else active_accent;
    const active_border_inactive: ?[3]f32 = if (cfg.border_inactive_len > 0) cfg.border_inactive_rgb else null;

    return .{
        .accent = active.accent orelse active_accent,
        .bg = active.bg orelse rgb3(out.theme_bg),
        .border_active = active.border_active orelse
            (if (out.theme_border_active) |color| rgb3(color) else null) orelse
            active_border,
        .border_inactive = active.border_inactive orelse
            (if (out.theme_border_inactive) |color| rgb3(color) else null) orelse
            active_border_inactive,
        .panel_bg = active.panel_bg orelse themeRoleColor(cfg, "panel.background") orelse configColor(cfg.panel_bg[0..cfg.panel_bg_len]),
        .panel_fg = active.panel_fg orelse themeRoleColor(cfg, "panel.foreground") orelse configColor(cfg.panel_fg[0..cfg.panel_fg_len]),
        .bg_top = active.bg_top orelse themeRoleColor(cfg, "wallpaper.top") orelse configColor(cfg.bg_top[0..cfg.bg_top_len]),
        .bg_bottom = active.bg_bottom orelse themeRoleColor(cfg, "wallpaper.bottom") orelse configColor(cfg.bg_bottom[0..cfg.bg_bottom_len]),
    };
}

fn summaryByName(server: *Server, name: []const u8) ?*types.SceneSummary {
    var i: usize = 0;
    while (i < server.scene_summary_count) : (i += 1) {
        const summary = &server.scene_summaries[i];
        if (summary.name_len == name.len and
            std.mem.eql(u8, summary.name[0..summary.name_len], name)) return summary;
    }
    return null;
}

fn captureWallpaper(server: *Server, out: *Output, ws: usize) types.SceneWallpaper {
    const cfg = &server.config;
    var wallpaper = types.SceneWallpaper{};
    if (out.scene_name_len[ws - 1] > 0) {
        if (summaryByName(server, out.scene_name[ws - 1][0..out.scene_name_len[ws - 1]])) |summary| {
            wallpaper = summary.wallpaper;
        }
    }
    if (wallpaper.image_len == 0 and cfg.wallpaper_image_len > 0) {
        core.copyString(&wallpaper.image, &wallpaper.image_len, cfg.wallpaper_image[0..cfg.wallpaper_image_len]);
    }
    if (wallpaper.fit == null) wallpaper.fit = cfg.wallpaper_fit;
    if (wallpaper.art == null) wallpaper.art = cfg.wallpaper_art;
    if (wallpaper.art_opacity == null) wallpaper.art_opacity = cfg.wallpaper_art_opacity;
    return wallpaper;
}

fn tuningFrom(server: *Server, out: *Output, ws: usize) types.SceneTuning {
    const tuning = rules.tuningFor(server, out, ws);
    return .{
        .gaps = tuning.gaps,
        .outer_gaps = tuning.outer_gaps,
        .master_ratio = tuning.master_ratio,
        .master_count = tuning.master_count,
        .mosaic_ratio = tuning.mosaic_ratio,
        .mosaic_min_size = tuning.mosaic_min_size,
        .grid_columns = tuning.grid_columns,
        .column_width = tuning.column_width,
        .center_focused_column = tuning.center_focused_column,
    };
}

pub fn save(server: *Server, name: []const u8, requested_ws: usize) bool {
    if (!validName(name)) {
        core.logInfo("scene: invalid name '{s}'", .{name});
        return false;
    }
    const out = core.focusOutput(server) orelse return false;
    const ws = if (requested_ws >= 1 and requested_ws <= types.WS_COUNT) requested_ws else out.active_ws;
    var scene: Scene = .{};
    core.copyString(&scene.name, &scene.name_len, name);
    scene.workspace = ws;
    scene.layout = out.ws_layouts[ws - 1];
    scene.tuning = tuningFrom(server, out, ws);
    scene.theme = captureTheme(server, out, ws);
    scene.wallpaper = captureWallpaper(server, out, ws);

    var i: usize = 0;
    while (i < server.clients.len and scene.app_count < scene.apps.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (!client.mapped or client.output != out or client.ws != ws) continue;
        if (client.scratchpad or client.special_workspace_len > 0) continue;
        const app = &scene.apps[scene.app_count];
        scene.app_count += 1;
        core.copyString(&app.app_id, &app.app_id_len, client.app_id[0..client.app_id_len]);
        core.copyString(&app.title, &app.title_len, client.title[0..client.title_len]);
        var command_buf: [types.MAX_SCENE_COMMAND]u8 = undefined;
        const command = commandForClient(client, &command_buf);
        core.copyString(&app.command, &app.command_len, command);
        app.floating = client.floating;
        if (client.floating) {
            app.x = client.x;
            app.y = client.y;
            app.w = client.w;
            app.h = client.h;
        }
    }

    if (!writeSceneFile(server, &scene)) return false;
    reload(server);
    core.logInfo("scene: saved '{s}' ws={d} apps={d}", .{ name, ws, scene.app_count });
    return true;
}

fn appMatches(app: *const SceneApp, client: *const Client) bool {
    if (app.app_id_len > 0) {
        return std.mem.eql(u8, app.app_id[0..app.app_id_len], client.app_id[0..client.app_id_len]);
    }
    if (app.title_len > 0) {
        return std.mem.eql(u8, app.title[0..app.title_len], client.title[0..client.title_len]);
    }
    return false;
}

fn existingOnWorkspace(server: *Server, app: *const SceneApp, out: *Output, ws: usize) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < server.clients.len) : (i += 1) {
        const client = server.clients[i] orelse continue;
        if (!client.mapped or client.output != out or client.ws != ws) continue;
        if (appMatches(app, client)) count += 1;
    }
    return count;
}

pub fn apply(server: *Server, name: []const u8, requested_ws: usize, output_name: []const u8, activate: bool) bool {
    var scene: Scene = .{};
    if (!parseNamed(server, name, &scene)) {
        core.logInfo("scene: '{s}' not found", .{name});
        return false;
    }
    const out = if (output_name.len > 0)
        (core.outputByName(server, output_name) orelse return false)
    else
        (core.focusOutput(server) orelse return false);
    const ws = if (requested_ws >= 1 and requested_ws <= types.WS_COUNT)
        requested_ws
    else if (activate and scene.workspace >= 1 and scene.workspace <= types.WS_COUNT)
        scene.workspace
    else
        out.active_ws;

    out.scene_tuning[ws - 1] = scene.tuning;
    out.scene_tuning_set[ws - 1] = true;
    out.scene_theme[ws - 1] = scene.theme;
    out.scene_theme_set[ws - 1] = true;
    core.copyString(&out.scene_name[ws - 1], &out.scene_name_len[ws - 1], scene.name[0..scene.name_len]);

    if (out.active_ws != ws) layout.switchWorkspaceOnOutput(server, out, ws);
    layout.applySceneLayout(server, out, ws, scene.layout);
    core.updateBackground(out);

    server.scene_restore = .{};
    core.copyString(&server.scene_restore.name, &server.scene_restore.name_len, scene.name[0..scene.name_len]);
    core.copyString(&server.scene_restore.output_name, &server.scene_restore.output_len, core.outputName(out));
    server.scene_restore.workspace = ws;
    server.scene_restore.deadline_ms = core.timeNowMs() + RESTORE_TIMEOUT_MS;

    var launch_count: usize = 0;
    var i: usize = 0;
    while (i < scene.app_count) : (i += 1) {
        const app = &scene.apps[i];
        if (existingOnWorkspace(server, app, out, ws) > 0) continue;
        if (app.command_len == 0) continue;
        if (server.scene_restore.app_count >= server.scene_restore.apps.len) break;
        const target = &server.scene_restore.apps[server.scene_restore.app_count];
        server.scene_restore.app_count += 1;
        target.* = .{};
        core.copyString(&target.app_id, &target.app_id_len, app.app_id[0..app.app_id_len]);
        core.copyString(&target.title, &target.title_len, app.title[0..app.title_len]);
        target.floating = app.floating;
        target.x = app.x;
        target.y = app.y;
        target.w = app.w;
        target.h = app.h;
        launch_count += 1;
    }
    server.scene_restore.active = launch_count > 0;

    i = 0;
    while (i < scene.app_count) : (i += 1) {
        const app = &scene.apps[i];
        if (existingOnWorkspace(server, app, out, ws) > 0) continue;
        if (app.command_len == 0) continue;
        core.logInfo("scene: launch {s}", .{app.command[0..app.command_len]});
        core.spawn(app.command[0..app.command_len]);
    }

    events.emit(server, .{
        .name = event_names.scene_change,
        .workspace = ws,
        .output = core.outputName(out),
        .arg = scene.name[0..scene.name_len],
    });
    core.markDirty(server);
    core.logInfo("scene: apply '{s}' ws={d} launch={d}", .{ name, ws, launch_count });
    return true;
}

pub fn clear(server: *Server) bool {
    const out = core.focusOutput(server) orelse return false;
    const ws = out.active_ws;
    out.scene_tuning_set[ws - 1] = false;
    out.scene_tuning[ws - 1] = .{};
    out.scene_theme_set[ws - 1] = false;
    out.scene_theme[ws - 1] = .{};
    out.scene_name_len[ws - 1] = 0;
    core.updateBackground(out);
    layout.arrangeOutput(server, out);
    core.markDirty(server);
    core.logInfo("scene: cleared ws={d} on {s}", .{ ws, core.outputName(out) });
    return true;
}

pub fn delete(server: *Server, name: []const u8) bool {
    var path_buf: [512]u8 = undefined;
    const path = scenePath(server, name, &path_buf);
    if (path.len == 0) return false;
    var zpath: [512:0]u8 = undefined;
    if (!copyZ(&zpath, path)) return false;
    if (c.unlink(&zpath) != 0) return false;
    reload(server);
    core.logInfo("scene: deleted '{s}'", .{name});
    return true;
}

fn nameFromFile(file_name: []const u8) []const u8 {
    if (!std.mem.endsWith(u8, file_name, ".scene")) return "";
    return file_name[0 .. file_name.len - ".scene".len];
}

fn summaryLess(a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

pub fn reload(server: *Server) void {
    server.scene_summary_count = 0;
    const dir = openDir(server) orelse {
        core.logInfo("scene: no scene directory", .{});
        return;
    };
    defer _ = c.closedir(dir);

    while (c.readdir(dir)) |entry| {
        const file_name = std.mem.span(@as([*:0]const u8, @ptrCast(&entry.*.d_name)));
        const name = nameFromFile(file_name);
        if (!validName(name)) continue;
        if (server.scene_summary_count >= server.scene_summaries.len) break;
        var path_buf: [512]u8 = undefined;
        const path = scenePath(server, name, &path_buf);
        if (path.len == 0) continue;
        var scene: Scene = .{};
        if (!parseFile(path, &scene)) continue;
        var summary = &server.scene_summaries[server.scene_summary_count];
        summary.* = .{};
        core.copyString(&summary.name, &summary.name_len, name);
        summary.workspace = scene.workspace;
        summary.layout = scene.layout;
        summary.app_count = scene.app_count;
        summary.theme = scene.theme;
        summary.wallpaper = scene.wallpaper;
        server.scene_summary_count += 1;

        var i = server.scene_summary_count - 1;
        while (i > 0 and summaryLess(server.scene_summaries[i].name[0..server.scene_summaries[i].name_len], server.scene_summaries[i - 1].name[0..server.scene_summaries[i - 1].name_len])) : (i -= 1) {
            const tmp = server.scene_summaries[i - 1];
            server.scene_summaries[i - 1] = server.scene_summaries[i];
            server.scene_summaries[i] = tmp;
        }
    }
    core.logInfo("scene: loaded {d} scene(s)", .{server.scene_summary_count});
}

fn sceneIsActive(server: *Server, name: []const u8) bool {
    var i: usize = 0;
    while (i < server.outputs.len) : (i += 1) {
        const out = server.outputs[i] orelse continue;
        const ws = out.active_ws;
        if (out.scene_name_len[ws - 1] == name.len and
            std.mem.eql(u8, out.scene_name[ws - 1][0..out.scene_name_len[ws - 1]], name))
        {
            return true;
        }
    }
    return false;
}

pub fn appendState(server: *Server, buf: []u8, off: *usize) void {
    var si: usize = 0;
    while (si < server.scene_summary_count) : (si += 1) {
        const summary = &server.scene_summaries[si];
        const name = summary.name[0..summary.name_len];
        var live: usize = 0;
        var preview_count: usize = 0;
        var preview_ids: [types.MAX_SCENE_PREVIEWS]u64 = @splat(0);

        var path_buf: [512]u8 = undefined;
        const path = scenePath(server, name, &path_buf);
        var scene: Scene = .{};
        const parsed = path.len > 0 and parseFile(path, &scene);
        if (parsed) {
            var ci: usize = 0;
            while (ci < server.clients.len) : (ci += 1) {
                const client = server.clients[ci] orelse continue;
                if (!client.mapped) continue;
                var ai: usize = 0;
                while (ai < scene.app_count) : (ai += 1) {
                    if (appMatches(&scene.apps[ai], client)) {
                        live += 1;
                        if (preview_count < preview_ids.len) {
                            preview_ids[preview_count] = client.id;
                            preview_count += 1;
                        }
                        break;
                    }
                }
            }
        }

        const active = sceneIsActive(server, name);
        const line = std.fmt.bufPrint(buf[off.*..], "SCENE\t{s}\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\n", .{
            name,
            types.layoutName(summary.layout),
            summary.app_count,
            live,
            summary.workspace,
            @as(u8, if (active) 1 else 0),
            preview_ids[0],
            preview_ids[1],
            preview_ids[2],
            preview_ids[3],
        }) catch return;
        off.* += line.len;
    }
}

fn hexOrDash(buf: *[7]u8, value: ?[3]f32) []const u8 {
    if (value) |rgb| return hexColor(buf, rgb);
    return "-";
}

pub fn appendActiveStyle(server: *Server, buf: []u8, off: *usize) void {
    var oi: usize = 0;
    while (oi < server.outputs.len) : (oi += 1) {
        const out = server.outputs[oi] orelse continue;
        const ws = out.active_ws;
        const name = if (out.scene_name_len[ws - 1] > 0)
            out.scene_name[ws - 1][0..out.scene_name_len[ws - 1]]
        else
            "-";
        var accent_buf: [7]u8 = undefined;
        var bg_buf: [7]u8 = undefined;
        var top_buf: [7]u8 = undefined;
        var bottom_buf: [7]u8 = undefined;
        var panel_bg_buf: [7]u8 = undefined;
        var panel_fg_buf: [7]u8 = undefined;
        var border_active_buf: [7]u8 = undefined;
        var border_inactive_buf: [7]u8 = undefined;
        var image_buf: [512]u8 = undefined;
        var art_buf: [2]u8 = undefined;
        var opacity_buf: [16]u8 = undefined;
        var fit: []const u8 = "-";
        var image: []const u8 = "-";
        var art: []const u8 = "-";
        var opacity: []const u8 = "-";
        var accent: []const u8 = "-";
        var bg: []const u8 = "-";
        var bg_top: []const u8 = "-";
        var bg_bottom: []const u8 = "-";
        var panel_bg: []const u8 = "-";
        var panel_fg: []const u8 = "-";
        var border_active: []const u8 = "-";
        var border_inactive: []const u8 = "-";

        if (out.scene_name_len[ws - 1] > 0) {
            if (summaryByName(server, name)) |summary| {
                accent = hexOrDash(&accent_buf, summary.theme.accent);
                bg = hexOrDash(&bg_buf, summary.theme.bg);
                bg_top = hexOrDash(&top_buf, summary.theme.bg_top);
                bg_bottom = hexOrDash(&bottom_buf, summary.theme.bg_bottom);
                panel_bg = hexOrDash(&panel_bg_buf, summary.theme.panel_bg);
                panel_fg = hexOrDash(&panel_fg_buf, summary.theme.panel_fg);
                border_active = hexOrDash(&border_active_buf, summary.theme.border_active);
                border_inactive = hexOrDash(&border_inactive_buf, summary.theme.border_inactive);
                if (summary.wallpaper.image_len > 0) {
                    @memcpy(image_buf[0..summary.wallpaper.image_len], summary.wallpaper.image[0..summary.wallpaper.image_len]);
                    image = image_buf[0..summary.wallpaper.image_len];
                }
                if (summary.wallpaper.fit) |value| fit = @tagName(value);
                if (summary.wallpaper.art) |value| {
                    art_buf[0] = if (value) '1' else '0';
                    art = art_buf[0..1];
                }
                if (summary.wallpaper.art_opacity) |value| {
                    const text = std.fmt.bufPrint(&opacity_buf, "{d:.3}", .{value}) catch "";
                    if (text.len > 0) opacity = text;
                }
            }
        }

        const line = std.fmt.bufPrint(
            buf[off.*..],
            "SCENE_STYLE\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\n",
            .{ core.outputName(out), name, accent, bg, bg_top, bg_bottom, panel_bg, panel_fg, border_active, border_inactive, image, fit, art, opacity },
        ) catch return;
        off.* += line.len;
    }
}

pub fn buildList(server: *Server, buf: []u8) []const u8 {
    var off: usize = 0;
    const header = "SCENE_LIST\n";
    if (buf.len < header.len) return "";
    @memcpy(buf[0..header.len], header);
    off = header.len;

    var i: usize = 0;
    while (i < server.scene_summary_count) : (i += 1) {
        const summary = &server.scene_summaries[i];
        const line = std.fmt.bufPrint(buf[off..], "{s}\t{d}\t{s}\t{d}\n", .{
            summary.name[0..summary.name_len],
            summary.workspace,
            types.layoutName(summary.layout),
            summary.app_count,
        }) catch break;
        off += line.len;
    }
    if (off + 4 > buf.len) return buf[0..off];
    @memcpy(buf[off .. off + 4], "END\n");
    off += 4;
    return buf[0..off];
}

pub fn onClientMap(server: *Server, client: *Client) void {
    const restore = &server.scene_restore;
    if (!restore.active) return;
    if (core.timeNowMs() > restore.deadline_ms) {
        restore.active = false;
        return;
    }
    const target_out = core.outputByName(server, restore.output_name[0..restore.output_len]) orelse {
        restore.active = false;
        return;
    };
    if (client.output != target_out) return;

    var i: usize = 0;
    while (i < restore.app_count) : (i += 1) {
        const app = &restore.apps[i];
        if (app.matched) continue;
        var matches = false;
        if (app.app_id_len > 0) {
            matches = std.mem.eql(u8, app.app_id[0..app.app_id_len], client.app_id[0..client.app_id_len]);
        } else if (app.title_len > 0) {
            matches = std.mem.eql(u8, app.title[0..app.title_len], client.title[0..client.title_len]);
        }
        if (!matches) continue;

        app.matched = true;
        client.ws = restore.workspace;
        client.scratchpad = false;
        client.special_workspace_len = 0;
        if (app.floating) {
            client.floating = true;
            client.x = app.x;
            client.y = app.y;
            client.w = app.w;
            client.h = app.h;
            client.float_x = app.x;
            client.float_y = app.y;
            client.float_w = app.w;
            client.float_h = app.h;
        }
        core.logInfo("scene: restored '{s}' app={s} ws={d}", .{
            restore.name[0..restore.name_len],
            client.app_id[0..client.app_id_len],
            restore.workspace,
        });

        var all = true;
        var j: usize = 0;
        while (j < restore.app_count) : (j += 1) {
            if (!restore.apps[j].matched) {
                all = false;
                break;
            }
        }
        if (all) restore.active = false;
        return;
    }
}
