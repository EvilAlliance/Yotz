const std = @import("std");

const Lexer = @import("./Lexer/Lexer.zig");

pub fn l(comptime message_level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const level_txt = comptime switch (message_level) {
        .info => "[INFO]",
        .warn => "[WARNING]",
        .err => "[ERROR]",
        .debug => "[DEBUG]",
    };

    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    var buffer: [256]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();
    nosuspend stderr.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
}
