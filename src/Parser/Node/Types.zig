const Self = @This();

tag: Value(Node.Tag),
tokenIndex: Value(mod.TokenIndex) = .init(0),
left: Value(mod.NodeIndex) = .init(0),
right: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const allTypes = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "left" },
    .{ .b = "right", .v = "right" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &allTypes);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
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

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64) std.mem.Allocator.Error!void {
    switch (self.tag.load(.acquire)) {
        .type => try self.asConstType().toString(global, alloc, cont, d),
        .funcType => try self.asConstFuncType().toString(global, alloc, cont, d),
        .argType => try self.asConstArgType().toString(global, alloc, cont, d),
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
