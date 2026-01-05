const Token = @This();

pub const Type = enum(u32) {
    //symbols delimeters
    openParen,
    closeParen,

    openBrace,
    closeBrace,

    semicolon,
    colon,

    //keyword
    ret,
    func,

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

            .ret => "return",
            .func => "fn",

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

const keyword = std.StaticStringMap(Type).initComptime(.{
    .{ "return", .ret },
    .{ "fn", .func },
});

tag: Type,
loc: Location,

pub fn getKeyWord(w: []const u8) ?Type {
    return keyword.get(w);
}

pub fn init(tag: Type, loc: Location) Token {
    return Token{
        .tag = tag,
        .loc = loc,
    };
}

pub fn getText(self: @This(), content: [:0]const u8) []const u8 {
    return self.tag.toSymbol() orelse self.loc.getText(content);
}

pub fn toString(self: @This(), alloc: Allocator, cont: *std.ArrayList(u8), path: []const u8, content: [:0]const u8) std.mem.Allocator.Error!void {
    try cont.appendSlice(alloc, path);
    try cont.append(alloc, ':');

    const row = try std.fmt.allocPrint(alloc, "{}", .{self.loc.row});
    try cont.appendSlice(alloc, row);
    alloc.free(row);

    try cont.append(alloc, ':');

    const col = try std.fmt.allocPrint(alloc, "{}", .{self.loc.col});
    try cont.appendSlice(alloc, col);
    alloc.free(col);

    try cont.append(alloc, ' ');

    try cont.appendSlice(alloc, self.getText(content));

    try cont.appendSlice(alloc, " (");
    try cont.appendSlice(alloc, @tagName(self.tag));
    try cont.appendSlice(alloc, ")\n");
}

const Location = @import("Location.zig");

const Util = @import("../Util.zig");

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
