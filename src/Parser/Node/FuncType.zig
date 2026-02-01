const Self = @This();

tag: Value(Node.Tag) = .init(.funcType),
tokenIndex: Value(mod.TokenIndex) = .init(0),
argsType: Value(mod.NodeIndex) = .init(0),
retType: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const funcType = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "argsType" },
    .{ .b = "right", .v = "retType" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &funcType);
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
    const argsIndex = self.argsType.load(.acquire);
    if (argsIndex != 0) try global.nodes.getPtr(argsIndex).asConstArgType().toString(global, alloc, cont, d);
    try cont.appendSlice(alloc, ") ");

    try global.nodes.getPtr(self.retType.load(.acquire)).asConstTypes().toString(global, alloc, cont, d);
    
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
