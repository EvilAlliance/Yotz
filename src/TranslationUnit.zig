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

pub fn start(self: *const Self) std.mem.Allocator.Error!struct { []const u8, u8 } {
    var parser = Parser.init(self.alloc, self.cont.path) orelse return .{ "", 1 };
    defer parser.deinit();

    if (self.cont.subCom == .Lexer)
        return .{ try parser.lexerToString(self.alloc), 0 };

    var ast = try parser.parse();

    for (parser.errors.items) |e| {
        e.display(ast.getInfo());
    }

    if (self.cont.subCom == .Parser)
        return .{ try ast.toString(self.alloc), 0 };

    const err = try typeCheck(self.alloc, &ast);

    if (self.cont.subCom == .TypeCheck)
        return .{ try ast.toString(self.alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };

    if (err) return .{ "", 1 };
    if (parser.errors.items.len > 0) return .{ "", 1 };

    unreachable;
}

pub fn deinit(self: *const Self, bytes: []const u8) void {
    self.alloc.free(bytes);
    self.alloc.free(self.cont.path);
    self.alloc.free(self.cont.tokens);
    self.alloc.free(self.cont.source);
}

const std = @import("std");
const Util = @import("./Util.zig");

const ParseArgs = @import("ParseArgs.zig");
const Lexer = @import("./Lexer/Lexer.zig");
const Parser = @import("./Parser/Parser.zig");
const typeCheck = @import("./TypeCheck/TypeCheck.zig").typeCheck;
