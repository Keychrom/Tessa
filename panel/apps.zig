const std = @import("std");
const c = @import("c.zig").c;

pub const MAX_APPS = 256;

pub const App = struct {
    id: [128]u8 = [_]u8{0} ** 128,
    id_len: usize = 0,
    name: [160]u8 = [_]u8{0} ** 160,
    name_len: usize = 0,
    comment: [192]u8 = [_]u8{0} ** 192,
    comment_len: usize = 0,
    exec: [512]u8 = [_]u8{0} ** 512,
    exec_len: usize = 0,
    terminal: bool = false,
};

pub const AppList = struct {
    apps: [MAX_APPS]App = undefined,
    count: usize = 0,
};

fn copyTrunc(dest: []u8, len: *usize, src: []const u8) void {
    var n = @min(src.len, dest.len - 1);
    if (n < src.len) {
        while (n > 0 and (src[n] & 0xC0) == 0x80) n -= 1;
    }
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
    len.* = n;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn unescape(dest: []u8, src: []const u8) []const u8 {
    var j: usize = 0;
    var i: usize = 0;
    while (i < src.len and j + 1 < dest.len) {
        if (src[i] == '\\' and i + 1 < src.len) {
            i += 1;
            switch (src[i]) {
                'n' => dest[j] = '\n',
                't' => dest[j] = '\t',
                'r' => dest[j] = '\r',
                's' => dest[j] = ' ',
                '\\' => dest[j] = '\\',
                else => dest[j] = src[i],
            }
            i += 1;
        } else {
            dest[j] = src[i];
            i += 1;
        }
        j += 1;
    }
    return dest[0..j];
}

fn cleanFieldCodes(dest: []u8, src: []const u8) []const u8 {
    var j: usize = 0;
    var i: usize = 0;
    while (i < src.len and j + 1 < dest.len) {
        if (src[i] == '%' and i + 1 < src.len) {
            const code = src[i + 1];
            if (code == '%') {
                dest[j] = '%';
                j += 1;
                i += 2;
                continue;
            }
            if (std.ascii.isAlphabetic(code)) {
                i += 2;
                continue;
            }
        }
        dest[j] = src[i];
        j += 1;
        i += 1;
    }
    return trim(dest[0..j]);
}

fn pathJoin(dest: []u8, a: []const u8, b: []const u8) []u8 {
    return std.fmt.bufPrint(dest, "{s}/{s}", .{ a, b }) catch dest[0..0];
}

fn hasId(list: *AppList, id: []const u8) bool {
    var i: usize = 0;
    while (i < list.count) : (i += 1) {
        if (std.mem.eql(u8, list.apps[i].id[0..list.apps[i].id_len], id)) return true;
    }
    return false;
}

fn scanFile(list: *AppList, dir_path: []const u8, filename: []const u8) void {
    var id_buf: [128]u8 = undefined;
    const id_len = filename.len - ".desktop".len;
    if (id_len == 0 or id_len >= id_buf.len) return;
    @memcpy(id_buf[0..id_len], filename[0..id_len]);
    if (hasId(list, id_buf[0..id_len])) return;

    var path_buf: [1024]u8 = undefined;
    const path = pathJoin(&path_buf, dir_path, filename);
    if (path.len == 0) return;
    var zpath: [1024:0]u8 = undefined;
    const n = @min(path.len, zpath.len - 1);
    @memcpy(zpath[0..n], path[0..n]);
    zpath[n] = 0;

    const file = c.fopen(&zpath, "r") orelse return;
    defer _ = c.fclose(file);

    var app: App = .{};
    var name_ja: [160]u8 = [_]u8{0} ** 160;
    var name_ja_len: usize = 0;
    var comment_ja: [192]u8 = [_]u8{0} ** 192;
    var comment_ja_len: usize = 0;
    var type_ok = true;
    var hidden = false;

    var line: [2048]u8 = undefined;
    var in_desktop = false;

    while (c.fgets(&line, @intCast(line.len), file)) |_| {
        const raw = std.mem.span(@as([*:0]const u8, @ptrCast(&line)));
        const t = trim(raw);
        if (t.len == 0 or t[0] == '#') continue;
        if (t[0] == '[') {
            in_desktop = std.mem.eql(u8, t, "[Desktop Entry]");
            continue;
        }
        if (!in_desktop) continue;

        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = trim(t[0..eq]);
        const val_raw = trim(t[eq + 1 ..]);
        var vbuf: [1024]u8 = undefined;
        const val = unescape(&vbuf, val_raw);

        if (std.mem.eql(u8, key, "Name")) {
            copyTrunc(&app.name, &app.name_len, val);
        } else if (std.mem.eql(u8, key, "Name[ja]")) {
            copyTrunc(&name_ja, &name_ja_len, val);
        } else if (std.mem.eql(u8, key, "Comment")) {
            copyTrunc(&app.comment, &app.comment_len, val);
        } else if (std.mem.eql(u8, key, "Comment[ja]")) {
            copyTrunc(&comment_ja, &comment_ja_len, val);
        } else if (std.mem.eql(u8, key, "Exec")) {
            var cbuf: [1024]u8 = undefined;
            const exec = cleanFieldCodes(&cbuf, val);
            copyTrunc(&app.exec, &app.exec_len, exec);
        } else if (std.mem.eql(u8, key, "Terminal")) {
            app.terminal = eqlIgnoreCase(val, "true");
        } else if (std.mem.eql(u8, key, "NoDisplay") or std.mem.eql(u8, key, "Hidden")) {
            if (eqlIgnoreCase(val, "true")) hidden = true;
        } else if (std.mem.eql(u8, key, "Type")) {
            type_ok = eqlIgnoreCase(val, "Application");
        }
    }

    if (!type_ok or hidden or app.exec_len == 0) return;
    if (name_ja_len > 0) {
        @memcpy(app.name[0 .. name_ja_len + 1], name_ja[0 .. name_ja_len + 1]);
        app.name_len = name_ja_len;
    }
    if (comment_ja_len > 0) {
        @memcpy(app.comment[0 .. comment_ja_len + 1], comment_ja[0 .. comment_ja_len + 1]);
        app.comment_len = comment_ja_len;
    }
    if (app.name_len == 0) {
        copyTrunc(&app.name, &app.name_len, id_buf[0..id_len]);
    }

    @memcpy(app.id[0..id_len], id_buf[0..id_len]);
    app.id[id_len] = 0;
    app.id_len = id_len;

    if (list.count < list.apps.len) {
        list.apps[list.count] = app;
        list.count += 1;
    }
}

fn scanDir(list: *AppList, dir_path: []const u8) void {
    var zpath: [1024:0]u8 = undefined;
    const n = @min(dir_path.len, zpath.len - 1);
    @memcpy(zpath[0..n], dir_path[0..n]);
    zpath[n] = 0;

    const dir = c.opendir(&zpath) orelse return;
    defer _ = c.closedir(dir);

    while (c.readdir(dir)) |ent| {
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&ent.*.d_name)));
        if (!std.mem.endsWith(u8, name, ".desktop")) continue;
        scanFile(list, dir_path, name);
        if (list.count >= list.apps.len) return;
    }
}

