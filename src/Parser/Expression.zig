const Parser = @import("Parser.zig");

const Lexer = @import("../Lexer/Lexer.zig");

//https://en.cppreference.com/w/c/language/operator_precedence
pub fn operandPresedence(t: Parser.Node.Tag) u8 {
    return switch (t) {
        .power => 3,
        .multiplication => 2,
        .division => 2,
        .addition => 1,
        .subtraction => 1,
        else => unreachable,
    };
}

pub const Associativity = enum {
    left,
    right,
};

pub fn operandAssociativity(t: Parser.Node.Tag) Associativity {
    return switch (t) {
        .power => Associativity.right,
        .multiplication => Associativity.left,
        .division => Associativity.left,
        .addition => Associativity.left,
        .subtraction => Associativity.left,
        else => unreachable,
    };
}

pub fn tokenTagToNodeTag(tag: Lexer.Token.TokenType) Parser.Node.Tag {
    return switch (tag) {
        .minus => .subtraction,
        .plus => .addition,
        .asterik => .multiplication,
        .slash => .division,
        .caret => .power,
        else => unreachable,
    };
}
