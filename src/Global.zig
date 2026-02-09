const Self = @This();
pub const FileInfo = struct { path: []const u8, source: [:0]const u8 };
pub const Args = struct { *TranslationUnit, Allocator, Parser.NodeIndex, *const Parser.Node.Types, ?*Report.Reports };

threadPool: Thread.Pool = undefined,
observer: Observer.Multiple(usize, Args, struct {
    pub fn init(self: @This(), arg: *Args) void {
        _ = self;
        _ = arg;
    }

    pub fn deinit(self: @This(), arg: Args, runned: bool) void {
        _ = self;
        const tu, const alloc, _, _, const reports = arg;

        if (!runned) {
            @panic("What to do");
        }

        tu.deinit(alloc, reports);
        alloc.destroy(tu);
    }
}) = .{},
readyTu: ArrayListThreadSafe(Atomic(bool)) = .{},

subCommand: ParseArgs.SubCommand,

files: ArrayListThreadSafe(FileInfo) = .{},
tokens: Lexer.Tokens = .{},
nodes: Parser.NodeList = .{},

pub fn init(self: *Self, alloc: Allocator, threads: usize) !void {
    try self.threadPool.init(.{
        .allocator = alloc,
        .n_jobs = threads,
    });
    self.observer.init(&self.threadPool);
}

pub fn addFile(self: *Self, alloc: Allocator, path: []const u8) Allocator.Error!bool {
    const realPath, const source = Util.readEntireFile(alloc, path) catch |err| {
        switch (err) {
            error.couldNotResolvePath => std.log.err("Could not resolve path: {s}\n", .{path}),
            error.couldNotOpenFile => std.log.err("Could not open file: {s}\n", .{path}),
            error.couldNotReadFile => std.log.err("Could not read file: {s}]n", .{path}),
            error.couldNotGetFileSize => std.log.err("Could not get file ({s}) size\n", .{path}),
        }
        return false;
    };

    const file = FileInfo{ .path = realPath, .source = source };

    const index = try self.files.appendIndex(alloc, file);

    try Lexer.lex(alloc, &self.tokens, file.source, @intCast(index));

    return true;
}

pub fn deinitStage1(self: *Self, alloc: Allocator) void {
    self.threadPool.deinit();
    self.observer.deinit(alloc);
}

pub fn deinitStage2(self: *Self, alloc: Allocator) void {
    for (self.files.slice()) |f| {
        alloc.free(f.path);
        alloc.free(f.source);
    }

    self.files.deinit(alloc);
    self.tokens.deinit(alloc);
    self.nodes.deinit(alloc);
    self.readyTu.deinit(alloc);
    Typing.Expression.deinitStatic(alloc);
}

pub fn toStringToken(self: *Self, alloc: std.mem.Allocator) Allocator.Error![]const u8 {
    var al = std.ArrayList(u8){};
    defer self.tokens.unlock();

    for (self.tokens.slice()) |value| {
        const fileInfo = self.files.get(value.loc.source);
        try value.toString(alloc, &al, fileInfo.path, fileInfo.source);
    }

    return al.toOwnedSlice(alloc);
}

const TranslationUnit = @import("TranslationUnit.zig");
const Lexer = @import("Lexer/mod.zig");
const ParseArgs = @import("ParseArgs.zig");
const Parser = @import("Parser/mod.zig");
const Typing = @import("Typing/mod.zig");
const Report = @import("Report/mod.zig");
const ArrayListThreadSafe = @import("Util/ArrayListThreadSafe.zig").ArrayListThreadSafe;
const Util = @import("Util.zig");
const Observer = @import("Util/Observer.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Atomic = std.atomic.Value;
const assert = std.debug.assert;
