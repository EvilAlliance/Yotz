const Self = @This();

ast: *Parser.Ast,
message: Message,

pub fn init(ast: *Parser.Ast) Self {
    return Self{
        .ast = ast,
        .message = Message.init(ast),
    };
}

pub fn checkRoot(self: *const Self, alloc: Allocator, rootIndex: Parser.NodeIndex) void {
    _ = alloc;
    const root = self.ast.getNode(.Bound, rootIndex);

    var nodeIndex = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (nodeIndex != endIndex) {
        const node = self.ast.getNode(.Bound, nodeIndex);
        defer nodeIndex = node.next.load(.acquire);

        switch (node.tag.load(.acquire)) {
            .variable, .constant => {
                if (node.data[1].load(.acquire) == 0) @panic("Fuck this is multithraded and the function was not parsed yet, what do I do, make a checkpoint system that saves this and then does it");
            },

            else => unreachable,
        }
    }
}

pub fn checkFunction(self: *Self, alloc: Allocator, funcIndex: Parser.NodeIndex) void {
    _ = .{ self, alloc, funcIndex };
}

const Parser = @import("./../Parser/Parser.zig");
const Message = @import("../Message/Message.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
