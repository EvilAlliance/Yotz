const Self = @This();

tag: Value(Node.Tag) = .init(.protoArg),
tokenIndex: Value(mod.TokenIndex) = .init(0),
type: Value(mod.NodeIndex) = .init(0), // Declarator
count: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const protoArg = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "type", .v = "type" },
    .{ .b = "right", .v = "count" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node.Declarator, Self, &protoArg);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
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

pub fn iterate(self: *const Self, global: *Global) Node.Iterator(*Self, "next") {
    return .init(global, global.nodes.indexOf(self.asConst()));
}

pub fn iterateConst(self: *const Self, global: *Global) Node.Iterator(*const Self, "next") {
    return .init(global, global.nodes.indexOf(self.asConst()));
}

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
