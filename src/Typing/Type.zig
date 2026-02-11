pub fn transformType(global: *Global, type_: *Parser.Node.FakeTypes) void {
    switch (type_.tag.load(.acquire)) {
        .fakeType => transformIdentiferType(global, type_.asFakeType()),
        .fakeFuncType => transformFuncType(global, type_.asFakeFuncType()),
        .fakeArgType => transformArgsType(global, type_.asFakeArgType()),
        .type, .funcType, .argType => {},
        else => unreachable,
    }
}

fn transformFuncType(global: *Global, funcType: *Parser.Node.FakeFuncType) void {
    const argIndex = funcType.fakeArgsType.load(.acquire);
    if (argIndex != 0) {
        const args = global.nodes.getPtr(argIndex);
        if (Parser.Node.isFakeTypes(args.tag.load(.acquire)))
            transformType(global, args.asFakeTypes())
        else
            assert(Parser.Node.isTypes(args.tag.load(.acquire)));
    }

    const retTypeIndex = funcType.fakeRetType.load(.acquire);
    const retType = global.nodes.getPtr(retTypeIndex);
    if (Parser.Node.isFakeTypes(retType.tag.load(.acquire)))
        transformType(global, retType.asFakeTypes())
    else
        assert(Parser.Node.isTypes(retType.tag.load(.acquire)));

    if (funcType.tag.cmpxchgStrong(.fakeFuncType, .funcType, .seq_cst, .monotonic) != null) {
        std.debug.assert(funcType.tag.load(.acquire) == .funcType);
        return;
    }
}

fn transformArgsType(global: *Global, argType: *Parser.Node.FakeArgType) void {
    const nextI = argType.next.load(.acquire);
    if (nextI != 0) {
        const args = global.nodes.getPtr(nextI);
        if (Parser.Node.isFakeTypes(args.tag.load(.acquire)))
            transformType(global, args.asFakeTypes())
        else
            assert(Parser.Node.isTypes(args.tag.load(.acquire)));
    }

    const typeI = argType.fakeType.load(.acquire);
    const type_ = global.nodes.getPtr(typeI);

    if (Parser.Node.isFakeTypes(type_.tag.load(.acquire)))
        transformType(global, type_.asFakeTypes())
    else
        assert(Parser.Node.isTypes(type_.tag.load(.acquire)));

    if (argType.tag.cmpxchgStrong(.fakeArgType, .argType, .seq_cst, .monotonic) != null) {
        std.debug.assert(argType.tag.load(.acquire) == .argType);
        return;
    }
}

pub fn isIdenType(self: *Global, type_: *const Parser.Node.Declarator) bool {
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

    const name = type_.asConst().getText(self);
    if (name.len > 3) return false;

    _ = std.meta.stringToEnum(TypeName, name[0..1]) orelse return false;

    const res = std.fmt.parseInt(u32, name[1..], 10) catch return false;

    return res <= 64;
}

// NOTE: Maybe good idea to create a new node, if the panic is triggered and cannot check if the correctness is still okey
fn transformIdentiferType(self: *Global, type_: *Parser.Node.FakeType) void {
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

    const name = type_.asConst().getText(self);
    if (name.len > 3) @panic("Aliases or struct arent supported yet");

    const typeInfo = std.meta.stringToEnum(TypeName, name[0..1]) orelse @panic("Aliases or struct arent supported yet");

    const res = std.fmt.parseInt(u32, name[1..], 10) catch @panic("Aliases or struct arent supported yet");
    if (res > 64) @panic("Aliases or Struct arent supported yet");

    type_.left.store(res, .release);
    type_.right.store(@intFromEnum(typeInfo.nodeKind()), .release);

    if (type_.tag.cmpxchgStrong(.fakeType, .type, .seq_cst, .monotonic) != null) {
        std.debug.assert(type_.tag.load(.acquire) == .type);
        return;
    }
}

