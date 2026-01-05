const Self = @This();

base: StringHashMapUnmanaged(Parser.NodeIndex) = .{},
observer: Util.Observer([]const u8, ObserverParams) = .{},
refCount: std.atomic.Value(usize) = std.atomic.Value(usize).init(1),
rwLock: std.Thread.RwLock = .{},

fn init(pool: *std.Thread.Pool) Self {
    var self: Self = .{};

    self.observer.init(pool);
    return self;
}

// NOTE: Always initializes on heap
pub fn initHeap(alloc: Allocator, pool: *std.Thread.Pool) Allocator.Error!*Self {
    const self: *Self = try alloc.create(Self);
    self.* = init(pool);

    return self;
}

pub fn put(ctx: *anyopaque, alloc: Allocator, key: []const u8, value: Parser.NodeIndex) Allocator.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    std.debug.assert(get(self, key) == null);
    {
        self.rwLock.lock();
        defer self.rwLock.unlock();

        try self.base.put(alloc, key, value);
    }

    try self.observer.alert(alloc, key);
}

pub fn get(ctx: *anyopaque, key: []const u8) ?Parser.NodeIndex {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.rwLock.lockShared();
    defer self.rwLock.unlockShared();

    return self.base.get(key);
}

pub fn waitingFor(ctx: *anyopaque, alloc: Allocator, key: []const u8, func: *const fn (ObserverParams) void, args: ObserverParams) Allocator.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    try self.observer.push(alloc, key, func, args);

    if (get(self, key)) |_| {
        try self.observer.alert(alloc, key);
    }
}

pub fn waitingForUnlock(ctx: *anyopaque, alloc: Allocator, key: []const u8, func: *const fn (ObserverParams) void, args: ObserverParams) Allocator.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    try self.observer.pushUnlock(alloc, key, func, args);
}

pub fn getOrWait(ctx: *anyopaque, alloc: Allocator, key: []const u8, func: *const fn (ObserverParams) void, args: ObserverParams) Allocator.Error!?Parser.NodeIndex {
    const self: *Self = @ptrCast(@alignCast(ctx));

    self.observer.mutex.lock();
    defer self.observer.mutex.unlock();

    const result = get(ctx, key);

    if (result) |r| return r;

    try waitingForUnlock(self, alloc, key, func, args);

    return null;
}

pub fn push(ctx: *const anyopaque, alloc: Allocator) Allocator.Error!void {
    const self: *const Self = @ptrCast(@alignCast(ctx));
    _ = .{ self, alloc };
    unreachable;
}

pub fn pop(ctx: *const anyopaque, alloc: Allocator) void {
    const self: *const Self = @ptrCast(@alignCast(ctx));
    _ = .{ self, alloc };
    unreachable;
}

pub fn getGlobal(ctx: *anyopaque) *Self {
    const self: *Self = @ptrCast(@alignCast(ctx));
    return self.acquire();
}

pub fn deepClone(ctx: *anyopaque, alloc: Allocator) Allocator.Error!Scope {
    const self: *Self = @ptrCast(@alignCast(ctx));
    _ = alloc;

    return self.acquire().scope();
}

pub fn deinit(ctx: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (self.release()) {
        self.base.deinit(alloc);
        self.observer.deinit(alloc);
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

            .waitingFor = waitingFor,
            .getOrWait = getOrWait,

            .push = push,
            .pop = pop,

            .getGlobal = getGlobal,
            .deepClone = deepClone,

            .deinit = deinit,
        },
    };
}

pub const ObserverParams = struct { @import("../TranslationUnit.zig"), @import("std").mem.Allocator, Parser.NodeIndex, Parser.NodeIndex, ?*Report.Reports };

const Scope = @import("Scope.zig");
const ScopeFunc = @import("ScopeFunc.zig");

const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");
const Util = @import("../Util/Observer.zig");

const std = @import("std");
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;
const Allocator = std.mem.Allocator;
