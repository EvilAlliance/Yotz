const Self = @This();

base: StringHashMapUnmanaged(struct { *Parser.Node.Declarator, std.SinglyLinkedList }) = .{},
refCount: std.atomic.Value(usize) = std.atomic.Value(usize).init(1),
rwLock: std.Thread.RwLock = .{},

node: std.SinglyLinkedList = .{},

// NOTE: Always initializes on heap
pub fn initHeap(alloc: Allocator) Allocator.Error!*Self {
    const self: *Self = try alloc.create(Self);
    self.* = .{};

    return self;
}

pub fn put(ctx: *anyopaque, alloc: Allocator, key: []const u8, value: *Parser.Node.Declarator) (Allocator.Error || mod.Error)!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (get(self, key)) |_| return mod.Error.KeyAlreadyExists;
    {
        self.rwLock.lock();
        defer self.rwLock.unlock();

        try self.base.put(alloc, key, .{ value, .{} });
    }
}

pub fn get(ctx: *anyopaque, key: []const u8) ?*Parser.Node.Declarator {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.rwLock.lockShared();
    defer self.rwLock.unlockShared();

    return if (self.base.get(key)) |x| x.@"0" else null;
}

pub fn push(ctx: *const anyopaque, alloc: Allocator) Allocator.Error!void {
    const self: *const Self = @ptrCast(@alignCast(ctx));
    _ = .{ self, alloc };
    unreachable;
}

pub fn pop(ctx: *const anyopaque, alloc: Allocator, reports: ?*Report.Reports) void {
    const self: *const Self = @ptrCast(@alignCast(ctx));
    _ = .{ self, alloc, reports };
    unreachable;
}

pub fn getGlobal(ctx: *anyopaque) *Self {
    const self: *Self = @ptrCast(@alignCast(ctx));
    return self;
}

pub fn deepClone(ctx: *anyopaque, alloc: Allocator) Allocator.Error!Scope {
    const self: *Self = @ptrCast(@alignCast(ctx));
    _ = alloc;

    return self.acquire().scope();
}

pub fn pushDependant(ctx: *anyopaque, alloc: Allocator, key: []const u8, value: *Parser.Node.VarConst) Allocator.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.rwLock.lock();
    defer self.rwLock.unlock();

    const baseValue = self.base.getPtr(key) orelse return;

    const dependant: *mod.Dependant = if (self.node.popFirst()) |node| @fieldParentPtr("node", node) else try alloc.create(mod.Dependant);
    dependant.variable = value;

    baseValue.@"1".prepend(&dependant.node);
}

pub fn popDependant(ctx: *anyopaque, key: []const u8) ?*Parser.Node.VarConst {
    const self: *Self = @ptrCast(@alignCast(ctx));

    self.rwLock.lock();
    defer self.rwLock.unlock();

    const value = self.base.getPtr(key) orelse return null;

    const node = value.@"1".popFirst() orelse return null;
    const variable: *mod.Dependant = @fieldParentPtr("node", node);
    self.node.prepend(node);

    return variable.variable;
}

pub fn deinit(ctx: *anyopaque, alloc: Allocator, reports: ?*Report.Reports) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (self.release()) {
        var it = self.base.valueIterator();
        while (it.next()) |val| {
            while (val.@"1".popFirst()) |node| alloc.destroy(@as(*mod.Dependant, @fieldParentPtr("node", node)));
            if (!val.@"0".flags.load(.acquire).used) {
                Report.unusedVariable(reports, val.@"0");
            }
        }

        self.base.deinit(alloc);

        while (self.node.popFirst()) |n| {
            const dependant: *mod.Dependant = @fieldParentPtr("node", n);
            alloc.destroy(dependant);
        }
        alloc.destroy(self);
    }
}

pub fn acquire(self: *@This()) *Self {
    _ = self.refCount.fetchAdd(1, .acquire);
    return self;
}

pub fn release(self: *@This()) bool {
    const prev = self.refCount.fetchSub(1, .release);
    return prev == 1;
}

pub fn scope(self: *Self) Scope {
    return .{
        .ptr = self,
        .vtable = &.{
            .put = put,
            .get = get,

            .push = push,
            .pop = pop,

            .getGlobal = getGlobal,
            .deepClone = deepClone,

            .pushDependant = pushDependant,
            .popDependant = popDependant,

            .deinit = deinit,
        },
    };
}

const Scope = @import("Scope.zig");
const ScopeFunc = @import("ScopeFunc.zig");
const mod = @import("mod.zig");

const TranslationUnit = @import("../../TranslationUnit.zig");
const Parser = @import("../../Parser/mod.zig");
const Report = @import("../../Report/mod.zig");
const Observer = @import("../../Util/Observer.zig");

const std = @import("std");
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;
const Allocator = std.mem.Allocator;
