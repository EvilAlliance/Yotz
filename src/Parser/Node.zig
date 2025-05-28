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
    parentesis,
    neg,
    load,

    lit,
};

tag: Tag,
tokenIndex: Parser.TokenIndex = 0,
// 0 is invalid beacause 0 is root
data: struct { Parser.NodeIndex, Parser.NodeIndex } = .{ 0, 0 },
next: Parser.NodeIndex = 0,

pub fn getToken(self: *const @This(), tl: []Lexer.Token) Lexer.Token {
    return tl[self.tokenIndex];
}

pub fn getLocation(self: *const @This(), tl: []Lexer.Token) Lexer.Location {
    return tl[self.tokenIndex].loc;
}

pub fn getTokenTag(self: *const @This(), tl: []Lexer.Token) Lexer.TokenType {
    return tl[self.tokenIndex].tag;
}

pub fn getText(self: *const @This(), tl: []Lexer.Token, content: [:0]const u8) []const u8 {
    return tl[self.tokenIndex].getText(content);
}

pub fn getName(self: *const @This(), tl: []Lexer.Token) []const u8 {
    return tl[self.tokenIndex].tag.getName();
}
