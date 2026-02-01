const Self = @This();

pub const Error = error{
    TooBig,
    IncompatibleType,
    UndefVar,
};

const Reason = enum {
    addInference,
    inference,
    check,
    cycleGlobalTracing,

    pub fn toString(self: Reason) []const u8 {
        return switch (self) {
            .addInference => "Adding Inference",
            .inference => "Inferring Type",
            .check => "Checking Type",
            .cycleGlobalTracing => "Tracing Global Cycle",
        };
    }
};

pub const CycleUnit = struct {
    node: *const Parser.Node,
    reason: Reason,

    pub fn eql(a: CycleUnit, b: CycleUnit) bool {
        return a.node == b.node and a.reason == b.reason;
    }
};

var bufCycle: [std.math.pow(usize, 2, 9)]std.ArrayList(CycleUnit) = undefined;
var reuseCycle = ArrayListThreadSafe(std.ArrayList(CycleUnit)){
    .items = .{
        .items = bufCycle[0..0],
        .capacity = bufCycle.len,
    },
};

const startCycleUnitSize = 32;

tu: *const TranslationUnit,
hasCycle: std.ArrayList(CycleUnit) = .{},

pub fn init(alloc: Allocator, tu: *const TranslationUnit) Allocator.Error!Self {
    const self: Self = .{
        .tu = tu,
        .hasCycle = reuseCycle.pop() orelse blk: {
            var hasCycle = std.ArrayList(CycleUnit){};
            try hasCycle.ensureTotalCapacity(alloc, startCycleUnitSize);
            break :blk hasCycle;
        },
    };

    return self;
}

pub fn reset(self: *Self) void {
    self.hasCycle.clearRetainingCapacity();
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    self.hasCycle.clearRetainingCapacity();
    reuseCycle.appendBounded(self.hasCycle) catch {
        self.hasCycle.deinit(alloc);
    };
}

pub fn deinitStatic(alloc: Allocator) void {
    for (reuseCycle.slice()) |*x| x.deinit(alloc);
}

fn push(self: *Self, alloc: Allocator, variable: *const Parser.Node, reason: Reason) (Allocator.Error)!void {
    const unit: CycleUnit = .{ .node = variable, .reason = reason };
    if (Util.listContainsCtx(CycleUnit, self.hasCycle.items, unit)) {
        try self.hasCycle.append(alloc, unit);

        const r = try Report.dependencyCycle(alloc, self.hasCycle.items);

        const message = Report.Message.init(self.tu.global);
        r.display(message);
        std.process.exit(1);
    }

    try self.hasCycle.append(alloc, unit);
}

fn pop(self: *Self) void {
    _ = self.hasCycle.pop();
}
pub fn traceVariable(self: *Self, alloc: Allocator, variable: *const Parser.Node) Allocator.Error!void {
    try self.push(alloc, variable, .cycleGlobalTracing);
    defer self.pop();

    const exprI = variable.data.@"1".load(.acquire);

    try self._traceVariable(alloc, self.tu.global.nodes.getConstPtr(exprI));
}

fn _traceVariable(self: *Self, alloc: Allocator, expr: *const Parser.Node) Allocator.Error!void {
    switch (expr.tag.load(.acquire)) {
        .load => {
            try self.push(alloc, expr, .cycleGlobalTracing);
            defer self.pop();

            const variable = self.tu.scope.get(expr.getText(self.tu.global)) orelse return;
            try self.traceVariable(alloc, variable);
        },
        .neg => {
            const left = expr.data[0].load(.acquire);

            try self.traceVariable(alloc, self.tu.global.nodes.getPtr(left));
        },
        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.data[0].load(.acquire);
            const right = expr.data[1].load(.acquire);

            try self.traceVariable(alloc, self.tu.global.nodes.getPtr(left));
            try self.traceVariable(alloc, self.tu.global.nodes.getPtr(right));
        },
        else => {},
    }
}

pub fn inferType(self: *Self, alloc: Allocator, variable: *Parser.Node, expr: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Error)!bool {
    try self.push(alloc, expr, .inference);
    defer self.pop();

    const exprTag = expr.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition, .call, .funcProto }, exprTag));

    const variableToInferTag = variable.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .variable, .constant }, variableToInferTag));

    const typeI = try self._inferType(alloc, expr, reports);

    if (typeI == null) return false;

    try self.addInferType(alloc, .inferedFromExpression, typeI.?.place, variable, typeI.?.type);

    return true;
}

