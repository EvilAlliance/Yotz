pub fn transformType(self: *TypeChecker, typeIndex: Parser.NodeIndex) void {
    const node = self.ast.getNode(.UnCheck, typeIndex);

    const tag = node.tag.load(.acquire);
    switch (tag) {
        .fakeType => transformIdentiferType(self, typeIndex),
        .funcType => transformFuncType(self, typeIndex),
        .type => {},
        else => unreachable,
    }
}

fn transformFuncType(self: *TypeChecker, typeIndex: Parser.NodeIndex) void {
    const node = self.ast.getNode(.UnCheck, typeIndex);
    std.debug.assert(node.tag.load(.acquire) == .funcType);

    std.debug.assert(node.data[0].load(.acquire) == 0);

    const retTypeIndex = node.data[1].load(.acquire);
    std.debug.assert(retTypeIndex != 0);
    transformType(self, retTypeIndex);
}

// NOTE: Maybe good idea to create a new node, if the panic is triggered and cannot check if the correctness is still okey
fn transformIdentiferType(self: *TypeChecker, typeIndex: Parser.NodeIndex) void {
    const TypeName = enum {
        u8,
        u16,
        u32,
        u64,
        s8,
        s16,
        s32,
        s64,

        pub fn bitSize(s: @This()) Parser.NodeIndex {
            return switch (s) {
                .u8, .s8 => 8,
                .u16, .s16 => 16,
                .u32, .s32 => 32,
                .u64, .s64 => 64,
            };
        }

        pub fn nodeKind(s: @This()) Parser.Node.Primitive {
            return switch (s) {
                .s8, .s16, .s32, .s64 => .int,
                .u8, .u16, .u32, .u64 => .uint,
            };
        }
    };

    const node = self.ast.getNode(.UnCheck, typeIndex);

    std.debug.assert(node.tag.load(.acquire) == .fakeType);

    const name = node.getTextAst(self.ast);

    const typeInfo = std.meta.stringToEnum(TypeName, name) orelse @panic("Aliases or struct arent supported yet");

    const nodePtr = self.ast.getNodePtr(.UnCheck, typeIndex);
    if (nodePtr.tag.cmpxchgStrong(.fakeType, .type, .seq_cst, .monotonic) != null) @panic("I Have to check this but theoretically this was change by another thread, this could be a return, verify");
    const resultSize = nodePtr.data.@"0".cmpxchgStrong(0, typeInfo.bitSize(), .acq_rel, .monotonic);
    const resultPrimitive = nodePtr.data.@"1".cmpxchgStrong(0, @intFromEnum(typeInfo.nodeKind()), .acq_rel, .monotonic);
    self.ast.unlockShared();

    // NOTE: if this fails and the if was successful is sus
    std.debug.assert(resultSize == null and resultPrimitive == null);
}

pub fn typeEqual(self: *const TypeChecker, actualI: Parser.NodeIndex, expectedI: Parser.NodeIndex) bool {
    const actual = self.ast.getNode(.UnCheck, actualI);
    const expected = self.ast.getNode(.UnCheck, expectedI);

    std.debug.assert(actual.tag.load(.acquire) == .type and expected.tag.load(.acquire) == .type);

    return expected.data[1].load(.acquire) == actual.data[1].load(.acquire) and expected.data[0].load(.acquire) == actual.data[0].load(.acquire);
}

const std = @import("std");

const TypeChecker = @import("./TypeCheck.zig");
const Parser = @import("../Parser/mod.zig");
