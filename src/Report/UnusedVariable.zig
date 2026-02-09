variable: *const Parser.Node.Declarator,

pub fn display(self: @This(), message: Message) void {
    message.warn.unusedVariable(self.variable);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");
