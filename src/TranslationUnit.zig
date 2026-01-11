const Self = @This();

pub const Type = enum {
    Root,
    Function,
};

// TODO: Take this out
pub var failed = false;

pub fn deinitStatic(alloc: Allocator, bytes: []const u8) void {
    alloc.free(bytes);
}

var ID = std.atomic.Value(usize).init(0);

tag: Type,
global: *Global,
scope: TypeCheck.Scope.Scope,
rootIndex: Parser.NodeIndex = 0,
id: usize,

pub fn initRoot(alloc: Allocator, globa: *Global) Allocator.Error!Self {
    const tu = Self{
        .tag = .Root,
        .global = globa,
        .scope = (try TypeCheck.Scope.Global.initHeap(alloc, &globa.threadPool)).scope(),
        .id = ID.fetchAdd(1, .acq_rel),
    };

    return tu;
}

pub fn initFunc(self: *const Self, alloc: Allocator) Allocator.Error!Self {
    const scope = try TypeCheck.Scope.Func.initHeap(alloc, self.scope.getGlobal().acquire());

    const tu = Self{
        .tag = .Function,
        .global = self.global,
        .scope = scope.scope(),
        .id = self.id,
    };

    return tu;
}

pub fn deinit(self: Self, alloc: Allocator) void {
    self.scope.deinit(alloc);
}

pub fn reserve(self: Self, alloc: Allocator) Allocator.Error!Self {
    return Self{
        .tag = self.tag,
        .global = self.global,
        .scope = try self.scope.deepClone(alloc),
        .id = self.id,
    };
}

pub fn acquire(self: Self) Allocator.Error!Self {
    _ = self.scope.getGlobal().acquire();

    return Self{
        .tag = self.tag,
        .global = self.global,
        .scope = self.scope,
        .id = self.id,
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

    try TypeCheck.Func.check(self, alloc, placeHolder, reports);
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

pub fn startRoot(self: Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    std.debug.assert(self.tag == .Root);

    const callBack = struct {
        fn callBack(comptime func: anytype, args: anytype) void {
            @call(.auto, func, args) catch {
                std.debug.panic("Run Out of Memory", .{});
            };
        }
    }.callBack;

    try self.global.threadPool.spawn(callBack, .{ _startRoot, .{ self, alloc, start, placeHolder, reports } });
}

fn _startRoot(self: Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    if (self.global.subCommand == .Lexer) unreachable;
    defer self.deinit(alloc);

    var parser = try Parser.Parser.init(&self);

    try parser.parseRoot(alloc, start, placeHolder, reports);

    if (self.global.subCommand == .Parser) return;

    try TypeCheck.Root.check(self, alloc, self.global.nodes.get(placeHolder).data[1].load(.acquire), reports);

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

pub fn startEntry(alloc: Allocator, arguments: *const ParseArgs.Arguments) std.mem.Allocator.Error!struct { []const u8, u8 } {
    var global: Global = .{ .subCommand = arguments.subCom };
    global.init(alloc, 20) catch std.debug.panic("Could not create threads", .{});
    defer global.deinit(alloc);

    if (!try global.addFile(alloc, arguments.path)) return .{ "", 1 };

    const tu = try initRoot(alloc, &global);

    const index = try global.nodes.appendIndex(alloc, Parser.Node{ .tag = .init(.entry) });

    var reports = Report.Reports{};

    if (arguments.subCom != .Lexer) try tu.startRoot(alloc, 0, index, &reports);

    const ret = try waitForWork(alloc, &global);

    const message = Report.Message.init(&global);
    for (0..reports.nextIndex.load(.acquire)) |i| {
        reports.get(i).display(message);
    }

    return ret;
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
const Lexer = @import("Lexer/mod.zig");
const Parser = @import("Parser/mod.zig");
const TypeCheck = @import("TypeCheck/mod.zig");
const Report = @import("Report/mod.zig");
const Global = @import("Global.zig");
const Util = @import("Util.zig");
const Observer = @import("Util/Observer.zig");

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Thread = std.Thread;
