expectedCount: u64,
actualCount: u64,

place: *const Parser.Node.FuncProto,
expectedFunction: *const Parser.Node.Types,

pub fn display(self: @This(), message: Message) void {
    message.err.argumentCountMismatch(self.actualCount, self.expectedCount, self.place.asConst().getLocation(message.global));
    message.info.isDeclaredHere(self.expectedFunction.asConst());
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
