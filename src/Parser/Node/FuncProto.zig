const Self = @This();

tag: Value(Node.Tag) = .init(.funcProto),
tokenIndex: Value(mod.TokenIndex) = .init(0),
args: Value(mod.NodeIndex),
retType: Value(mod.NodeIndex),
scope: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const func = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "args" },
    .{ .b = "right", .v = "retType" },
    .{ .b = "next", .v = "scope" },
    .{ .b = "flags", .v = "flags" },
};
comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &func);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64) std.mem.Allocator.Error!void {
    try cont.append(alloc, '(');
    const argIndex = self.args.load(.acquire);
    if (argIndex != 0) {
        var protoArg = global.nodes.getConstPtr(argIndex).asConstProtoArg();

        try cont.appendSlice(alloc, protoArg.asConst().getText(global));
        try cont.appendSlice(alloc, ": ");
        const type_ = global.nodes.getPtr(protoArg.type.load(.acquire));
        if (Node.isFakeTypes(type_.tag.load(.acquire))) {
            try type_.asFakeTypes().toString(global, alloc, cont, d);
        } else if (Node.isTypes(type_.tag.load(.acquire))) {
            try type_.asTypes().toString(global, alloc, cont, d);
        } else unreachable;

        while (protoArg.next.load(.acquire) != 0) {
            protoArg = global.nodes.getConstPtr(protoArg.next.load(.acquire)).asConstProtoArg();

            try cont.appendSlice(alloc, ", ");

            try cont.appendSlice(alloc, protoArg.asConst().getText(global));
            try cont.appendSlice(alloc, ": ");
            if (Node.isFakeTypes(type_.tag.load(.acquire))) {
                try type_.asFakeTypes().toString(global, alloc, cont, d);
            } else if (Node.isTypes(type_.tag.load(.acquire))) {
                try type_.asTypes().toString(global, alloc, cont, d);
            } else unreachable;
        }
    }

    try cont.appendSlice(alloc, ") ");

    const retType = global.nodes.getConstPtr(self.retType.load(.acquire));
    if (Node.isFakeTypes(retType.tag.load(.acquire))) {
        try retType.asConstFakeTypes().toString(global, alloc, cont, 0);
    } else if (Node.isTypes(retType.tag.load(.acquire))) {
        try retType.asConstTypes().toString(global, alloc, cont, 0);
    } else unreachable;

    if (self.scope.load(.acquire) == 0) return;

    const scopeOrStmt = global.nodes.getConstPtr(self.scope.load(.acquire));
    if (!Node.isStatement(scopeOrStmt.tag.load(.acquire))) {
        try scopeOrStmt.asConstScope().toString(global, alloc, cont, d + 4);
    } else {
        try scopeOrStmt.asConstStatement().toString(global, alloc, cont, d);
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
