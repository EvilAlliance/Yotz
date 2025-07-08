const Self = @This();

const std = @import("std");
const Parser = @import("./../Parser/Parser.zig");

pub const Scope = std.StringHashMap(Parser.NodeIndex);

list: std.ArrayList(Scope),

pub fn init(alloc: std.mem.Allocator) @This() {
    return .{ .list = std.ArrayList(Scope).init(alloc) };
}

pub fn deinit(self: *@This()) void {
    for (self.list.items) |*value| {
        value.deinit();
    }
    self.list.deinit();
}

pub inline fn len(self: @This()) usize {
    return self.list.items.len;
}

pub inline fn items(self: @This()) []Scope {
    return self.list.items;
}

pub inline fn append(self: *@This(), scope: Scope) std.mem.Allocator.Error!void {
    return self.list.append(scope);
}

pub inline fn pop(self: *@This()) ?Scope {
    return self.list.pop();
}

pub inline fn getLastPtr(self: *@This()) *Scope {
    return &self.list.items[self.len() - 1];
}

pub fn deepClone(self: @This()) std.mem.Allocator.Error!@This() {
    var x: @This() = .{ .list = std.ArrayList(Scope).init(self.list.allocator) };
    for (self.list.items) |value| {
        try x.append(try value.clone());
    }

    return x;
}
