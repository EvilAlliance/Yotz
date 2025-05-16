const std = @import("std");
const Logger = @import("Logger.zig");
const util = @import("Util.zig");

pub const Arguments = struct {
    build: bool = false,
    stdout: bool = false,
    run: bool = false,
    simulation: bool = false,
    lex: bool = false,
    parse: bool = false,
    check: bool = false,
    ir: bool = false,
    silence: bool = false,
    bench: bool = false,
    path: []const u8,
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
        args.build = true;
    } else if (std.mem.eql(u8, subcommand, "run")) {
        args.run = true;
    } else if (std.mem.eql(u8, subcommand, "sim")) {
        args.simulation = true;
    } else if (std.mem.eql(u8, subcommand, "lex")) {
        args.lex = true;
    } else if (std.mem.eql(u8, subcommand, "parse")) {
        args.parse = true;
    } else if (std.mem.eql(u8, subcommand, "check")) {
        args.check = true;
    } else if (std.mem.eql(u8, subcommand, "ir")) {
        args.ir = true;
    } else {
        args.build = true;
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
