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

    var i = root.left.load(.acquire);
    while (i != 0) : (i = self.nodes.get(i).next.load(.acquire)) {
        try self.toStringVariable(alloc, &cont, 0, self.nodes.getPtr(i).asVarConst());

        if (self.nodes.get(self.nodes.get(i).right.load(.acquire)).tag.load(.acquire) != .funcProto) {
            try cont.appendSlice(alloc, ";\n");
        } else {
            try cont.append(alloc, '\n');
        }
    }

    return cont.toOwnedSlice(alloc);
}

fn toStringFuncProto(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, node: *const Parser.Node.FuncProto) std.mem.Allocator.Error!void {
    std.debug.assert(node.tag.load(.acquire) == .funcProto);

    // TODO : Put arguments
    try cont.append(alloc, '(');
    const argIndex = node.args.load(.acquire);
    if (argIndex != 0) {
        var args = self.nodes.getConstPtr(argIndex);

        try cont.appendSlice(alloc, args.getText(self));
        try cont.appendSlice(alloc, ": ");
        try self.toStringType(alloc, cont, d, self.nodes.getPtr(args.left.load(.acquire)));

        while (args.next.load(.acquire) != 0) {
            args = self.nodes.getConstPtr(args.next.load(.acquire));

            try cont.appendSlice(alloc, ", ");

            try cont.appendSlice(alloc, args.getText(self));
            try cont.appendSlice(alloc, ": ");
            try self.toStringType(alloc, cont, d, self.nodes.getPtr(args.left.load(.acquire)));
        }
    }

    try cont.appendSlice(alloc, ") ");

    try self.toStringType(alloc, cont, d, self.nodes.getPtr(node.retType.load(.acquire)));

    try cont.append(alloc, ' ');

    const scopeOrStmt = node.scope.load(.acquire);
    if (self.nodes.get(scopeOrStmt).tag.load(.acquire) == .scope) return try self.toStringScope(alloc, cont, d, self.nodes.getPtr(scopeOrStmt));

    if (scopeOrStmt != 0) try self.toStringStatement(alloc, cont, d, self.nodes.getPtr(scopeOrStmt));
}

