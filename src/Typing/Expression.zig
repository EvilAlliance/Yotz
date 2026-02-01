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
pub fn traceVariable(self: *Self, alloc: Allocator, variable: *const Parser.Node.VarConst) Allocator.Error!void {
    try self.push(alloc, variable.asConst(), .cycleGlobalTracing);
    defer self.pop();

    const exprI = variable.expr.load(.acquire);

    try self._traceVariable(alloc, self.tu.global.nodes.getConstPtr(exprI).asConstExpression());
}

fn _traceVariable(self: *Self, alloc: Allocator, expr: *const Parser.Node.Expression) Allocator.Error!void {
    switch (expr.tag.load(.acquire)) {
        .load => {
            const load = expr.asConstLoad();
            try self.push(alloc, load.asConst(), .cycleGlobalTracing);
            defer self.pop();

            const variable = self.tu.scope.get(load.getText(self.tu.global)) orelse return;
            try self.traceVariable(alloc, variable.asConstVarConst());
        },
        .neg => {
            const left = expr.left.load(.acquire);

            try self._traceVariable(alloc, self.tu.global.nodes.getPtr(left).asConstExpression());
        },
        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.left.load(.acquire);
            const right = expr.right.load(.acquire);

            try self._traceVariable(alloc, self.tu.global.nodes.getPtr(left).asConstExpression());
            try self._traceVariable(alloc, self.tu.global.nodes.getPtr(right).asConstExpression());
        },
        else => {},
    }
}

pub fn inferType(self: *Self, alloc: Allocator, variable: *Parser.Node.VarConst, expr: *const Parser.Node.Expression, reports: ?*Report.Reports) (Allocator.Error || Error)!bool {
    try self.push(alloc, expr.asConst(), .inference);
    defer self.pop();

    const exprTag = expr.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition, .call, .funcProto }, exprTag));

    const typeI = try self._inferType(alloc, expr, reports);

    if (typeI == null) return false;

    try self.addInferType(alloc, .inferedFromExpression, typeI.?.place, variable, typeI.?.type);

    return true;
}

