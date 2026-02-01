const Self = @This();

pub const COMMONTYPE: []const []const u8 = &.{ "tag", "tokenIndex", "flags" };
pub const COMMONDEFAULT: []const []const u8 = &.{ "tokenIndex", "flags" };

pub const FuncProto = @import("Node/FuncProto.zig");
pub const Expression = @import("Node/Expression.zig");
pub const BinaryOp = @import("Node/BinaryOp.zig");
pub const UnaryOp = @import("Node/UnaryOp.zig");
pub const VarConst = @import("Node/VarConst.zig");
pub const Literal = @import("Node/Literal.zig");
pub const Load = @import("Node/Load.zig");
pub const Call = @import("Node/Call.zig");
pub const FakeType = @import("Node/FakeType.zig");
pub const Type = @import("Node/Type.zig");
pub const FakeTypes = @import("Node/FakeTypes.zig");
pub const Types = @import("Node/Types.zig");
pub const FuncType = @import("Node/FuncType.zig");
pub const FakeFuncType = @import("Node/FakeFuncType.zig");
pub const FakeArgType = @import("Node/FakeArgType.zig");
pub const ArgType = @import("Node/ArgType.zig");
pub const Ret = @import("Node/Ret.zig");
pub const Scope = @import("Node/Scope.zig");
pub const ProtoArg = @import("Node/ProtoArg.zig");
pub const CallArg = @import("Node/CallArg.zig");

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

pub fn asExpression(self: *Self) *Expression {
    const tag = self.tag.load(.acquire);
    assert(Util.listContains(Tag, &.{ .addition, .subtraction, .multiplication, .division, .power, .neg, .load, .lit, .funcProto, .call }, tag));
    return @ptrCast(self);
}

pub fn asConstExpression(self: *const Self) *const Expression {
    const tag = self.tag.load(.acquire);
    assert(Util.listContains(Tag, &.{ .addition, .subtraction, .multiplication, .division, .power, .neg, .load, .lit, .funcProto, .call }, tag));
    return @ptrCast(self);
}

pub fn asBinaryOp(self: *Self) *BinaryOp {
    const tag = self.tag.load(.acquire);
    assert(Util.listContains(Tag, &.{ .addition, .subtraction, .multiplication, .division, .power }, tag));
    return @ptrCast(self);
}

pub fn asConstBinaryOp(self: *const Self) *const BinaryOp {
    const tag = self.tag.load(.acquire);
    assert(Util.listContains(Tag, &.{ .addition, .subtraction, .multiplication, .division, .power }, tag));
    return @ptrCast(self);
}

pub fn asUnaryOp(self: *Self) *UnaryOp {
    assert(self.tag.load(.acquire) == .neg);
    return @ptrCast(self);
}

pub fn asConstUnaryOp(self: *const Self) *const UnaryOp {
    assert(self.tag.load(.acquire) == .neg);
    return @ptrCast(self);
}

pub fn asVarConst(self: *Self) *VarConst {
    const tag = self.tag.load(.acquire);
    assert(tag == .variable or tag == .constant);
    return @ptrCast(self);
}

pub fn asConstVarConst(self: *const Self) *const VarConst {
    const tag = self.tag.load(.acquire);
    assert(tag == .variable or tag == .constant);
    return @ptrCast(self);
}

pub fn asLiteral(self: *Self) *Literal {
    assert(self.tag.load(.acquire) == .lit);
    return @ptrCast(self);
}

pub fn asConstLiteral(self: *const Self) *const Literal {
    assert(self.tag.load(.acquire) == .lit);
    return @ptrCast(self);
}

pub fn asLoad(self: *Self) *Load {
    assert(self.tag.load(.acquire) == .load);
    return @ptrCast(self);
}

pub fn asConstLoad(self: *const Self) *const Load {
    assert(self.tag.load(.acquire) == .load);
    return @ptrCast(self);
}

pub fn asCall(self: *Self) *Call {
    assert(self.tag.load(.acquire) == .call);
    return @ptrCast(self);
}

pub fn asConstCall(self: *const Self) *const Call {
    assert(self.tag.load(.acquire) == .call);
    return @ptrCast(self);
}

