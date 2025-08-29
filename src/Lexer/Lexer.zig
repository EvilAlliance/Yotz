const std = @import("std");
const util = @import("./../Util.zig");

const Arguments = @import("./../ParseArgs.zig").Arguments;

pub const Location = @import("./Location.zig");
pub const Token = @import("./Token.zig");
pub const TokenType = Token.TokenType;

const Allocator = std.mem.Allocator;
const print = std.debug.print;
const assert = std.debug.assert;

content: [:0]const u8,
index: u32 = 0,
loc: Location,

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
    var t = Token.init(undefined, self.loc.shallowCopy(self.index, undefined));

    state: switch (Status.start) {
        .start => switch (self.content[self.index]) {
            0 => {
                t.tag = .EOF;
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
                std.log.info("Found {s}", .{self.content[self.index .. self.index + 1]});
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

fn init(c: [:0]const u8) @This() {
    const l = @This(){
        .content = c,
        .loc = Location.init(),
    };

    return l;
}

pub fn lex(alloc: std.mem.Allocator, c: [:0]const u8) std.mem.Allocator.Error![]Token {
    var al = try std.ArrayList(Token).initCapacity(alloc, 100);

    var lexer = init(c);
    var t = lexer.advance();

    while (t.tag != .EOF) : (t = lexer.advance()) {
        try al.append(alloc, t);
    }
    try al.append(alloc, t);

    return try al.toOwnedSlice(alloc);
}
