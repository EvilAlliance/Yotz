const std = @import("std");
const util = @import("./../Util.zig");

const Logger = @import("../Logger.zig");

const Arguments = @import("./../ParseArgs.zig").Arguments;

pub const Location = @import("./Location.zig");
pub const Token = @import("./Token.zig");
pub const TokenType = Token.TokenType;

const Allocator = std.mem.Allocator;
const print = std.debug.print;
const assert = std.debug.assert;

path: []const u8,
absPath: []const u8,
content: [:0]const u8,
index: usize = 0,
loc: Location,
peeked: ?Token = null,
finished: bool = false,

const Status = enum {
    start,
    identifier,
    numberLiteral,
    slash,
    ignoreEndLine,
};

fn advanceIndex(self: *@This()) void {
    if (self.content.len == 0 or self.index >= self.content.len) unreachable;

    self.index += 1;
    self.loc.col += 1;
}

fn advance(self: *@This()) Token {
    if (self.finished) @panic("This function shouldnt be called if this has finished lexing");
    var t = Token.init(undefined, self.loc.shallowCopy(self.index, undefined));

    state: switch (Status.start) {
        .start => switch (self.content[self.index]) {
            0 => {
                t.tag = .EOF;
                self.finished = true;
            },
            '\n' => {
                self.advanceIndex();
                self.loc.col = 1;
                self.loc.row += 1;

                t.loc.start = self.index;
                t.loc.col = self.loc.col;
                t.loc.row = self.loc.row;
                continue :state .start;
            },
            '\t', '\r', ' ' => {
                self.advanceIndex();

                t.loc.start = self.index;
                t.loc.col = self.loc.col;
                t.loc.row = self.loc.row;
                continue :state .start;
            },

            'a'...'z', 'A'...'Z', '_' => {
                t.tag = .iden;
                continue :state .identifier;
            },
            '(' => {
                self.advanceIndex();
                t.tag = .openParen;
            },
            ')' => {
                self.advanceIndex();
                t.tag = .closeParen;
            },
            '{' => {
                self.advanceIndex();
                t.tag = .openBrace;
            },
            '}' => {
                self.advanceIndex();
                t.tag = .closeBrace;
            },
            '0'...'9' => {
                t.tag = .numberLiteral;
                continue :state .numberLiteral;
            },
            ':' => {
                self.advanceIndex();
                t.tag = .colon;
            },
            ';' => {
                self.advanceIndex();
                t.tag = .semicolon;
            },
            '+' => {
                self.advanceIndex();
                t.tag = .plus;
            },
            '-' => {
                self.advanceIndex();
                t.tag = .minus;
            },
            '*' => {
                self.advanceIndex();
                t.tag = .asterik;
            },
            '/' => {
                self.advanceIndex();
                t.tag = .slash;
                continue :state .slash;
            },
            '^' => {
                self.advanceIndex();
                t.tag = .caret;
            },
            '=' => {
                self.advanceIndex();
                t.tag = .equal;
            },
            else => {
                Logger.log.info("Found {s}", .{self.content[self.index .. self.index + 1]});
                unreachable;
            },
        },
        .identifier => {
            self.advanceIndex();
            switch (self.content[self.index]) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                else => {
                    if (Token.getKeyWord(self.content[t.loc.start..self.index])) |tag| {
                        t.tag = tag;
                    }
                },
            }
        },
        .numberLiteral => {
            self.advanceIndex();
            switch (self.content[self.index]) {
                '0'...'9' => continue :state .numberLiteral,
                else => {},
            }
        },
        .slash => {
            switch (self.content[self.index]) {
                '/' => continue :state .ignoreEndLine,
                else => {},
            }
        },
        .ignoreEndLine => {
            switch (self.content[self.index]) {
                '\n' => {
                    self.advanceIndex();

                    self.loc.col = 1;
                    self.loc.row += 1;

                    t.loc.start = self.index;

                    continue :state .start;
                },
                else => {
                    self.advanceIndex();
                    continue :state .ignoreEndLine;
                },
            }
        },
    }

    t.loc.end = self.index;

    return t;
}

fn pop(self: *@This()) Token {
    if (self.peeked) |t| {
        self.peeked = null;
        return t;
    }

    return self.advance();
}

fn toString(self: *@This(), alloc: std.mem.Allocator) std.mem.Allocator.Error!std.ArrayList(u8) {
    var cont = std.ArrayList(u8).init(alloc);

    try cont.appendSlice(self.absPath);
    try cont.appendSlice(":\n");

    var t = self.pop();
    while (!self.finished) : (t = self.pop()) {
        try t.toString(alloc, &cont, self.path);
    }

    try t.toString(alloc, &cont, self.path);

    return cont;
}

fn init(path: []const u8, abspath: []const u8, c: [:0]const u8) @This() {
    const l = @This(){
        .content = c,
        .absPath = abspath,
        .path = path,
        .loc = Location.init(path, c),
    };

    return l;
}

pub fn lex(alloc: std.mem.Allocator, path: []const u8, abspath: []const u8, c: [:0]const u8) std.mem.Allocator.Error![]Token {
    var al = try std.ArrayList(Token).initCapacity(alloc, 100);

    var lexer = init(path, abspath, c);
    var t = lexer.pop();

    while (t.tag != .EOF) : (t = lexer.pop()) {
        try al.append(t);
    }
    try al.append(t);

    return try al.toOwnedSlice();
}
