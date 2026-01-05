expected: []Lexer.Token.Type,
found: Lexer.Token.Type,
loc: Lexer.Location,

pub fn display(self: @This(), alloc: std.mem.Allocator, fileInfo: Ast.FileInfo) void {
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
    @import("std").log.err("{s}:{}:{}: Expected: {s} but found: \'{s}\'", .{
        path,      self.loc.row,         self.loc.col,
        arr.items, self.found.getName(),
    });
    std.log.debug("Must use message struct, which should be in the translation unit", .{});
}

pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
    alloc.free(self.expected);
}

const Logger = @import("../Logger.zig");
const Lexer = @import("../Lexer/mod.zig");

const std = @import("std");
