pub fn transformType(self: *const TranslationUnit, type_: *Parser.Node) void {
    const tag = type_.tag.load(.acquire);
    switch (tag) {
        .fakeType => transformIdentiferType(self, type_),
        .funcType => transformFuncType(self, type_),
        .type => {},
        else => unreachable,
    }
}

fn transformFuncType(self: *const TranslationUnit, funcType: *const Parser.Node) void {
    std.debug.assert(funcType.tag.load(.acquire) == .funcType);

    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);
    std.debug.assert(retTypeIndex != 0);
    transformType(self, self.global.nodes.getPtr(retTypeIndex));
}

// NOTE: Maybe good idea to create a new node, if the panic is triggered and cannot check if the correctness is still okey
fn transformIdentiferType(self: *const TranslationUnit, type_: *Parser.Node) void {
    const TypeName = enum {
        u,
        s,
        f,

        pub fn nodeKind(s: @This()) Parser.Node.Primitive {
            return switch (s) {
                .s => .sint,
                .u => .uint,
                .f => .float,
            };
        }
    };

    const tag = type_.tag.load(.acquire);
    if (tag == .type) return;
    std.debug.assert(tag == .fakeType);

    const name = type_.getText(self.global);
    if (name.len > 3) @panic("Aliases or struct arent supported yet");

    const typeInfo = std.meta.stringToEnum(TypeName, name[0..1]) orelse @panic("Aliases or struct arent supported yet");

    if (type_.tag.cmpxchgStrong(.fakeType, .type, .seq_cst, .monotonic) != null) {
        std.debug.assert(type_.tag.load(.acquire) == .type);
        return;
    }

    const resultSize = type_.data.@"0".cmpxchgStrong(0, std.fmt.parseInt(u32, name[1..], 10) catch @panic("Aliases or struct arent supported yet"), .acq_rel, .monotonic);
    const resultPrimitive = type_.data.@"1".cmpxchgStrong(0, @intFromEnum(typeInfo.nodeKind()), .acq_rel, .monotonic);

    // NOTE: if this fails and the if was successful is sus
    std.debug.assert(resultSize == null and resultPrimitive == null);
}

pub fn typeEqual(actual: *const Parser.Node, expected: *const Parser.Node) bool {
    std.debug.assert(actual.tag.load(.acquire) == .type and expected.tag.load(.acquire) == .type);

    return expected.data[1].load(.acquire) == actual.data[1].load(.acquire) and expected.data[0].load(.acquire) == actual.data[0].load(.acquire);
}

pub fn canTypeBeCoerced(actual: *const Parser.Node, expected: *const Parser.Node) bool {
    return expected.data[1].load(.acquire) == actual.data[1].load(.acquire) and expected.data[0].load(.acquire) >= actual.data[0].load(.acquire);
}

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");

const std = @import("std");
