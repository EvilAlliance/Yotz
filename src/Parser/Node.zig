const Self = @This();

pub const COMMONTYPE: []const []const u8 = &.{ "tag", "tokenIndex", "flags" };
pub const COMMONDEFAULT: []const []const u8 = &.{ "tokenIndex", "flags" };

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

    assigment,
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
    hasName: bool = false,
    reserved: u28 = undefined,
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

pub fn typeToString(self: @This()) u8 {
    return @as(u8, switch (@as(mod.Node.Primitive, @enumFromInt(self.right.load(.acquire)))) {
        .sint => 's',
        .uint => 'u',
        .float => 'f',
    });
}

pub fn Iterator(comptime T: type, comptime field: []const u8) type {
    if (@typeInfo(T) != .pointer) @compileError("Must be a pointer");
    if (@sizeOf(@typeInfo(T).pointer.child) != @sizeOf(Self)) @compileError("Must be a pointer");
    return struct {
        const IterSelf = @This();

        global: *const Global,
        current: mod.NodeIndex,

        pub fn init(global: *const Global, start: mod.NodeIndex) IterSelf {
            return .{
                .global = global,
                .current = start,
            };
        }

        pub fn next(self: *IterSelf) ?T {
            if (self.current == 0) return null;

            const node = if (@typeInfo(T).pointer.is_const)
                self.global.nodes.getConstPtr(self.current)
            else
                self.global.nodes.getPtr(self.current);

            const nextIndex = @field(node, field).load(.acquire);
            self.current = nextIndex;

            return @ptrCast(node);
        }
    };
}

pub fn toStringFlags(self: *const Self, alloc: std.mem.Allocator, cont: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    const fields = std.meta.fields(Flags);
    inline for (fields) |field| {
        if (field.type != bool) continue;
        if (comptime std.mem.eql(u8, field.name, "hasName")) continue;

        const set = @field(self.flags.load(.acquire), field.name);
        if (set) {
            try cont.appendSlice(alloc, " #");
            try cont.appendSlice(alloc, field.name);
        }
    }
}

const mod = @import("mod.zig");

const Lexer = @import("../Lexer/mod.zig");
const Global = @import("../Global.zig");
const Util = @import("../Util.zig");

const std = @import("std");
const assert = std.debug.assert;
const Value = std.atomic.Value;

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
pub const Return = @import("Node/Return.zig");
pub const Scope = @import("Node/Scope.zig");
pub const ProtoArg = @import("Node/ProtoArg.zig");
pub const CallArg = @import("Node/CallArg.zig");
pub const Entry = @import("Node/Entry.zig");
pub const Root = @import("Node/Root.zig");
pub const Statement = @import("Node/Statement.zig");
pub const Declarator = @import("Node/Declarator.zig");
pub const Assignment = @import("Node/Assigment.zig");

pub fn asFuncProto(self: *Self) *FuncProto {
    assert(self.tag.load(.acquire) == .funcProto);
    return @ptrCast(self);
}

pub fn asConstFuncProto(self: *const Self) *const FuncProto {
    assert(self.tag.load(.acquire) == .funcProto);
    return @ptrCast(self);
}

pub fn isExpression(tag: Tag) bool {
    return Util.listContains(Tag, &.{ .addition, .subtraction, .multiplication, .division, .power, .neg, .load, .lit, .funcProto, .call, .funcProto }, tag);
}

pub fn asExpression(self: *Self) *Expression {
    const tag = self.tag.load(.acquire);
    assert(isExpression(tag));
    return @ptrCast(self);
}

pub fn asConstExpression(self: *const Self) *const Expression {
    const tag = self.tag.load(.acquire);
    assert(isExpression(tag));
    return @ptrCast(self);
}

pub fn isBinaryOp(tag: Tag) bool {
    return Util.listContains(Tag, &.{ .addition, .subtraction, .multiplication, .division, .power }, tag);
}

pub fn asBinaryOp(self: *Self) *BinaryOp {
    const tag = self.tag.load(.acquire);
    assert(isBinaryOp(tag));
    return @ptrCast(self);
}

pub fn asConstBinaryOp(self: *const Self) *const BinaryOp {
    const tag = self.tag.load(.acquire);
    assert(isBinaryOp(tag));
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

pub fn isFakeTypes(tag: Tag) bool {
    return Util.listContains(Tag, &.{ .fakeType, .fakeFuncType, .fakeArgType }, tag);
}

pub fn asFakeTypes(self: *Self) *FakeTypes {
    const tag = self.tag.load(.acquire);
    assert(isFakeTypes(tag));
    return @ptrCast(self);
}

pub fn asConstFakeTypes(self: *const Self) *const FakeTypes {
    const tag = self.tag.load(.acquire);
    assert(isFakeTypes(tag));
    return @ptrCast(self);
}

pub fn isTypes(tag: Tag) bool {
    return Util.listContains(Tag, &.{ .type, .funcType, .argType }, tag);
}

pub fn asTypes(self: *Self) *Types {
    const tag = self.tag.load(.acquire);
    assert(isTypes(tag));
    return @ptrCast(self);
}

pub fn asConstTypes(self: *const Self) *const Types {
    const tag = self.tag.load(.acquire);
    assert(isTypes(tag));
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

pub fn asRet(self: *Self) *Return {
    assert(self.tag.load(.acquire) == .ret);
    return @ptrCast(self);
}

pub fn asConstRet(self: *const Self) *const Return {
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

pub fn asEntry(self: *Self) *Entry {
    assert(self.tag.load(.acquire) == .entry);
    return @ptrCast(self);
}

pub fn asConstEntry(self: *const Self) *const Entry {
    assert(self.tag.load(.acquire) == .entry);
    return @ptrCast(self);
}

pub fn asRoot(self: *Self) *Root {
    assert(self.tag.load(.acquire) == .root);
    return @ptrCast(self);
}

pub fn asConstRoot(self: *const Self) *const Root {
    assert(self.tag.load(.acquire) == .root);
    return @ptrCast(self);
}

pub fn isStatement(tag: Tag) bool {
    return Util.listContains(Tag, &.{ .ret, .variable, .constant, .assigment }, tag);
}

pub fn asStatement(self: *Self) *Statement {
    const tag = self.tag.load(.acquire);
    assert(isStatement(tag));
    return @ptrCast(self);
}

pub fn asConstStatement(self: *const Self) *const Statement {
    const tag = self.tag.load(.acquire);
    assert(isStatement(tag));
    return @ptrCast(self);
}

pub fn isDeclarator(tag: Tag) bool {
    return Util.listContains(Tag, &.{ .variable, .constant, .protoArg }, tag);
}

pub fn asDeclarator(self: *Self) *Declarator {
    const tag = self.tag.load(.acquire);
    assert(isDeclarator(tag));
    return @ptrCast(self);
}

pub fn asConstDeclarator(self: *const Self) *const Declarator {
    const tag = self.tag.load(.acquire);
    assert(isDeclarator(tag));
    return @ptrCast(self);
}

pub fn asAssigment(self: *Self) *Assignment {
    const tag = self.tag.load(.acquire);
    assert(tag == .assigment);
    return @ptrCast(self);
}

pub fn asConstAssigment(self: *const Self) *const Assignment {
    const tag = self.tag.load(.acquire);
    assert(tag == .assigment);
    return @ptrCast(self);
}
