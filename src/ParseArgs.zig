const std = @import("std");
const Logger = @import("Logger.zig");
const util = @import("Util.zig");
const clap = @import("clap");

pub const SubCommand = enum {
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
            .Run => "",
            .Build => "",
            .Interpret => @panic("Interprete file should not generate a file"),
            .Lexer => "lex",
            .Parser => "parse",
            .TypeCheck => "check",
            .IntermediateRepresentation => "ir",
        };
    }
};

pub const Command = enum {
    const Self = @This();

    run,
    build,
    sim,
    lex,
    parse,
    check,
    ir,

    pub fn toSubCommand(self: Self) SubCommand {
        return switch (self) {
            .run => SubCommand.Run,
            .build => SubCommand.Build,
            .sim => SubCommand.Interpret,
            .lex => SubCommand.Lexer,
            .parse => SubCommand.Parser,
            .check => SubCommand.TypeCheck,
            .ir => SubCommand.IntermediateRepresentation,
        };
    }
};

pub const Arguments = struct {
    stdout: bool = false,
    silence: bool = false,

    subCom: SubCommand = .Build,
    path: []const u8,
};

const parser = .{
    .command = clap.parsers.enumeration(Command),
    .filePath = clap.parsers.string,
};

const params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\-s, --silence  No output from the compiler except errors.
    \\-p, --stdout  Insted of creating a file it prints the content.
    \\ <command>  not optional [run|build|sim|lex|parse|check|ir]
    \\ <filePath> not optional
    \\
);

pub fn getArguments(allocator: std.mem.Allocator) Arguments {
    var diag = clap.Diagnostic{};
    const res = clap.parse(clap.Help, &params, parser, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch {
        clap.help(std.io.getStdOut().writer(), clap.Help, &params, .{}) catch {};
        std.process.exit(1);
    };

    if (res.positionals[0] == null or res.positionals[1] == null or res.args.help != 0) {
        clap.help(std.io.getStdOut().writer(), clap.Help, &params, .{}) catch {};
        std.process.exit(0);
    }

    return Arguments{
        .stdout = res.args.stdout != 0,
        .silence = res.args.silence != 0,

        .subCom = res.positionals[0].?.toSubCommand(),
        .path = res.positionals[1].?,
    };
}
