const std = @import("std");
const SubCommand = @import("SubCommand.zig").SubCommand;
const Test = @import("Test.zig");
const Tests = std.ArrayList(Test);

absolute: []const u8,
relative: []const u8,
subCommand: SubCommand,
alloc: std.mem.Allocator,
pool: *std.Thread.Pool,
generateCheck: bool,
tests: *Tests,

pub fn init(alloc: std.mem.Allocator, abs: []const u8, rel: []const u8, pool: *std.Thread.Pool, tests: *Tests, subCommand: SubCommand, generateCheck: bool) @This() {
    return .{
        .pool = pool,

        .alloc = alloc,

        .absolute = abs,
        .relative = rel,

        .tests = tests,
        .subCommand = subCommand,
        .generateCheck = generateCheck,
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

    const index = self.tests.items.len;
    self.tests.append(.{ .file = self }) catch return;

    inline for (@typeInfo(SubCommand).@"enum".fields) |falseValue| {
        const value: SubCommand = @enumFromInt(falseValue.value);

        if (value != .All) {
            if (self.subCommand == .All or value != self.subCommand) {
                const testStoragePath = std.fmt.allocPrint(self.alloc, "{s}.{s}/{s}", .{ self.absolute[0 .. storageIndex + 1], self.absolute[storageIndex + 1 .. extensionIndex], falseValue.name }) catch return;

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
                    ) catch return;
                } else {
                    self.tests.items[index].results[@intFromEnum(value)] = .Unknown;
                }
            } else {
                self.tests.items[index].results[@intFromEnum(value)] = .Unknown;
            }
        }
    }
    return;
}

fn testSubCommand(
    self: @This(),
    index: usize,
    subCommand: SubCommand,
    fileWithAnswer: []const u8,
) void {
    const command = [_][]const u8{
        "./zig-out/bin/yot",
        subCommand.toSubCommnad() catch {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .NotYet;
            return;
        },
        self.relative,
        "-s",
        "-stdout",
    };
    var exec = std.process.Child.init(&command, self.alloc);

    exec.stdout_behavior = .Pipe;
    exec.stderr_behavior = .Pipe;

    exec.spawn() catch return;

    var stdout: []u8 = undefined;
    var stderr: []u8 = undefined;

    stdout = exec.stdout.?.reader().readAllAlloc(self.alloc, std.math.maxInt(u64)) catch return;
    stderr = exec.stderr.?.reader().readAllAlloc(self.alloc, std.math.maxInt(u64)) catch return;

    const result = (exec.wait() catch return).Exited;

    if (self.generateCheck) {
        const fileAnswer = std.fs.openFileAbsolute(fileWithAnswer, .{ .mode = .read_write }) catch file: {
            std.fs.makeDirAbsolute(fileWithAnswer[0..std.mem.lastIndexOf(u8, fileWithAnswer, "/").?]) catch |e| {
                if (e != error.PathAlreadyExists) {
                    self.tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
                    return;
                }
            };

            break :file std.fs.createFileAbsolute(fileWithAnswer, .{ .read = true }) catch {
                self.tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
                return;
            };
        };

        defer fileAnswer.close();

        const w = fileAnswer.writer();

        // TODO: When args in cmd are implemented this must be changed;
        w.print(":i argc 0\n", .{}) catch {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };
        // TODO: When stdin in cmd are implemented this must be changed;
        w.print(":b stdin 0\n\n", .{}) catch {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };

        w.print(":i returncode {}\n", .{result}) catch {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };
        w.print(":b stdout {}\n{s}\n", .{ stdout.len, stdout }) catch {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };
        w.print(":b stderr {}\n{s}\n", .{ stderr.len, stderr }) catch {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Fail;
            return;
        };

        self.tests.items[index].results[@intFromEnum(subCommand)] = .Updated;
    } else {
        const fileAnswer = std.fs.openFileAbsolute(fileWithAnswer, .{ .mode = .read_write }) catch {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Error;
            return;
        };
        defer fileAnswer.close();

        const r = fileAnswer.reader();

        // TODO: When args in cmd are implemented this must be changed;
        r.skipBytes((":i argc 0\n").len, .{}) catch unreachable;

        // TODO: When stdin in cmd are implemented this must be changed;
        r.skipBytes((":b stdin 0\n\n").len, .{}) catch unreachable;

        r.skipBytes((":i returncode ").len, .{}) catch unreachable;

        var rc = r.readUntilDelimiterAlloc(self.alloc, '\n', std.math.maxInt(usize)) catch unreachable;
        const returnCode = std.fmt.parseInt(usize, rc, 10) catch unreachable;

        if (returnCode != result) {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Error;
            return;
        }

        self.tests.items[index].results[@intFromEnum(subCommand)] = .Success;

        r.skipBytes((":b stdout ").len, .{}) catch unreachable;
        rc = r.readUntilDelimiterAlloc(self.alloc, '\n', std.math.maxInt(usize)) catch unreachable;
        const stdoutLen = std.fmt.parseInt(usize, rc, 10) catch unreachable;
        rc = self.alloc.alloc(u8, stdoutLen) catch unreachable;
        _ = r.read(rc) catch unreachable;
        r.skipBytes(1, .{}) catch unreachable;

        if (!std.mem.eql(u8, rc, stdout)) {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Error;
            return;
        }

        r.skipBytes((":b stderr ").len, .{}) catch unreachable;
        rc = r.readUntilDelimiterAlloc(self.alloc, '\n', std.math.maxInt(usize)) catch unreachable;
        const stderrLen = std.fmt.parseInt(usize, rc, 10) catch unreachable;
        rc = self.alloc.alloc(u8, stderrLen) catch unreachable;
        _ = r.read(rc) catch unreachable;
        r.skipBytes(1, .{}) catch unreachable;

        if (!std.mem.eql(u8, rc, stderr)) {
            self.tests.items[index].results[@intFromEnum(subCommand)] = .Error;
            return;
        }
    }

    return;
}
