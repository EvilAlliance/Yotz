const std = @import("std");
const Logger = @import("../Logger.zig");
const Parser = @import("../Parser/Parser.zig");

const Lexer = @import("../Lexer/Lexer.zig");
const TokenType = Lexer.TokenType;
const Token = Lexer.Token;
const Location = Lexer.Location;

expected: []TokenType,
found: TokenType,
loc: Location,
alloc: std.mem.Allocator,

pub fn display(self: @This(), fileInfo: Parser.Ast.FileInfo) void {
    const path = fileInfo[0];
    const content = fileInfo[1];
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

    Logger.logLocation.err(path, self.loc, "Expected: {s} but found: \'{s}\' {s}\n", .{
        arr.buffer[0..arr.len],
        self.found.getName(),
        Logger.placeSlice(self.loc, content),
    });
}

pub fn deinit(self: @This()) void {
    self.alloc.free(self.expected);
}
