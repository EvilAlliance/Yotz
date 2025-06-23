const std = @import("std");

const Lexer = @import("./Lexer/Lexer.zig");

pub var silence = false;

pub fn placeSlice(location: Lexer.Location, content: [:0]const u8) []const u8 {
    _ = location;
    _ = content;
    unreachable;
}

pub const logLocation = struct {
    pub fn info(path: []const u8, location: Lexer.Location, comptime format: []const u8, args: anytype) void {
        l(.info, path, location, format, args);
    }
    pub fn warn(path: []const u8, location: Lexer.Location, comptime format: []const u8, args: anytype) void {
        l(.warn, path, location, format, args);
    }
    pub fn err(path: []const u8, location: Lexer.Location, comptime format: []const u8, args: anytype) void {
        l(.err, path, location, format, args);
    }
    pub fn debug(path: []const u8, location: Lexer.Location, comptime format: []const u8, args: anytype) void {
        l(.debug, path, location, format, args);
    }

    fn l(comptime message_level: std.log.Level, path: []const u8, location: Lexer.Location, comptime format: []const u8, args: anytype) void {
        if (silence and message_level != .err) return;
        const level_txt = comptime switch (message_level) {
            .info => "[INFO]",
            .warn => "[WARNING]",
            .err => "[ERROR]",
            .debug => "[DEBUG]",
        };

        const stderr = std.io.getStdErr().writer();
        var bw = std.io.bufferedWriter(stderr);
        const writer = bw.writer();

        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        nosuspend {
            writer.print("{s}:{}:{} ", .{ path, location.row, location.col }) catch return;
            writer.print(level_txt ++ ": " ++ format ++ "\n", args) catch return;
            bw.flush() catch return;
        }
        unreachable;
    }
};

pub const log = struct {
    pub fn info(comptime format: []const u8, args: anytype) void {
        l(.info, format, args);
    }
    pub fn warn(comptime format: []const u8, args: anytype) void {
        l(.warn, format, args);
    }
    pub fn err(comptime format: []const u8, args: anytype) void {
        l(.err, format, args);
    }
    pub fn debug(comptime format: []const u8, args: anytype) void {
        l(.debug, format, args);
    }

    fn l(comptime message_level: std.log.Level, comptime format: []const u8, args: anytype) void {
        if (silence and message_level != .err) return;
        const level_txt = comptime switch (message_level) {
            .info => "[INFO]",
            .warn => "[WARNING]",
            .err => "[ERROR]",
            .debug => "[DEBUG]",
        };

        const stderr = std.io.getStdErr().writer();
        var bw = std.io.bufferedWriter(stderr);
        const writer = bw.writer();

        std.debug.lockStdErr();
        defer std.debug.unlockStdErr();
        nosuspend {
            writer.print(level_txt ++ ": " ++ format ++ "\n", args) catch return;
            bw.flush() catch return;
        }
    }
};
