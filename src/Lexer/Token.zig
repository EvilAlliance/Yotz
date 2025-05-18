const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Util = @import("../Util.zig");

const Lexer = @import("Lexer.zig");
const Location = Lexer.Location;
const Token = Lexer.Token;

pub const TokenType = enum(u32) {
    //symbols delimeters
    openParen,
    closeParen,

    openBrace,
    closeBrace,

    semicolon,
    colon,

    //keyword
    let,
    mut,
    ret,
    func,

    //Types
    unsigned8,
    unsigned16,
    unsigned32,
    unsigned64,
    signed8,
    signed16,
    signed32,
    signed64,

    //Can be many things
    numberLiteral,
    iden,

    //Symbols
    plus,
    minus,
    asterik,
    slash,
    caret,
    equal,

    EOF,

    pub fn getName(self: @This()) []const u8 {
        return self.toSymbol() orelse switch (self) {
            .numberLiteral => "number literal",
            .iden => "identifier",
            else => unreachable,
        };
    }

    pub fn toSymbol(self: @This()) ?[]const u8 {
        return switch (self) {
            .openParen => "(",
            .closeParen => ")",

            .openBrace => "{",
            .closeBrace => "}",

            .colon => ":",
            .semicolon => ";",

            .let => "let",
            .mut => "mut",
            .ret => "return",
            .func => "fn",

            .unsigned8 => "u8",
            .unsigned16 => "u16",
            .unsigned32 => "u32",
            .unsigned64 => "u64",
            .signed8 => "s8",
            .signed16 => "s16",
            .signed32 => "s32",
            .signed64 => "s64",

            .numberLiteral => null,
            .iden => null,

            .plus => "+",
            .minus => "-",
            .asterik => "*",
            .slash => "/",
            .caret => "^",
            .equal => "=",

            .EOF => "EOF",
        };
    }
};

const keyword = std.StaticStringMap(TokenType).initComptime(.{
    .{ "let", .let },
    .{ "mut", .mut },
    .{ "return", .ret },
    .{ "fn", .func },

    .{ "u8", .unsigned8 },
    .{ "u16", .unsigned16 },
    .{ "u32", .unsigned32 },
    .{ "u64", .unsigned64 },

    .{ "s8", .signed8 },
    .{ "s16", .signed16 },
    .{ "s32", .signed32 },
    .{ "s64", .signed64 },
});

tag: TokenType,
loc: Location,

pub fn getKeyWord(w: []const u8) ?TokenType {
    return keyword.get(w);
}

pub fn init(tag: TokenType, loc: Location) Token {
    return Token{
        .tag = tag,
        .loc = loc,
    };
}

pub fn getText(self: @This(), content: [:0]const u8) []const u8 {
    return self.tag.toSymbol() orelse self.loc.getText(content);
}

pub fn toString(self: @This(), alloc: Allocator, cont: *std.ArrayList(u8), path: []const u8, content: [:0]const u8) std.mem.Allocator.Error!void {
    try cont.appendSlice(path);
    try cont.append(':');

    const row = try std.fmt.allocPrint(alloc, "{}", .{self.loc.row});
    try cont.appendSlice(row);
    alloc.free(row);

    try cont.append(':');

    const col = try std.fmt.allocPrint(alloc, "{}", .{self.loc.col});
    try cont.appendSlice(col);
    alloc.free(col);

    try cont.append(' ');

    try cont.appendSlice(self.getText(content));

    try cont.appendSlice(" (");
    try cont.appendSlice(@tagName(self.tag));
    try cont.appendSlice(")\n");
}
