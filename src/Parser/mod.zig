pub const NodeIndex = u32;
pub const TokenIndex = u32;

pub const Parser = @import("Parser.zig");
pub const Ast = @import("Ast.zig");
pub const Node = @import("Node.zig");

pub const NodeList = ArrayListThreadSafe(true, Node, NodeIndex, 10);

const ArrayListThreadSafe = @import("../Util/ArrayListThreadSafe.zig").ChunkBase;
