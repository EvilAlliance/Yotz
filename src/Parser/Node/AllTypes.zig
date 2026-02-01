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

pub fn asType(self: *Self) *Node.Type {
    return self.as().asType();
}

pub fn asConstType(self: *const Self) *const Node.Type {
    return self.asConst().asConstType();
}

pub fn asFuncType(self: *Self) *Node.FuncType {
    return self.as().asFuncType();
}

pub fn asConstFuncType(self: *const Self) *const Node.FuncType {
    return self.asConst().asConstFuncType();
}

pub fn asArgType(self: *Self) *Node.ArgType {
    return self.as().asArgType();
}

pub fn asConstArgType(self: *const Self) *const Node.ArgType {
    return self.asConst().asConstArgType();
}

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
