pub const Lexer = @import("Lexer.zig");
pub const Location = @import("./Location.zig");
pub const Token = @import("./Token.zig");

pub fn lex(alloc: std.mem.Allocator, c: [:0]const u8) std.mem.Allocator.Error![]Token {
    var al = try std.ArrayList(Token).initCapacity(alloc, c.len / 4);

    var lexer = Lexer.init(c);
    var t = lexer.advance();

    while (t.tag != .EOF) : (t = lexer.advance()) {
        try al.append(alloc, t);
    }
    try al.append(alloc, t);

    return try al.toOwnedSlice(alloc);
}

const std = @import("std");
