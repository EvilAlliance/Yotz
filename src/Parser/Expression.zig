const Node = @import("Node.zig");

const Lexer = @import("../Lexer/mod.zig");

//https://en.cppreference.com/w/c/language/operator_precedence
pub fn operandPresedence(t: Node.Tag) u8 {
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

pub fn operandAssociativity(t: Node.Tag) Associativity {
    return switch (t) {
        .power => Associativity.right,
        .multiplication => Associativity.left,
        .division => Associativity.left,
        .addition => Associativity.left,
        .subtraction => Associativity.left,
        else => unreachable,
    };
}

pub fn tokenTagToNodeTag(tag: Lexer.Token.Type) Node.Tag {
    return switch (tag) {
        .minus => .subtraction,
        .plus => .addition,
        .asterik => .multiplication,
        .slash => .division,
        .caret => .power,
        else => unreachable,
    };
}
