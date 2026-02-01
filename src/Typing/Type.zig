pub fn transformType(self: *const TranslationUnit, type_: *Parser.Node.FakeTypes) void {
    // CLEAN: Here the race condition can still happen
    if (Parser.Node.isTypes(type_.tag.load(.acquire))) return;

    switch (type_.tag.load(.acquire)) {
        .fakeType => transformIdentiferType(self, type_.asFakeType()),
        .fakeFuncType => transformFuncType(self, type_.asFakeFuncType()),
        .fakeArgType => transformArgsType(self, type_.asFakeArgType()),
        .type, .funcType, .argType => {},
        else => unreachable,
    }
}

fn transformFuncType(self: *const TranslationUnit, funcType: *Parser.Node.FakeFuncType) void {
    const argIndex = funcType.fakeArgsType.load(.acquire);
    if (argIndex != 0) transformType(self, self.global.nodes.getPtr(argIndex).asFakeTypes());

    const retTypeIndex = funcType.fakeRetType.load(.acquire);
    std.debug.assert(retTypeIndex != 0);
    transformType(self, self.global.nodes.getPtr(retTypeIndex).asFakeTypes());

    if (funcType.tag.cmpxchgStrong(.fakeFuncType, .funcType, .seq_cst, .monotonic) != null) {
        std.debug.assert(funcType.tag.load(.acquire) == .funcType);
        return;
    }
}

fn transformArgsType(self: *const TranslationUnit, argType: *Parser.Node.FakeArgType) void {
    const nextI = argType.next.load(.acquire);
    if (nextI != 0) transformType(self, self.global.nodes.getPtr(nextI).asFakeTypes());

    const typeI = argType.fakeType.load(.acquire);
    std.debug.assert(typeI != 0);
    transformType(self, self.global.nodes.getPtr(typeI).asFakeTypes());

    if (argType.tag.cmpxchgStrong(.fakeArgType, .argType, .seq_cst, .monotonic) != null) {
        std.debug.assert(argType.tag.load(.acquire) == .argType);
        return;
    }
}

// NOTE: Maybe good idea to create a new node, if the panic is triggered and cannot check if the correctness is still okey
fn transformIdentiferType(self: *const TranslationUnit, type_: *Parser.Node.FakeType) void {
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

    const name = type_.asConst().getText(self.global);
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

    if (actualTag == .type and expectedTag == .type) {
        const actualType = actual.asConstType();
        const expectedType = expected.asConstType();
        return expectedType.primitive.load(.acquire) == actualType.primitive.load(.acquire) and expectedType.size.load(.acquire) == actualType.size.load(.acquire);
    }

    if (actualTag == .funcType and expectedTag == .funcType) {
        const actualFunc = actual.asConstFuncType();
        const expectedFunc = expected.asConstFuncType();

        const expectedArgsI = expectedFunc.argsType.load(.acquire);
        const actualArgsI = actualFunc.argsType.load(.acquire);

        if (!typeEqual(
            global,
            global.nodes.getConstPtr(actualFunc.retType.load(.acquire)),
            global.nodes.getConstPtr(expectedFunc.retType.load(.acquire)),
        )) return false;

        if (actualArgsI == expectedArgsI and actualArgsI == 0)
            return true;

        var actualArgs = global.nodes.getConstPtr(actualArgsI).asConstArgType();
        var expectedArgs = global.nodes.getConstPtr(expectedArgsI).asConstArgType();

        while (true) {
            const actualArgType = global.nodes.getConstPtr(actualArgs.type_.load(.acquire));
            const expectedArgType = global.nodes.getConstPtr(expectedArgs.type_.load(.acquire));

            if (!typeEqual(global, actualArgType, expectedArgType))
                return false;

            const actualNext = actualArgs.next.load(.acquire);
            const expectedNext = expectedArgs.next.load(.acquire);

            if (actualNext == 0 or expectedNext == 0) return actualNext == 0 and expectedNext == 0;

            actualArgs = global.nodes.getConstPtr(actualNext).asConstArgType();
            expectedArgs = global.nodes.getConstPtr(expectedNext).asConstArgType();
        }
    }

    return false;
}

pub fn canTypeBeCoerced(actual: *const Parser.Node, expected: *const Parser.Node) bool {
    const actualType = actual.asConstType();
    const expectedType = expected.asConstType();
    return expectedType.primitive.load(.acquire) == actualType.primitive.load(.acquire) and expectedType.size.load(.acquire) >= actualType.size.load(.acquire);
}

const TranslationUnit = @import("../TranslationUnit.zig");
const Global = @import("../Global.zig");
const Parser = @import("../Parser/mod.zig");

const std = @import("std");

const assert = std.debug.assert;
