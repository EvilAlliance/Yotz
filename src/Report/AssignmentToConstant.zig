const Self = @This();

constant: *const Parser.Node.Assignment,
declared: *const Parser.Node.VarConst,

pub fn display(self: *const Self, message: Message) void {
    message.err.assignmentToConstant(self.constant);
    message.info.isDeclaredHere(self.declared.asConst());
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
