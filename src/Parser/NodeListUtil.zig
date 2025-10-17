pub fn addNode(alloc: Allocator, arr: *Parser.NodeList.Chunk, node: Parser.Node) std.mem.Allocator.Error!Parser.NodeIndex {
    return try arr.appendIndex(alloc, node);
}

pub fn reserveNode(alloc: Allocator, arr: *Parser.NodeList.Chunk, node: Parser.Node) std.mem.Allocator.Error!Parser.NodeIndex {
    return try arr.appendIndex(alloc, node);
}

const std = @import("std");
const ArrayList = std.ArrayList;
const mem = std.mem;

const Allocator = mem.Allocator;

const Parser = @import("./Parser.zig");
