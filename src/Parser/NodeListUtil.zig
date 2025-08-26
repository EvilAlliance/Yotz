pub fn addNode(alloc: Allocator, arr: *ArrayList(Parser.Node), node: Parser.Node) std.mem.Allocator.Error!Parser.NodeIndex {
    const index: Parser.NodeIndex = @intCast(arr.items.len);
    try arr.append(alloc, node);
    return index;
}

pub fn reserveNode(alloc: Allocator, arr: *ArrayList(Parser.Node), node: Parser.Node) std.mem.Allocator.Error!Parser.NodeIndex {
    const index: Parser.NodeIndex = @intCast(arr.items.len);
    try arr.append(alloc, node);
    return index;
}

const std = @import("std");
const ArrayList = std.ArrayList;
const mem = std.mem;

const Allocator = mem.Allocator;

const Parser = @import("./Parser.zig");
