const std = @import("std");
const diffz = @import("diffz");
const Folder = @import("Folder.zig");
const File = @import("File.zig");
const SubCommand = @import("SubCommand.zig").SubCommand;
const Result = @import("Result.zig").Result;
const Test = @import("Test.zig");

const Tests = std.ArrayList(Test);

fn cleanTestCoverage(alloc: std.mem.Allocator) !void {
    var childs = std.fs.cwd().openDir(".test", .{ .iterate = true }) catch folder: {
        try std.fs.cwd().makeDir(".test");

        break :folder try std.fs.cwd().openDir(".test", .{ .iterate = true });
    };

    defer childs.close();
    var it = childs.iterate();
    var arr = std.ArrayList([]const u8){};

    while (try it.next()) |child| {
        std.debug.assert(child.kind == .directory);
        try arr.append(alloc, try std.fs.path.join(alloc, &.{ ".test", child.name }));
    }

    const rmCommand = [_][]const u8{ "rm", "-r" };
    var rmExec = std.process.Child.init(try std.mem.concat(alloc, []const u8, &.{ &rmCommand, try arr.toOwnedSlice(alloc) }), alloc);

    rmExec.stdout_behavior = .Ignore;
    rmExec.stderr_behavior = .Ignore;

    try rmExec.spawn();
    _ = try rmExec.wait();
}

fn testInit(
    alloc: std.mem.Allocator,
    FolderOrFile: []const u8,
    subCommand: SubCommand,
    generateCheck: bool,
    coverage: bool,
    result: *Tests,
) void {
    var pool: std.Thread.Pool = undefined;
    pool.init(.{
        .allocator = alloc,
        .n_jobs = 20,
    }) catch return;

    const absPath = std.fs.realpathAlloc(alloc, FolderOrFile) catch return;
    const relative = std.fs.path.resolve(alloc, &.{FolderOrFile}) catch return;

    const isFolder = std.fs.openDirAbsolute(absPath, .{});

    if (isFolder) |_| {
        pool.spawn(
            Folder.testIt,
            .{
                Folder.init(
                    alloc,
                    absPath,
                    relative,
                    &pool,
                    &mutex,
                    result,
                    subCommand,
                    generateCheck,
                    coverage,
                ),
            },
        ) catch return;
    } else |_| {
        pool.spawn(
            File.testIt,
            .{
                File.init(
                    alloc,
                    absPath,
                    relative,
                    &pool,
                    &mutex,
                    result,
                    subCommand,
                    generateCheck,
                    coverage,
                ),
            },
        ) catch return;
    }

    pool.deinit();
}

var mutex = std.Thread.Mutex{};
var c = std.Thread.Mutex{};

