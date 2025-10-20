const std = @import("std");
const Atomic = std.atomic.Value;
const Lexer = @import("./../Lexer/Lexer.zig");
const Parser = @import("Parser.zig");

pub const Tag = enum(Parser.NodeIndex) {
    // Mark begining and end
    entry, // right is the first root
    root, // data[0] start, when next is zero of the children stop

    empty,

    funcProto, // data[0] args data[1] retutn type next scope
    args,
    fakeType, // indentifier in token
    type, // data[0] size in bits, data[1] Primitive if next != 0 can have multiple types
    funcType, // data[0] argsType, data[1] type
    argType, // data[0] argsType, data[1] type

    scope, // data[0] start, when next is zero of the children stop

    ret, // right expression
    variable, // left type, right expr
    constant, // left type, right expr

    //expresion
    addition,
    subtraction,
    multiplication,
    division,
    power,
    neg,
    load,

    lit,

    poison = std.math.maxInt(Parser.NodeIndex),
};

pub const Primitive = enum(Parser.NodeIndex) {
    int,
    uint,
    float,
};

pub const Flags = packed struct {
    inferedFromUse: bool = false,
    inferedFromExpression: bool = false,
    implicitCast: bool = false,
    reserved: u29 = undefined,
};

tag: Atomic(Tag) = .init(.poison),
tokenIndex: Atomic(Parser.TokenIndex) = .init(0),
data: struct { Atomic(Parser.NodeIndex), Atomic(Parser.NodeIndex) } = .{ .init(0), .init(0) },
flags: Atomic(Flags) = .init(Flags{}),
next: Atomic(Parser.NodeIndex) = .init(0),

pub inline fn getTokenAst(self: *const @This(), ast: Parser.Ast) Lexer.Token {
    return ast.tu.cont.tokens[self.tokenIndex.load(.acquire)];
}

pub inline fn getLocationAst(self: *const @This(), ast: Parser.Ast) Lexer.Location {
    return ast.tu.cont.tokens[self.tokenIndex.load(.acquire)].loc;
}

pub inline fn getTokenTagAst(self: *const @This(), ast: Parser.Ast) Lexer.TokenType {
    return ast.tu.cont.tokens[self.tokenIndex.load(.acquire)].tag;
}

pub inline fn getTextAst(self: *const @This(), ast: *const Parser.Ast) []const u8 {
    return ast.tu.cont.tokens[self.tokenIndex.load(.acquire)].getText(ast.tu.cont.source);
}

pub inline fn getNameAst(self: *const @This(), ast: Parser.Ast) []const u8 {
    return ast.cont.tokens[self.tokenIndex.load(.acquire)].tag.getName();
}

pub fn typeToString(self: @This()) u8 {
    return @as(u8, switch (@as(Parser.Node.Primitive, @enumFromInt(self.data[1].load(.acquire)))) {
        .int => 'i',
        .uint => 'u',
        .float => 'f',
    });
}
