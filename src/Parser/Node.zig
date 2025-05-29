const Lexer = @import("./../Lexer/Lexer.zig");
const Parser = @import("Parser.zig");

pub const Tag = enum(Parser.NodeIndex) {
    // Mark begining and end
    root, // Placeholder in 0 so any 0 value it cant be an index

    empty,

    funcProto, // data[0] args data[1] retutn type next scope
    args,
    typeGroup, // data[0] first type data[1] last type, must be continuos
    type,

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

tag: Tag,
tokenIndex: Parser.TokenIndex = 0,
// 0 is invalid beacause 0 is root
data: struct { Parser.NodeIndex, Parser.NodeIndex } = .{ 0, 0 },
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
