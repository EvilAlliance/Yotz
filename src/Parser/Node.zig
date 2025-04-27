const Lexer = @import("./../Lexer/Lexer.zig");
const Parser = @import("Parser.zig");

pub const Tag = enum(Parser.NodeIndex) {
    // Mark begining and end
    root,

    empty,

    funcDecl,
    funcProto,
    args,
    type,

    scope,

    // Right must be free for the index of next statement
    ret, // left expression
    variable, // left variable Prot
    constant, // left variable Proto
    VarProto, //left type, right expr

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
data: struct { Parser.NodeIndex, Parser.NodeIndex },

pub fn getLocation(self: *const @This(), tl: []Lexer.Token) Lexer.Location {
    return tl[self.tokenIndex].loc;
}

pub fn getTokenTag(self: *const @This(), tl: []Lexer.Token) Lexer.TokenType {
    return tl[self.tokenIndex].tag;
}

pub fn getText(self: *const @This(), tl: []Lexer.Token) []const u8 {
    return tl[self.tokenIndex].getText();
}

pub fn getName(self: *const @This(), tl: []Lexer.Token) []const u8 {
    return tl[self.tokenIndex].tag.getName();
}