pub fn scan(list: *AppList) void {
    list.count = 0;

    var path_buf: [1024]u8 = undefined;
    if (c.getenv("HOME")) |home| {
        const home_s = std.mem.span(home);
        const p = std.fmt.bufPrint(&path_buf, "{s}/.local/share/applications", .{home_s}) catch "";
        if (p.len > 0) scanDir(list, p);
    }

    if (c.getenv("XDG_DATA_DIRS")) |dirs| {
        var it = std.mem.splitScalar(u8, std.mem.span(dirs), ':');
        while (it.next()) |base| {
            if (base.len == 0) continue;
            const p = std.fmt.bufPrint(&path_buf, "{s}/applications", .{base}) catch continue;
            scanDir(list, p);
        }
    } else {
        scanDir(list, "/usr/local/share/applications");
        scanDir(list, "/usr/share/applications");
    }
}

fn isPinned(app: *const App) bool {
    const pinned = [_][]const u8{
        "kitty",       "foot",                 "firefox",        "chromium", "code",
        "nautilus",    "thunar",               "gimp",           "mpv",      "libreoffice",
        "spotify",     "discord",              "telegram",       "signal",   "steam",
        "pavucontrol", "gnome-control-center", "xfce4-settings", "kitty",
    };
    const id = app.id[0..app.id_len];
    const name = app.name[0..app.name_len];
    for (pinned) |p| {
        if (std.ascii.indexOfIgnoreCase(id, p) != null) return true;
        if (std.ascii.indexOfIgnoreCase(name, p) != null) return true;
    }
    return false;
}

fn toLower(dest: []u8, src: []const u8) []const u8 {
    const n = @min(dest.len, src.len);
    for (src[0..n], 0..) |ch, i| {
        dest[i] = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
    }
    return dest[0..n];
}

fn isWordStart(s: []const u8, pos: usize) bool {
    if (pos == 0) return true;
    const ch = s[pos - 1];
    return ch == ' ' or ch == '-' or ch == '.' or ch == '_' or ch == '(' or ch == '/';
}

fn subseq(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    var j: usize = 0;
    for (hay) |ch| {
        if (ch == needle[j]) {
            j += 1;
            if (j == needle.len) return true;
        }
    }
    return false;
}

