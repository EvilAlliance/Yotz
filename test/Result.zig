const std = @import("std");
const Diffz = @import("DiffMatchPatch.zig");

pub const Type = enum {
    NotYet,
    NotCompiled,
    Compiled,
    Updated,
    Error,
    Success,
    Fail,
    Unknown,

    pub fn toStringSingle(self: @This()) []const u8 {
        const red = "\x1b[31m";
        const green = "\x1b[32m";
        const yellow = "\x1b[33m";
        const blue = "\x1b[34m";
        const magenta = "\x1b[35m";
        const reset = "\x1b[0m";

        return switch (self) {
            .NotYet => yellow ++ "Y" ++ reset,
            .NotCompiled => blue ++ "N" ++ reset,
            .Compiled => yellow ++ "C" ++ reset,
            .Error => red ++ "E" ++ reset,
            .Fail => red ++ "F" ++ reset,
            .Success => green ++ "S" ++ reset,
            .Updated => green ++ "U" ++ reset,
            .Unknown => magenta ++ "U" ++ reset,
        };
    }
};

type: Type,
returnCodeDiff: ?struct { i64, i64 } = null,
stdout: ?std.ArrayListUnmanaged(Diffz.Diff) = null,
stderr: ?std.ArrayListUnmanaged(Diffz.Diff) = null,
