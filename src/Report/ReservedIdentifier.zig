const Self = @This();

where: *const Parser.Node.Declarator,

pub fn display(self: *const Self, message: Message) void {
    message.err.identifierIsReserved(self.where);
}

const Message = @import("Message.zig");
const Parser = @import("../Parser/mod.zig");
