const Self = @This();

statement: *const Parser.Node,

pub fn display(self: *const Self, message: Message) void {
    message.warn.unreachableStatement(self.statement);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
