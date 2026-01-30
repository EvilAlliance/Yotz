const Self = @This();

returnType: *const Parser.Node,

pub fn display(self: *const Self, message: Message) void {
    message.err.missingReturn(self.returnType);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
