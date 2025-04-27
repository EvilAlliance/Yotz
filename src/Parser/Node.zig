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
token: ?Lexer.Token,

// 0 is invalid beacause 0 is root
data: struct { Parser.NodeIndex, Parser.NodeIndex },

pub fn getLocation(self: *const @This()) Lexer.Location {
    return self.token.?.loc;
}

pub fn getTokenTag(self: *const @This()) Lexer.TokenType {
    return self.token.?.tag;
}

pub fn getText(self: *const @This()) []const u8 {
    return self.token.?.loc.getText();
}

pub fn getName(self: *const @This()) []const u8 {
    return self.token.?.tag.getName();
}
