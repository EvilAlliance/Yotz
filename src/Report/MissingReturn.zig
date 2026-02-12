const Self = @This();

returnType: *const Parser.Node,

pub fn display(self: *const Self, alloc: Allocator, message: Message) Allocator.Error!void {
    try message.err.missingReturn(alloc, self.returnType);
}

const Message = @import("Message.zig");

const Parser = @import("../Parser/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
