const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Parser = @import("./../Parser/Parser.zig");

pub const Scope = std.StringHashMapUnmanaged(Parser.NodeIndex);

list: std.ArrayList(Scope),

pub fn init() @This() {
    return .{
        .list = .{},
    };
}

pub fn deinit(self: *@This(), alloc: Allocator) void {
    for (self.list.items) |*value| {
        value.deinit(alloc);
    }
    self.list.deinit(alloc);
}

pub inline fn len(self: @This()) usize {
    return self.list.items.len;
}

pub inline fn items(self: @This()) []Scope {
    return self.list.items;
}

pub inline fn append(self: *@This(), alloc: Allocator, scope: Scope) std.mem.Allocator.Error!void {
    return self.list.append(alloc, scope);
}

pub inline fn pop(self: *@This()) ?Scope {
    return self.list.pop();
}

pub inline fn getLastPtr(self: *@This()) *Scope {
    return &self.list.items[self.len() - 1];
}

pub fn deepClone(self: @This(), alloc: Allocator) std.mem.Allocator.Error!@This() {
    var x: @This() = @This().init();
    for (self.list.items) |value| {
        try x.append(alloc, try value.clone(alloc));
    }

    return x;
}