fn toStringType(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, node: *const Parser.Node) std.mem.Allocator.Error!void {
    var current = node;

    while (true) {
        switch (current.tag.load(.acquire)) {
            .fakeFuncType => {
                const fakeFuncType = current.asConstFakeFuncType();
                try cont.append(alloc, '(');
                const argsIndex = fakeFuncType.fakeArgsType.load(.acquire);
                if (argsIndex != 0) try self.toStringType(alloc, cont, d, self.nodes.getPtr(argsIndex));
                try cont.appendSlice(alloc, ") ");

                current = self.nodes.getPtr(fakeFuncType.fakeRetType.load(.acquire));
                continue;
            },
            .funcType => {
                const funcType = current.asConstFuncType();
                try cont.append(alloc, '(');
                const argsIndex = funcType.argsType.load(.acquire);
                if (argsIndex != 0) try self.toStringType(alloc, cont, d, self.nodes.getPtr(argsIndex));
                try cont.appendSlice(alloc, ") ");

                current = self.nodes.getPtr(funcType.retType.load(.acquire));
                continue;
            },
            .type => {
                const type_ = current.asConstType();
                try cont.append(alloc, type_.asConst().typeToString());

                const size = try std.fmt.allocPrint(alloc, "{}", .{type_.size.load(.acquire)});
                try cont.appendSlice(alloc, size);
                alloc.free(size);
            },
            .fakeType => {
                const x = current.getText(self);
                try cont.appendSlice(alloc, x);
            },
            .fakeArgType => {
                const fakeArgType = current.asConstFakeArgType();
                if (fakeArgType.isName.load(.acquire) == 1) {
                    try cont.appendSlice(alloc, fakeArgType.asConst().getText(self));
                    try cont.appendSlice(alloc, ": ");
                }

                try self.toStringType(alloc, cont, d, self.nodes.getConstPtr(fakeArgType.fakeType.load(.acquire)));
            },
            .argType => {
                const argType = current.asConstArgType();
                if (argType.isName.load(.acquire) == 1) {
                    try cont.appendSlice(alloc, argType.asConst().getText(self));
                    try cont.appendSlice(alloc, ": ");
                }

                try self.toStringType(alloc, cont, d, self.nodes.getConstPtr(argType.type_.load(.acquire)));
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

    var j = scope.left.load(.acquire);

    while (j != 0) {
        const node = self.nodes.getPtr(j);

        try self.toStringStatement(alloc, cont, d + 4, node);

        j = node.next.load(.acquire);
    }

    for (0..d) |_| {
        try cont.append(alloc, ' ');
    }

    try cont.append(alloc, '}');
}

fn toStringStatement(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, stmt: *const Parser.Node) std.mem.Allocator.Error!void {
    for (0..d) |_| {
        try cont.append(alloc, ' ');
    }

    const exprIndex = stmt.right.load(.acquire);

    switch (stmt.tag.load(.acquire)) {
        .ret => {
            try cont.appendSlice(alloc, "return ");
            if (exprIndex != 0) try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(exprIndex).asExpression());
        },
        .variable, .constant => {
            try self.toStringVariable(alloc, cont, d, stmt.asConstVarConst());
        },
        else => std.debug.panic("What node is this {}", .{stmt}),
    }

    if (self.nodes.get(exprIndex).tag.load(.acquire) != .funcProto) {
        try cont.appendSlice(alloc, ";");
    }

    try cont.appendSlice(alloc, "\n");
}

fn toStringVariable(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, variable: *const Parser.Node.VarConst) std.mem.Allocator.Error!void {
    try cont.appendSlice(alloc, variable.asConst().getText(self));

    const variableLeft = variable.type.load(.acquire);
    if (variableLeft == 0)
        try cont.append(alloc, ' ');

    try cont.append(alloc, ':');
    if (variableLeft != 0) {
        try cont.append(alloc, ' ');
        try self.toStringType(alloc, cont, d, self.nodes.getPtr(variableLeft));
        try cont.append(alloc, ' ');
    }

    if (variable.expr.load(.acquire) != 0) {
        switch (variable.tag.load(.acquire)) {
            .constant => try cont.appendSlice(alloc, ": "),
            .variable => try cont.appendSlice(alloc, "= "),
            else => unreachable,
        }
        const expr = variable.expr.load(.acquire);
        if (expr != 0) try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(expr).asExpression());
    }
}

fn toStringExpression(self: *@This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, node: *const Parser.Node.Expression) std.mem.Allocator.Error!void {
    switch (node.tag.load(.acquire)) {
        .funcProto => try self.toStringFuncProto(alloc, cont, d, node.asConstFuncProto()),
        .addition, .subtraction, .multiplication, .division, .power => {
            const binOp = node.asConstBinaryOp();
            try cont.append(alloc, '(');

            const leftIndex = binOp.left.load(.acquire);
            try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(leftIndex).asExpression());

            try cont.append(alloc, ' ');
            try cont.appendSlice(alloc, node.asConst().getTokenTag(self).toSymbol().?);
            try cont.append(alloc, ' ');

            const rightIndex = binOp.right.load(.acquire);
            try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(rightIndex).asExpression());

            try cont.append(alloc, ')');
        },
        .neg => {
            const unOp = node.asConstUnaryOp();
            try cont.appendSlice(alloc, node.asConst().getTokenTag(self).toSymbol().?);
            try cont.append(alloc, '(');
            const leftIndex = unOp.left.load(.acquire);

            try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(leftIndex).asExpression());
            try cont.append(alloc, ')');
        },
        .load => {
            try cont.appendSlice(alloc, node.asConst().getText(self));
        },
        .call => {
            const callNode = node.asConstCall();
            try cont.appendSlice(alloc, node.asConst().getText(self));
            try cont.append(alloc, '(');

            var argIndex = callNode.firstArg.load(.acquire);
            while (argIndex != 0) {
                const arg = self.nodes.getConstPtr(argIndex);
                const exprIndex = arg.right.load(.acquire);
                if (exprIndex != 0) {
                    try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(exprIndex).asExpression());
                }

                argIndex = arg.next.load(.acquire);
                if (argIndex != 0) try cont.appendSlice(alloc, ", ");
            }

            try cont.append(alloc, ')');

            var next = node.next.load(.acquire);
            while (next != 0) {
                const call = self.nodes.getConstPtr(next);

                try cont.append(alloc, '(');

                argIndex = call.left.load(.acquire);
                while (argIndex != 0) {
                    const arg = self.nodes.getConstPtr(argIndex);
                    const exprIndex = arg.right.load(.acquire);
                    if (exprIndex != 0) {
                        try self.toStringExpression(alloc, cont, d, self.nodes.getPtr(exprIndex).asExpression());
                    }

                    argIndex = arg.next.load(.acquire);
                    if (argIndex != 0) try cont.appendSlice(alloc, ", ");
                }

                try cont.append(alloc, ')');

                next = call.next.load(.acquire);
            }
        },
        .lit => {
            try cont.appendSlice(alloc, node.asConst().getText(self));
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