pub fn _inferType(self: *Self, alloc: Allocator, expr: *const Parser.Node.Expression, reports: ?*Report.Reports) (Allocator.Error || Error)!?struct { type: *const Parser.Node.Types, place: *const Parser.Node.Expression } {
    const exprTag = expr.tag.load(.acquire);

    switch (exprTag) {
        .lit => return null,
        .load => {
            const load = expr.asConstLoad();
            const id = load.getText(self.tu.global);

            const variable = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, expr.asConst());

            const typeIndex = variable.left.load(.acquire);

            return if (typeIndex == 0) null else .{ .type = self.tu.global.nodes.getConstPtr(typeIndex).asConstTypes(), .place = expr };
        },
        .funcProto => {
            const funcProto = expr.asConstFuncProto();
            const tIndex = funcProto.retType.load(.acquire);
            std.debug.assert(tIndex != 0);

            const t = self.tu.global.nodes.getPtr(tIndex);
            if (Parser.Node.isFakeTypes(t.tag.load(.acquire))) Type.transformType(self.tu, t.asFakeTypes());
            std.debug.assert(Parser.Node.isTypes(t.tag.load(.acquire)));

            var argTypeIndex: Parser.NodeIndex = 0;
            const protoArgsIndex = funcProto.args.load(.acquire);

            if (protoArgsIndex != 0) {
                var protoArg = self.tu.global.nodes.getConstPtr(protoArgsIndex);
                const firstArgType = try self.tu.global.nodes.reserve(alloc);
                var currentArgType = firstArgType;

                while (true) {
                    const argType = protoArg.left.load(.acquire);
                    const argTypeNode = self.tu.global.nodes.getPtr(argType);

                    if (Parser.Node.isFakeTypes(argTypeNode.tag.load(.acquire))) Type.transformType(self.tu, argTypeNode.asFakeTypes());
                    assert(Parser.Node.isTypes(argTypeNode.tag.load(.acquire)));

                    currentArgType.* = .{
                        .tag = .init(.argType),
                        .tokenIndex = .init(protoArg.tokenIndex.load(.acquire)),
                        .left = .init(0),
                        .right = .init(argType),
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
                .tokenIndex = .init(funcProto.tokenIndex.load(.acquire)),
                .left = .init(argTypeIndex),
                .right = .init(tIndex),
                .flags = .init(.{ .inferedFromExpression = true }),
            });

            return .{ .type = self.tu.global.nodes.getConstPtr(i).asConstTypes(), .place = funcProto.asConst().asConstExpression() };
        },
        .call => {
            var call = expr.asConstCall();
            const id = call.getText(self.tu.global);
            const func = (self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, call.asConst())).asVarConst();

            if (func.type.load(.acquire) == 0) {
                assert(self.inferType(alloc, func, self.tu.global.nodes.getPtr(func.expr.load(.acquire)).asExpression(), reports) catch |err| std.debug.panic("Why would this fail, it should be valid {}", .{err}));
            }

            var funcType = self.tu.global.nodes.getConstPtr(func.type.load(.acquire));
            while (call.next.load(.acquire) != 0) {
                if (funcType.tag.load(.acquire) != .funcType) return Report.expectedFunction(reports, call.asConst(), funcType);

                const ft = funcType.asConstFuncType();
                funcType = self.tu.global.nodes.getConstPtr(ft.retType.load(.acquire));

                call = self.tu.global.nodes.getConstPtr(call.next.load(.acquire)).asConstCall();
            }

            const ft = funcType.asConstFuncType();
            return .{ .type = self.tu.global.nodes.getConstPtr(ft.retType.load(.acquire)).asConstTypes(), .place = expr };
        },

        .neg => {
            const unOp = expr.asConstUnaryOp();
            const left = unOp.left.load(.acquire);

            return self._inferType(alloc, self.tu.global.nodes.getConstPtr(left).asConstExpression(), reports);
        },

        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.left.load(.acquire);
            const right = expr.right.load(.acquire);

            const typeL = try self._inferType(alloc, self.tu.global.nodes.getConstPtr(left).asConstExpression(), reports);
            const typeR = try self._inferType(alloc, self.tu.global.nodes.getConstPtr(right).asConstExpression(), reports);

            if (typeL == null and typeR == null) return null;
            if (typeL == null or typeR == null) return if (typeL == null) typeR else typeL;

            if (typeL != null and typeR != null) {
                if (Type.canTypeBeCoerced(typeL.?.type, typeR.?.type)) return typeR;
                if (Type.canTypeBeCoerced(typeR.?.type, typeL.?.type)) return typeL;

                const declared = self.tu.scope.get(typeR.?.place.asConst().getText(self.tu.global)).?;
                return Report.incompatibleType(
                    reports,
                    typeL.?.type.asConst(),
                    typeR.?.type.asConst(),
                    expr.asConst(),
                    declared,
                );
            }
        },
        else => {
            const loc = expr.asConst().getLocation(self.tu.global);
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

pub fn checkType(self: *Self, alloc: Allocator, expr: *Parser.Node.Expression, expectedType: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    try self.push(alloc, expr.asConst(), .check);
    defer self.pop();

    const typeTag = expectedType.tag.load(.acquire);
    const exprTag = expr.tag.load(.acquire);
    assert(typeTag == .type or typeTag == .funcType);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition, .call, .funcProto }, exprTag));

    try self.checkExpected(alloc, expr, expectedType, reports);
}

