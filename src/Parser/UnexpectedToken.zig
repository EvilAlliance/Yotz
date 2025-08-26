const std = @import("std");
const Logger = @import("../Logger.zig");
const Parser = @import("../Parser/Parser.zig");

const Lexer = @import("../Lexer/Lexer.zig");
const TokenType = Lexer.TokenType;
const Location = Lexer.Location;

expected: []TokenType,
found: TokenType,
loc: Location,
alloc: std.mem.Allocator,

pub fn display(self: @This(), fileInfo: Parser.Ast.FileInfo) void {
    const path = fileInfo[0];
    const content = fileInfo[1];
    var buff: [1024]u8 = undefined;
    var arr = std.ArrayList(u8).initBuffer(&buff);

    arr.appendBounded('\"') catch return;
    arr.appendSliceBounded(self.expected[0].getName()) catch return;
    arr.appendBounded('\"') catch return;
    for (self.expected[1..]) |e| {
        arr.appendSliceBounded(", ") catch return;
        arr.appendBounded('\"') catch return;
        arr.appendSliceBounded(e.getName()) catch return;
        arr.appendBounded('\"') catch return;
    }

    Logger.logLocation.err(path, self.loc, "Expected: {s} but found: \'{s}\' {s}\n", .{
        arr.items,
        self.found.getName(),
        Logger.placeSlice(self.loc, content),
    });

    self.deinit();
}

pub fn deinit(self: @This()) void {
    self.alloc.free(self.expected);
}
