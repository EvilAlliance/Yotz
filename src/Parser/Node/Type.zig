const Self = @This();

tag: Value(Node.Tag) = .init(.type),
tokenIndex: Value(mod.TokenIndex) = .init(0),
size: Value(mod.NodeIndex) = .init(0),
primitive: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const type_ = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "size" },
    .{ .b = "right", .v = "primitive" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &type_);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, printFlags: bool) std.mem.Allocator.Error!void {
    try cont.append(alloc, @as(u8, switch (@as(Node.Primitive, @enumFromInt(self.primitive.load(.acquire)))) {
        .sint => 's',
        .uint => 'u',
        .float => 'f',
    }));

    const size = try std.fmt.allocPrint(alloc, "{}", .{self.size.load(.acquire)});
    try cont.appendSlice(alloc, size);
    alloc.free(size);

    if (printFlags) try self.asConst().toStringFlags(alloc, cont);

    if (self.next.load(.acquire) != 0) {
        try cont.appendSlice(alloc, ", ");
        try global.nodes.getConstPtr(self.next.load(.acquire)).asConstTypes().toString(global, alloc, cont, d, printFlags);
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
