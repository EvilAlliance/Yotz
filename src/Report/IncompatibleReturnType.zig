const Self = @This();

actualReturnType: *const Parser.Node,
expectedReturnType: *const Parser.Node,

place: *const Parser.Node,
declared: *const Parser.Node,

pub fn display(self: @This(), message: Message) void {
    message.err.incompatibleReturnType(self.actualReturnType, self.expectedReturnType, self.place.getLocation(message.global));
    message.info.isDeclaredHere(self.declared);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
