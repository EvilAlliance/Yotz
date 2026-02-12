const Self = @This();

tag: Value(Node.Tag),
tokenIndex: Value(mod.TokenIndex) = .init(0),
type: Value(mod.NodeIndex) = .init(0), // Declarator
expr: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const declarator = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "type", .v = "type" },
    .{ .b = "right", .v = "expr" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

const statement = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "type" },
    .{ .b = "expr", .v = "expr" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node.Declarator, Self, &declarator);
    Struct.assertSameOffsetsFromMap(Node.Statement, Self, &statement);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
}

pub fn typeIterator(self: *const Self, global: *const Global) Node.Iterator(*Node.Types, "next") {
    return .init(global, self.type.load(.acquire));
}

pub fn typeIteratorConst(self: *const Self, global: *const Global) Node.Iterator(*const Node.Types, "next") {
    return .init(global, self.type);
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

    const variableLeft = self.type.load(.acquire);
    if (variableLeft == 0)
        try cont.append(alloc, ' ');

    try cont.append(alloc, ':');
    if (variableLeft != 0) {
        try cont.append(alloc, ' ');
        const typeNode = global.nodes.getPtr(variableLeft);
        const typeTag = typeNode.tag.load(.acquire);
        if (Node.isFakeTypes(typeTag)) {
            try typeNode.asFakeTypes().toString(global, alloc, cont, d);
        } else if (Node.isTypes(typeTag)) {
            try typeNode.asTypes().toString(global, alloc, cont, d, true);
        } else unreachable;
        try cont.append(alloc, ' ');
    }

    const exprIndex = self.expr.load(.acquire);
    if (exprIndex != 0) {
        switch (self.tag.load(.acquire)) {
            .constant => try cont.appendSlice(alloc, ": "),
            .variable => try cont.appendSlice(alloc, "= "),
            else => unreachable,
        }
        try global.nodes.getPtr(exprIndex).asExpression().toString(global, alloc, cont, d);
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
