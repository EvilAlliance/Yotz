const Self = @This();

pub const COMMONTYPE: []const []const u8 = &.{ "tag", "tokenIndex" };
pub const COMMONDEFAULT: []const []const u8 = &.{"tokenIndex"};

pub const FuncProto = @import("Node/FuncProto.zig");

pub const Tag = enum(mod.NodeIndex) {
    // Mark begining and end
    entry, // right is the first root
    root, // data[0] start, when next is zero of the children stop

    empty,

    funcProto, // data[0] args data[1] retutn type next scope
    protoArg, // left fakeType or Type next arg

    fakeType, // indentifier in token
    type, // data[0] size in bits, data[1] Primitive if next != 0 can have multiple types

    fakeFuncType, // data[0] fakeArgsType, data[1] type
    funcType, // data[0] argsType, data[1] type

    fakeArgType, // letf bool (0-1) name in token index, if 0 the same as the fake type, right fakeType next next fakeArgType
    argType, // letf bool (0-1)  name in token index, if 0 the same as the fake type, right fakeType next next fakeArgType

    scope, // data[0] start, when next is zero of the children stop

    ret, // right expression
    variable, // left type, right expr
    constant, // left type, right expr
    call, // left first arg (linked list), next can hold another call executed before
    callArg, // rigth expr or Type next arg

    //expresion
    addition,
    subtraction,
    multiplication,
    division,
    power,
    neg,
    load,

    lit,

    poison = std.math.maxInt(mod.NodeIndex),
};

pub const Primitive = enum(mod.NodeIndex) {
    sint,
    uint,
    float,
};

pub const Flags = packed struct {
    inferedFromUse: bool = false,
    inferedFromExpression: bool = false,
    implicitCast: bool = false,
    reserved: u29 = undefined,
};

tag: Value(Tag) = .init(.poison),
tokenIndex: Value(mod.TokenIndex) = .init(0),
left: Value(mod.NodeIndex) = .init(0),
right: Value(mod.NodeIndex) = .init(0),
next: Value(mod.NodeIndex) = .init(0),
flags: Value(Flags) = .init(Flags{}),

pub inline fn getToken(self: *const @This(), global: *Global) Lexer.Token {
    return global.tokens.get(self.tokenIndex.load(.acquire));
}

pub inline fn getLocation(self: *const @This(), global: *Global) Lexer.Location {
    return global.tokens.get(self.tokenIndex.load(.acquire)).loc;
}

pub inline fn getTokenTag(self: *const @This(), global: *Global) Lexer.Token.Type {
    return global.tokens.get(self.tokenIndex.load(.acquire)).tag;
}

pub inline fn getText(self: *const @This(), global: *Global) []const u8 {
    const token = global.tokens.get(self.tokenIndex.load(.acquire));
    return token.getText(global.files.get(token.loc.source).source);
}

pub inline fn getName(self: *const @This(), global: Global) []const u8 {
    return global.tokens.get(self.tokenIndex.load(.acquire)).tag.getName();
}

pub fn asFuncProto(self: *Self) *FuncProto {
    assert(self.tag.load(.acquire) == .funcProto);
    return @ptrCast(self);
}

pub fn asConstFuncProto(self: *const Self) *const FuncProto {
    assert(self.tag.load(.acquire) == .funcProto);
    return @ptrCast(self);
}

pub fn typeToString(self: @This()) u8 {
    return @as(u8, switch (@as(mod.Node.Primitive, @enumFromInt(self.right.load(.acquire)))) {
        .sint => 's',
        .uint => 'u',
        .float => 'f',
    });
}

const mod = @import("mod.zig");

const Lexer = @import("../Lexer/mod.zig");
const Global = @import("../Global.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
