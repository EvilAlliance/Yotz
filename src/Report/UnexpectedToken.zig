expected: []Lexer.Token.Type,
found: Lexer.Token.Type,
loc: Lexer.Location,

pub fn display(self: @This(), message: Message) void {
    message.err.unexpectedToken(self.found, self.expected, self.loc);
}

const Lexer = @import("../Lexer/mod.zig");
const Message = @import("Message.zig");

const std = @import("std");
