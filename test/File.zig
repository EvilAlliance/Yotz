const std = @import("std");
const SubCommand = @import("SubCommand.zig").SubCommand;
const Test = @import("Test.zig");
const TestCase = @import("TestCase.zig");
const Tests = std.ArrayList(Test);

var mutex = std.Thread.Mutex{};

absolute: []const u8,
relative: []const u8,
subCommand: SubCommand,
alloc: std.mem.Allocator,
pool: *std.Thread.Pool,
generateCheck: bool,
tests: *Tests,
coverage: bool,

pub fn init(alloc: std.mem.Allocator, abs: []const u8, rel: []const u8, pool: *std.Thread.Pool, tests: *Tests, subCommand: SubCommand, generateCheck: bool, coverage: bool) @This() {
    return .{
        .pool = pool,

        .alloc = alloc,

        .absolute = abs,
        .relative = rel,

        .tests = tests,
        .subCommand = subCommand,
        .generateCheck = generateCheck,

        .coverage = coverage,
    };
}

pub fn initCopy(self: @This(), abs: []const u8, rel: []const u8) @This() {
    self.relative = rel;
    self.absolute = abs;
    return self;
}

pub fn testIt(self: @This()) void {
    const storageIndex = std.mem.lastIndexOf(u8, self.absolute, "/").?;
    const extensionIndex = std.mem.lastIndexOf(u8, self.absolute, ".").?;

    if (std.mem.eql(u8, self.absolute[extensionIndex..], "yt")) unreachable;

    mutex.lock();
    const index = self.tests.items.len;
    self.tests.append(.{ .file = self }) catch @panic("Could not add the test to the list");
    mutex.unlock();

    inline for (@typeInfo(SubCommand).@"enum".fields) |falseValue| {
        const value: SubCommand = @enumFromInt(falseValue.value);

        if (value == .All) continue;
        if (self.subCommand == .All or value != self.subCommand) {
            const testStoragePath = std.fmt.allocPrint(self.alloc, "{s}.{s}/{s}", .{ self.absolute[0 .. storageIndex + 1], self.absolute[storageIndex + 1 .. extensionIndex], falseValue.name }) catch @panic("Could not form file were the test is saved");

            const fileOP = std.fs.openFileAbsolute(testStoragePath, .{ .mode = .read_only }) catch null;
            if (fileOP != null or self.generateCheck) {
                self.pool.spawn(
                    testSubCommand,
                    .{
                        self,
                        index,
                        value,
                        testStoragePath,
                    },
                ) catch @panic("Could not spawn a Thread in the pool");
            } else {
                self.tests.items[index].results[@intFromEnum(value)].type = .NotCompiled;
            }
        } else {
            self.tests.items[index].results[@intFromEnum(value)].type = .NotCompiled;
        }
    }
}

var i: usize = 0;
var mutexI = std.Thread.Mutex{};

fn testSubCommand(
    self: @This(),
    index: usize,
    subCommand: SubCommand,
    fileWithAnswer: []const u8,
) void {
    var expected = TestCase.initFromFile(self.alloc, fileWithAnswer) catch {
        self.tests.items[index].results[@intFromEnum(subCommand)].type = .Fail;
        return;
    };
    defer expected.deinit();

    mutexI.lock();
    i += 1;
    mutexI.unlock();

    std.debug.assert(expected.args.len == 0);

    const command = if (self.coverage and !self.generateCheck) &[_][]const u8{
        "kcov",
        "--include-path=./src/",
        "--collect-only",
        "--clean",
        std.fmt.allocPrint(self.alloc, ".test/{}", .{i}) catch return,
        "./zig-out/bin/yot",
        subCommand.toSubCommnad() catch {
            self.tests.items[index].results[@intFromEnum(subCommand)].type = .NotYet;
            return;
        },
        self.relative,
        "-s",
        "-stdout",
    } else &[_][]const u8{
        "./zig-out/bin/yot",
        subCommand.toSubCommnad() catch {
            self.tests.items[index].results[@intFromEnum(subCommand)].type = .NotYet;
            return;
        },
        self.relative,
        "-s",
        "-stdout",
    };
    var exec = std.process.Child.init(command, self.alloc);

    exec.stdin_behavior = .Pipe;
    exec.stdout_behavior = .Pipe;
    exec.stderr_behavior = .Pipe;

    exec.spawn() catch {
        self.tests.items[index].results[@intFromEnum(subCommand)].type = .Fail;
        return;
    };

    var stdout: []u8 = undefined;
    var stderr: []u8 = undefined;

    exec.stdin.?.writer().writeAll(expected.stdin) catch {
        self.tests.items[index].results[@intFromEnum(subCommand)].type = .Fail;
        return;
    };

    stdout = exec.stdout.?.reader().readAllAlloc(self.alloc, std.math.maxInt(u64)) catch {
        self.tests.items[index].results[@intFromEnum(subCommand)].type = .Fail;
        return;
    };

    stderr = exec.stderr.?.reader().readAllAlloc(self.alloc, std.math.maxInt(u64)) catch {
        self.tests.items[index].results[@intFromEnum(subCommand)].type = .Fail;
        return;
    };
    const result = (exec.wait() catch {
        self.tests.items[index].results[@intFromEnum(subCommand)].type = .Fail;
        return;
    }).Exited;

    var actual = TestCase.init(self.alloc, fileWithAnswer, &[0][]const u8{}, expected.stdin, result, stdout, stderr);
    defer actual.deinit();

    if (self.generateCheck) {
        actual.saveTest() catch {
            self.tests.items[index].results[@intFromEnum(subCommand)].type = .Fail;
            return;
        };

        self.tests.items[index].results[@intFromEnum(subCommand)].type = .Updated;
    } else {
        self.tests.items[index].results[@intFromEnum(subCommand)] = expected.compare(&actual) catch {
            self.tests.items[index].results[@intFromEnum(subCommand)].type = .Fail;
            return;
        };
    }
}
