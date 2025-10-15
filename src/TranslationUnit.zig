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

var failed = false;

// TODO: Delete Type, 13/10/2025 is not use
tag: Type,
cont: *const Content,
pool: *Thread.Pool,

pub fn initGlobal(cont: *const Content, pool: *Thread.Pool) Self {
    const tu = Self{
        .tag = .Global,
        .pool = pool,
        .cont = cont,
    };

    return tu;
}

pub fn initFunc(self: *const Self) Self {
    const tu = Self{
        .tag = .Function,
        .cont = self.cont,
        .pool = self.pool,
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

    try self.pool.spawn(callBack, .{ _startFunction, .{ selfDupe, alloc, nodes, start, placeHolder } });
}

fn _startFunction(self: *const Self, alloc: Allocator, nodes: *Parser.NodeList, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex) Allocator.Error!void {
    defer alloc.destroy(self);
    const chunk = try Parser.NodeList.Chunk.init(alloc, nodes);

    var parser = try Parser.init(self, chunk);
    defer parser.deinit(alloc);

    try parser.parseFunction(alloc, start, placeHolder);

    for (parser.errors.items) |e| {
        e.display(alloc, self.cont.getInfo());
    }

    if (parser.errors.items.len > 0) failed = true;

    // const err = try typeCheck(alloc, &ast);
    //
    // if (self.cont.subCom == .TypeCheck)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
    // if (err) return .{ "", 1 };
    // if (parser.errors.items.len > 0) return .{ "", 1 };
}

pub fn startEntry(self: *const Self, alloc: Allocator, nodes: *Parser.NodeList) std.mem.Allocator.Error!struct { []const u8, u8 } {
    const chunk = try Parser.NodeList.Chunk.init(alloc, nodes);
    var parser = try Parser.init(self, chunk);
    defer parser.deinit(alloc);

    if (self.cont.subCom == .Lexer)
        return .{ try parser.lexerToString(alloc), 0 };

    var ast = try parser.parse(alloc);
    defer ast.deinit(alloc);

    for (parser.errors.items) |e| {
        e.display(alloc, self.cont.getInfo());
    }

    if (self.cont.subCom == .Parser) {
        self.pool.deinit();
        return .{ try ast.toString(alloc), 0 };
    }

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
const Lexer = @import("./Lexer/Lexer.zig");
const Parser = @import("./Parser/Parser.zig");
const typeCheck = @import("./TypeCheck/TypeCheck.zig").typeCheck;
const Thread = std.Thread;