pub fn _inferType(self: *Self, alloc: Allocator, expr: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Error)!?struct { type: *const Parser.Node, place: *const Parser.Node } {
    const exprTag = expr.tag.load(.acquire);

    switch (exprTag) {
        .lit => return null,
        .load => {
            const leaf = expr;
            const id = leaf.getText(self.tu.global);

            const variable = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, expr);

            const typeIndex = variable.data.@"0".load(.acquire);

            return if (typeIndex == 0) null else .{ .type = self.tu.global.nodes.getConstPtr(typeIndex), .place = expr };
        },
        .funcProto => {
            const tIndex = expr.data[1].load(.acquire);
            std.debug.assert(tIndex != 0);

            const t = self.tu.global.nodes.getPtr(tIndex);
            const tTag = t.tag.load(.acquire);
            if (tTag == .fakeFuncType or tTag == .fakeType) {
                Type.transformType(self.tu, t);
            }
            const tTag1 = t.tag.load(.acquire);

            std.debug.assert(tTag1 == .type or tTag1 == .funcType);

            var argTypeIndex: Parser.NodeIndex = 0;
            const protoArgsIndex = expr.data[0].load(.acquire);

            if (protoArgsIndex != 0) {
                var protoArg = self.tu.global.nodes.getConstPtr(protoArgsIndex);
                const firstArgType = try self.tu.global.nodes.reserve(alloc);
                var currentArgType = firstArgType;

                while (true) {
                    const argType = protoArg.data[0].load(.acquire);
                    const argTypeNode = self.tu.global.nodes.getPtr(argType);

                    const argTypeTag = argTypeNode.tag.load(.acquire);
                    if (argTypeTag == .fakeType or argTypeTag == .fakeFuncType) {
                        Type.transformType(self.tu, argTypeNode);
                    }

                    currentArgType.* = .{
                        .tag = .init(.argType),
                        .tokenIndex = .init(protoArg.tokenIndex.load(.acquire)),
                        .data = .{ .init(0), .init(argType) },
                    };

                    const nextProtoArgIndex = protoArg.next.load(.acquire);
                    if (nextProtoArgIndex == 0) break;

                    protoArg = self.tu.global.nodes.getConstPtr(nextProtoArgIndex);

                    const nextArgType = try self.tu.global.nodes.reserve(alloc);
                    currentArgType.next.store(self.tu.global.nodes.indexOf(nextArgType), .release);
                    currentArgType = nextArgType;
                }

                argTypeIndex = self.tu.global.nodes.indexOf(firstArgType);
            }

            const i = try self.tu.global.nodes.appendIndex(alloc, Parser.Node{
                .tag = .init(.funcType),
                .tokenIndex = .init(expr.tokenIndex.load(.acquire)),
                .data = .{ .init(argTypeIndex), .init(tIndex) },
                .flags = .init(.{ .inferedFromExpression = true }),
            });

            return .{ .type = self.tu.global.nodes.getConstPtr(i), .place = expr };
        },
        .call => {
            const id = expr.getText(self.tu.global);
            const func = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, expr);

            if (func.data.@"0".load(.acquire) == 0) {
                assert(self.inferType(alloc, func, self.tu.global.nodes.getPtr(func.data.@"1".load(.acquire)), reports) catch |err| std.debug.panic("Why would this fail, it should be valid {}", .{err}));
            }

            var funcType = self.tu.global.nodes.getConstPtr(func.data.@"0".load(.acquire));
            var call = expr;

            while (call.next.load(.acquire) != 0) {
                if (funcType.tag.load(.acquire) != .funcType) return Report.expectedFunction(reports, call, funcType);

                funcType = self.tu.global.nodes.getConstPtr(funcType.data.@"1".load(.acquire));

                call = self.tu.global.nodes.getPtr(call.next.load(.acquire));
                assert(call.tag.load(.acquire) == .call);
            }

            return .{ .type = self.tu.global.nodes.getConstPtr(funcType.data.@"1".load(.acquire)), .place = expr };
        },

        .neg => {
            const left = expr.data[0].load(.acquire);

            return self._inferType(alloc, self.tu.global.nodes.getConstPtr(left), reports);
        },

        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.data[0].load(.acquire);
            const right = expr.data[1].load(.acquire);

            const typeL = try self._inferType(alloc, self.tu.global.nodes.getConstPtr(left), reports);
            const typeR = try self._inferType(alloc, self.tu.global.nodes.getConstPtr(right), reports);

            if (typeL == null and typeR == null) return null;
            if (typeL == null or typeR == null) return if (typeL == null) typeR else typeL;

            if (typeL != null and typeR != null) {
                if (Type.canTypeBeCoerced(typeL.?.type, typeR.?.type)) return typeR;
                if (Type.canTypeBeCoerced(typeR.?.type, typeL.?.type)) return typeL;

                const declared = self.tu.scope.get(typeR.?.place.getText(self.tu.global)).?;
                return Report.incompatibleType(
                    reports,
                    typeL.?.type,
                    typeR.?.type,
                    expr,
                    declared,
                );
            }
        },
        else => {
            const loc = expr.getLocation(self.tu.global);
            const fileInfo = self.tu.global.files.get(loc.source);
            const where = Report.Message.placeSlice(loc, fileInfo.source);
            std.debug.panic("{s}:{}:{}: Node not supported here: {}\n{s}\n{[5]c: >[6]}", .{
                fileInfo.path,
                loc.row,
                loc.col,
                exprTag,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            });
        },
    }

    unreachable;
}