fn scoreApp(app: *const App, query: []const u8) i32 {
    if (query.len == 0) return if (isPinned(app)) 2000 else 0;

    var name_buf: [160]u8 = undefined;
    var id_buf: [128]u8 = undefined;
    var comment_buf: [192]u8 = undefined;
    const name = toLower(&name_buf, app.name[0..app.name_len]);
    const id = toLower(&id_buf, app.id[0..app.id_len]);
    const comment = toLower(&comment_buf, app.comment[0..app.comment_len]);

    var score: i32 = -1;
    if (std.mem.startsWith(u8, name, query)) {
        score = 3000 - @as(i32, @intCast(name.len));
    } else if (std.mem.startsWith(u8, id, query)) {
        score = 2400 - @as(i32, @intCast(id.len));
    } else if (std.mem.indexOf(u8, name, query)) |pos| {
        score = if (isWordStart(name, pos)) 1900 else 1500;
        score -= @intCast(pos);
    } else if (std.mem.indexOf(u8, id, query)) |pos| {
        score = 1000 - @as(i32, @intCast(pos));
    } else if (std.mem.indexOf(u8, comment, query) != null) {
        score = 500;
    } else if (subseq(name, query)) {
        score = 250;
    }

    if (score >= 0 and isPinned(app)) score += 120;
    return score;
}

const Match = struct {
    index: usize,
    score: i32,
};

fn nameLess(list: *const AppList, a: usize, b: usize) bool {
    const an = list.apps[a].name[0..list.apps[a].name_len];
    const bn = list.apps[b].name[0..list.apps[b].name_len];
    return std.ascii.lessThanIgnoreCase(an, bn);
}

pub fn filter(list: *const AppList, query_in: []const u8, out: []usize) usize {
    var qbuf: [128]u8 = undefined;
    const q = toLower(&qbuf, trim(query_in));

    var matches: [MAX_APPS]Match = undefined;
    var mcount: usize = 0;

    var i: usize = 0;
    while (i < list.count) : (i += 1) {
        const score = scoreApp(&list.apps[i], q);
        if (score < 0) continue;
        matches[mcount] = .{ .index = i, .score = score };
        mcount += 1;
    }

    // insertion sort: score desc, then name asc
    var k: usize = 1;
    while (k < mcount) : (k += 1) {
        const item = matches[k];
        var j = k;
        while (j > 0) {
            const prev = matches[j - 1];
            const swap = prev.score < item.score or
                (prev.score == item.score and nameLess(list, item.index, prev.index));
            if (!swap) break;
            matches[j] = prev;
            j -= 1;
        }
        matches[j] = item;
    }

    const n = @min(out.len, mcount);
    var m: usize = 0;
    while (m < n) : (m += 1) out[m] = matches[m].index;
    return n;
}

pub fn addEntry(list: *AppList, name: []const u8, command: []const u8, comment: []const u8) void {
    if (list.count >= list.apps.len or name.len == 0 or command.len == 0) return;
    var app = App{};
    var id_buf: [32]u8 = undefined;
    const id = std.fmt.bufPrint(&id_buf, "custom-{d}", .{list.count}) catch return;
    copyTrunc(&app.id, &app.id_len, id);
    copyTrunc(&app.name, &app.name_len, name);
    copyTrunc(&app.comment, &app.comment_len, comment);
    copyTrunc(&app.exec, &app.exec_len, command);
    app.terminal = false;
    list.apps[list.count] = app;
    list.count += 1;
}

pub fn buildCommand(list: *const AppList, index: usize, terminal: []const u8, out: []u8) []const u8 {
    const app = &list.apps[index];
    var cbuf: [1024]u8 = undefined;
    const exec = cleanFieldCodes(&cbuf, app.exec[0..app.exec_len]);

    if (!app.terminal or terminal.len == 0) {
        const n = @min(out.len - 1, exec.len);
        @memcpy(out[0..n], exec[0..n]);
        out[n] = 0;
        return out[0..n];
    }

    var quoted: [1024]u8 = undefined;
    var qi: usize = 0;
    quoted[qi] = '\'';
    qi += 1;
    for (exec) |ch| {
        if (qi + 5 >= quoted.len) break;
        if (ch == '\'') {
            @memcpy(quoted[qi .. qi + 4], "'\\''");
            qi += 4;
        } else {
            quoted[qi] = ch;
            qi += 1;
        }
    }
    quoted[qi] = '\'';
    qi += 1;

    const s = std.fmt.bufPrint(out, "{s} sh -c {s}", .{ terminal, quoted[0..qi] }) catch return "";
    return s;
}
