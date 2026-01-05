pub const Lexer = @import("Lexer.zig");
pub const Location = @import("./Location.zig");
pub const Token = @import("./Token.zig");
pub const Tokens = ArrayListThreadSafe(Token);

pub fn lex(alloc: std.mem.Allocator, tokens: *Tokens, c: [:0]const u8, index: u32) std.mem.Allocator.Error!void {
    tokens.lock();
    defer tokens.unlock();

    var lexer = Lexer.init(c);
    var t = lexer.advance();

    while (t.tag != .EOF) : (t = lexer.advance()) {
        t.loc.source = index;
        try tokens.appendUnlock(alloc, t);
    }
    try tokens.appendUnlock(alloc, t);
}

const ArrayListThreadSafe = @import("../Util/ArrayListThreadSafe.zig").ArrayListThreadSafe;
const Parser = @import("../Parser/mod.zig");

const std = @import("std");
