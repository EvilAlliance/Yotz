pub const NodeIndex = u32;
pub const TokenIndex = u32;

pub const Error = Parser.Error;

pub const Parser = @import("Parser.zig");
pub const Ast = @import("Ast.zig");
pub const Node = @import("Node.zig");

const BucketSize = std.math.pow(NodeIndex, 2, 4);

pub const NodeList = BucketList(Node, NodeIndex, BucketSize);

const BucketList = @import("../Util/BucketArray.zig").BucketArray;

const std = @import("std");
