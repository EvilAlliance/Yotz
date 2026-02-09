const Self = @This();

ptr: *anyopaque,
vtable: *const VTable,

const VTable = struct {
    put: *const fn (*anyopaque, alloc: Allocator, key: []const u8, variable: *Parser.Node.Declarator) (Allocator.Error || mod.Error)!void,
    get: *const fn (*anyopaque, key: []const u8) ?*Parser.Node.Declarator,

    push: *const fn (*anyopaque, alloc: Allocator) Allocator.Error!void,
    pop: *const fn (*anyopaque, alloc: Allocator, reports: ?*Report.Reports) void,

    getGlobal: *const fn (*anyopaque) *ScopeGlobal,
    deepClone: *const fn (*anyopaque, alloc: Allocator) Allocator.Error!Self,

    pushDependant: *const fn (*anyopaque, Allocator, []const u8, *Parser.Node.VarConst) Allocator.Error!void,
    popDependant: *const fn (*anyopaque, []const u8) ?*Parser.Node.VarConst,

    deinit: *const fn (*anyopaque, alloc: Allocator, reports: ?*Report.Reports) void,
};

pub fn put(self: Self, alloc: Allocator, key: []const u8, value: *Parser.Node.Declarator) (Allocator.Error || mod.Error)!void {
    try self.vtable.put(self.ptr, alloc, key, value);
}

pub fn get(self: Self, key: []const u8) ?*Parser.Node.Declarator {
    return self.vtable.get(self.ptr, key);
}

pub fn push(self: Self, alloc: Allocator) Allocator.Error!void {
    try self.vtable.push(self.ptr, alloc);
}

pub fn pop(self: Self, alloc: Allocator, reports: ?*Report.Reports) void {
    self.vtable.pop(self.ptr, alloc, reports);
}

pub fn getGlobal(self: Self) *ScopeGlobal {
    return self.vtable.getGlobal(self.ptr);
}

pub fn deepClone(self: Self, alloc: Allocator) Allocator.Error!Self {
    return self.vtable.deepClone(self.ptr, alloc);
}

pub fn pushDependant(self: Self, alloc: Allocator, key: []const u8, value: *Parser.Node.VarConst) Allocator.Error!void {
    return self.vtable.pushDependant(self.ptr, alloc, key, value);
}

pub fn popDependant(self: Self, key: []const u8) ?*Parser.Node.VarConst {
    return self.vtable.popDependant(self.ptr, key);
}

pub fn deinit(self: Self, alloc: Allocator, reports: ?*Report.Reports) void {
    self.vtable.deinit(self.ptr, alloc, reports);
}

const ScopeGlobal = @import("ScopeGlobal.zig");
const mod = @import("mod.zig");

const Parser = @import("../../Parser/mod.zig");
const Report = @import("../../Report/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
