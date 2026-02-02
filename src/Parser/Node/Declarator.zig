const Self = @This();

tag: Value(Node.Tag),
tokenIndex: Value(mod.TokenIndex) = .init(0),
type: Value(mod.NodeIndex) = .init(0),
right: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const declarator = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "type" },
    .{ .b = "right", .v = "right" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &declarator);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn asVarConst(self: *Self) *Node.VarConst {
    return self.as().asVarConst();
}

pub fn asConstVarConst(self: *const Self) *const Node.VarConst {
    return self.asConst().asConstVarConst();
}

pub fn asProtoArg(self: *Self) *Node.ProtoArg {
    return self.as().asProtoArg();
}

pub fn asConstProtoArg(self: *const Self) *const Node.ProtoArg {
    return self.asConst().asConstProtoArg();
}

pub fn getText(self: *const Self, global: *Global) []const u8 {
    return self.asConst().getText(global);
}

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
