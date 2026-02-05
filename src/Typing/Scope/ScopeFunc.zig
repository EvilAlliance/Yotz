const Self = @This();

global: *ScopeGlobal,
base: ArrayList(StringHashMapUnmanaged(*Parser.Node.Declarator)) = .{},

// NOTE: Always initializes on heap
pub fn initHeap(alloc: Allocator, globaScope: *ScopeGlobal) Allocator.Error!*Self {
    const self: *Self = try alloc.create(Self);
    self.* = .{
        .global = globaScope,
    };

    return self;
}

pub fn put(ctx: *anyopaque, alloc: Allocator, key: []const u8, value: *Parser.Node.Declarator) (Allocator.Error || mod.Error)!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (get(self, key)) |_| return mod.Error.KeyAlreadyExists;

    const count = self.base.items.len;
    assert(count > 0);

    const lastScope = &self.base.items[count - 1];
    try lastScope.put(alloc, key, value);
}

pub fn get(ctx: *anyopaque, key: []const u8) ?*Parser.Node.Declarator {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var i: usize = self.base.items.len;
    while (i > 0) {
        i -= 1;

        const dic = self.base.items[i];
        if (dic.get(key)) |n| return n;
    }
    if (ScopeGlobal.get(self.global, key)) |n| return n;

    return null;
}

pub fn push(ctx: *anyopaque, alloc: Allocator) Allocator.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    try self.base.append(alloc, .{});
}

pub fn pop(ctx: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    assert(self.base.items.len > 0);
    var dic = self.base.pop().?;

    dic.deinit(alloc);
}

pub fn getGlobal(ctx: *anyopaque) *ScopeGlobal {
    const self: *Self = @ptrCast(@alignCast(ctx));
    return ScopeGlobal.getGlobal(self.global);
}

pub fn putGlobal(self: *Self, alloc: Allocator, key: []const u8, value: Parser.Node.Declarator) Allocator.Error!void {
    return self.global.vtable.put(self.global, alloc, key, value);
}

pub fn getFromGlobal(self: *Self, key: []const u8) ?Parser.Node.Declarator {
    return self.global.vtable.get(self.global, key);
}

pub fn deepClone(ctx: *anyopaque, alloc: Allocator) Allocator.Error!Scope {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const x = try initHeap(alloc, self.global.acquire());

    for (self.base.items) |value| {
        try x.base.append(alloc, try value.clone(alloc));
    }

    return x.scope();
}

pub fn deinit(ctx: *anyopaque, alloc: Allocator) void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    for (self.base.items) |*value| {
        value.deinit(alloc);
    }

    self.base.deinit(alloc);

    ScopeGlobal.deinit(self.global, alloc);

    alloc.destroy(self);
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

            .deinit = deinit,
        },
    };
}

const Scope = @import("Scope.zig");
const ScopeGlobal = @import("ScopeGlobal.zig");
const mod = @import("mod.zig");

const TypeCheck = @import("../mod.zig");

const Parser = @import("../../Parser/mod.zig");

const std = @import("std");
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
