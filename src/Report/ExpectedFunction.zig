const Self = @This();

variable: *const Parser.Node,
declared: *const Parser.Node,

pub fn display(self: *const Self, message: Message) void {
    message.err.expectedFunction(self.variable);
    message.info.isDeclaredHere(self.declared);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
