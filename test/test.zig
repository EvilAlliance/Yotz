const std = @import("std");

fn buildZig(alloc: std.mem.Allocator) !bool {
    std.debug.print("Trying to compile Yotz\n", .{});

    const command = [_][]const u8{ "zig", "build" };
    var exec = std.process.Child.init(&command, alloc);

    exec.stdout_behavior = .Pipe;
    exec.stderr_behavior = .Pipe;

    try exec.spawn();

    var stdout: []u8 = undefined;
    var stderr: []u8 = undefined;

    stdout = try exec.stdout.?.reader().readAllAlloc(alloc, std.math.maxInt(u64));
    stderr = try exec.stderr.?.reader().readAllAlloc(alloc, std.math.maxInt(u64));

    const result = try exec.wait();
    if (switch (result) {
        .Exited => |e| e != 0,
        else => true,
    }) {
        switch (result) {
            .Exited => |e| std.debug.print("Exited with {}\n", .{e}),
            .Signal => |e| std.debug.print("Signal with {}\n", .{e}),
            .Stopped => |e| std.debug.print("Stopped with {}\n", .{e}),
            .Unknown => |e| std.debug.print("Unknown with {}\n", .{e}),
        }

        std.debug.print("stderr:\n {s}", .{stderr});
        std.debug.print("stdout:\n {s}", .{stdout});

        return false;
    }

    return true;
}