pub fn main() !u8 {
    var generalPurpose: std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }) = .init;
    const gpa = generalPurpose.allocator();
    defer _ = generalPurpose.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var allocSafe = std.heap.ThreadSafeAllocator{
        .child_allocator = arena.allocator(),
        .mutex = std.Thread.Mutex{},
    };

    const alloc = allocSafe.allocator();

    try cleanTestCoverage(alloc);

    var argIterator = try std.process.ArgIterator.initWithAllocator(alloc);
    _ = argIterator.skip();
    const coverage = argIterator.next() orelse "run";
    const coverageBool = std.mem.eql(u8, "-coverage", coverage);
    const firstArg = if (coverageBool) argIterator.next() orelse "run" else coverage;
    var update = false;

    var result = Tests{};
    defer result.deinit(alloc);

    if (std.mem.eql(u8, "update", firstArg)) {
        const subsubcommand = argIterator.next() orelse "output";
        if (std.mem.eql(u8, "output", subsubcommand)) {
            const target = argIterator.next() orelse "Example";
            const subcommand = argIterator.next() orelse "all";
            update = true;
            testInit(alloc, target, SubCommand.toEnum(subcommand), true, coverageBool, &result);
        } else if (std.mem.eql(u8, "input", subsubcommand)) {
            @panic("Input unimplemented");
        } else {
            unreachable;
        }
    } else if (std.mem.eql(u8, "run", firstArg)) {
        const target = argIterator.next() orelse "Example";
        const subcommand = argIterator.next() orelse "all";
        testInit(alloc, target, SubCommand.toEnum(subcommand), false, coverageBool, &result);
    } else if (std.mem.eql(u8, "help", firstArg)) {
        std.debug.print(
            "Usage <-coverage> [SUBCOMAND]\n" ++
                "   Subcommand:\n" ++
                "     run <TARGET> <SUBCOMMAND>\n" ++
                "       Run the test on the [TARGET]. The [TARGET] is either a '*.yt' file or \n" ++
                "       folder with '*.yt' files. The default [TARGET] is '.yt'.\n" ++
                "       Subcommand\n" ++
                "         lexer\n" ++
                "         parser\n" ++
                "         check\n" ++
                "         ir\n" ++
                "         build\n" ++
                "         inter\n" ++
                "         run\n" ++
                "         all\n" ++
                "     update [SUBSUBCOMMAND]\n" ++
                "       SUBSUBCOMMAND\n" ++
                "         input <TARGET>\n" ++
                "           TARGET: Must be a '.yt' file\n" ++
                "         output <TARGET> <SUBCOMAND>\n" ++
                "           Must be a folder with .yt files or a .yt file\n" ++
                "           Subcommand\n" ++
                "              lexer\n" ++
                "              parser\n" ++
                "              check\n" ++
                "              ir\n" ++
                "              build\n" ++
                "              inter\n" ++
                "              run\n" ++
                "              all\n" ++
                "     help\n",
            .{},
        );
    } else {
        testInit(alloc, "Example", .All, false, coverageBool, &result);
    }

    var childs = std.fs.cwd().openDir(".test", .{ .iterate = true }) catch unreachable;
    defer childs.close();
    var it = childs.iterate();
    var arr: std.ArrayList([]const u8) = .{};

    while (try it.next()) |child| {
        std.debug.assert(child.kind == .directory);
        try arr.append(alloc, try std.fs.path.join(alloc, &.{ ".test", child.name }));
    }

    if (coverageBool and !update and result.items.len > 0) {
        const command = [_][]const u8{ "kcov", "--merge", ".test/merge" };
        var exec = std.process.Child.init(try std.mem.concat(alloc, []const u8, &.{ &command, try arr.toOwnedSlice(alloc) }), alloc);

        try exec.spawn();
        _ = try exec.wait();
    }

    printTests(alloc, &result);

    for (result.items) |case|
        for (case.results) |res|
            if (res.type == .Error) return 1;

    return 0;
}

fn printTests(alloc: std.mem.Allocator, result: *Tests) void {
    var max: usize = 0;
    for (result.items) |value| {
        if (max < value.file.relative.len) max = value.file.relative.len;
    }

    for (result.items) |value| {
        std.debug.print("{s}", .{value.file.relative});
        for (0..max - value.file.relative.len + 2) |_| std.debug.print(" ", .{});

        for (value.results, 0..) |res, i| {
            if (i == @intFromEnum(SubCommand.All)) continue;
            std.debug.print("{s} ", .{res.type.toStringSingle()});
        }

        std.debug.print("\n", .{});
    }

    const fields = @typeInfo(SubCommand).@"enum".fields;
    inline for (0..fields.len) |falseI| {
        const i = fields.len - falseI - 1;
        const falseValue = fields[i];
        const value: SubCommand = @enumFromInt(falseValue.value);

        if (value != .All) {
            for (0..max + 2) |_| std.debug.print(" ", .{});
            for (0..fields.len - falseI - 1) |_|
                std.debug.print("║ ", .{});

            std.debug.print("╚ {s}", .{value.toString()});
            std.debug.print("\n", .{});
        }
    }

    for (result.items) |value| {
        for (value.results) |res| {
            if (res.type != .Error) continue;

            std.debug.print("{s}: \n", .{value.file.relative});

            if (res.returnCodeDiff) |retCodes| {
                std.debug.print("Expected {}, Actaul {}\n", retCodes);
            }

            if (res.stdout) |stdout| {
                const text = diffz.diffPrettyFormatXTerm(alloc, stdout) catch @panic("Try again");
                std.debug.print("Stdout: \n{s}\n", .{text});
            }

            if (res.stderr) |stderror| {
                const text = diffz.diffPrettyFormatXTerm(alloc, stderror) catch @panic("Try Again");
                std.debug.print("Stderror: \n{s}\n", .{text});
            }
        }
    }
}