pub fn checkType(self: *Self, alloc: Allocator, expr: *Parser.Node, expectedType: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    try self.push(alloc, expr, .check);
    defer self.pop();

    const typeTag = expectedType.tag.load(.acquire);
    const exprTag = expr.tag.load(.acquire);
    assert(typeTag == .type or typeTag == .funcType);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition, .call, .funcProto }, exprTag));

    try self.checkExpected(alloc, expr, expectedType, reports);
}

fn checkExpected(self: *Self, alloc: Allocator, expr: *Parser.Node, expectedType: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const expectedTypeTag = expectedType.tag.load(.acquire);
    assert(expectedTypeTag == .type or expectedTypeTag == .funcType);

    const exprTag = expr.tag.load(.acquire);

    switch (exprTag) {
        .lit => try self.checkLitType(expr, expectedType, reports),
        .load => try self.checkVarType(alloc, expr, expectedType, reports),
        .funcProto => try self.checkFuncProtoType(expr, expectedType, reports),
        .call => try self.checkCallType(alloc, expr, expectedType, reports),

        .neg => {
            const left = expr.data[0].load(.acquire);

            try self.checkExpected(alloc, self.tu.global.nodes.getPtr(left), expectedType, reports);
        },

        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.data[0].load(.acquire);
            const right = expr.data[1].load(.acquire);

            try self.checkExpected(alloc, self.tu.global.nodes.getPtr(left), expectedType, reports);
            try self.checkExpected(alloc, self.tu.global.nodes.getPtr(right), expectedType, reports);
        },
        else => {
            const loc = expr.getLocation(self.tu.global);
            const fileInfo = self.tu.global.files.get(loc.source);
            const where = Report.Message.placeSlice(loc, fileInfo.source);
            std.debug.panic("{s}:{}:{}: Node not supported here: {}\n{s}\n{[5]c: >[6]}", .{
                fileInfo.path,
                loc.row,
                loc.col,
                exprTag,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            });
        },
    }
}

fn checkCallType(self: *Self, alloc: Allocator, call_: *Parser.Node, expectedType: *const Parser.Node, reports: ?*Report.Reports) (Error)!void {
    var call = call_;

    const id = call.getText(self.tu.global);
    const func = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, call);

    if (func.data.@"0".load(.acquire) == 0) {
        assert(self.inferType(alloc, func, self.tu.global.nodes.getPtr(func.data.@"1".load(.acquire)), reports) catch |err| std.debug.panic("Why would this fail, it should be valid {}", .{err}));
    }

    const funcType = self.tu.global.nodes.getConstPtr(func.data.@"0".load(.acquire));

    if (funcType.tag.load(.acquire) != .funcType) {
        return Report.expectedFunction(reports, call, func);
    }

    var retType = self.tu.global.nodes.getConstPtr(funcType.data.@"1".load(.acquire));

    while (call.next.load(.acquire) != 0) {
        if (retType.tag.load(.acquire) != .funcType) return Report.expectedFunction(reports, call, retType);

        retType = self.tu.global.nodes.getConstPtr(retType.data.@"1".load(.acquire));

        call = self.tu.global.nodes.getPtr(call.next.load(.acquire));
        assert(call.tag.load(.acquire) == .call);
    }

    if (Type.typeEqual(self.tu.global, retType, expectedType)) return;
    if (Type.canTypeBeCoerced(retType, expectedType)) {
        var x: ?Parser.Node.Flags = .{};
        while (x) |_| {
            const pastFlags = call.flags.load(.acquire);
            var flags = pastFlags;
            flags.implicitCast = true;

            x = call.flags.cmpxchgWeak(pastFlags, flags, .acquire, .monotonic);
        }
        return;
    }

    return Report.incompatibleReturnType(reports, retType, expectedType, call, func);
}

