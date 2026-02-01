const Self = @This();

tag: Value(Node.Tag),
tokenIndex: Value(mod.TokenIndex) = .init(0),
left: Value(mod.NodeIndex) = .init(0),
right: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const allFakeTypes = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "left" },
    .{ .b = "right", .v = "right" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &allFakeTypes);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn asFakeType(self: *Self) *Node.FakeType {
    return self.as().asFakeType();
}

pub fn asConstFakeType(self: *const Self) *const Node.FakeType {
    return self.asConst().asConstFakeType();
}

pub fn asFakeFuncType(self: *Self) *Node.FakeFuncType {
    return self.as().asFakeFuncType();
}

pub fn asConstFakeFuncType(self: *const Self) *const Node.FakeFuncType {
    return self.asConst().asConstFakeFuncType();
}

pub fn asFakeArgType(self: *Self) *Node.FakeArgType {
    return self.as().asFakeArgType();
}

pub fn asConstFakeArgType(self: *const Self) *const Node.FakeArgType {
    return self.asConst().asConstFakeArgType();
}

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64) std.mem.Allocator.Error!void {
    switch (self.tag.load(.acquire)) {
        .fakeType => try self.asConstFakeType().toString(global, alloc, cont, d),
        .fakeFuncType => try self.asConstFakeFuncType().toString(global, alloc, cont, d),
        .fakeArgType => try self.asConstFakeArgType().toString(global, alloc, cont, d),
        else => unreachable,
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