const Result = enum {
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

const SubCommand = enum(usize) {
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
            .Check => "check",
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
};

const Test = struct {
    file: File,
    results: [@typeInfo(SubCommand).@"enum".fields.len]Result = undefined,
};

const Tests = std.ArrayList(Test);

const File = struct {
    absolute: []const u8,
    relative: []const u8,

    fn init(abs: []const u8, rel: []const u8) @This() {
        return .{ .absolute = abs, .relative = rel };
    }
};

fn testSubCommand(
    alloc: std.mem.Allocator,
    tests: *Tests,
    file: File,
    subCommand: SubCommand,
    index: usize,
    generateCheck: bool,
    fileWithAnswer: []const u8,
) void {
    const command = [_][]const u8{
        "./zig-out/bin/yot",
        subCommand.toSubCommnad() catch {
            tests.items[index].results[@intFromEnum(subCommand)] = .NotYet;
            return;
        },
        file.relative,
        "-s",
        "-stdout",
    };
    var exec = std.process.Child.init(&command, alloc);

    exec.stdout_behavior = .Pipe;
    exec.stderr_behavior = .Pipe;

    exec.spawn() catch return;

    var stdout: []u8 = undefined;
    var stderr: []u8 = undefined;

    stdout = exec.stdout.?.reader().readAllAlloc(alloc, std.math.maxInt(u64)) catch return;
    stderr = exec.stderr.?.reader().readAllAlloc(alloc, std.math.maxInt(u64)) catch return;

    const result = (exec.wait() catch return).Exited;

    if (generateCheck) {
        const fileAnswer = std.fs.openFileAbsolute(fileWithAnswer, .{ .mode = .read_write }) catch file: {
            std.fs.makeDirAbsolute(fileWithAnswer[0..std.mem.lastIndexOf(u8, fileWithAnswer, "/").?]) catch |e| {
                if (e != error.PathAlreadyExists) {
                    tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
                    return;
                }
            };

            break :file std.fs.createFileAbsolute(fileWithAnswer, .{ .read = true }) catch {
                tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
                return;
            };
        };

        defer fileAnswer.close();

        const w = fileAnswer.writer();

        // TODO: When args in cmd are implemented this must be changed;
        w.print(":i argc 0\n", .{}) catch {
            tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };
        // TODO: When stdin in cmd are implemented this must be changed;
        w.print(":b stdin 0\n\n", .{}) catch {
            tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };

        w.print(":i returncode {}\n", .{result}) catch {
            tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };
        w.print(":b stdout {}\n{s}\n", .{ stdout.len, stdout }) catch {
            tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };
        w.print(":b stderr {}\n{s}\n", .{ stderr.len, stderr }) catch {
            tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };

        tests.items[index].results[@intFromEnum(subCommand)] = .Updated;
    } else {
        const fileAnswer = std.fs.openFileAbsolute(fileWithAnswer, .{ .mode = .read_write }) catch {
            tests.items[index].results[@intFromEnum(subCommand)] = .Error;
            return;
        };
        defer fileAnswer.close();

        const r = fileAnswer.reader();

        // TODO: When args in cmd are implemented this must be changed;
        r.skipBytes((":i argc 0\n").len, .{}) catch unreachable;

        // TODO: When stdin in cmd are implemented this must be changed;
        r.skipBytes((":b stdin 0\n\n").len, .{}) catch unreachable;

        r.skipBytes((":i returncode ").len, .{}) catch unreachable;

        var rc = r.readUntilDelimiterAlloc(alloc, '\n', std.math.maxInt(usize)) catch unreachable;
        const returnCode = std.fmt.parseInt(usize, rc, 10) catch unreachable;

        if (returnCode != result) {
            tests.items[index].results[@intFromEnum(subCommand)] = .Error;
            return;
        }

        tests.items[index].results[@intFromEnum(subCommand)] = .Success;

        r.skipBytes((":b stdout ").len, .{}) catch unreachable;
        rc = r.readUntilDelimiterAlloc(alloc, '\n', std.math.maxInt(usize)) catch unreachable;
        const stdoutLen = std.fmt.parseInt(usize, rc, 10) catch unreachable;
        rc = alloc.alloc(u8, stdoutLen) catch unreachable;
        _ = r.read(rc) catch unreachable;
        r.skipBytes(1, .{}) catch unreachable;

        if (!std.mem.eql(u8, rc, stdout)) {
            tests.items[index].results[@intFromEnum(subCommand)] = .Error;
            return;
        }

        r.skipBytes((":b stderr ").len, .{}) catch unreachable;
        rc = r.readUntilDelimiterAlloc(alloc, '\n', std.math.maxInt(usize)) catch unreachable;
        const stderrLen = std.fmt.parseInt(usize, rc, 10) catch unreachable;
        rc = alloc.alloc(u8, stderrLen) catch unreachable;
        _ = r.read(rc) catch unreachable;
        r.skipBytes(1, .{}) catch unreachable;

        if (!std.mem.eql(u8, rc, stderr)) {
            tests.items[index].results[@intFromEnum(subCommand)] = .Error;
            return;
        }
    }

    return;
}

fn testFile(pool: *std.Thread.Pool, alloc: std.mem.Allocator, subCommand: SubCommand, tests: *Tests, generateCheck: bool, file: File) void {
    const storageIndex = std.mem.lastIndexOf(u8, file.absolute, "/").?;
    const extensionIndex = std.mem.lastIndexOf(u8, file.absolute, ".").?;
    if (std.mem.eql(u8, file.absolute[extensionIndex..], "yt")) unreachable;
    const index = tests.items.len;
    tests.append(.{
        .file = file,
    }) catch return;
    inline for (@typeInfo(SubCommand).@"enum".fields) |falseValue| {
        const value: SubCommand = @enumFromInt(falseValue.value);
        if (value != .All) {
            if (subCommand == .All or value != subCommand) {
                const testStoragePath = std.fmt.allocPrint(alloc, "{s}.{s}/{s}", .{ file.absolute[0 .. storageIndex + 1], file.absolute[storageIndex + 1 .. extensionIndex], falseValue.name }) catch return;

                const fileOP = std.fs.openFileAbsolute(testStoragePath, .{ .mode = .read_only }) catch null;
                if (fileOP != null or generateCheck) {
                    pool.spawn(
                        testSubCommand,
                        .{
                            alloc,
                            tests,
                            file,
                            value,
                            index,
                            generateCheck,
                            testStoragePath,
                        },
                    ) catch return;
                } else {
                    tests.items[index].results[@intFromEnum(value)] = .Unknown;
                }
            } else {
                tests.items[index].results[@intFromEnum(value)] = .Unknown;
            }
        }
    }
    return;
}

const Folder = struct {
    absolute: []const u8,
    relative: []const u8,

    fn init(abs: []const u8, rel: []const u8) @This() {
        return .{ .absolute = abs, .relative = rel };
    }
};

fn testFolder(pool: *std.Thread.Pool, alloc: std.mem.Allocator, subCommand: SubCommand, tests: *Tests, generateCheck: bool, folder: Folder) void {
    const children = std.fs.openDirAbsolute(folder.absolute, .{
        .access_sub_paths = true,
        .iterate = true,
    }) catch return;

    var iterator = children.iterate();

    while (iterator.next() catch return) |child| {
        switch (child.kind) {
            .directory => {
                if (child.name[0] == '.') continue;
                pool.spawn(testFolder, .{
                    pool,
                    alloc,
                    subCommand,
                    tests,
                    generateCheck,
                    Folder.init(
                        std.fmt.allocPrint(alloc, "{s}/{s}", .{ folder.absolute, child.name }) catch return,
                        std.fmt.allocPrint(alloc, "{s}/{s}", .{ folder.relative, child.name }) catch return,
                    ),
                }) catch return;
            },
            .file => pool.spawn(testFile, .{
                pool,
                alloc,
                subCommand,
                tests,
                generateCheck,
                File.init(
                    std.fmt.allocPrint(alloc, "{s}/{s}", .{ folder.absolute, child.name }) catch return,
                    std.fmt.allocPrint(alloc, "{s}/{s}", .{ folder.relative, child.name }) catch return,
                ),
            }) catch return,
            else => std.debug.print("Not handle kind {} \n", .{child.kind}),
        }
    }
}

fn testInit(
    alloc: std.mem.Allocator,
    FolderOrFile: []const u8,
    subCommand: SubCommand,
    generateCheck: bool,
    result: *Tests,
) void {
    var pool: std.Thread.Pool = undefined;
    pool.init(.{
        .allocator = alloc,
        .n_jobs = 12,
    }) catch return;

    const absPath = std.fs.realpathAlloc(alloc, FolderOrFile) catch return;

    const isFolder = std.fs.openDirAbsolute(absPath, .{});

    if (isFolder) |_| {
        pool.spawn(
            testFolder,
            .{
                &pool,
                alloc,
                subCommand,
                result,
                generateCheck,
                Folder.init(
                    absPath,
                    FolderOrFile,
                ),
            },
        ) catch return;
    } else |_| {
        pool.spawn(
            testFile,
            .{
                &pool,
                alloc,
                subCommand,
                result,
                generateCheck,
                File.init(
                    absPath,
                    FolderOrFile,
                ),
            },
        ) catch return;
    }

    pool.deinit();
}

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

    if (!try buildZig(alloc)) return 1;

    var argIterator = try std.process.ArgIterator.initWithAllocator(alloc);
    _ = argIterator.next();
    const firstArg = argIterator.next() orelse "run";

    var result = Tests.init(alloc);
    result.deinit();

    if (std.mem.eql(u8, "update", firstArg)) {
        const subsubcommand = argIterator.next() orelse "output";
        if (std.mem.eql(u8, "output", subsubcommand)) {
            const target = argIterator.next() orelse "Example";
            const subcommand = argIterator.next() orelse "all";
            testInit(alloc, target, SubCommand.toEnum(subcommand), true, &result);
        } else if (std.mem.eql(u8, "input", subsubcommand)) {
            @panic("Input unimplemented");
        } else {
            unreachable;
        }
    } else if (std.mem.eql(u8, "run", firstArg)) {
        const target = argIterator.next() orelse "Example";
        const subcommand = argIterator.next() orelse "all";
        testInit(alloc, target, SubCommand.toEnum(subcommand), false, &result);
    } else if (std.mem.eql(u8, "help", firstArg)) {
        std.debug.print(
            "Usage [SUBCOMAND]\n" ++
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
        testInit(alloc, "Example", .All, false, &result);
    }

    printTests(&result);

    return 0;
}

fn printTests(result: *Tests) void {
    var max: usize = 0;
    for (result.items) |value| {
        if (max < value.file.relative.len) max = value.file.relative.len;
    }

    for (result.items) |value| {
        std.debug.print("{s}", .{value.file.relative});
        for (0..max - value.file.relative.len + 2) |_| std.debug.print(" ", .{});

        for (value.results, 0..) |res, i| {
            if (i == @intFromEnum(SubCommand.All)) continue;
            std.debug.print("{s} ", .{res.toStringSingle()});
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
}
