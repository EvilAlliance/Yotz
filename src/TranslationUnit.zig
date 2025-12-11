const Self = @This();

pub const Type = enum {
    Global,
    Function,
};

pub const Content = struct {
    subCom: ParseArgs.SubCommand = .Build,

    path: []const u8 = "",

    source: [:0]const u8 = "",
    tokens: []Lexer.Token = undefined,

    pub const FileInfo = struct { []const u8, [:0]const u8 };

    pub fn getInfo(self: @This()) FileInfo {
        return .{ self.path, self.source };
    }
};

pub var failed = false;

pub var threadPool: Thread.Pool = undefined;
pub var observer: TypeCheck.Observer = .{};

// TODO: Delete Type, 13/10/2025 is not use
tag: Type,
cont: *const Content,

pub fn initGlobal(cont: *const Content) Self {
    const tu = Self{
        .tag = .Global,
        .cont = cont,
    };

    return tu;
}

pub fn initFunc(self: *const Self) Self {
    const tu = Self{
        .tag = .Function,
        .cont = self.cont,
    };

    return tu;
}

pub fn readTokens(alloc: Allocator, cont: *Content) bool {
    const path = cont.path;
    const resolvedPath, const source = Util.readEntireFile(alloc, path) catch |err| {
        switch (err) {
            error.couldNotResolvePath => std.log.err("Could not resolve path: {s}\n", .{path}),
            error.couldNotOpenFile => std.log.err("Could not open file: {s}\n", .{path}),
            error.couldNotReadFile => std.log.err("Could not read file: {s}]n", .{path}),
            error.couldNotGetFileSize => std.log.err("Could not get file ({s}) size\n", .{path}),
        }
        return false;
    };
    cont.tokens = Lexer.lex(alloc, source) catch {
        std.log.err("Out of memory", .{});

        alloc.free(resolvedPath);
        alloc.free(source);

        return false;
    };

    cont.source = source;

    cont.path = resolvedPath;

    return true;
}

pub fn startFunction(self: Self, alloc: Allocator, nodes: *mod.NodeList, start: mod.TokenIndex, placeHolder: mod.NodeIndex) Allocator.Error!void {
    std.debug.assert(self.tag == .Function);

    const selfDupe = try Util.dupe(alloc, self);

    const callBack = struct {
        fn callBack(comptime func: anytype, args: anytype) void {
            @call(.auto, func, args) catch {
                failed = true;
                std.log.err("Run Out of Memory", .{});
            };
        }
    }.callBack;

    try threadPool.spawn(callBack, .{ _startFunction, .{ selfDupe, alloc, nodes, start, placeHolder } });
}

fn _startFunction(self: *const Self, alloc: Allocator, nodes: *mod.NodeList, start: mod.TokenIndex, placeHolder: mod.NodeIndex) Allocator.Error!void {
    defer alloc.destroy(self);
    if (self.cont.subCom == .Lexer) unreachable;

    var chunk = try mod.NodeList.Chunk.init(alloc, nodes);

    var parser = try mod.Parser.init(self, &chunk);
    defer parser.deinit(alloc);

    try parser.parseFunction(alloc, start, placeHolder);

    try observer.alert(alloc, placeHolder);

    for (parser.errors.items) |e| {
        e.display(alloc, self.cont.getInfo());
    }

    if (parser.errors.items.len > 0) {
        failed = true;
        return;
    }

    if (self.cont.subCom == .Parser) return;

    var ast = mod.Ast.init(&chunk, self);

    var checker = TypeCheck.TypeCheck.init(&ast, self);
    try checker.checkFunction(alloc, ast.getNode(.UnBound, placeHolder).data[1].load(.acquire));
    if (failed) return;

    if (self.cont.subCom == .TypeCheck) return;
    //
    // unreachable;
    // const err = try typeCheck(alloc, &ast);
    //
    // if (self.cont.subCom == .TypeCheck)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
    // if (err) return .{ "", 1 };
    // if (parser.errors.items.len > 0) return .{ "", 1 };
}

fn _startRoot(self: *const Self, alloc: Allocator, nodes: *mod.NodeList, start: mod.TokenIndex, placeHolder: mod.NodeIndex) Allocator.Error!void {
    if (self.cont.subCom == .Lexer) unreachable;

    defer alloc.destroy(self);
    var chunk = try mod.NodeList.Chunk.init(alloc, nodes);

    var parser = try mod.Parser.init(self, &chunk);
    defer parser.deinit(alloc);

    try parser.parseRoot(alloc, start, placeHolder);

    for (parser.errors.items) |e| {
        e.display(alloc, self.cont.getInfo());
    }

    if (parser.errors.items.len > 0) {
        failed = true;
        return;
    }
    if (self.cont.subCom == .Parser) return;

    var ast = mod.Ast.init(&chunk, self);
    var checker = TypeCheck.TypeCheck.init(&ast, self);
    try checker.checkRoot(alloc, ast.getNode(.UnBound, placeHolder).data[1].load(.acquire));

    if (self.cont.subCom == .TypeCheck) return;

    unreachable;
    //
    // const err = try typeCheck(alloc, &ast);
    //
    // if (self.cont.subCom == .TypeCheck)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
    // if (err) return .{ "", 1 };
    // if (parser.errors.items.len > 0) return .{ "", 1 };
}

pub fn startEntry(stakcSelf: Self, alloc: Allocator, nodes: *mod.NodeList) std.mem.Allocator.Error!struct { []const u8, u8 } {
    var chunk = try mod.NodeList.Chunk.init(alloc, nodes);

    const self = try Util.dupe(alloc, stakcSelf);

    if (self.cont.subCom == .Lexer) {
        var parser = try mod.Parser.init(self, &chunk);
        defer parser.deinit(alloc);
        return .{ try parser.lexerToString(alloc), 0 };
    }

    const index = try chunk.appendIndex(alloc, mod.Node{ .tag = .init(.entry) });

    try self._startRoot(alloc, nodes, 0, index);

    threadPool.deinit();

    if (failed) return .{ "", 1 };

    const ast = mod.Ast.init(&chunk, self);

    if (self.cont.subCom == .Parser) return .{ try ast.toString(alloc, chunk.get(index).data[1].load(.acquire)), 0 };

    if (self.cont.subCom == .TypeCheck) return .{ try ast.toString(alloc, chunk.get(index).data[1].load(.acquire)), 0 };

    // const err = try typeCheck(alloc, &ast);
    //
    // if (self.cont.subCom == .TypeCheck)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
    // if (failed) return .{ "", 1 };
    // if (err) return .{ "", 1 };
    // if (parser.errors.items.len > 0) return .{ "", 1 };

    return .{ "", 1 };
}

pub fn deinit(self: *const Self, alloc: Allocator, bytes: []const u8) void {
    alloc.free(bytes);
    _ = self;
}

const std = @import("std");
const Util = @import("./Util.zig");

const mem = std.mem;

const Allocator = mem.Allocator;

const ParseArgs = @import("ParseArgs.zig");
const Lexer = @import("./Lexer/mod.zig");
const mod = @import("./Parser/mod.zig");
const TypeCheck = @import("./TypeCheck/mod.zig");
const Thread = std.Thread;
