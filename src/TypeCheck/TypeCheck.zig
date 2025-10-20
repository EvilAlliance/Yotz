const Self = @This();

ast: *Parser.Ast,
message: Message,

pub fn init(ast: *Parser.Ast) Self {
    return Self{
        .ast = ast,
        .message = Message.init(ast),
    };
}

pub fn checkRoot(self: *Self, alloc: Allocator, rootIndex: Parser.NodeIndex) Allocator.Error!void {
    const root = self.ast.getNode(.Bound, rootIndex);

    var nodeIndex = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (nodeIndex != endIndex) {
        const node = self.ast.getNode(.Bound, nodeIndex);
        defer nodeIndex = node.next.load(.acquire);

        switch (node.tag.load(.acquire)) {
            .variable, .constant => {
                // NOTE: At the time being this is not changed so it should be fine;
                const functionIndex = node.data.@"1".load(.acquire);
                if (functionIndex == 0) @panic("Fuck this is multithraded and the function was not parsed yet, what do I do, make a checkpoint system that saves this and then does it");

                while (true) {
                    Type.transformType(self, self.ast.getNode(.UnBound, functionIndex).data[1].load(.acquire));

                    const typeIndex = node.data[0].load(.acquire);
                    if (typeIndex != 0) {
                        Type.transformType(self, typeIndex);
                        self.checkTypeFunction(alloc, typeIndex, functionIndex);
                        break;
                    } else {
                        const functionTypeIndex = try self.inferTypeFunction(alloc, functionIndex);
                        const nodePtr = self.ast.getNodePtr(.Bound, nodeIndex);
                        const result = nodePtr.data.@"0".cmpxchgWeak(0, functionTypeIndex, .acq_rel, .monotonic);
                        self.ast.unlockShared();

                        if (result == null)
                            break;
                    }
                }
            },

            else => unreachable,
        }
    }
}

pub fn checkTypeFunction(self: *const Self, alloc: Allocator, funcTypeIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex) void {
    _ = alloc;
    const funcProto = self.ast.getNode(.UnBound, funcIndex);
    std.debug.assert(funcProto.tag.load(.acquire) == .funcProto);
    std.debug.assert(funcProto.data[0].load(.acquire) == 0);

    const funcRetTypeIndex = funcProto.data[1].load(.acquire);

    const funcType = self.ast.getNode(.Bound, funcTypeIndex);
    std.debug.assert(funcType.tag.load(.acquire) == .funcType);
    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);

    if (!Type.typeEqual(self, funcRetTypeIndex, retTypeIndex)) {
        self.message.err.incompatibleType(retTypeIndex, funcRetTypeIndex, self.ast.getNodeLocation(.UnBound, funcRetTypeIndex));
    }
}

// TODO: It would be nice that this does not return the function type index and set it inside of it
// TODO: tIndex is an idenfier not a type itself
pub fn inferTypeFunction(self: *Self, alloc: Allocator, funcIndex: Parser.NodeIndex) Allocator.Error!Parser.NodeIndex {
    const proto = self.ast.getNode(.UnBound, funcIndex);
    std.debug.assert(proto.tag.load(.acquire) == .funcProto);

    const tIndex = proto.data[1].load(.acquire);
    std.debug.assert(tIndex != 0);
    std.debug.assert(self.ast.getNode(.UnBound, tIndex).tag.load(.acquire) == .type);

    const functionTypeIndex = try self.ast.nodeList.appendIndex(alloc, Parser.Node{
        .tag = .init(.funcType),
        .tokenIndex = .init(proto.tokenIndex.load(.acquire)),
        .data = .{ .init(0), .init(tIndex) },
        .flags = .init(.{ .inferedFromExpression = true }),
    });

    return functionTypeIndex;
}

pub fn checkFunction(self: *Self, alloc: Allocator, funcIndex: Parser.NodeIndex) void {
    _ = .{ self, alloc, funcIndex };
}

const Observer = @import("./Observer.zig").Observer;
const Type = @import("Type.zig");

const Parser = @import("./../Parser/Parser.zig");
const Message = @import("../Message/Message.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