fn checkExpected(self: *Self, alloc: Allocator, expr: *Parser.Node.Expression, expectedType: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const exprTag = expr.tag.load(.acquire);

    switch (exprTag) {
        .lit => try self.checkLitType(expr.asConstLiteral(), expectedType, reports),
        .load => try self.checkVarType(alloc, expr.asLoad(), expectedType, reports),
        .funcProto => try self.checkFuncProtoType(expr.asConstFuncProto(), expectedType, reports),
        .call => try self.checkCallType(alloc, expr.asCall(), expectedType, reports),

        .neg => {
            const left = expr.left.load(.acquire);

            try self.checkExpected(alloc, self.tu.global.nodes.getPtr(left).asExpression(), expectedType, reports);
        },

        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.left.load(.acquire);
            const right = expr.right.load(.acquire);

            try self.checkExpected(alloc, self.tu.global.nodes.getPtr(left).asExpression(), expectedType, reports);
            try self.checkExpected(alloc, self.tu.global.nodes.getPtr(right).asExpression(), expectedType, reports);
        },
        else => {
            const loc = expr.asConst().getLocation(self.tu.global);
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

fn checkCallType(self: *Self, alloc: Allocator, call_: *Parser.Node.Call, expectedType: *const Parser.Node.Types, reports: ?*Report.Reports) (Error)!void {
    var call = call_;

    const id = call.getText(self.tu.global);
    const func = (self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, call.asConst())).asVarConst();

    if (func.type.load(.acquire) == 0) {
        assert(self.inferType(alloc, func, self.tu.global.nodes.getPtr(func.expr.load(.acquire)).asExpression(), reports) catch |err| std.debug.panic("Why would this fail, it should be valid {}", .{err}));
    }

    const funcType = self.tu.global.nodes.getConstPtr(func.type.load(.acquire));

    if (funcType.tag.load(.acquire) != .funcType) {
        return Report.expectedFunction(reports, call.asConst(), func.asConst());
    }

    var retType = self.tu.global.nodes.getConstPtr(funcType.right.load(.acquire)).asConstTypes();

    while (call.as().next.load(.acquire) != 0) {
        if (retType.tag.load(.acquire) != .funcType) return Report.expectedFunction(reports, call.as(), retType.asConst());

        retType = self.tu.global.nodes.getConstPtr(retType.right.load(.acquire)).asConstTypes();

        call = self.tu.global.nodes.getPtr(call.as().next.load(.acquire)).asCall();
        assert(call.as().tag.load(.acquire) == .call);
    }

    if (Type.typeEqual(self.tu.global, retType, expectedType)) return;
    if (Type.canTypeBeCoerced(retType, expectedType)) {
        var x: ?Parser.Node.Flags = .{};
        while (x) |_| {
            const pastFlags = call.as().flags.load(.acquire);
            var flags = pastFlags;
            flags.implicitCast = true;

            x = call.as().flags.cmpxchgWeak(pastFlags, flags, .acquire, .monotonic);
        }
        return;
    }

    return Report.incompatibleReturnType(reports, retType.asConst(), expectedType.asConst(), call.asConst(), func.asConst());
}

fn checkFuncProtoType(self: *Self, funcProtoNode: *const Parser.Node.FuncProto, expectedType: *const Parser.Node.Types, reports: ?*Report.Reports) (Error)!void {
    const funcProto = funcProtoNode.asConst();

    const funcRetTypeIndex = funcProto.right.load(.acquire);

    std.debug.assert(expectedType.tag.load(.acquire) == .funcType);

    const retTypeIndex = expectedType.right.load(.acquire);

    const retType = self.tu.global.nodes.getPtr(retTypeIndex);
    const funcRetType = self.tu.global.nodes.getPtr(funcRetTypeIndex);

    // NOTE: this is needed because it is possible that the typing of the function didnt do it yet
    if (Parser.Node.isFakeTypes(funcRetType.tag.load(.acquire))) Type.transformType(self.tu, funcRetType.asFakeTypes());
    assert(Parser.Node.isTypes(funcRetType.tag.load(.acquire)));

    if (!Type.typeEqual(self.tu.global, funcRetType.asTypes(), retType.asTypes())) {
        return Report.incompatibleType(reports, retType, funcRetType, funcRetType, funcRetType);
    }

    const argsI = funcProtoNode.args.load(.acquire);
    const typeArgsI = expectedType.left.load(.acquire);

    if (argsI == 0 and typeArgsI == 0) return;

    if (argsI == 0 or typeArgsI == 0) {
        return Report.incompatibleType(reports, funcProto, expectedType.asConst(), funcProto, funcProto);
    }

    var protoArg = self.tu.global.nodes.getConstPtr(argsI);
    var typeArg = self.tu.global.nodes.getConstPtr(typeArgsI);

    while (true) {
        const protoArgTypeIndex = protoArg.left.load(.acquire);
        const typeArgTypeIndex = typeArg.right.load(.acquire);

        const protoArgType = self.tu.global.nodes.getPtr(protoArgTypeIndex);
        const typeArgType = self.tu.global.nodes.getPtr(typeArgTypeIndex);

        if (Parser.Node.isFakeTypes(protoArgType.tag.load(.acquire))) Type.transformType(self.tu, protoArgType.asFakeTypes());
        assert(Parser.Node.isTypes(protoArgType.tag.load(.acquire)));

        if (Parser.Node.isFakeTypes(typeArgType.tag.load(.acquire))) Type.transformType(self.tu, typeArgType.asFakeTypes());
        assert(Parser.Node.isTypes(typeArgType.tag.load(.acquire)));

        if (!Type.typeEqual(self.tu.global, protoArgType.asTypes(), typeArgType.asTypes())) {
            return Report.incompatibleType(reports, typeArgType, protoArgType, protoArg, protoArg);
        }

        const protoNextIndex = protoArg.next.load(.acquire);
        const typeNextIndex = typeArg.next.load(.acquire);

        if (protoNextIndex == 0 and typeNextIndex == 0) break;
        if (protoNextIndex == 0 or typeNextIndex == 0) {
            return Report.incompatibleType(reports, expectedType.asConst(), funcProto, funcProto, funcProto);
        }

        protoArg = self.tu.global.nodes.getConstPtr(protoNextIndex);
        typeArg = self.tu.global.nodes.getConstPtr(typeNextIndex);
    }
}

fn checkVarType(self: *Self, alloc: Allocator, load: *Parser.Node.Load, type_: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const id = load.getText(self.tu.global);

    const variable = (self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, load.asConst())).asVarConst();

    var typeIndex = variable.type.load(.acquire);

    if (typeIndex == 0)
        return addInferType(self, alloc, .inferedFromUse, load.as().asExpression(), variable, type_);

    const tag = variable.tag.load(.acquire);

    var variableType: *const Parser.Node.Types = undefined;

    var couldBeCoerce = false;
    // NOTE: This will be runned once for variable and could be multiple with constants
    while (typeIndex != 0) : (typeIndex = variableType.next.load(.acquire)) {
        variableType = self.tu.global.nodes.getConstPtr(typeIndex).asConstTypes();

        if (Type.typeEqual(self.tu.global, variableType, type_)) return;
        // NOTE: This has to be appart because if it a constant I want to check if it has an equal
        if (Type.canTypeBeCoerced(variableType, type_)) couldBeCoerce = true;
    }

    if (tag == .constant)
        return addInferType(self, alloc, .inferedFromUse, load.as().asExpression(), variable, type_);

    if (couldBeCoerce) {
        var x: ?Parser.Node.Flags = .{};
        while (x) |_| {
            const pastFlags = load.flags.load(.acquire);
            var flags = pastFlags;
            flags.implicitCast = true;

            x = load.flags.cmpxchgWeak(pastFlags, flags, .acquire, .monotonic);
        }

        return;
    }

    return Report.incompatibleType(reports, variableType.asConst(), type_.asConst(), load.as(), variable.as());
}

