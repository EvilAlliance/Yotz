const Self = @This();

name: Parser.NodeIndex,
definition: Parser.NodeIndex,

pub fn display(self: *const Self, message: Message) void {
    message.err.usedBeforeDefined(self.name);
    message.info.isDeclaredHere(self.definition);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
