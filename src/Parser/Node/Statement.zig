const Self = @This();

tag: Value(Node.Tag),
tokenIndex: Value(mod.TokenIndex) = .init(0),
left: Value(mod.NodeIndex) = .init(0),
expr: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const stmt = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "left" },
    .{ .b = "right", .v = "expr" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &stmt);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
}

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, enter: bool) std.mem.Allocator.Error!void {
    const exprIndex = self.expr.load(.acquire);

    switch (self.tag.load(.acquire)) {
        .ret => try self.asConstReturn().toString(global, alloc, cont, d),
        .variable, .constant => try self.asConstVarConst().toString(global, alloc, cont, d),
        .assigment => try self.asConstAssigment().toString(global, alloc, cont, d),
        else => unreachable,
    }

    if (global.nodes.get(exprIndex).tag.load(.acquire) != .funcProto) {
        if (enter) try cont.appendSlice(alloc, ";");
    }

    if (enter) try cont.appendSlice(alloc, "\n");
}

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn asReturn(self: *Self) *Node.Return {
    return self.as().asRet();
}

pub fn asConstReturn(self: *const Self) *const Node.Return {
    return self.asConst().asConstRet();
}

pub fn asVarConst(self: *Self) *Node.VarConst {
    return self.as().asVarConst();
}

pub fn asConstVarConst(self: *const Self) *const Node.VarConst {
    return self.asConst().asConstVarConst();
}

pub fn asAssigment(self: *Self) *Node.Assigment {
    return self.as().asAssigment();
}

pub fn asConstAssigment(self: *const Self) *const Node.Assigment {
    return self.asConst().asConstAssigment();
}
