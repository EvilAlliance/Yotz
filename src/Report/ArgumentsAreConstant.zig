const Self = @This();

argument: *const Parser.Node.Assignment,
declared: *const Parser.Node.ProtoArg,

pub fn display(self: *const Self, message: Message) void {
    message.err.argumentsAreConstant(self.argument);
    message.info.isDeclaredHere(self.declared.asConst());
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
