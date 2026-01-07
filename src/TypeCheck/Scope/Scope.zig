const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    put: *const fn (*anyopaque, alloc: Allocator, key: []const u8, varI: Parser.NodeIndex) (Allocator.Error || mod.Error)!void,
    get: *const fn (*anyopaque, key: []const u8) ?Parser.NodeIndex,

    getOrWait: *const fn (ctx: *anyopaque, alloc: Allocator, key: []const u8, func: *const fn (ScopeGlobal.ObserverParams) void, args: ScopeGlobal.ObserverParams) Allocator.Error!?Parser.NodeIndex,

    push: *const fn (*anyopaque, alloc: Allocator) Allocator.Error!void,
    pop: *const fn (*anyopaque, alloc: Allocator) void,

    getGlobal: *const fn (*anyopaque) *ScopeGlobal,
    deepClone: *const fn (*anyopaque, alloc: Allocator) Allocator.Error!Self,

    deinit: *const fn (*anyopaque, alloc: Allocator) void,
};

pub fn put(self: Self, alloc: Allocator, key: []const u8, value: Parser.NodeIndex) (Allocator.Error || mod.Error)!void {
    try self.vtable.put(self.ptr, alloc, key, value);
}

pub fn get(self: Self, key: []const u8) ?Parser.NodeIndex {
    return self.vtable.get(self.ptr, key);
}

pub fn getOrWait(self: Self, alloc: Allocator, key: []const u8, func: *const fn (ScopeGlobal.ObserverParams) void, args: ScopeGlobal.ObserverParams) Allocator.Error!?Parser.NodeIndex {
    return try self.vtable.getOrWait(self.ptr, alloc, key, func, args);
}

pub fn push(self: Self, alloc: Allocator) Allocator.Error!void {
    try self.vtable.push(self.ptr, alloc);
}

pub fn pop(self: Self, alloc: Allocator) void {
    self.vtable.pop(self.ptr, alloc);
}

pub fn getGlobal(self: Self) *ScopeGlobal {
    return self.vtable.getGlobal(self.ptr);
}

pub fn deepClone(self: Self, alloc: Allocator) Allocator.Error!Self {
    return self.vtable.deepClone(self.ptr, alloc);
}

pub fn deinit(self: Self, alloc: Allocator) void {
    self.vtable.deinit(self.ptr, alloc);
}

const ScopeGlobal = @import("ScopeGlobal.zig");
const mod = @import("mod.zig");

const Parser = @import("../../Parser/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