pub fn typeEqual(global: *const Global, actual: *const Parser.Node.Types, expected: *const Parser.Node.Types, mismatch: ?*MismatchLocation) bool {
    const actualTag = actual.tag.load(.acquire);
    const expectedTag = expected.tag.load(.acquire);

    assert(actualTag != .fakeType and expectedTag != .fakeType and
        actualTag != .fakeFuncType and expectedTag != .fakeFuncType and
        actualTag != .fakeArgType and expectedTag != .fakeArgType);

    if (actualTag == .type and expectedTag == .type) {
        const actualType = actual.asConstType();
        const expectedType = expected.asConstType();
        const matches = expectedType.primitive.load(.acquire) == actualType.primitive.load(.acquire) and expectedType.size.load(.acquire) == actualType.size.load(.acquire);
        if (!matches and mismatch != null) {
            mismatch.?.* = .{
                .actualNode = actual,
                .expectedNode = expected,
                .kind = .primitiveType,
            };
        }
        return matches;
    }

    if (actualTag == .funcType and expectedTag == .funcType) {
        const actualFunc = actual.asConstFuncType();
        const expectedFunc = expected.asConstFuncType();

        const expectedArgsI = expectedFunc.argsType.load(.acquire);
        const actualArgsI = actualFunc.argsType.load(.acquire);

        const actualRetType = global.nodes.getConstPtr(actualFunc.retType.load(.acquire)).asConstTypes();
        const expectedRetType = global.nodes.getConstPtr(expectedFunc.retType.load(.acquire)).asConstTypes();

        if (!typeEqual(global, actualRetType, expectedRetType, mismatch)) {
            if (mismatch != null and mismatch.?.kind == .primitiveType) {
                mismatch.?.kind = .returnType;
            }
            return false;
        }

        if (actualArgsI == expectedArgsI and actualArgsI == 0)
            return true;

        var actualArgs = global.nodes.getConstPtr(actualArgsI).asConstArgType();
        var expectedArgs = global.nodes.getConstPtr(expectedArgsI).asConstArgType();

        while (true) {
            const actualArgType = global.nodes.getConstPtr(actualArgs.type_.load(.acquire));
            const expectedArgType = global.nodes.getConstPtr(expectedArgs.type_.load(.acquire));

            if (!typeEqual(global, actualArgType.asConstTypes(), expectedArgType.asConstTypes(), mismatch)) {
                if (mismatch != null and mismatch.?.kind == .primitiveType) {
                    mismatch.?.kind = .argumentType;
                }
                return false;
            }

            const actualNext = actualArgs.next.load(.acquire);
            const expectedNext = expectedArgs.next.load(.acquire);

            if (actualNext == 0 or expectedNext == 0) {
                const matches = actualNext == 0 and expectedNext == 0;
                if (!matches and mismatch != null) {
                    mismatch.?.* = .{
                        .actualNode = actual,
                        .expectedNode = expected,
                        .kind = .argumentCount,
                    };
                }
                return matches;
            }

            actualArgs = global.nodes.getConstPtr(actualNext).asConstArgType();
            expectedArgs = global.nodes.getConstPtr(expectedNext).asConstArgType();
        }
    }

    return false;
}

pub fn canTypeBeCoerced(actual: *const Parser.Node.Types, expected: *const Parser.Node.Types) bool {
    const actualType = actual.asConstType();
    const expectedType = expected.asConstType();
    return expectedType.primitive.load(.acquire) == actualType.primitive.load(.acquire) and expectedType.size.load(.acquire) >= actualType.size.load(.acquire);
}

pub const MismatchKind = enum {
    correct,
    primitiveType,
    returnType,
    argumentType,
    argumentCount,
};

pub const MismatchLocation = struct {
    actualNode: *const Parser.Node.Types,
    expectedNode: *const Parser.Node.Types,
    kind: MismatchKind = .correct,
};

const EqualCoerce = union(enum) { notFound: MismatchLocation, coerce: void, found: *Parser.Node.Types };
const Equal = union(enum) { notFound: MismatchLocation, found: *Parser.Node.Types };
const Coerce = union(enum) { notFound: void, coerce: void };
const None = union(enum) { notFound: void };

// NOTE: All type connected to actual are check when the expected (if expected next != 0 the other type is not checked)
pub fn compareActualsTypes(global: *const Global, actual: *Parser.Node.Types, expecected: *const Parser.Node.Types, comptime equal: bool, comptime coerce: bool) if (equal and coerce) EqualCoerce else if (equal) Equal else if (coerce) Coerce else None {
    var node: *Parser.Node = actual.as();
    var couldBeCoerce = false;
    var mismatch: MismatchLocation = .{
        .actualNode = actual,
        .expectedNode = expecected,
    };

    while (Parser.Node.isTypes(node.tag.load(.acquire))) : (node = global.nodes.getPtr(node.next.load(.acquire))) {
        const variableType = node.asTypes();

        if (equal and typeEqual(global, variableType, expecected, &mismatch)) return .{ .found = variableType };
        if (coerce and canTypeBeCoerced(variableType, expecected)) couldBeCoerce = true;
    }

    if (coerce and couldBeCoerce) return .coerce;
    if (equal or (equal and coerce)) {
        return .{ .notFound = mismatch };
    }
    return .notFound;
}

const TranslationUnit = @import("../TranslationUnit.zig");
const Global = @import("../Global.zig");
const Parser = @import("../Parser/mod.zig");

const std = @import("std");

const assert = std.debug.assert;
