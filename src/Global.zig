const Self = @This();
pub const FileInfo = struct { path: []const u8, source: [:0]const u8 };
pub const Args = struct { *TranslationUnit, Allocator, Parser.NodeIndex, *const Parser.Node, ?*Report.Reports };

threadPool: Thread.Pool = undefined,
observer: Observer.Multiple(usize, Args, struct {
    pub fn init(self: @This(), arg: *Args) void {
        _ = self;
        _ = arg;
    }

    pub fn deinit(self: @This(), arg: Args, runned: bool) void {
        _ = self;
        const tu, const alloc, _, _, _ = arg;

        if (!runned) {
            @panic("What to do");
        }

        tu.deinit(alloc);
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

pub fn toStringAst(self: *@This(), alloc: std.mem.Allocator, rootIndex: Parser.NodeIndex) std.mem.Allocator.Error![]const u8 {
    var cont = std.ArrayList(u8){};

    const root = self.nodes.get(rootIndex);

    var i = root.data[0].load(.acquire);
    while (i != 0) : (i = self.nodes.get(i).next.load(.acquire)) {
        try self.toStringVariable(alloc, &cont, 0, self.nodes.getPtr(i));

        if (self.nodes.get(self.nodes.get(i).data[1].load(.acquire)).tag.load(.acquire) != .funcProto) {
            try cont.appendSlice(alloc, ";\n");
        }
    }

    return cont.toOwnedSlice(alloc);
}

fn toStringFuncProto(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, node: *const Parser.Node) std.mem.Allocator.Error!void {
    std.debug.assert(node.tag.load(.acquire) == .funcProto);
    std.debug.assert(node.data[0].load(.acquire) == 0);

    // TODO : Put arguments
    try cont.appendSlice(alloc, "() ");

    try self.toStringType(alloc, cont, d, self.nodes.getPtr(node.data[1].load(.acquire)));

    try cont.append(alloc, ' ');

    const protoNext = node.next.load(.acquire);
    if (self.nodes.get(protoNext).tag.load(.acquire) == .scope) return try self.toStringScope(alloc, cont, d, self.nodes.getPtr(protoNext));

    try self.toStringStatement(alloc, cont, d, self.nodes.getPtr(protoNext));
}

fn toStringType(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, node: *const Parser.Node) std.mem.Allocator.Error!void {
    _ = d;

    var current = node;

    while (true) {
        switch (current.tag.load(.acquire)) {
            .funcType => {
                std.debug.assert(current.data[0].load(.acquire) == 0);
                try cont.appendSlice(alloc, "() ");

                current = self.nodes.getPtr(current.data[1].load(.acquire));
                continue;
            },
            .type => {
                try cont.append(alloc, current.typeToString());

                const size = try std.fmt.allocPrint(alloc, "{}", .{current.data[0].load(.acquire)});
                try cont.appendSlice(alloc, size);
                alloc.free(size);
            },
            .fakeType => {
                const x = current.getText(self);
                try cont.appendSlice(alloc, x);
            },
            else => unreachable,
        }

        try self.toStringFlags(alloc, cont, current.flags.load(.acquire));

        const nextIndex = current.next.load(.acquire);

        if (nextIndex != 0) {
            try cont.appendSlice(alloc, ", ");
            current = self.nodes.getPtr(nextIndex);
        } else {
            break;
        }
    }
}

fn toStringScope(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, scope: *const Parser.Node) std.mem.Allocator.Error!void {
    std.debug.assert(scope.tag.load(.acquire) == .scope);

    try cont.appendSlice(alloc, "{ \n");

    var j = scope.data[0].load(.acquire);

    while (j != 0) {
        const node = self.nodes.getPtr(j);

        try self.toStringStatement(alloc, cont, d + 4, node);

        j = node.next.load(.acquire);
    }

    for (0..d) |_| {
        try cont.append(alloc, ' ');
    }

    try cont.appendSlice(alloc, "} \n");
}

fn toStringStatement(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, stmt: *const Parser.Node) std.mem.Allocator.Error!void {
    for (0..d) |_| {
        try cont.append(alloc, ' ');
    }

    const exprIndex = stmt.data[1].load(.acquire);

    switch (stmt.tag.load(.acquire)) {
        .ret => {
            try cont.appendSlice(alloc, "return ");
            if (exprIndex != 0) try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(exprIndex));
        },
        .variable, .constant => {
            try self.toStringVariable(alloc, cont, d, stmt);
        },
        else => std.debug.panic("What node is this {}", .{stmt}),
    }

    if (self.nodes.get(exprIndex).tag.load(.acquire) != .funcProto) {
        try cont.appendSlice(alloc, ";");
    }

    try cont.appendSlice(alloc, "\n");
}

fn toStringVariable(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, variable: *const Parser.Node) std.mem.Allocator.Error!void {
    std.debug.assert(variable.tag.load(.acquire) == .constant or variable.tag.load(.acquire) == .variable);

    try cont.appendSlice(alloc, variable.getText(self));

    const variableLeft = variable.data[0].load(.acquire);
    if (variableLeft == 0)
        try cont.append(alloc, ' ');

    try cont.append(alloc, ':');
    if (variableLeft != 0) {
        try cont.append(alloc, ' ');
        try self.toStringType(alloc, cont, d, self.nodes.getPtr(variableLeft));
        try cont.append(alloc, ' ');
    }

    if (variable.data[1].load(.acquire) != 0) {
        switch (variable.tag.load(.acquire)) {
            .constant => try cont.appendSlice(alloc, ": "),
            .variable => try cont.appendSlice(alloc, "= "),
            else => unreachable,
        }
        const expr = variable.data[1].load(.acquire);
        if (expr != 0) try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(expr));
    }
}

fn toStringExpression(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, node: *const Parser.Node) std.mem.Allocator.Error!void {
    switch (node.tag.load(.acquire)) {
        .funcProto => try self.toStringFuncProto(alloc, cont, d, node),
        .addition, .subtraction, .multiplication, .division, .power => {
            try cont.append(alloc, '(');

            const leftIndex = node.data[0].load(.acquire);
            try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(leftIndex));

            try cont.append(alloc, ' ');
            try cont.appendSlice(alloc, node.getTokenTag(self).toSymbol().?);
            try cont.append(alloc, ' ');

            const rightIndex = node.data[1].load(.acquire);
            try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(rightIndex));

            try cont.append(alloc, ')');
        },
        .neg => {
            try cont.appendSlice(alloc, node.getTokenTag(self).toSymbol().?);
            try cont.append(alloc, '(');
            const leftIndex = node.data[0].load(.acquire);

            try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(leftIndex));
            try cont.append(alloc, ')');
        },
        .load => {
            try cont.appendSlice(alloc, node.getText(self));
        },
        .call => {
            try cont.appendSlice(alloc, node.getText(self));
            try cont.appendSlice(alloc, "()");
            assert(node.data.@"0".load(.acquire) == 0 and node.data.@"1".load(.acquire) == 0);
        },
        .lit => {
            try cont.appendSlice(alloc, node.getText(self));
        },
        else => unreachable,
    }

    try self.toStringFlags(alloc, cont, node.flags.load(.acquire));
}

fn toStringFlags(self: *Self, alloc: Allocator, cont: *std.ArrayList(u8), flags: Parser.Node.Flags) Allocator.Error!void {
    _ = self;
    const fields = std.meta.fields(Parser.Node.Flags);

    inline for (fields) |field| {
        if (field.type != bool) return;

        const set = @field(flags, field.name);

        if (set) {
            try cont.append(alloc, ' ');
            try cont.append(alloc, '#');
            try cont.appendSlice(alloc, field.name);
        }
    }
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
