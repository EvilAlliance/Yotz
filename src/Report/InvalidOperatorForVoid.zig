const Self = @This();

expr: *const Parser.Node,

pub fn display(self: *const Self, message: Message) void {
    message.err.invalidOperatorForVoid(self.expr);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
