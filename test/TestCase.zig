const std = @import("std");
const Result = @import("Result.zig");
const Diffz = @import("DiffMatchPatch.zig");

alloc: std.mem.Allocator,

args: []const []const u8 = undefined,
stdin: []const u8 = undefined,
returnCode: i64 = undefined,
stdout: []const u8 = undefined,
stderr: []const u8 = undefined,

file: std.fs.File,
w: std.fs.File.Writer,
r: std.fs.File.Reader,

pub fn init(
    alloc: std.mem.Allocator,
    fileAbs: []const u8,
    args: []const []const u8,
    stdin: []const u8,
    returnCode: i64,
    stdout: []const u8,
    stderr: []const u8,
) @This() {
    var fileAnswer = std.fs.openFileAbsolute(fileAbs, .{ .mode = .read_write }) catch null;
    if (fileAnswer == null) {
        std.fs.makeDirAbsolute(fileAbs[0..std.mem.lastIndexOf(u8, fileAbs, "/").?]) catch |e| {
            switch (e) {
                error.PathAlreadyExists => {},
                else => @panic("Could not create a tests directory"),
            }
        };
        fileAnswer = std.fs.createFileAbsolute(fileAbs, .{ .read = true }) catch @panic("Could not create file to store test");
    }

    return .{
        .alloc = alloc,

        .args = args,
        .stdin = stdin,
        .returnCode = returnCode,
        .stdout = stdout,
        .stderr = stderr,

        .file = fileAnswer.?,
        .w = fileAnswer.?.writer(),
        .r = fileAnswer.?.reader(),
    };
}

pub fn deinit(self: *@This()) void {
    self.file.close();
}

pub fn initFromFile(
    alloc: std.mem.Allocator,
    fileAbs: []const u8,
) !@This() {
    var fileAnswer = std.fs.openFileAbsolute(fileAbs, .{ .mode = .read_write }) catch {
        return @This(){
            .alloc = alloc,

            .args = &[_][]const u8{},
            .stdin = "",
            .returnCode = 0,
            .stdout = "",
            .stderr = "",

            .file = undefined,
            .w = undefined,
            .r = undefined,
        };
    };

    var self = @This(){
        .alloc = alloc,

        .file = fileAnswer,
        .w = fileAnswer.writer(),
        .r = fileAnswer.reader(),
    };

    try self.readTest();

    return self;
}

pub fn readTest(self: *@This()) !void {
    const size = try self.readInteger("argc");
    var args = try self.alloc.alloc([]u8, @intCast(size));

    for (0..@intCast(size)) |i| {
        args[i] = try self.readBlob(try std.fmt.allocPrint(self.alloc, "arg{}", .{i}));
    }
    self.args = args;

    self.stdin = try self.readBlob("stdin");

    self.returnCode = try self.readInteger("returncode");

    self.stdout = try self.readBlob("stdout");

    self.stderr = try self.readBlob("stderr");
}

pub fn saveTest(self: *@This()) !void {
    try self.writeInteger("argc", @intCast(self.args.len));

    for (self.args, 0..) |arg, i| {
        try self.writeBlob(try std.fmt.allocPrint(self.alloc, "arg{}", .{i}), arg);
    }

    try self.writeBlob("stdin", self.stdin);

    try self.writeInteger("returncode", self.returnCode);

    try self.writeBlob("stdout", self.stdout);

    try self.writeBlob("stderr", self.stderr);
}

fn writeBlob(self: *@This(), name: []const u8, blob: []const u8) !void {
    try self.w.print(":b {s} {}\n{s}\n", .{ name, blob.len, blob });
}

fn writeInteger(self: *@This(), name: []const u8, integer: i64) !void {
    try self.w.print(":i {s} {}\n", .{ name, integer });
}

fn readInteger(self: *@This(), name: []const u8) !i64 {
    const line = try self.r.readUntilDelimiterAlloc(self.alloc, '\n', std.math.maxInt(usize));
    const field = try std.fmt.allocPrint(self.alloc, ":i {s} ", .{name});
    std.debug.assert(std.mem.startsWith(u8, line, field));
    return try std.fmt.parseInt(i64, line[field.len..], 10);
}

fn readBlob(self: *@This(), name: []const u8) ![]u8 {
    const line = try self.r.readUntilDelimiterAlloc(self.alloc, '\n', std.math.maxInt(usize));
    const field = try std.fmt.allocPrint(self.alloc, ":b {s} ", .{name});
    std.debug.assert(std.mem.startsWith(u8, line, field));

    const size = try std.fmt.parseInt(i64, line[field.len..], 10);

    const buf = try self.alloc.alloc(u8, @intCast(size));
    const read = try self.r.read(buf);

    std.debug.assert(read == size);
    std.debug.assert(try self.r.readByte() == '\n');

    return buf;
}

pub fn compare(expected: *@This(), actual: *@This()) !Result {
    var result = Result{
        .type = .Success,
    };

    if (expected.returnCode != actual.returnCode) {
        result.returnCodeDiff = .{ expected.returnCode, actual.returnCode };
    }

    const diffStdout = try Diffz.diff(Diffz.default, expected.alloc, expected.stdout, actual.stdout, true);
    result.stdout = if (diffStdout.items.len == 0 or (diffStdout.items.len == 1 and diffStdout.items[0].operation == .equal)) null else @as(?std.ArrayListUnmanaged(Diffz.Diff), diffStdout);

    const diffStderr = try Diffz.diff(Diffz.default, expected.alloc, expected.stderr, actual.stderr, true);
    result.stderr = if (diffStderr.items.len == 0 or (diffStderr.items.len == 1 and diffStderr.items[0].operation == .equal)) null else @as(?std.ArrayListUnmanaged(Diffz.Diff), diffStderr);

    if (result.returnCodeDiff != null or result.stdout != null or result.stderr != null) result.type = .Error;

    return result;
}
