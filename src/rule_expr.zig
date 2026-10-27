const std = @import("std");
const c = @import("c.zig").c;

pub const Context = struct {
    app_id: []const u8,
    title: []const u8,
    output: []const u8,
    event: []const u8 = "",
    workspace: []const u8 = "",
    window_id: []const u8 = "",
};

const EvalError = error{ Syntax, InvalidRegex, TooLong };
const Parser = struct {
    text: []const u8,
    pos: usize,
    ctx: Context,
    regex_error: bool = false,

    fn skipSpace(self: *Parser) void {
        while (self.pos < self.text.len and
            (self.text[self.pos] == ' ' or self.text[self.pos] == '\t')) self.pos += 1;
    }

    fn startsWord(self: *Parser, word: []const u8) bool {
        if (!std.mem.startsWith(u8, self.text[self.pos..], word)) return false;
        const end = self.pos + word.len;
        return end >= self.text.len or
            !std.ascii.isAlphanumeric(self.text[end]);
    }

    fn consumeWord(self: *Parser, word: []const u8) bool {
        if (!self.startsWord(word)) return false;
        self.pos += word.len;
        return true;
    }

    fn parseOr(self: *Parser) EvalError!bool {
        var value = try self.parseAnd();
        while (true) {
            self.skipSpace();
            if (self.pos < self.text.len and self.text[self.pos] == '|' and
                self.pos + 1 < self.text.len and self.text[self.pos + 1] == '|')
            {
                self.pos += 2;
            } else if (!self.consumeWord("or")) {
                return value;
            }
            const rhs = try self.parseAnd();
            value = value or rhs;
        }
    }

    fn parseAnd(self: *Parser) EvalError!bool {
        var value = try self.parseUnary();
        while (true) {
            self.skipSpace();
            if (self.pos < self.text.len and self.text[self.pos] == '&' and
                self.pos + 1 < self.text.len and self.text[self.pos + 1] == '&')
            {
                self.pos += 2;
            } else if (!self.consumeWord("and")) {
                return value;
            }
            const rhs = try self.parseUnary();
            value = value and rhs;
        }
    }

    fn parseUnary(self: *Parser) EvalError!bool {
        self.skipSpace();
        if (self.pos < self.text.len and self.text[self.pos] == '!') {
            if (self.pos + 1 < self.text.len and self.text[self.pos + 1] == '~') {
                return error.Syntax;
            }
            self.pos += 1;
            return !try self.parseUnary();
        }
        if (self.consumeWord("not")) return !try self.parseUnary();
        if (self.pos < self.text.len and self.text[self.pos] == '(') {
            self.pos += 1;
            const value = try self.parseOr();
            self.skipSpace();
            if (self.pos >= self.text.len or self.text[self.pos] != ')') return error.Syntax;
            self.pos += 1;
            return value;
        }
        return self.parseComparison();
    }

    fn parseField(self: *Parser) EvalError![]const u8 {
        self.skipSpace();
        const start = self.pos;
        while (self.pos < self.text.len) {
            const ch = self.text[self.pos];
            if (!std.ascii.isAlphanumeric(ch) and ch != '-' and ch != '_') break;
            self.pos += 1;
        }
        if (self.pos == start) return error.Syntax;
        const field = self.text[start..self.pos];
        if (std.mem.eql(u8, field, "app") or
            std.mem.eql(u8, field, "app-id") or
            std.mem.eql(u8, field, "app_id") or
            std.mem.eql(u8, field, "class")) return self.ctx.app_id;
        if (std.mem.eql(u8, field, "title")) return self.ctx.title;
        if (std.mem.eql(u8, field, "output") or
            std.mem.eql(u8, field, "monitor")) return self.ctx.output;
        if (std.mem.eql(u8, field, "event")) return self.ctx.event;
        if (std.mem.eql(u8, field, "ws") or
            std.mem.eql(u8, field, "workspace")) return self.ctx.workspace;
        if (std.mem.eql(u8, field, "id") or
            std.mem.eql(u8, field, "window")) return self.ctx.window_id;
        return error.Syntax;
    }

    fn parseValue(self: *Parser) EvalError![]const u8 {
        self.skipSpace();
        if (self.pos >= self.text.len) return error.Syntax;
        if (self.text[self.pos] == '"' or self.text[self.pos] == '\'') {
            const quote = self.text[self.pos];
            self.pos += 1;
            const start = self.pos;
            while (self.pos < self.text.len and self.text[self.pos] != quote) {
                if (self.text[self.pos] == '\\' and self.pos + 1 < self.text.len) self.pos += 1;
                self.pos += 1;
            }
            if (self.pos >= self.text.len) return error.Syntax;
            const value = self.text[start..self.pos];
            self.pos += 1;
            return value;
        }
        const start = self.pos;
        while (self.pos < self.text.len) {
            const ch = self.text[self.pos];
            if (ch == ' ' or ch == '\t' or ch == ')' or ch == '&' or ch == '|') break;
            self.pos += 1;
        }
        if (self.pos == start) return error.Syntax;
        return self.text[start..self.pos];
    }

    fn regexMatches(self: *Parser, pattern: []const u8, value: []const u8) bool {
        if (pattern.len >= 255) {
            self.regex_error = true;
            return false;
        }
        var pattern_buf: [256:0]u8 = undefined;
        @memcpy(pattern_buf[0..pattern.len], pattern);
        pattern_buf[pattern.len] = 0;
        const regex = c.tessa_regex_create() orelse {
            self.regex_error = true;
            return false;
        };
        defer c.tessa_regex_destroy(regex);
        if (c.tessa_regex_compile(regex, &pattern_buf) != 0) {
            self.regex_error = true;
            return false;
        }
        if (value.len >= 4096) return false;
        var value_buf: [4097:0]u8 = undefined;
        @memcpy(value_buf[0..value.len], value);
        value_buf[value.len] = 0;
        return c.tessa_regex_match(regex, &value_buf) != 0;
    }

    fn parseComparison(self: *Parser) EvalError!bool {
        const value = try self.parseField();
        self.skipSpace();
        var op: u8 = 0;
        if (self.pos + 1 < self.text.len) {
            const two = self.text[self.pos .. self.pos + 2];
            if (std.mem.eql(u8, two, "==")) {
                op = '=';
                self.pos += 2;
            } else if (std.mem.eql(u8, two, "!=")) {
                op = '!';
                self.pos += 2;
            } else if (std.mem.eql(u8, two, "!~")) {
                op = 'n';
                self.pos += 2;
            }
        }
        if (op == 0 and self.pos < self.text.len and self.text[self.pos] == '~') {
            op = '~';
            self.pos += 1;
        }
        if (op == 0) return error.Syntax;
        const expected = try self.parseValue();
        return switch (op) {
            '=' => std.mem.eql(u8, value, expected),
            '!' => !std.mem.eql(u8, value, expected),
            '~' => self.regexMatches(expected, value),
            'n' => !self.regexMatches(expected, value),
            else => error.Syntax,
        };
    }
};

pub fn evaluate(expr: []const u8, ctx: Context) ?bool {
    var parser = Parser{ .text = expr, .pos = 0, .ctx = ctx };
    const value = parser.parseOr() catch return null;
    parser.skipSpace();
    if (parser.regex_error or parser.pos != expr.len) return null;
    return value;
}

pub fn validate(expr: []const u8) bool {
    return evaluate(expr, .{ .app_id = "", .title = "", .output = "" }) != null;
}
