const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    put: *const fn (*anyopaque, alloc: Allocator, key: []const u8, varI: Parser.NodeIndex) Allocator.Error!void,
    get: *const fn (*anyopaque, key: []const u8) ?Parser.NodeIndex,

    waitingFor: *const fn (ctx: *anyopaque, alloc: Allocator, key: []const u8, func: *const fn (Expression.ObserverParams) void, args: Expression.ObserverParams) Allocator.Error!void,

    push: *const fn (*anyopaque, alloc: Allocator) Allocator.Error!void,
    pop: *const fn (*anyopaque, alloc: Allocator) void,

    getGlobal: *const fn (*anyopaque) *ScopeGlobal,
    deepClone: *const fn (*anyopaque, alloc: Allocator) Allocator.Error!ScopeFunc,

    deinit: *const fn (*anyopaque, alloc: Allocator) void,
};

pub fn put(self: *Self, alloc: Allocator, key: []const u8, value: Parser.NodeIndex) Allocator.Error!void {
    try self.vtable.put(self.ptr, alloc, key, value);
}

pub fn get(self: *const Self, key: []const u8) ?Parser.NodeIndex {
    return self.vtable.get(self.ptr, key);
}

pub fn waitingFor(self: *Self, alloc: Allocator, key: []const u8, func: *const fn (Expression.ObserverParams) void, args: Expression.ObserverParams) Allocator.Error!void {
    try self.vtable.waitingFor(self.ptr, alloc, key, func, args);
}

pub fn push(self: *const Self, alloc: Allocator) Allocator.Error!void {
    try self.vtable.push(self.ptr, alloc);
}

pub fn pop(self: *const Self, alloc: Allocator) void {
    self.vtable.pop(self.ptr, alloc);
}

pub fn getGlobal(self: *const Self) *ScopeGlobal {
    return self.vtable.getGlobal(self.ptr);
}

pub fn deinit(self: *const Self, alloc: Allocator) void {
    self.vtable.deinit(self.ptr, alloc);
}

const ScopeGlobal = @import("ScopeGlobal.zig");
const ScopeFunc = @import("ScopeFunc.zig");

const Expression = @import("../Expression.zig");

const Parser = @import("../../Parser/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
