const Self = @This();

tag: Value(Node.Tag) = .init(.root),
tokenIndex: Value(mod.TokenIndex) = .init(0),
firstStmt: Value(mod.NodeIndex) = .init(0),
endStmt: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const root = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "firstStmt" },
    .{ .b = "right", .v = "endStmt" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &root);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64) std.mem.Allocator.Error!void {
    var currentIndex = self.firstStmt.load(.acquire);

    while (currentIndex != 0) {
        const stmt = global.nodes.getPtr(currentIndex);

        var i: u64 = 0;
        while (i < d) : (i += 1) {
            try cont.appendSlice(alloc, "  ");
        }

        try stmt.asStatement().toString(global, alloc, cont, d);

        currentIndex = stmt.next.load(.acquire);
    }

    try self.asConst().toStringFlags(alloc, cont);

    const nextIndex = self.next.load(.acquire);
    if (nextIndex != 0) {
        try global.nodes.getPtr(nextIndex).asConstRoot().toString(global, alloc, cont, d);
    }
}

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
