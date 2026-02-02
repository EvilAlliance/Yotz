functionName: *const Parser.Node.Declarator,

const Parser = @import("../Parser/mod.zig");

pub fn display(self: @This(), message: mod.Message) void {
    message.err.funcExpect0Args(self.functionName);
}

const mod = @import("mod.zig");
