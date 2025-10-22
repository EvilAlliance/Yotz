const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Util = @import("../Util.zig");

const Location = @import("Location.zig");
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

    //Types
    // TODO: this functions is for the typechecker
    // fn _transformType(t: Lexer.Token, source: [:0]const u8) !struct { Parser.NodeIndex, Parser.NodeIndex } {
    //     if (t.tag != .iden) return error.ExpectedIdentifier;
    //
    //     const name = t.loc.getText(source);
    //
    //     const type_info = std.meta.stringToEnum(TypeName, name) orelse
    //         return error.UnknownType;
    //
    //     return .{
    //         type_info.bit_size,
    //         @intFromEnum(type_info.node_kind),
    //     };
    // }
    //
    // const TypeName = enum {
    //     u8,
    //     u16,
    //     u32,
    //     u64,
    //     s8,
    //     s16,
    //     s32,
    //     s64,
    //
    //     pub fn bit_size(self: TypeName) Parser.NodeIndex {
    //         return switch (self) {
    //             .u8, .s8 => 8,
    //             .u16, .s16 => 16,
    //             .u32, .s32 => 32,
    //             .u64, .s64 => 64,
    //         };
    //     }
    //
    //     pub fn node_kind(self: TypeName) Parser.Node.Primitive {
    //         return switch (self) {
    //             .s8, .s16, .s32, .s64 => .int,
    //             .u8, .u16, .u32, .u64 => .uint,
    //         };
    //     }
    // };

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