pub fn asFakeType(self: *Self) *FakeType {
    assert(self.tag.load(.acquire) == .fakeType);
    return @ptrCast(self);
}

pub fn asConstFakeType(self: *const Self) *const FakeType {
    assert(self.tag.load(.acquire) == .fakeType);
    return @ptrCast(self);
}

pub fn asType(self: *Self) *Type {
    assert(self.tag.load(.acquire) == .type);
    return @ptrCast(self);
}

pub fn asConstType(self: *const Self) *const Type {
    assert(self.tag.load(.acquire) == .type);
    return @ptrCast(self);
}

pub fn asFakeTypes(self: *Self) *FakeTypes {
    const tag = self.tag.load(.acquire);
    assert(Util.listContains(&.{ .fakeType, .fakeFuncType, .fakeArgType }, tag));
    return @ptrCast(self);
}

pub fn asConstFakeTypes(self: *const Self) *const FakeTypes {
    const tag = self.tag.load(.acquire);
    assert(Util.listContains(&.{ .fakeType, .fakeFuncType, .fakeArgType }, tag));
    return @ptrCast(self);
}

pub fn asTypes(self: *Self) *Types {
    const tag = self.tag.load(.acquire);
    assert(Util.listContains(&.{ .type, .funcType, .argType }, tag));
    return @ptrCast(self);
}

pub fn asConstTypes(self: *const Self) *const Types {
    const tag = self.tag.load(.acquire);
    assert(Util.listContains(&.{ .type, .funcType, .argType }, tag));
    return @ptrCast(self);
}

pub fn asFuncType(self: *Self) *FuncType {
    assert(self.tag.load(.acquire) == .funcType);
    return @ptrCast(self);
}

pub fn asConstFuncType(self: *const Self) *const FuncType {
    assert(self.tag.load(.acquire) == .funcType);
    return @ptrCast(self);
}

pub fn asFakeFuncType(self: *Self) *FakeFuncType {
    assert(self.tag.load(.acquire) == .fakeFuncType);
    return @ptrCast(self);
}

pub fn asConstFakeFuncType(self: *const Self) *const FakeFuncType {
    assert(self.tag.load(.acquire) == .fakeFuncType);
    return @ptrCast(self);
}

pub fn asFakeArgType(self: *Self) *FakeArgType {
    assert(self.tag.load(.acquire) == .fakeArgType);
    return @ptrCast(self);
}

pub fn asConstFakeArgType(self: *const Self) *const FakeArgType {
    assert(self.tag.load(.acquire) == .fakeArgType);
    return @ptrCast(self);
}

pub fn asArgType(self: *Self) *ArgType {
    assert(self.tag.load(.acquire) == .argType);
    return @ptrCast(self);
}

pub fn asConstArgType(self: *const Self) *const ArgType {
    assert(self.tag.load(.acquire) == .argType);
    return @ptrCast(self);
}

pub fn asRet(self: *Self) *Ret {
    assert(self.tag.load(.acquire) == .ret);
    return @ptrCast(self);
}

pub fn asConstRet(self: *const Self) *const Ret {
    assert(self.tag.load(.acquire) == .ret);
    return @ptrCast(self);
}

pub fn asScope(self: *Self) *Scope {
    assert(self.tag.load(.acquire) == .scope);
    return @ptrCast(self);
}

pub fn asConstScope(self: *const Self) *const Scope {
    assert(self.tag.load(.acquire) == .scope);
    return @ptrCast(self);
}

pub fn asProtoArg(self: *Self) *ProtoArg {
    assert(self.tag.load(.acquire) == .protoArg);
    return @ptrCast(self);
}

pub fn asConstProtoArg(self: *const Self) *const ProtoArg {
    assert(self.tag.load(.acquire) == .protoArg);
    return @ptrCast(self);
}

pub fn asCallArg(self: *Self) *CallArg {
    assert(self.tag.load(.acquire) == .callArg);
    return @ptrCast(self);
}

pub fn asConstCallArg(self: *const Self) *const CallArg {
    assert(self.tag.load(.acquire) == .callArg);
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
const Util = @import("../Util.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;
