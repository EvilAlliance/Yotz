const Self = @This();

pub const Type = enum {
    Global,
    Function,
};

// TODO: Take this out
pub var failed = false;

pub fn deinit(self: *const Self, alloc: Allocator, bytes: []const u8) void {
    alloc.free(bytes);

    self.global.deinit(alloc);
}

tag: Type,
global: *Global,
scope: TypeCheck.Scope,

pub fn initGlobal(cont: *Global, scope: TypeCheck.Scope) Self {
    const tu = Self{
        .tag = .Global,
        .global = cont,
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
        .global = self.global,
        .scope = scope.scope(),
    };

    return tu;
}

pub fn startFunction(self: Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex) Allocator.Error!void {
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

    try self.global.threadPool.spawn(callBack, .{ _startFunction, .{ selfDupe, alloc, start, placeHolder } });
}

fn _startFunction(self: *Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex) Allocator.Error!void {
    defer self.scope.deinit(alloc);
    defer alloc.destroy(self);

    if (self.global.subCommand == .Lexer) unreachable;

    var parser = try Parser.Parser.init(self);
    defer parser.deinit(alloc);

    try parser.parseFunction(alloc, start, placeHolder);

    try self.global.observer.alert(alloc, placeHolder);

    for (parser.errors.items) |e| {
        _ = e;
        @panic("TODO:");
    }

    if (parser.errors.items.len > 0) {
        failed = true;
        return;
    }

    if (self.global.subCommand == .Parser) return;

    var checker = TypeCheck.TypeCheck.init(self);
    try checker.checkFunction(alloc, self.global.nodes.get(placeHolder).data[1].load(.acquire));
    if (failed) return;

    if (self.global.subCommand == .TypeCheck) return;
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

fn _startRoot(self: *Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex) Allocator.Error!void {
    if (self.global.subCommand == .Lexer) unreachable;

    defer alloc.destroy(self);

    var parser = try Parser.Parser.init(self);
    defer parser.deinit(alloc);

    try parser.parseRoot(alloc, start, placeHolder);

    for (parser.errors.items) |e| {
        _ = e;
        @panic("TODO");
    }

    if (parser.errors.items.len > 0) {
        failed = true;
        return;
    }
    if (self.global.subCommand == .Parser) return;

    var checker = TypeCheck.TypeCheck.init(self);
    try checker.checkRoot(alloc, self.global.nodes.get(placeHolder).data[1].load(.acquire));

    if (self.global.subCommand == .TypeCheck) return;

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

pub fn startEntry(stakcSelf: Self, alloc: Allocator) std.mem.Allocator.Error!struct { []const u8, u8 } {
    const self = try Util.dupe(alloc, stakcSelf);

    if (self.global.subCommand == .Lexer) {
        var parser = try Parser.Parser.init(self);
        defer parser.deinit(alloc);
        return .{ try self.global.toStringToken(alloc), 0 };
    }

    const index = try self.global.nodes.appendIndex(alloc, Parser.Node{ .tag = .init(.entry) });

    try self._startRoot(alloc, 0, index);

    self.global.threadPool.deinit();

    if (failed) return .{ "", 1 };

    if (self.global.subCommand == .Parser) return .{ try self.global.toStringAst(alloc, self.global.nodes.get(index).data[1].load(.acquire)), 0 };

    if (self.global.subCommand == .TypeCheck) return .{ try self.global.toStringAst(alloc, self.global.nodes.get(index).data[1].load(.acquire)), 0 };

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

const ParseArgs = @import("ParseArgs.zig");
const Lexer = @import("./Lexer/mod.zig");
const Parser = @import("./Parser/mod.zig");
const TypeCheck = @import("./TypeCheck/mod.zig");
const Global = @import("Global.zig");

const Util = @import("./Util.zig");

const std = @import("std");

const mem = std.mem;

const Allocator = mem.Allocator;
const Thread = std.Thread;
