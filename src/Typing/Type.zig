pub fn transformType(self: *const TranslationUnit, type_: *Parser.Node) void {
    const tag = type_.tag.load(.acquire);
    switch (tag) {
        .fakeType => transformIdentiferType(self, type_),
        .fakeFuncType => transformFuncType(self, type_),
        .fakeArgType => transformArgsType(self, type_),
        .type, .funcType, .argType => {},
        else => unreachable,
    }
}

fn transformFuncType(self: *const TranslationUnit, funcType: *Parser.Node) void {
    std.debug.assert(funcType.tag.load(.acquire) == .fakeFuncType);

    const argIndex = funcType.left.load(.acquire);
    if (argIndex != 0) transformType(self, self.global.nodes.getPtr(argIndex));

    const retTypeIndex = funcType.right.load(.acquire);
    std.debug.assert(retTypeIndex != 0);
    transformType(self, self.global.nodes.getPtr(retTypeIndex));

    if (funcType.tag.cmpxchgStrong(.fakeFuncType, .funcType, .seq_cst, .monotonic) != null) {
        std.debug.assert(funcType.tag.load(.acquire) == .funcType);
        return;
    }
}

fn transformArgsType(self: *const TranslationUnit, argType: *Parser.Node) void {
    std.debug.assert(argType.tag.load(.acquire) == .fakeArgType);

    const nextI = argType.next.load(.acquire);
    if (nextI != 0) transformType(self, self.global.nodes.getPtr(nextI));

    const typeI = argType.right.load(.acquire);
    std.debug.assert(typeI != 0);
    transformType(self, self.global.nodes.getPtr(typeI));

    if (argType.tag.cmpxchgStrong(.fakeArgType, .argType, .seq_cst, .monotonic) != null) {
        std.debug.assert(argType.tag.load(.acquire) == .argType);
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

    type_.left.store(std.fmt.parseInt(u32, name[1..], 10) catch @panic("Aliases or struct arent supported yet"), .release);
    type_.right.store(@intFromEnum(typeInfo.nodeKind()), .release);

    if (type_.tag.cmpxchgStrong(.fakeType, .type, .seq_cst, .monotonic) != null) {
        std.debug.assert(type_.tag.load(.acquire) == .type);
        return;
    }
}

pub fn typeEqual(global: *const Global, actual: *const Parser.Node, expected: *const Parser.Node) bool {
    const actualTag = actual.tag.load(.acquire);
    const expectedTag = expected.tag.load(.acquire);

    assert(actualTag != .fakeType and expectedTag != .fakeType and
        actualTag != .fakeFuncType and expectedTag != .fakeFuncType and
        actualTag != .fakeArgType and expectedTag != .fakeArgType);

    if (actualTag == .type and expectedTag == .type)
        return expected.right.load(.acquire) == actual.right.load(.acquire) and expected.left.load(.acquire) == actual.left.load(.acquire);

    if (actualTag == .funcType and expectedTag == .funcType) {
        const expectedArgsI = expected.left.load(.acquire);
        const actualArgsI = actual.left.load(.acquire);

        if (!typeEqual(
            global,
            global.nodes.getConstPtr(actual.right.load(.acquire)),
            global.nodes.getConstPtr(expected.right.load(.acquire)),
        )) return false;

        if (actualArgsI == expectedArgsI and actualArgsI == 0)
            return true;

        var actualArgs = global.nodes.getConstPtr(actualArgsI);
        var expectedArgs = global.nodes.getConstPtr(expectedArgsI);

        while (true) {
            const actualArgType = global.nodes.getConstPtr(actualArgs.right.load(.acquire));
            const expectedArgType = global.nodes.getConstPtr(expectedArgs.right.load(.acquire));

            if (!typeEqual(global, actualArgType, expectedArgType))
                return false;

            const actualNext = actualArgs.next.load(.acquire);
            const expectedNext = actualArgs.next.load(.acquire);

            if (actualNext == 0 or expectedNext == 0) return actualNext == 0 and expectedNext == 0;

            actualArgs = global.nodes.getConstPtr(actualNext);
            expectedArgs = global.nodes.getConstPtr(expectedNext);
        }
    }

    return false;
}

pub fn canTypeBeCoerced(actual: *const Parser.Node, expected: *const Parser.Node) bool {
    return expected.right.load(.acquire) == actual.right.load(.acquire) and expected.left.load(.acquire) >= actual.left.load(.acquire);
}

const TranslationUnit = @import("../TranslationUnit.zig");
const Global = @import("../Global.zig");
const Parser = @import("../Parser/mod.zig");

const std = @import("std");

const assert = std.debug.assert;
