expectedType: Parser.NodeIndex,
literal: Parser.NodeIndex,

pub fn display(self: @This(), message: Message) void {
    message.err.numberDoesNotFit(self.literal, self.expectedType);

    const expectedTypeNode = message.global.nodes.get(self.expectedType);
    const flags = expectedTypeNode.flags.load(.acquire);
    if (flags.inferedFromExpression or flags.inferedFromUse) {
        message.info.inferedType(self.expectedType);
    }
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
