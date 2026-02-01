const Self = @This();

tag: Value(Node.Tag),
tokenIndex: Value(mod.TokenIndex),
left: Value(mod.NodeIndex),
right: Value(mod.NodeIndex),
next: Value(mod.NodeIndex),
flags: Value(Node.Flags),

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");
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

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
