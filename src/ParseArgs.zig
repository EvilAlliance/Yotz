const std = @import("std");
const Logger = @import("Logger.zig");
const util = @import("Util.zig");

pub const SubCommamd = enum {
    const Self = @This();

    Run,
    Build,
    Interpret,
    Lexer,
    Parser,
    TypeCheck,
    IntermediateRepresentation,

    pub fn getExt(self: Self) []const u8 {
        return switch (self) {
            .Run => @panic("Run should not generate file"),
            .Build => "",
            .Interpret => @panic("Interprete file should not generate a file"),
            .Lexer => "lex",
            .Parser => "parse",
            .TypeCheck => "check",
            .IntermediateRepresentation => "ir",
        };
    }
};

pub const Arguments = struct {
    stdout: bool = false,
    silence: bool = false,
    bench: bool = false,

    path: []const u8,

    subCom: SubCommamd = .Build,
};

const ArgumentsError = error{
    noSubcommandProvided,
    noFilePathProvided,
    unknownSubcommand,
    unknownArgument,
};

const ArgError = util.ErrorPayLoad(ArgumentsError, ?[]const u8);
const ArgumentResult = util.Result(Arguments, ArgError);

pub fn getArguments() ?Arguments {
    var args = std.BoundedArray([]const u8, 1024).init(0) catch unreachable;

    var argsIterator = std.process.args();

    _ = argsIterator.skip();

    while (argsIterator.next()) |arg| {
        args.append(arg) catch {
            Logger.log.err("Out of space, too many args, max = 1024. Change soruce code", .{});
            return null;
        };
    }

    const a: ArgumentResult = parseArguments(args.constSlice());
    switch (a) {
        .err => |err| {
            switch (err.err) {
                error.noSubcommandProvided => Logger.log.err("No subcommand provided\n", .{}),
                error.noFilePathProvided => Logger.log.err("No file provided\n", .{}),
                error.unknownSubcommand => Logger.log.err("Unknown subcommand {s}\n", .{err.payload.?}),
                error.unknownArgument => Logger.log.err("unknown argument {s}\n", .{err.payload.?}),
                else => unreachable,
            }
            return null;
        },
        .ok => {},
    }

    return a.ok;
}

fn parseArguments(args: []const []const u8) ArgumentResult {
    if (args.len == 0) {
        return ArgumentResult.Err(ArgError.init(error.noSubcommandProvided, null));
    } else if (args.len == 1) {
        return ArgumentResult.Err(ArgError.init(error.noFilePathProvided, null));
    }

    var a = Arguments{ .path = args[1] };

    parseSubcommand(args[0], &a) catch |err|
        return ArgumentResult.Err(ArgError.init(err, args[0]));

    const arguments = args[2..];

    for (arguments) |arg| {
        parseArgument(arg, &a) catch |err|
            return ArgumentResult.Err(ArgError.init(err, arg));
    }

    return ArgumentResult.Ok(a);
}

fn parseSubcommand(subcommand: []const u8, args: *Arguments) !void {
    if (std.mem.eql(u8, subcommand, "build")) {
        args.subCom = .Build;
    } else if (std.mem.eql(u8, subcommand, "run")) {
        args.subCom = .Run;
    } else if (std.mem.eql(u8, subcommand, "sim")) {
        args.subCom = .Interpret;
    } else if (std.mem.eql(u8, subcommand, "lex")) {
        args.subCom = .Lexer;
    } else if (std.mem.eql(u8, subcommand, "parse")) {
        args.subCom = .Parser;
    } else if (std.mem.eql(u8, subcommand, "check")) {
        args.subCom = .TypeCheck;
    } else if (std.mem.eql(u8, subcommand, "ir")) {
        args.subCom = .IntermediateRepresentation;
    } else {
        return error.unknownSubcommand;
    }
}

fn parseArgument(arg: []const u8, args: *Arguments) !void {
    if (std.mem.eql(u8, arg, "-b")) {
        args.bench = true;
    } else if (std.mem.eql(u8, arg, "-s")) {
        args.silence = true;
    } else if (std.mem.eql(u8, arg, "-stdout")) {
        args.stdout = true;
    } else {
        return error.unknownArgument;
    }
}
