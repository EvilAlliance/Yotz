const Self = @This();

cycle: []const Parser.NodeIndex,

pub fn display(self: *const Self, message: Message) void {
    message.err.dependencyCycle(self.cycle);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
