const Self = @This();

cycle: []const Typing.Expression.CycleUnit,

pub fn display(self: *const Self, message: Message) void {
    message.err.dependencyCycle(self.cycle);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
const Typing = @import("../Typing/mod.zig");
