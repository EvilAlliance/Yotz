const Lexer = @import("./../Lexer/Lexer.zig");
const Parser = @import("Parser.zig");

pub const Tag = enum(Parser.NodeIndex) {
    // Mark begining and end
    root, // Placeholder in 0 so any 0 value it cant be an index

    empty,

    funcProto, // data[0] args data[1] retutn type next scope
    args,
    type, // data[0] size in bits, data[1] Primitive if next != 0 can have multiple types
    funcType, // data[0] argsType, data[1] type
    argType, // data[0] argsType, data[1] type
    typeExpression,

    scope,

    ret, // left expression
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
};

pub const Primitive = enum(Parser.NodeIndex) {
    int,
    uint,
    float,
};

pub const Flag = enum(Parser.NodeIndex) {
    inferedFromUse = 0b1,
    inferedFromExpression = 0b10,
};

tag: Tag,
tokenIndex: Parser.TokenIndex = 0,
// 0 is invalid beacause 0 is root
data: struct { Parser.NodeIndex, Parser.NodeIndex } = .{ 0, 0 },
flags: Parser.NodeIndex = 0,
next: Parser.NodeIndex = 0,

pub fn getTokenAst(self: *const @This(), ast: Parser.Ast) Lexer.Token {
    return ast.tokens[self.tokenIndex];
}

pub fn getLocationAst(self: *const @This(), ast: Parser.Ast) Lexer.Location {
    return ast.tokens[self.tokenIndex].loc;
}

pub fn getTokenTagAst(self: *const @This(), ast: Parser.Ast) Lexer.TokenType {
    return ast.tokens[self.tokenIndex].tag;
}

pub fn getTextAst(self: *const @This(), ast: Parser.Ast) []const u8 {
    return ast.tokens[self.tokenIndex].getText(ast.source);
}

pub fn getNameAst(self: *const @This(), ast: Parser.Ast) []const u8 {
    return ast.tokens[self.tokenIndex].tag.getName();
}
