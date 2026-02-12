const Self = @This();

tag: Value(Node.Tag) = .init(.assigment),
tokenIndex: Value(mod.TokenIndex) = .init(0),
none: Value(mod.NodeIndex) = .init(0),
expr: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const varConst = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "none" },
    .{ .b = "right", .v = "expr" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node.Statement, Self, &varConst);
    Struct.assertCommonFieldTypes(Node.Statement, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node.Statement, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn getText(self: *const Self, global: *Global) []const u8 {
    return self.asConst().getText(global);
}

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64) std.mem.Allocator.Error!void {
    try cont.appendSlice(alloc, self.asConst().getText(global));

    try cont.appendSlice(alloc, " = ");

    const exprIndex = self.expr.load(.acquire);
    try global.nodes.getPtr(exprIndex).asExpression().toString(global, alloc, cont, d);
}

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