fn checkFuncProtoType(self: *Self, funcProto: *const Parser.Node, expectedType: *const Parser.Node, reports: ?*Report.Reports) (Error)!void {
    std.debug.assert(funcProto.tag.load(.acquire) == .funcProto);

    const funcRetTypeIndex = funcProto.data[1].load(.acquire);

    std.debug.assert(expectedType.tag.load(.acquire) == .funcType);

    const retTypeIndex = expectedType.data[1].load(.acquire);

    const retType = self.tu.global.nodes.getPtr(retTypeIndex);
    const funcRetType = self.tu.global.nodes.getPtr(funcRetTypeIndex);
    var funcRetTypeTag = funcRetType.tag.load(.acquire);

    // NOTE: this is needed because it is possible that the typing of the function didnt do it yet
    assert(funcRetTypeTag != .argType and funcRetTypeTag != .fakeArgType);
    if (funcRetTypeTag == .fakeFuncType or funcRetTypeTag == .fakeType) Type.transformType(self.tu, funcRetType);
    funcRetTypeTag = funcRetType.tag.load(.acquire);
    assert(funcRetTypeTag == .funcType or funcRetTypeTag == .type);

    if (!Type.typeEqual(self.tu.global, funcRetType, retType)) {
        return Report.incompatibleType(reports, retType, funcRetType, funcRetType, funcRetType);
    }

    const argsI = funcProto.data.@"0".load(.acquire);
    const typeArgsI = expectedType.data.@"0".load(.acquire);

    if (argsI == 0 and typeArgsI == 0) return;

    if (argsI == 0 or typeArgsI == 0) {
        return Report.incompatibleType(reports, funcProto, expectedType, funcProto, funcProto);
    }

    var protoArg = self.tu.global.nodes.getConstPtr(argsI);
    var typeArg = self.tu.global.nodes.getConstPtr(typeArgsI);

    while (true) {
        const protoArgTypeIndex = protoArg.data[0].load(.acquire);
        const typeArgTypeIndex = typeArg.data[1].load(.acquire);

        const protoArgType = self.tu.global.nodes.getPtr(protoArgTypeIndex);
        const typeArgType = self.tu.global.nodes.getPtr(typeArgTypeIndex);

        const protoArgTypeTag = protoArgType.tag.load(.acquire);
        if (protoArgTypeTag == .fakeType or protoArgTypeTag == .fakeFuncType) {
            Type.transformType(self.tu, protoArgType);
        }

        const typeArgTypeTag = typeArgType.tag.load(.acquire);
        if (typeArgTypeTag == .fakeType or typeArgTypeTag == .fakeFuncType) {
            Type.transformType(self.tu, typeArgType);
        }

        if (!Type.typeEqual(self.tu.global, protoArgType, typeArgType)) {
            return Report.incompatibleType(reports, typeArgType, protoArgType, protoArg, protoArg);
        }

        const protoNextIndex = protoArg.next.load(.acquire);
        const typeNextIndex = typeArg.next.load(.acquire);

        if (protoNextIndex == 0 and typeNextIndex == 0) break;
        if (protoNextIndex == 0 or typeNextIndex == 0) {
            return Report.incompatibleType(reports, expectedType, funcProto, funcProto, funcProto);
        }

        protoArg = self.tu.global.nodes.getConstPtr(protoNextIndex);
        typeArg = self.tu.global.nodes.getConstPtr(typeNextIndex);
    }
}

