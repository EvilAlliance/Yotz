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

    try self.pool.spawn(_startFunction, .{ selfDupe, alloc, nodes, start, placeHolder });
}

fn _startFunction(self: *const Self, alloc: Allocator, nodes: *Parser.NodeList, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex) void {
    defer alloc.destroy(self);
    const chunk = Parser.NodeList.Chunk.init(alloc, nodes) catch {
        std.log.err("Run Out of Memory", .{});
        // TODO: This does not cause it to return 1 and execution keeps going
        return;
    };

    var parser = Parser.init(self, chunk) catch {
        std.log.err("Run Out of Memory", .{});
        // TODO: This does not cause it to return 1 and execution keeps going
        return;
    };
    defer parser.deinit(alloc);

    parser.parseFunction(alloc, start, placeHolder) catch {
        std.log.err("Run Out of Memory", .{});
        // TODO: This does not cause it to return 1 and execution keeps going
        return;
    };

    // TODO: This does not cause it to return 1
    for (parser.errors.items) |e| {
        e.display(alloc, self.cont.getInfo());
    }

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
    //
    // const err = try typeCheck(alloc, &ast);
    //
    // if (self.cont.subCom == .TypeCheck)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
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
