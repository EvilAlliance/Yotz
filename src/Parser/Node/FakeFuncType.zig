const Self = @This();

tag: Value(Node.Tag) = .init(.fakeFuncType),
tokenIndex: Value(mod.TokenIndex) = .init(0),
fakeArgsType: Value(mod.NodeIndex) = .init(0),
fakeRetType: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const fakeFuncType = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "fakeArgsType" },
    .{ .b = "right", .v = "fakeRetType" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &fakeFuncType);
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
    try cont.append(alloc, '(');
    const argsIndex = self.fakeArgsType.load(.acquire);
    if (argsIndex != 0) try global.nodes.getPtr(argsIndex).asConstFakeArgType().toString(global, alloc, cont, d);
    try cont.appendSlice(alloc, ") ");

    try global.nodes.getPtr(self.fakeRetType.load(.acquire)).asConstFakeTypes().toString(global, alloc, cont, d);
    
    try self.asConst().toStringFlags(alloc, cont);
}

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
