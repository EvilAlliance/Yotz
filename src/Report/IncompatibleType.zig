actualType: *const Parser.Node.Types,
expectedType: *const Parser.Node.Types,

place: *const Parser.Node,
declared: *const Parser.Node,
kind: ?Typing.Type.MismatchKind,

pub fn display(self: @This(), alloc: std.mem.Allocator, message: Message) Allocator.Error!void {
    const kindStr: ?[]const u8 = if (self.kind) |k| switch (k) {
        .correct => null,
        .primitiveType => "(types differ)",
        .returnType => "(return types are incompatible)",
        .argumentType => "(argument types are incompatible)",
        .argumentCount => "(argument count mismatch)",
    } else null;

    try message.err.incompatibleType(alloc, self.actualType, self.expectedType, self.place.getLocation(message.global), kindStr);

    message.info.isDeclaredHere(self.declared);

    const actualFlags = self.actualType.flags.load(.acquire);
    if (actualFlags.inferedFromExpression or actualFlags.inferedFromUse) {
        message.info.inferedType(self.actualType.asConst());
    }

    const expectedFlags = self.expectedType.flags.load(.acquire);
    if (expectedFlags.inferedFromExpression or expectedFlags.inferedFromUse) {
        message.info.inferedType(self.expectedType.asConst());
    }
}

const Message = @import("Message.zig");
const Typing = @import("../Typing/mod.zig");

const Parser = @import("../Parser/mod.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
