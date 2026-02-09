const Self = @This();

tag: Value(Node.Tag) = .init(.argType),
tokenIndex: Value(mod.TokenIndex) = .init(0),
count: Value(mod.NodeIndex) = .init(0),
type_: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const argType = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "count" },
    .{ .b = "right", .v = "type_" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node.Types, Self, &argType);
    Struct.assertCommonFieldTypes(Node.Types, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node.Types, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn iterate(self: *const Self, global: *Global) Node.Iterator(*Self, "next") {
    return .init(global, global.nodes.indexOf(self.asConst()));
}

pub fn iterateConst(self: *const Self, global: *Global) Node.Iterator(*const Self, "next") {
    return .init(global, global.nodes.indexOf(self.asConst()));
}

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, printFlags: bool) std.mem.Allocator.Error!void {
    if (self.flags.load(.acquire).hasName) {
        try cont.appendSlice(alloc, self.asConst().getText(global));
        try cont.appendSlice(alloc, ": ");
    }

    try global.nodes.getConstPtr(self.type_.load(.acquire)).asConstTypes().toString(global, alloc, cont, d, printFlags);

    if (printFlags) try self.asConst().toStringFlags(alloc, cont);

    const nextIndex = self.next.load(.acquire);
    if (nextIndex != 0) {
        try cont.appendSlice(alloc, ", ");
        try global.nodes.getPtr(nextIndex).asConstArgType().toString(global, alloc, cont, d, printFlags);
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
