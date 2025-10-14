const std = @import("std");

pub const SubCommand = enum(usize) {
    Lexer = 0,
    Parser,
    Check,
    Ir,
    Build,
    Run,
    Interprete,
    All,

    pub fn toSubCommnad(self: @This()) ![]const u8 {
        return switch (self) {
            .Lexer => "lex",
            .Parser => "parse",
            .Check => error.NotYet,
            .Ir => error.NotYet,
            .Build => error.NotYet,
            .Interprete => error.NotYet,
            .Run => error.NotYet,
            .All => @panic("Should not do this"),
        };
    }

    pub fn toString(self: @This()) []const u8 {
        return switch (self) {
            .Lexer => "Lexer",
            .Parser => "Parser",
            .Check => "Type Check",
            .Ir => "Intermediate Representation",
            .Build => "Build (Assembly)",
            .Interprete => "ByteCode",
            .Run => "Program Executed",
            .All => @panic("Should not do this"),
        };
    }

    pub fn toEnum(name: []const u8) @This() {
        if (std.mem.eql(u8, "lexer", name)) return .Lexer;
        if (std.mem.eql(u8, "parser", name)) return .Parser;
        if (std.mem.eql(u8, "check", name)) return .Check;
        if (std.mem.eql(u8, "ir", name)) return .Ir;
        if (std.mem.eql(u8, "build", name)) return .Build;
        if (std.mem.eql(u8, "inter", name)) return .Interprete;
        if (std.mem.eql(u8, "run", name)) return .Run;
        if (std.mem.eql(u8, "all", name)) return .All;
        unreachable;
    }

    pub fn toType(self: @This(), t: type) t {
        return @intFromEnum(self);
    }
};
