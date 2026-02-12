const Self = @This();

returnNode: *const Parser.Node,

pub fn display(self: *const Self, message: Message) void {
    message.err.expectedExpression(self.returnNode);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
