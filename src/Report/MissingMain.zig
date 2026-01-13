pub fn display(self: @This(), message: Message) void {
    _ = self;
    message.err.mainFunctionMissing();
}

const Message = @import("Message.zig");
