const Self = @This();

tag: Value(Node.Tag),
tokenIndex: Value(mod.TokenIndex) = .init(0),
left: Value(mod.NodeIndex) = .init(0),
right: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Node.Flags) = .init(Node.Flags{}),

const expr = [_]Struct.FieldMap{
    .{ .b = "tag", .v = "tag" },
    .{ .b = "tokenIndex", .v = "tokenIndex" },
    .{ .b = "left", .v = "left" },
    .{ .b = "right", .v = "right" },
    .{ .b = "next", .v = "next" },
    .{ .b = "flags", .v = "flags" },
};

comptime {
    if (@sizeOf(Node) != @sizeOf(Self)) @compileError("Must be same size");

    Struct.assertSameOffsetsFromMap(Node, Self, &expr);
    Struct.assertCommonFieldTypes(Node, Self, Node.COMMONTYPE);
    Struct.assertCommonFieldDefaults(Node, Self, Node.COMMONDEFAULT);
}

pub fn as(self: *Self) *Node {
    return @ptrCast(self);
}

pub fn asConst(self: *const Self) *const Node {
    return @ptrCast(self);
}

pub fn asBinaryOp(self: *Self) *Node.BinaryOp {
    return self.as().asBinaryOp();
}

pub fn asConstBinaryOp(self: *const Self) *const Node.BinaryOp {
    return self.asConst().asConstBinaryOp();
}

pub fn asUnaryOp(self: *Self) *Node.UnaryOp {
    return self.as().asUnaryOp();
}

pub fn asConstUnaryOp(self: *const Self) *const Node.UnaryOp {
    return self.asConst().asConstUnaryOp();
}

pub fn asFuncProto(self: *Self) *Node.FuncProto {
    return self.as().asFuncProto();
}

pub fn asConstFuncProto(self: *const Self) *const Node.FuncProto {
    return self.asConst().asConstFuncProto();
}

pub fn asLiteral(self: *Self) *Node.Literal {
    return self.as().asLiteral();
}

pub fn asConstLiteral(self: *const Self) *const Node.Literal {
    return self.asConst().asConstLiteral();
}

pub fn asLoad(self: *Self) *Node.Load {
    return self.as().asLoad();
}

pub fn asConstLoad(self: *const Self) *const Node.Load {
    return self.asConst().asConstLoad();
}

pub fn asCall(self: *Self) *Node.Call {
    return self.as().asCall();
}

pub fn asConstCall(self: *const Self) *const Node.Call {
    return self.asConst().asConstCall();
}

pub fn toString(self: *const Self, global: *Global, alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64) std.mem.Allocator.Error!void {
    switch (self.tag.load(.acquire)) {
        .funcProto => try self.asConstFuncProto().toString(global, alloc, cont, d),
        .addition, .subtraction, .multiplication, .division, .power => {
            const binOp = self.asConstBinaryOp();
            try cont.append(alloc, '(');

            const leftIndex = binOp.left.load(.acquire);
            try global.nodes.getPtr(leftIndex).asExpression().toString(global, alloc, cont, d);

            try cont.append(alloc, ' ');
            try cont.appendSlice(alloc, self.asConst().getTokenTag(global).toSymbol().?);
            try cont.append(alloc, ' ');

            const rightIndex = binOp.right.load(.acquire);
            try global.nodes.getPtr(rightIndex).asExpression().toString(global, alloc, cont, d);

            try cont.append(alloc, ')');
        },
        .neg => {
            const unOp = self.asConstUnaryOp();
            try cont.appendSlice(alloc, self.asConst().getTokenTag(global).toSymbol().?);
            try cont.append(alloc, '(');
            const leftIndex = unOp.left.load(.acquire);

            try global.nodes.getPtr(leftIndex).asExpression().toString(global, alloc, cont, d);
            try cont.append(alloc, ')');
        },
        .load => {
            try cont.appendSlice(alloc, self.asConst().getText(global));
        },
        .call => {
            const callNode = self.asConstCall();
            try cont.appendSlice(alloc, self.asConst().getText(global));
            try cont.append(alloc, '(');

            var argIndex = callNode.firstArg.load(.acquire);
            while (argIndex != 0) {
                const arg = global.nodes.getConstPtr(argIndex).asConstCallArg();
                const exprIndex = arg.expr.load(.acquire);
                if (exprIndex != 0) {
                    try global.nodes.getPtr(exprIndex).asExpression().toString(global, alloc, cont, d);
                }

                argIndex = arg.next.load(.acquire);
                if (argIndex != 0) try cont.appendSlice(alloc, ", ");
            }

            try cont.append(alloc, ')');

            var next = self.next.load(.acquire);
            while (next != 0) {
                const call = global.nodes.getConstPtr(next).asConstCall();

                try cont.append(alloc, '(');

                argIndex = call.firstArg.load(.acquire);
                while (argIndex != 0) {
                    const arg = global.nodes.getConstPtr(argIndex).asConstCallArg();
                    const exprIndex = arg.expr.load(.acquire);
                    if (exprIndex != 0) {
                        try global.nodes.getPtr(exprIndex).asExpression().toString(global, alloc, cont, d);
                    }

                    argIndex = arg.next.load(.acquire);
                    if (argIndex != 0) try cont.appendSlice(alloc, ", ");
                }

                try cont.append(alloc, ')');

                next = call.next.load(.acquire);
            }
        },
        .lit => {
            try cont.appendSlice(alloc, self.asConst().getText(global));
        },
        else => unreachable,
    }

    try self.asConst().toStringFlags(alloc, cont);
}

const mod = @import("../mod.zig");
const Node = @import("../Node.zig");

const Lexer = @import("../../Lexer/mod.zig");
const Global = @import("../../Global.zig");

const Struct = @import("../../Util/Struct.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
