const Self = @This();

tag: Value(Node.Tag) = .init(.call),
tokenIndex: Value(mod.TokenIndex) = .init(0),
firstArg: Value(mod.NodeIndex) = .init(0),
nextCall: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const call = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "firstArg" },
    .{ .b = "right", .v = "nextCall" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node.Statement, Self, &call);
    Struct.assertCommonFieldTypes(Node.Statement, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node.Statement, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn iterate(self: *Self, global: *Global) Node.Iterator(*Self, "nextCall") {
    return .init(global, global.nodes.indexOf(self.as()));
}

pub fn iterateConst(self: *const Self, global: *Global) Node.Iterator(*const Self, "nextCall") {
    return .init(global, global.nodes.indexOf(self.asConst()));
}

pub fn argIterator(self: *const Self, global: *Global) Node.Iterator(*Node.CallArg, "next") {
    return .init(global, self.firstArg.load(.acquire));
}

pub fn argIteratorConst(self: *const Self, global: *Global) Node.Iterator(*const Node.CallArg, "next") {
    return .init(global, self.firstArg.load(.acquire));
}

pub inline fn getText(self: *const Self, global: *Global) []const u8 {
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
