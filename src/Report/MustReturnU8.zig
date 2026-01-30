functionName: []const u8,
type_: *const Parser.Node,

const Parser = @import("../Parser/mod.zig");

pub fn display(self: @This(), message: mod.Message) void {
    message.err.funcReturnsU8(self.functionName, self.type_);
}

const mod = @import("mod.zig");
