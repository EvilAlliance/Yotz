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

    refCount: std.atomic.Value(usize) = std.atomic.Value(usize).init(1),

    pub fn init(alloc: Allocator, path: []const u8, subCom: ParseArgs.SubCommand) struct { bool, @This() } {
        var cont: @This() = .{
            .path = path,
            .subCom = subCom,
        };
        if (!readTokens(alloc, &cont)) return .{ false, cont };

        return .{ true, cont };
    }

    fn readTokens(alloc: Allocator, cont: *Content) bool {
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

    pub fn deinit(self: *const @This(), alloc: Allocator) void {
        alloc.free(self.path);
        alloc.free(self.tokens);
        alloc.free(self.source);
    }

    pub const FileInfo = struct { []const u8, [:0]const u8 };

    pub fn getInfo(self: @This()) FileInfo {
        return .{ self.path, self.source };
    }

    pub fn acquire(self: *@This()) void {
        _ = self.refCount.fetchAdd(1, .acquire);
    }

    pub fn release(self: *@This()) bool {
        const prev = self.refCount.fetchSub(1, .release);
        return prev == 1;
    }
};

pub var failed = false;

pub var threadPool: Thread.Pool = undefined;
pub var observer: TypeCheck.Observer = .{};

tag: Type,
cont: *const Content,
scope: TypeCheck.Scope,

pub fn initGlobal(cont: *const Content, scope: TypeCheck.Scope) Self {
    const tu = Self{
        .tag = .Global,
        .cont = cont,
        .scope = scope,
    };

    return tu;
}

// TODO: Aquire the content (Ref Counter)
pub fn initFunc(self: *const Self, alloc: Allocator) Allocator.Error!Self {
    const scope = try alloc.create(TypeCheck.ScopeFunc);
    scope.* = TypeCheck.ScopeFunc{
        .global = self.scope.getGlobal(),
    };

    const tu = Self{
        .tag = .Function,
        .cont = self.cont,
        .scope = scope.scope(),
    };

    return tu;
}

pub fn startFunction(self: Self, alloc: Allocator, nodes: *Parser.NodeList, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex) Allocator.Error!void {
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

fn _startFunction(self: *Self, alloc: Allocator, nodes: *Parser.NodeList, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex) Allocator.Error!void {
    defer self.scope.deinit(alloc);
    defer alloc.destroy(self);

    if (self.cont.subCom == .Lexer) unreachable;

    var parser = try Parser.Parser.init(self, nodes);
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

    var ast = Parser.Ast.init(nodes, self);

    var checker = TypeCheck.TypeCheck.init(&ast, self);
    try checker.checkFunction(alloc, ast.getNode(placeHolder).data[1].load(.acquire));
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

fn _startRoot(self: *Self, alloc: Allocator, nodes: *Parser.NodeList, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex) Allocator.Error!void {
    if (self.cont.subCom == .Lexer) unreachable;

    defer alloc.destroy(self);

    var parser = try Parser.Parser.init(self, nodes);
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

    var ast = Parser.Ast.init(nodes, self);
    var checker = TypeCheck.TypeCheck.init(&ast, self);
    try checker.checkRoot(alloc, ast.getNode(placeHolder).data[1].load(.acquire));

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

pub fn startEntry(stakcSelf: Self, alloc: Allocator, nodes: *Parser.NodeList) std.mem.Allocator.Error!struct { []const u8, u8 } {
    const self = try Util.dupe(alloc, stakcSelf);

    if (self.cont.subCom == .Lexer) {
        var parser = try Parser.Parser.init(self, nodes);
        defer parser.deinit(alloc);
        return .{ try parser.lexerToString(alloc), 0 };
    }

    const index = try nodes.appendIndex(alloc, Parser.Node{ .tag = .init(.entry) });

    try self._startRoot(alloc, nodes, 0, index);

    threadPool.deinit();

    if (failed) return .{ "", 1 };

    const ast = Parser.Ast.init(nodes, self);

    if (self.cont.subCom == .Parser) return .{ try ast.toString(alloc, nodes.get(index).data[1].load(.acquire)), 0 };

    if (self.cont.subCom == .TypeCheck) return .{ try ast.toString(alloc, nodes.get(index).data[1].load(.acquire)), 0 };

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

    self.cont.deinit(alloc);
}

const std = @import("std");
const Util = @import("./Util.zig");

const mem = std.mem;

const Allocator = mem.Allocator;

const ParseArgs = @import("ParseArgs.zig");
const Lexer = @import("./Lexer/mod.zig");
const Parser = @import("./Parser/mod.zig");
const TypeCheck = @import("./TypeCheck/mod.zig");
const Thread = std.Thread;
