pub fn transformType(self: TranslationUnit, typeIndex: Parser.NodeIndex) void {
    const node = self.global.nodes.get(typeIndex);

    const tag = node.tag.load(.acquire);
    switch (tag) {
        .fakeType => transformIdentiferType(self, typeIndex),
        .funcType => transformFuncType(self, typeIndex),
        .type => {},
        else => unreachable,
    }
}

fn transformFuncType(self: TranslationUnit, typeIndex: Parser.NodeIndex) void {
    const node = self.global.nodes.get(typeIndex);
    std.debug.assert(node.tag.load(.acquire) == .funcType);

    std.debug.assert(node.data[0].load(.acquire) == 0);

    const retTypeIndex = node.data[1].load(.acquire);
    std.debug.assert(retTypeIndex != 0);
    transformType(self, retTypeIndex);
}

// NOTE: Maybe good idea to create a new node, if the panic is triggered and cannot check if the correctness is still okey
fn transformIdentiferType(self: TranslationUnit, typeIndex: Parser.NodeIndex) void {
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
                .s8, .s16, .s32, .s64 => .sint,
                .u8, .u16, .u32, .u64 => .uint,
            };
        }
    };

    const node = self.global.nodes.get(typeIndex);

    const type_ = node.tag.load(.acquire);
    if (type_ == .type) return;
    std.debug.assert(type_ == .fakeType);

    const name = node.getText(self.global);

    const typeInfo = std.meta.stringToEnum(TypeName, name) orelse @panic("Aliases or struct arent supported yet");

    const nodePtr = self.global.nodes.getPtr(typeIndex);

    if (nodePtr.tag.cmpxchgStrong(.fakeType, .type, .seq_cst, .monotonic) != null) {
        std.debug.assert(nodePtr.tag.load(.acquire) == .type);
        return;
    }

    const resultSize = nodePtr.data.@"0".cmpxchgStrong(0, typeInfo.bitSize(), .acq_rel, .monotonic);
    const resultPrimitive = nodePtr.data.@"1".cmpxchgStrong(0, @intFromEnum(typeInfo.nodeKind()), .acq_rel, .monotonic);

    // NOTE: if this fails and the if was successful is sus
    std.debug.assert(resultSize == null and resultPrimitive == null);
}

pub fn typeEqual(self: TranslationUnit, actualI: Parser.NodeIndex, expectedI: Parser.NodeIndex) bool {
    const actual = self.global.nodes.get(actualI);
    const expected = self.global.nodes.get(expectedI);

    std.debug.assert(actual.tag.load(.acquire) == .type and expected.tag.load(.acquire) == .type);

    return expected.data[1].load(.acquire) == actual.data[1].load(.acquire) and expected.data[0].load(.acquire) == actual.data[0].load(.acquire);
}

pub fn canTypeBeCoerced(self: TranslationUnit, actualI: Parser.NodeIndex, expectedI: Parser.NodeIndex) bool {
    const actual = self.global.nodes.get(actualI);
    const expected = self.global.nodes.get(expectedI);
    return expected.data[1].load(.acquire) == actual.data[1].load(.acquire) and expected.data[0].load(.acquire) >= actual.data[0].load(.acquire);
}

const std = @import("std");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
