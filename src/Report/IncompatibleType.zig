actualType: Parser.NodeIndex,
expectedType: Parser.NodeIndex,

place: Parser.NodeIndex,
declared: Parser.NodeIndex,

pub fn display(self: @This(), message: Message) void {
    message.err.incompatibleType(self.actualType, self.expectedType, message.global.nodes.get(self.place).getLocation(message.global));
    message.info.isDeclaredHere(self.declared);

    const actual = message.global.nodes.get(self.actualType);
    const actualFlags = actual.flags.load(.acquire);
    if (actualFlags.inferedFromExpression or actualFlags.inferedFromUse) {
        message.info.inferedType(self.actualType);
    }

    const expected = message.global.nodes.get(self.expectedType);
    const expectedFlags = expected.flags.load(.acquire);
    if (expectedFlags.inferedFromExpression or expectedFlags.inferedFromUse) {
        message.info.inferedType(self.expectedType);
    }
}

const Parser = @import("../Parser/mod.zig");
const Message = @import("Message.zig");
