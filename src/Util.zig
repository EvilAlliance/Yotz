const std = @import("std");

pub fn Result(comptime Success: type, comptime Error: type) type {
    return union(enum) {
        err: Error,
        ok: Success,

        pub fn Err(e: Error) Result(Success, Error) {
            return Result(Success, Error){ .err = e };
        }

        pub fn Ok(s: Success) Result(Success, Error) {
            return Result(Success, Error){ .ok = s };
        }
    };
}

pub fn listContains(t: type, l: []const t, e: t) bool {
    for (l) |s| {
        if (e == s) {
            return true;
        }
    }
    return false;
}

pub fn dupe(allocator: std.mem.Allocator, value: anytype) std.mem.Allocator.Error!*@TypeOf(value) {
    const new_pointer = try allocator.create(@TypeOf(value));
    new_pointer.* = value;
    return new_pointer;
}

pub fn ErrorPayLoad(comptime Error: type, comptime PayLoad: type) type {
    return struct {
        err: Error,
        payload: PayLoad,

        pub fn init(err: Error, payload: PayLoad) ErrorPayLoad(Error, PayLoad) {
            return ErrorPayLoad(Error, PayLoad){ .err = err, .payload = payload };
        }
    };
}

pub const ReadingFileError = error{
    couldNotOpenFile,
    couldNotGetFileSize,
    couldNotReadFile,
    couldNotGetAbsolutePath,
    couldNotResolvePath,
};

// First absPath, second data of file
pub fn readEntireFile(alloc: std.mem.Allocator, path: []const u8) ReadingFileError!struct { []const u8, []const u8, [:0]const u8 } {
    const resolvedPath = std.fs.path.resolve(alloc, &.{path}) catch return error.couldNotResolvePath;
    const abspath = std.fs.realpathAlloc(alloc, path) catch return error.couldNotGetAbsolutePath;
    const f = std.fs.openFileAbsolute(abspath, .{ .mode = .read_only }) catch return error.couldNotOpenFile;
    defer f.close();
    const file_size = f.getEndPos() catch return error.couldNotGetFileSize;
    const max_bytes: usize = @intCast(file_size + 1);
    const c = f.readToEndAllocOptions(alloc, max_bytes, max_bytes, 1, 0) catch return error.couldNotReadFile;

    return .{ abspath, resolvedPath, c };
}
