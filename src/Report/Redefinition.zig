const Self = @This();

name: Parser.NodeIndex,
original: Parser.NodeIndex,

pub fn display(self: *const Self, message: Message) void {
    message.err.identifierIsUsed(self.name);
    message.info.isDeclaredHere(self.original);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
