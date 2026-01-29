expectedType: *const Parser.Node,
literal: *const Parser.Node,

pub fn display(self: @This(), message: Message) void {
    message.err.numberDoesNotFit(self.literal, self.expectedType);

    const flags = self.expectedType.flags.load(.acquire);
    if (flags.inferedFromExpression or flags.inferedFromUse) {
        message.info.inferedType(self.expectedType);
    }
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
