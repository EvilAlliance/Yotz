actualType: *const Parser.Node,
expectedType: *const Parser.Node,

place: *const Parser.Node,
declared: *const Parser.Node,

pub fn display(self: @This(), message: Message) void {
    message.err.incompatibleType(self.actualType, self.expectedType, self.place.getLocation(message.global));
    message.info.isDeclaredHere(self.declared);

    const actualFlags = self.actualType.flags.load(.acquire);
    if (actualFlags.inferedFromExpression or actualFlags.inferedFromUse) {
        message.info.inferedType(self.actualType);
    }

    const expectedFlags = self.expectedType.flags.load(.acquire);
    if (expectedFlags.inferedFromExpression or expectedFlags.inferedFromUse) {
        message.info.inferedType(self.expectedType);
    }
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
