const Self = @This();

pub const Type = enum {
    Root,
    Function,
};

pub fn deinitStatic(alloc: Allocator, bytes: []const u8) void {
    alloc.free(bytes);
}

var ID = std.atomic.Value(usize).init(0);

tag: Type,
global: *Global,
scope: Typing.Scope.Scope,
id: usize,

pub fn initRoot(alloc: Allocator, global: *Global) Allocator.Error!Self {
    const tu = Self{
        .tag = .Root,
        .global = global,
        .scope = (try Typing.Scope.Global.initHeap(alloc)).scope(),
        .id = ID.fetchAdd(1, .acq_rel),
    };

    try global.readyTu.resize(alloc, tu.id + 1);
    global.readyTu.getPtr(tu.id).store(false, .release);
    global.readyTu.unlock();
    assert(!global.readyTu.get(tu.id).load(.acquire));

    return tu;
}

pub fn initFunc(self: *const Self, alloc: Allocator) Allocator.Error!Self {
    const scope = try Typing.Scope.Func.initHeap(alloc, self.scope.getGlobal().acquire());

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

pub fn acquire(self: Self, alloc: Allocator) Allocator.Error!Self {
    return Self{
        .tag = self.tag,
        .global = self.global,
        .scope = try self.scope.deepClone(alloc),
        .id = self.id,
    };
}

pub fn startFunction(self: *const Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: *Parser.Node.FuncProto, reports: ?*Report.Reports) Allocator.Error!void {
    std.debug.assert(self.tag == .Function);

    const callBack = struct {
        fn callBack(comptime func: anytype, args: anytype) void {
            @call(.auto, func, .{ &args[0], args[1], args[2], args[3], args[4] }) catch {
                std.debug.panic("Run Out of Memory", .{});
            };
        }
    }.callBack;

    try self.global.threadPool.spawn(callBack, .{ _startFunction, .{ self.*, alloc, start, placeHolder, reports } });
}

fn _startFunction(self: *const Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: *Parser.Node.FuncProto, reports: ?*Report.Reports) Allocator.Error!void {
    defer self.deinit(alloc);

    if (self.global.subCommand == .Lexer) unreachable;

    var parser = try Parser.Parser.init(self);

    parser.parseFunction(alloc, start, placeHolder, reports) catch |err| switch (err) {
        Parser.Error.UnexpectedToken => return,
        else => return @errorCast(err),
    };

    if (self.global.subCommand == .Parser) return;

    try Typing.Func.typing(self, alloc, placeHolder, reports);

    if (self.global.subCommand == .Typing) return;

    unreachable;
    // const err = try Typing(alloc, &ast);
    //
    // if (self.cont.subCom == .Typing)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
    // if (err) return .{ "", 1 };
    // if (parser.errors.items.len > 0) return .{ "", 1 };
}

pub fn startRoot(self: *const Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: *Parser.Node.Entry, reports: ?*Report.Reports) Allocator.Error!void {
    std.debug.assert(self.tag == .Root);

    const callBack = struct {
        fn callBack(comptime func: anytype, args: anytype) void {
            @call(.auto, func, .{ &args[0], args[1], args[2], args[3], args[4] }) catch {
                std.debug.panic("Run Out of Memory", .{});
            };
        }
    }.callBack;

    try self.global.threadPool.spawn(callBack, .{ _startRoot, .{ self.*, alloc, start, placeHolder, reports } });
}

fn _startRoot(self: *const Self, alloc: Allocator, start: Parser.TokenIndex, placeHolder: *Parser.Node.Entry, reports: ?*Report.Reports) Allocator.Error!void {
    if (self.global.subCommand == .Lexer) unreachable;
    defer self.deinit(alloc);

    var parser = try Parser.Parser.init(self);

    try parser.parseRoot(alloc, start, placeHolder, reports);

    if (self.global.subCommand == .Parser) return;

    const rootIndex = placeHolder.firstRoot.load(.acquire);
    try Typing.Root.typing(self, alloc, self.global.nodes.getPtr(rootIndex), reports);

    if (self.global.subCommand == .Typing) return;

    unreachable;
    //
    // const err = try Typing(alloc, &ast);
    //
    // if (self.cont.subCom == .Typing)
    //     return .{ try ast.toString(alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };
    //
    // if (err) return .{ "", 1 };
    // if (parser.errors.items.len > 0) return .{ "", 1 };
}

pub fn startEntry(alloc: Allocator, arguments: *const ParseArgs.Arguments) std.mem.Allocator.Error!struct { []const u8, u8 } {
    var global: Global = .{ .subCommand = arguments.subCom };
    global.init(alloc, 20) catch std.debug.panic("Could not create threads", .{});
    defer global.deinitStage2(alloc);

    if (!try global.addFile(alloc, arguments.path)) return .{ "", 1 };

    var repBuff: [128]Report.Report = undefined;
    var reports = Report.Reports{
        .items = .{
            .items = repBuff[0..0],
            .capacity = repBuff.len,
        },
    };

    var scope: Typing.Scope.Scope = undefined;
    defer if (arguments.subCom != .Lexer) scope.deinit(alloc);
    if (arguments.subCom != .Lexer) {
        const tu = try initRoot(alloc, &global);
        scope = try tu.scope.deepClone(alloc);

        const entry = try global.nodes.reserve(alloc);
        entry.* = (Parser.Node.Entry{}).asConst().*;

        try tu.startRoot(alloc, 0, entry.asEntry(), &reports);
    }

    const ret = try waitForWork(alloc, &global);

    if (arguments.subCom != .Parser and arguments.subCom != .Lexer) {
        if (scope.get("main")) |main| {
            const funcProtoNode = global.nodes.getConstPtr(main.right.load(.acquire));
            if (funcProtoNode.tag.load(.acquire) != .funcProto) {
                Report.missingMain(&reports);
            } else {
                const funcProto = funcProtoNode.asConstFuncProto();
                const type_ = global.nodes.getConstPtr(funcProto.retType.load(.acquire));
                if (!Typing.Type.typeEqual(&global, type_, &.{
                    .tag = .init(.type),
                    .tokenIndex = .init(0),
                    .left = .init(8),
                    .right = .init(@intFromEnum(Parser.Node.Primitive.uint)),
                    .next = .init(0),
                })) Report.mustReturnU8(&reports, "main", type_);
            }
        } else Report.missingMain(&reports);
    }

    const message = Report.Message.init(&global);
    for (reports.slice()) |r| {
        r.display(message);
    }

    return ret;
}

pub fn waitForWork(alloc: Allocator, global: *Global) Allocator.Error!struct { []const u8, u8 } {
    global.deinitStage1(alloc);

    if (global.subCommand == .Lexer) {
        return .{ try global.toStringToken(alloc), 0 };
    }

    const index = 0;

    if (global.subCommand == .Parser) return .{ try global.toStringAst(alloc, global.nodes.get(index).right.load(.acquire)), 0 };

    if (global.subCommand == .Typing) return .{ try global.toStringAst(alloc, global.nodes.get(index).right.load(.acquire)), 0 };

    return .{ "", 1 };
}

const ParseArgs = @import("ParseArgs.zig");
const Lexer = @import("Lexer/mod.zig");
const Parser = @import("Parser/mod.zig");
const Typing = @import("Typing/mod.zig");
const Report = @import("Report/mod.zig");
const Global = @import("Global.zig");
const Util = @import("Util.zig");
const Observer = @import("Util/Observer.zig");

const std = @import("std");

const assert = std.debug.assert;

const mem = std.mem;
const Allocator = mem.Allocator;

const Thread = std.Thread;
