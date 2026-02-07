const Self = @This();

global: *ScopeGlobal,
base: ArrayList(StringHashMapUnmanaged(struct { *Parser.Node.Declarator, std.SinglyLinkedList })) = .{},

node: std.SinglyLinkedList = .{},

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
    try lastScope.put(alloc, key, .{ value, .{} });
}

pub fn get(ctx: *anyopaque, key: []const u8) ?*Parser.Node.Declarator {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var i: usize = self.base.items.len;
    while (i > 0) {
        i -= 1;

        const dic = self.base.items[i];
        if (dic.get(key)) |n| return n.@"0";
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

    var it = dic.valueIterator();
    while (it.next()) |val| while (val.@"1".popFirst()) |node| alloc.destroy(@as(*mod.Dependant, @fieldParentPtr("node", node)));
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
        var it = value.valueIterator();
        while (it.next()) |val| while (val.@"1".popFirst()) |node| alloc.destroy(@as(*mod.Dependant, @fieldParentPtr("node", node)));
        value.deinit(alloc);
    }

    self.base.deinit(alloc);

    ScopeGlobal.deinit(self.global, alloc);

    while (self.node.popFirst()) |n| {
        const dependant: *mod.Dependant = @fieldParentPtr("node", n);
        alloc.destroy(dependant);
    }

    alloc.destroy(self);
}

pub fn pushDependant(ctx: *anyopaque, alloc: Allocator, key: []const u8, value: *Parser.Node.VarConst) Allocator.Error!void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var i: usize = self.base.items.len;
    while (i > 0) {
        i -= 1;
        const baseValue = self.base.items[i].getPtr(key) orelse continue;

        const dependant: *mod.Dependant = if (self.node.popFirst()) |node| @fieldParentPtr("node", node) else try alloc.create(mod.Dependant);
        dependant.variable = value;
        baseValue.@"1".prepend(&dependant.node);

        return;
    }

    return ScopeGlobal.pushDependant(ctx, alloc, key, value);
}

pub fn popDependant(ctx: *anyopaque, key: []const u8) ?*Parser.Node.VarConst {
    const self: *Self = @ptrCast(@alignCast(ctx));

    var i: usize = self.base.items.len;
    while (i > 0) {
        i -= 1;
        const value = self.base.items[i].getPtr(key) orelse continue;

        const node = value.@"1".popFirst() orelse return null;

        const variable: *mod.Dependant = @fieldParentPtr("node", node);
        self.node.prepend(node);

        return variable.variable;
    }

    return ScopeGlobal.popDependant(self.global, key);
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
const ScopeGlobal = @import("ScopeGlobal.zig");
const mod = @import("mod.zig");

const TypeCheck = @import("../mod.zig");

const Parser = @import("../../Parser/mod.zig");

const std = @import("std");
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
