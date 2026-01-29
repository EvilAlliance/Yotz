const Self = @This();

name: *const Parser.Node,

pub fn display(self: *const Self, message: Message) void {
    message.err.unknownIdentifier(self.name);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
