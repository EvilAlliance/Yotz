const std = @import("std");
const Logger = @import("../Logger.zig");

const Lexer = @import("../Lexer/Lexer.zig");
const TokenType = Lexer.TokenType;
const Token = Lexer.Token;
const Location = Lexer.Location;

expected: []TokenType,
found: TokenType,
loc: Location,
alloc: std.mem.Allocator,

pub fn display(self: @This()) void {
    var arr = std.BoundedArray(u8, 10 * 1024).init(0) catch return;

    arr.append('\"') catch return;
    arr.appendSlice(self.expected[0].getName()) catch return;
    arr.append('\"') catch return;
    for (self.expected[1..]) |e| {
        arr.appendSlice(", ") catch return;
        arr.append('\"') catch return;
        arr.appendSlice(e.getName()) catch return;
        arr.append('\"') catch return;
    }

    Logger.logLocation.err(self.loc, "Expected: {s} but found: {s}{s}{s}", .{
        arr.buffer[0..arr.len],
        "\'",
        self.found.getName(),
        "\'",
    });
}

pub fn deinit(self: @This()) void {
    self.alloc.free(self.expected);
}
