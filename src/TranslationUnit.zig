const Self = @This();

pub const Type = enum {
    Global,
    Function,
};

// TODO: Take this out
pub var failed = false;

pub fn deinitStatic(alloc: Allocator, bytes: []const u8) void {
    alloc.free(bytes);
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

pub fn initFunc(self: *const Self, alloc: Allocator) Allocator.Error!Self {
    const scope = try TypeCheck.ScopeFunc.initHeap(alloc, self.scope.getGlobal());

    const tu = Self{
        .tag = .Function,
        .global = self.global,
        .scope = scope.scope(),
    };

    return tu;
}

pub fn deinit(self: Self, alloc: Allocator) void {
    self.scope.deinit(alloc);
}

pub fn acquire(self: Self, alloc: Allocator) Allocator.Error!Self {
    return Self{
        .tag = self.tag,
        .global = self.global,
        .scope = try self.scope.deepClone(alloc),
    };
}

pub fn startFunction(self: Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    std.debug.assert(self.tag == .Function);

    const callBack = struct {
        fn callBack(comptime func: anytype, args: anytype) void {
            @call(.auto, func, args) catch {
                failed = true;
                std.log.err("Run Out of Memory", .{});
            };
        }
    }.callBack;

    try self.global.threadPool.spawn(callBack, .{ _startFunction, .{ self, alloc, start, placeHolder, reports } });
}

fn _startFunction(self: Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    defer self.deinit(alloc);

    if (self.global.subCommand == .Lexer) unreachable;

    var parser = try Parser.Parser.init(&self);

    parser.parseFunction(alloc, start, placeHolder, reports) catch |err| switch (err) {
        Parser.Error.UnexpectedToken => return,
        else => return @errorCast(err),
    };

    if (self.global.subCommand == .Parser) return;

    try TypeCheck.TypeCheck.checkFunction(self, alloc, placeHolder, reports);
    if (failed) return;

    if (self.global.subCommand == .TypeCheck) return;

    unreachable;
    // const err = try typeCheck(alloc, &ast);
    //
    // if (self.cont.subCom == .TypeCheck)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
    // if (err) return .{ "", 1 };
    // if (parser.errors.items.len > 0) return .{ "", 1 };
}

fn _startRoot(self: Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    if (self.global.subCommand == .Lexer) unreachable;
    defer self.deinit(alloc);

    var parser = try Parser.Parser.init(&self);

    try parser.parseRoot(alloc, start, placeHolder, reports);

    if (self.global.subCommand == .Parser) return;

    try TypeCheck.TypeCheck.checkRoot(self, alloc, self.global.nodes.get(placeHolder).data[1].load(.acquire), reports);

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

pub fn startEntry(stakcSelf: Self, alloc: Allocator, reports: ?*Report.Reports) std.mem.Allocator.Error!void {
    if (stakcSelf.global.subCommand == .Lexer) return;

    const self = try Util.dupe(alloc, stakcSelf);

    const index = try self.global.nodes.appendIndex(alloc, Parser.Node{ .tag = .init(.entry) });
    std.debug.assert(index == 0);

    try self._startRoot(alloc, 0, index, reports);

    // const err = try typeCheck(alloc, &ast);
    //
    // if (self.cont.subCom == .TypeCheck)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
    // if (failed) return .{ "", 1 };
    // if (err) return .{ "", 1 };
    // if (parser.errors.items.len > 0) return .{ "", 1 };
}

pub fn waitForWork(alloc: Allocator, global: *Global) Allocator.Error!struct { []const u8, u8 } {
    if (global.subCommand == .Lexer) {
        return .{ try global.toStringToken(alloc), 0 };
    }

    global.threadPool.deinit();

    const index = 0;

    if (failed) return .{ "", 1 };

    if (global.subCommand == .Parser) return .{ try global.toStringAst(alloc, global.nodes.get(index).data[1].load(.acquire)), 0 };

    if (global.subCommand == .TypeCheck) return .{ try global.toStringAst(alloc, global.nodes.get(index).data[1].load(.acquire)), 0 };

    return .{ "", 1 };
}

const ParseArgs = @import("ParseArgs.zig");
const Lexer = @import("./Lexer/mod.zig");
const Parser = @import("./Parser/mod.zig");
const TypeCheck = @import("./TypeCheck/mod.zig");
const Report = @import("./Report/mod.zig");
const Global = @import("Global.zig");

const Util = @import("./Util.zig");

const std = @import("std");

const mem = std.mem;

const Allocator = mem.Allocator;
const Thread = std.Thread;
