const std = @import("std");
const Result = @import("Result.zig");
const diffz = @import("diffz");

alloc: std.mem.Allocator,

args: []const []const u8 = undefined,
stdin: []const u8 = undefined,
returnCode: i64 = undefined,
stdout: []const u8 = undefined,
stderr: []const u8 = undefined,

buff: [128]u8 = undefined,

filePath: []const u8,
file: std.fs.File,

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

    const self: @This() = .{
        .alloc = alloc,

        .args = args,
        .stdin = stdin,
        .returnCode = returnCode,
        .stdout = stdout,
        .stderr = stderr,

        .file = fileAnswer.?,
        .filePath = fileAbs,
    };

    return self;
}

pub fn deinit(self: *@This()) void {
    self.file.close();
}

pub fn initFromFile(
    alloc: std.mem.Allocator,
    fileAbs: []const u8,
) !@This() {
    const fileAnswer = std.fs.openFileAbsolute(fileAbs, .{ .mode = .read_write }) catch {
        return @This(){
            .alloc = alloc,

            .args = &[_][]const u8{},
            .stdin = "",
            .returnCode = 0,
            .stdout = "",
            .stderr = "",

            .filePath = fileAbs,
            .file = undefined,
        };
    };

    var self = @This(){
        .alloc = alloc,

        .file = fileAnswer,
        .filePath = fileAbs,
    };

    try self.readTest();

    return self;
}

pub fn readTest(self: *@This()) !void {
    var r = self.file.reader(&self.buff);

    const size = try self.readInteger("argc", &r.interface);
    var args = try self.alloc.alloc([]u8, @intCast(size));

    for (0..@intCast(size)) |i| {
        args[i] = try self.readBlob(try std.fmt.allocPrint(self.alloc, "arg{}", .{i}), &r.interface);
    }

    self.args = args;

    self.stdin = try self.readBlob("stdin", &r.interface);

    self.returnCode = try self.readInteger("returncode", &r.interface);

    self.stdout = try self.readBlob("stdout", &r.interface);

    self.stderr = try self.readBlob("stderr", &r.interface);
}

pub fn saveTest(self: *@This()) !void {
    var w = self.file.writer(&self.buff);
    try self.writeInteger("argc", @intCast(self.args.len), &w.interface);

    for (self.args, 0..) |arg, i| {
        try self.writeBlob(try std.fmt.allocPrint(self.alloc, "arg{}", .{i}), arg, &w.interface);
    }

    try self.writeBlob("stdin", self.stdin, &w.interface);

    try self.writeInteger("returncode", self.returnCode, &w.interface);

    try self.writeBlob("stdout", self.stdout, &w.interface);

    try self.writeBlob("stderr", self.stderr, &w.interface);
}

fn writeBlob(self: *@This(), name: []const u8, blob: []const u8, w: *std.io.Writer) !void {
    _ = .{self};
    try w.print(":b {s} {}\n{s}\n", .{ name, blob.len, blob });
}

fn writeInteger(self: *@This(), name: []const u8, integer: i64, w: *std.io.Writer) !void {
    _ = .{self};
    try w.print(":i {s} {}\n", .{ name, integer });
}

fn readInteger(self: *@This(), name: []const u8, r: *std.io.Reader) !i64 {
    var w = std.io.Writer.Allocating.init(self.alloc);
    defer w.deinit();

    _ = try r.streamDelimiter(&w.writer, '\n');
    const line = w.written();

    _ = try r.takeByte();

    const field = try std.fmt.allocPrint(self.alloc, ":i {s} ", .{name});
    std.debug.assert(std.mem.startsWith(u8, line, field));
    return try std.fmt.parseInt(i64, line[field.len..], 10);
}

fn readBlob(self: *@This(), name: []const u8, r: *std.io.Reader) ![]u8 {
    var w = std.io.Writer.Allocating.init(self.alloc);

    _ = try r.streamDelimiter(&w.writer, '\n');
    const line = w.written();
    w.clearRetainingCapacity();

    std.debug.assert(try r.takeByte() == '\n');

    const field = try std.fmt.allocPrint(self.alloc, ":b {s} ", .{name});
    std.debug.assert(std.mem.startsWith(u8, line, field));

    const size = try std.fmt.parseInt(u64, line[field.len..], 10);

    try r.streamExact64(&w.writer, size);

    var arr = w.toArrayList();
    const buf = try arr.toOwnedSlice(self.alloc);

    std.debug.assert(buf.len == size);
    std.debug.assert(try r.takeByte() == '\n');

    return buf;
}

pub fn compare(expected: *@This(), actual: *@This()) !Result {
    var result = Result{
        .type = .Success,
    };

    if (expected.returnCode != actual.returnCode) {
        result.returnCodeDiff = .{ expected.returnCode, actual.returnCode };
    }

    const diffStdout = try diffz.diff(diffz.default, expected.alloc, expected.stdout, actual.stdout, true);
    result.stdout = if (diffStdout.items.len == 0 or (diffStdout.items.len == 1 and diffStdout.items[0].operation == .equal)) null else @as(?std.ArrayListUnmanaged(diffz.Diff), diffStdout);

    const diffStderr = try diffz.diff(diffz.default, expected.alloc, expected.stderr, actual.stderr, true);
    result.stderr = if (diffStderr.items.len == 0 or (diffStderr.items.len == 1 and diffStderr.items[0].operation == .equal)) null else @as(?std.ArrayListUnmanaged(diffz.Diff), diffStderr);

    if (result.returnCodeDiff != null or result.stdout != null or result.stderr != null) result.type = .Error;

    return result;
}