fn checkVarType(self: *Self, alloc: Allocator, leaf: *Parser.Node, type_: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const id = leaf.getText(self.tu.global);

    const variable = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, leaf);

    var typeIndex = variable.data.@"0".load(.acquire);

    if (typeIndex == 0)
        return addInferType(self, alloc, .inferedFromUse, leaf, variable, type_);

    const tag = variable.tag.load(.acquire);

    var variableType: *const Parser.Node = undefined;

    var couldBeCoerce = false;
    // NOTE: This will be runned once for variable and could be multiple with constants
    while (typeIndex != 0) : (typeIndex = variableType.next.load(.acquire)) {
        variableType = self.tu.global.nodes.getConstPtr(typeIndex);

        if (Type.typeEqual(self.tu.global, variableType, type_)) return;
        // NOTE: This has to be appart because if it a constant I want to check if it has an equal
        if (Type.canTypeBeCoerced(variableType, type_)) couldBeCoerce = true;
    }

    if (tag == .constant)
        return addInferType(self, alloc, .inferedFromUse, leaf, variable, type_);

    if (couldBeCoerce) {
        var x: ?Parser.Node.Flags = .{};
        while (x) |_| {
            const pastFlags = leaf.flags.load(.acquire);
            var flags = pastFlags;
            flags.implicitCast = true;

            x = leaf.flags.cmpxchgWeak(pastFlags, flags, .acquire, .monotonic);
        }

        return;
    }

    return Report.incompatibleType(reports, variableType, type_, leaf, variable);
}

fn addInferType(self: *Self, alloc: Allocator, comptime flag: std.meta.FieldEnum(Parser.Node.Flags), leaf: *const Parser.Node, variable: *Parser.Node, type_: *const Parser.Node) (Allocator.Error || Error)!void {
    assert(flag == .inferedFromUse or flag == .inferedFromExpression);
    const typeTag = type_.tag.load(.acquire);
    assert(typeTag == .funcType or typeTag == .type);
    try self.push(alloc, variable, .addInference);
    defer self.pop();

    // Check Variable expression for that type
    try self.checkType(alloc, self.tu.global.nodes.getPtr(variable.data.@"1".load(.acquire)), type_, null);

    // Reset data
    var nodeType = type_.*;
    nodeType.tokenIndex.store(leaf.tokenIndex.load(.acquire), .release);

    nodeType.next.store(variable.data.@"0".load(.acquire), .release);
    var flags: Parser.Node.Flags = .{};
    @field(flags, @tagName(flag)) = true;
    nodeType.flags.store(flags, .release);

    // Add to list
    const x = try self.tu.global.nodes.appendIndex(alloc, nodeType);
    // Make the variable be that type
    // TODO: Check if this type was already added
    if (variable.data.@"0".cmpxchgStrong(nodeType.next.load(.acquire), x, .acq_rel, .monotonic) != null) try self.addInferType(alloc, flag, leaf, variable, type_);
}

fn checkLitType(self: *Self, lit: *const Parser.Node, expectedType: *const Parser.Node, reports: ?*Report.Reports) (Error)!void {
    std.debug.assert(expectedType.tag.load(.acquire) == .type);

    const primitive = expectedType.data[1].load(.acquire);
    const size = expectedType.data[0].load(.acquire);

    const text = lit.getText(self.tu.global);
    switch (@as(Parser.Node.Primitive, @enumFromInt(primitive))) {
        Parser.Node.Primitive.uint => {
            const max = std.math.pow(u64, 2, size) - 1;
            const number = std.fmt.parseInt(u64, text, 10) catch return Report.incompatibleLiteral(reports, lit, expectedType);

            if (number < max) return;
            return Report.incompatibleLiteral(reports, lit, expectedType);
        },
        Parser.Node.Primitive.sint => {
            const max = std.math.pow(i64, 2, (size - 1)) - 1;
            const number = std.fmt.parseInt(i64, text, 10) catch
                return Report.incompatibleLiteral(reports, lit, expectedType);

            if (number < max) return;
            return Report.incompatibleLiteral(reports, lit, expectedType);
        },
        Parser.Node.Primitive.float => unreachable,
    }
}

const Type = @import("Type.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Report = @import("../Report/mod.zig");
const Parser = @import("../Parser/mod.zig");
const Scope = @import("Scope/mod.zig");
const Util = @import("../Util.zig");
const ArrayListThreadSafe = @import("../Util/ArrayListThreadSafe.zig").ArrayListThreadSafe;

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
