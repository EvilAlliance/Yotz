const std = @import("std");
const Logger = @import("../Logger.zig");
const Parser = @import("../Parser/Parser.zig");

const Lexer = @import("../Lexer/Lexer.zig");
const TokenType = Lexer.TokenType;
const Location = Lexer.Location;

expected: []TokenType,
found: TokenType,
loc: Location,

pub fn display(self: @This(), alloc: std.mem.Allocator, fileInfo: Parser.Ast.FileInfo) void {
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

    _ = .{ path, content };
    self.deinit(alloc);
    @panic("Must use message struct, which should be in the translation unit");
    // Logger.log.err("{s}:{}:{}: Expected: {s} but found: \'{s}\' {s}\n", .{
    //     path,      self.loc.row,         self.loc.col,
    //     arr.items, self.found.getName(), ,
    // });

}

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    alloc.free(self.expected);
}