fn addInferType(self: *Self, alloc: Allocator, comptime flag: std.meta.FieldEnum(Parser.Node.Flags), leaf: *const Parser.Node.Expression, variable: *Parser.Node.VarConst, type_: *const Parser.Node.Types) (Allocator.Error || Error)!void {
    assert(flag == .inferedFromUse or flag == .inferedFromExpression);
    const typeTag = type_.tag.load(.acquire);
    assert(typeTag == .funcType or typeTag == .type);
    try self.push(alloc, variable.as(), .addInference);
    defer self.pop();

    // Check Variable expression for that type
    try self.checkType(alloc, self.tu.global.nodes.getPtr(variable.expr.load(.acquire)).asExpression(), type_, null);

    // Reset data
    var nodeType = type_.*;
    nodeType.tokenIndex.store(leaf.tokenIndex.load(.acquire), .release);

    nodeType.next.store(variable.type.load(.acquire), .release);
    var flags: Parser.Node.Flags = .{};
    @field(flags, @tagName(flag)) = true;
    nodeType.flags.store(flags, .release);

    // Add to list
    const x = try self.tu.global.nodes.appendIndex(alloc, nodeType.asConst().*);
    // Make the variable be that type
    // TODO: Check if this type was already added
    if (variable.type.cmpxchgStrong(nodeType.next.load(.acquire), x, .acq_rel, .monotonic) != null) try self.addInferType(alloc, flag, leaf, variable, type_);
}

fn checkLitType(self: *Self, lit: *const Parser.Node.Literal, expectedType: *const Parser.Node.Types, reports: ?*Report.Reports) (Error)!void {
    std.debug.assert(expectedType.tag.load(.acquire) == .type);

    const expectedT = expectedType.asConstType();
    const primitive = expectedT.primitive.load(.acquire);
    const size = expectedT.size.load(.acquire);

    const text = lit.getText(self.tu.global);
    switch (@as(Parser.Node.Primitive, @enumFromInt(primitive))) {
        Parser.Node.Primitive.uint => {
            const max = std.math.pow(u64, 2, size) - 1;
            const number = std.fmt.parseInt(u64, text, 10) catch return Report.incompatibleLiteral(reports, lit.asConst(), expectedType.asConst());

            if (number < max) return;
            return Report.incompatibleLiteral(reports, lit.asConst(), expectedType.asConst());
        },
        Parser.Node.Primitive.sint => {
            const max = std.math.pow(i64, 2, (size - 1)) - 1;
            const number = std.fmt.parseInt(i64, text, 10) catch
                return Report.incompatibleLiteral(reports, lit.asConst(), expectedType.asConst());

            if (number < max) return;
            return Report.incompatibleLiteral(reports, lit.asConst(), expectedType.asConst());
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
