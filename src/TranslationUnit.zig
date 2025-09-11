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

alloc: std.mem.Allocator,

tag: Type,
cont: Content,

pub fn initGlobal(alloc: std.mem.Allocator, args: ParseArgs.Arguments) struct { Self, bool } {
    var tu = Self{
        .tag = .Global,
        .alloc = alloc,

        .cont = .{
            .subCom = args.subCom,
            .path = args.path,
        },
    };

    if (!tu.readTokens()) return .{ undefined, false };

    return .{ tu, true };
}

pub fn readTokens(self: *Self) bool {
    const path = self.cont.path;
    const resolvedPath, const source = Util.readEntireFile(self.alloc, path) catch |err| {
        switch (err) {
            error.couldNotResolvePath => std.log.err("Could not resolve path: {s}\n", .{path}),
            error.couldNotOpenFile => std.log.err("Could not open file: {s}\n", .{path}),
            error.couldNotReadFile => std.log.err("Could not read file: {s}]n", .{path}),
            error.couldNotGetFileSize => std.log.err("Could not get file ({s}) size\n", .{path}),
        }
        return false;
    };
    self.cont.tokens = Lexer.lex(self.alloc, source) catch {
        std.log.err("Out of memory", .{});

        self.alloc.free(resolvedPath);
        self.alloc.free(source);

        return false;
    };

    self.cont.source = source;

    self.cont.path = resolvedPath;

    return true;
}

pub fn start(self: *const Self, alloc: Allocator) std.mem.Allocator.Error!struct { []const u8, u8 } {
    var nodes = Parser.NodeList.init();
    defer nodes.deinit(alloc);
    var parser = try Parser.init(self, try Parser.NodeList.Chunk.init(alloc, &nodes));
    defer parser.deinit(alloc);

    if (self.cont.subCom == .Lexer)
        return .{ try parser.lexerToString(alloc), 0 };

    var ast = try parser.parse(alloc);
    defer ast.deinit(alloc);

    for (parser.errors.items) |e| {
        e.display(alloc, self.cont.getInfo());
    }

    if (self.cont.subCom == .Parser)
        return .{ try ast.toString(alloc), 0 };
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
    alloc.free(self.cont.path);
    alloc.free(self.cont.tokens);
    alloc.free(self.cont.source);
}

const std = @import("std");
const Util = @import("./Util.zig");

const mem = std.mem;

const Allocator = mem.Allocator;

const ParseArgs = @import("ParseArgs.zig");
const Lexer = @import("./Lexer/Lexer.zig");
const Parser = @import("./Parser/Parser.zig");
const typeCheck = @import("./TypeCheck/TypeCheck.zig").typeCheck;
