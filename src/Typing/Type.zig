pub fn transformType(self: *const TranslationUnit, type_: *Parser.Node) void {
    const tag = type_.tag.load(.acquire);
    switch (tag) {
        .fakeType => transformIdentiferType(self, type_),
        .fakeFuncType => transformFuncType(self, type_),
        .type, .funcType => {},
        else => unreachable,
    }
}

fn transformFuncType(self: *const TranslationUnit, funcType: *Parser.Node) void {
    std.debug.assert(funcType.tag.load(.acquire) == .fakeFuncType);

    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);
    std.debug.assert(retTypeIndex != 0);
    transformType(self, self.global.nodes.getPtr(retTypeIndex));

    if (funcType.tag.cmpxchgStrong(.fakeFuncType, .funcType, .seq_cst, .monotonic) != null) {
        std.debug.assert(funcType.tag.load(.acquire) == .funcType);
        return;
    }
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

    type_.data.@"0".store(std.fmt.parseInt(u32, name[1..], 10) catch @panic("Aliases or struct arent supported yet"), .release);
    type_.data.@"1".store(@intFromEnum(typeInfo.nodeKind()), .release);

    if (type_.tag.cmpxchgStrong(.fakeType, .type, .seq_cst, .monotonic) != null) {
        std.debug.assert(type_.tag.load(.acquire) == .type);
        return;
    }
}

pub fn typeEqual(global: *const Global, actual: *const Parser.Node, expected: *const Parser.Node) bool {
    const actualTag = actual.tag.load(.acquire);
    const expectedTag = expected.tag.load(.acquire);

    if (actualTag == .fakeType) std.log.debug("Actual: {}", .{actual});
    if (expectedTag == .fakeType) std.log.debug("Expected: {}", .{expected});
    assert(actualTag != .fakeType and expectedTag != .fakeType);

    if (actualTag == .type and expectedTag == .type)
        return expected.data[1].load(.acquire) == actual.data[1].load(.acquire) and expected.data[0].load(.acquire) == actual.data[0].load(.acquire);
    if (actualTag == .funcType and expectedTag == .funcType) {
        //Args
        assert(actual.data[0].load(.acquire) == 0 and expected.data.@"0".load(.acquire) == 0);
        return typeEqual(
            global,
            global.nodes.getConstPtr(actual.data.@"1".load(.acquire)),
            global.nodes.getConstPtr(expected.data.@"1".load(.acquire)),
        );
    }

    return false;
}

pub fn canTypeBeCoerced(actual: *const Parser.Node, expected: *const Parser.Node) bool {
    return expected.data[1].load(.acquire) == actual.data[1].load(.acquire) and expected.data[0].load(.acquire) >= actual.data[0].load(.acquire);
}

const TranslationUnit = @import("../TranslationUnit.zig");
const Global = @import("../Global.zig");
const Parser = @import("../Parser/mod.zig");

const std = @import("std");

const assert = std.debug.assert;
