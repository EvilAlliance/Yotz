pub const SubCommand = enum {
    const Self = @This();

    Run,
    Build,
    Interpret,
    Lexer,
    Parser,
    Typing,
    IntermediateRepresentation,

    pub fn getExt(self: Self) []const u8 {
        return switch (self) {
            .Run => "",
            .Build => "",
            .Interpret => @panic("Interprete should not generate a file"),
            .Lexer => "lex",
            .Parser => "parse",
            .Typing => "check",
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
            .check => SubCommand.Typing,
            .ir => SubCommand.IntermediateRepresentation,
        };
    }
};

pub const Arguments = struct {
    stdout: bool = false,

    subCom: SubCommand = .Build,
    path: []const u8,
};

const parser = .{
    .command = clap.parsers.enumeration(Command),
    .filePath = clap.parsers.string,
};

const params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    // \\-s, --silence  No output from the compiler except errors.
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
    }) catch |err| {
        clap.helpToFile(.stdout(), clap.Help, &params, .{}) catch {};
        diag.reportToFile(.stderr(), err) catch {};
        std.process.exit(1);
    };

    defer res.deinit();

    if (res.positionals[0] == null or res.positionals[1] == null or res.args.help != 0) {
        clap.helpToFile(.stdout(), clap.Help, &params, .{}) catch {};
        std.process.exit(0);
    }

    return Arguments{
        .stdout = res.args.stdout != 0,
        // .silence = res.args.silence != 0,

        .subCom = res.positionals[0].?.toSubCommand(),
        .path = res.positionals[1].?,
    };
}

const clap = @import("clap");

const std = @import("std");
