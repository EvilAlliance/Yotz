const Self = @This();

actualReturnType: *const Parser.Node.Types,
expectedReturnType: *const Parser.Node.Types,

place: *const Parser.Node,
declared: *const Parser.Node,
kind: ?Typing.Type.MismatchKind,

pub fn display(self: @This(), alloc: Allocator, message: Message) Allocator.Error!void {
    const kindStr: ?[]const u8 = if (self.kind) |k| switch (k) {
        .correct => null,
        .primitiveType => "(types differ)",
        .returnType => "(return types are incompatible)",
        .argumentType => "(argument types are incompatible)",
        .argumentCount => "(argument count mismatch)",
    } else null;

    try message.err.incompatibleReturnType(alloc, self.actualReturnType, self.expectedReturnType, self.place.getLocation(message.global), kindStr);

    message.info.isDeclaredHere(self.declared);
}

const Message = @import("Message.zig");
const Typing = @import("../Typing/mod.zig");

const Parser = @import("../Parser/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
