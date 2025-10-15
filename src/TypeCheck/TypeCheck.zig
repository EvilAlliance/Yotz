const Self = @This();

pub fn init() Self {
    return Self{};
}

pub fn checkRoot(self: *Self, alloc: Allocator, rootIndex: Parser.NodeIndex) void {
    _ = .{ self, alloc, rootIndex };
    unreachable;
}

pub fn checkFunction(self: *Self, alloc: Allocator, funcIndex: Parser.NodeIndex) void {
    _ = .{ self, alloc, funcIndex };
    unreachable;
}

const Parser = @import("./../Parser/Parser.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;

