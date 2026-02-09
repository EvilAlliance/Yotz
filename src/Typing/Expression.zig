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

            if (variable.tag.load(.acquire) == .protoArg) return;

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

pub fn pushDependant(self: *Self, alloc: Allocator, variable: *Parser.Node.VarConst) Allocator.Error!void {
    try self.push(alloc, variable.asConst(), .cycleGlobalTracing);
    defer self.pop();

    const exprI = variable.expr.load(.acquire);

    try self._pushDependant(alloc, variable, self.tu.global.nodes.getConstPtr(exprI).asConstExpression());
}

fn _pushDependant(self: *Self, alloc: Allocator, variable: *Parser.Node.VarConst, expr: *const Parser.Node.Expression) Allocator.Error!void {
    switch (expr.tag.load(.acquire)) {
        .load => {
            const load = expr.asConstLoad();
            try self.push(alloc, load.asConst(), .cycleGlobalTracing);
            defer self.pop();

            const id = load.getText(self.tu.global);
            const loadedVariable = self.tu.scope.get(id) orelse return;

            if (loadedVariable.tag.load(.acquire) == .protoArg) return;

            try self.tu.scope.pushDependant(alloc, id, variable);
        },
        .neg => {
            const left = expr.left.load(.acquire);

            try self._pushDependant(alloc, variable, self.tu.global.nodes.getPtr(left).asConstExpression());
        },
        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.left.load(.acquire);
            const right = expr.right.load(.acquire);

            try self._pushDependant(alloc, variable, self.tu.global.nodes.getPtr(left).asConstExpression());
            try self._pushDependant(alloc, variable, self.tu.global.nodes.getPtr(right).asConstExpression());
        },
        else => {},
    }
}

pub fn inferType(self: *Self, alloc: Allocator, variable: *Parser.Node.VarConst, expr: *const Parser.Node.Expression, reports: ?*Report.Reports) (Allocator.Error || Error)!bool {
    try self.push(alloc, expr.asConst(), .inference);
    defer self.pop();

    const typeI = try self._inferType(alloc, expr, reports);

    if (typeI == null) return false;

    if (variable.type.load(.acquire) != 0) return true;
    try self.addInferType(alloc, .inferedFromExpression, typeI.?.place, variable, typeI.?.type, reports);

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

            const typeIndex = variable.type.load(.acquire);

            return if (typeIndex == 0) null else .{ .type = self.tu.global.nodes.getConstPtr(typeIndex).asConstTypes(), .place = expr };
        },
        .funcProto => {
            const funcProto = expr.asConstFuncProto();
            const tIndex = funcProto.retType.load(.acquire);
            std.debug.assert(tIndex != 0);

            var argTypeIndex: Parser.NodeIndex = 0;
            const protoArgsIndex = funcProto.args.load(.acquire);

            if (protoArgsIndex != 0) {
                const protoArgFirst = self.tu.global.nodes.getConstPtr(protoArgsIndex).asConstProtoArg();
                var firstIndex: Parser.NodeIndex = 0;
                var nextIndex: Parser.NodeIndex = 0;

                var itProtoArg = protoArgFirst.iterate(self.tu.global);
                // Adding it in reverse order then when adding the count It is reversed
                while (itProtoArg.next()) |protoArg| {
                    const argTypeI = protoArg.type.load(.acquire);

                    const argType = Parser.Node.ArgType{
                        .tokenIndex = .init(protoArg.tokenIndex.load(.acquire)),
                        .count = .init(0),
                        .type_ = .init(argTypeI),

                        .next = .init(nextIndex),
                    };

                    nextIndex = try self.tu.global.nodes.appendIndex(alloc, argType.asConst().*);
                    if (firstIndex == 0) firstIndex = nextIndex;
                }

                var itArgType = self.tu.global.nodes.getPtr(nextIndex).asArgType().iterate(self.tu.global);
                var counter: Parser.NodeIndex = 0;
                var prevIndex: Parser.NodeIndex = 0;

                while (itArgType.next()) |argType| {
                    counter += 1;
                    assert(argType.count.cmpxchgStrong(0, counter, .acq_rel, .monotonic) == null);

                    argType.next.store(prevIndex, .release);

                    prevIndex = self.tu.global.nodes.indexOf(argType.as());
                }

                argTypeIndex = firstIndex;
            }

            const i = try self.tu.global.nodes.appendIndex(alloc, (Parser.Node.FuncType{
                .tokenIndex = .init(funcProto.tokenIndex.load(.acquire)),
                .argsType = .init(argTypeIndex),
                .retType = .init(tIndex),
                .flags = .init(.{ .inferedFromExpression = true }),
            }).asConst().*);

            return .{ .type = self.tu.global.nodes.getConstPtr(i).asConstTypes(), .place = funcProto.asConst().asConstExpression() };
        },
        .call => {
            const call = expr.asConstCall();
            const id = call.getText(self.tu.global);
            const func = (self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, call.asConst())).asVarConst();

            if (func.type.load(.acquire) == 0) {
                assert(self.inferType(alloc, func, self.tu.global.nodes.getPtr(func.expr.load(.acquire)).asExpression(), reports) catch |err| std.debug.panic("Why would this fail, it should be valid {}", .{err}));
            }

            var funcType = self.tu.global.nodes.getConstPtr(func.type.load(.acquire));

            var it = call.iterateConst(self.tu.global);
            // Consume the firstOne, I am searching a()()()
            _ = it.next();
            while (it.next()) |_| {
                if (funcType.tag.load(.acquire) != .funcType) return Report.expectedFunction(reports, call.asConst(), funcType);

                const ft = funcType.asConstFuncType();
                funcType = self.tu.global.nodes.getConstPtr(ft.retType.load(.acquire));
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
                    declared.as(),
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

fn checkCallType(self: *Self, alloc: Allocator, call_: *Parser.Node.Call, expectedType: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    var call = call_;

    const id = call.getText(self.tu.global);
    const func = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, call.asConst());

    if (func.type.load(.acquire) == 0) {
        assert(self.inferType(alloc, func.asVarConst(), self.tu.global.nodes.getPtr(func.asVarConst().expr.load(.acquire)).asExpression(), reports) catch |err| std.debug.panic("Why would this fail, it should be valid {}", .{err}));
    }

    const funcType = self.tu.global.nodes.getPtr(func.type.load(.acquire));

    // Lets say that there is an identity function, to use it in the loop uniformly
    var retType = funcType.asTypes();

    var itCall = call_.iterate(self.tu.global);
    while (itCall.next()) |callNode| {
        if (retType.tag.load(.acquire) != .funcType) return Report.expectedFunction(reports, callNode.as(), retType.asConst());
        const retFuncType = retType.asFuncType();

        var itArgType = retFuncType.argIterator(self.tu.global);
        var itArg = callNode.argIterator(self.tu.global);

        while (itArgType.next()) |argType| {
            const arg = itArg.next() orelse break;

            try self.checkType(
                alloc,
                self.tu.global.nodes.getPtr(arg.expr.load(.acquire)).asExpression(),
                self.tu.global.nodes.getConstPtr(argType.type_.load(.acquire)).asConstTypes(),
                reports,
            );
        }

        retType = self.tu.global.nodes.getPtr(retFuncType.retType.load(.acquire)).asTypes();
        call = callNode;
    }

    return switch (Type.compareActualsTypes(self.tu.global, retType, expectedType, true, true)) {
        .found => {},
        .coerce => {
            const pastFlags = call.as().flags.load(.acquire);
            var flags = pastFlags;
            flags.implicitCast = true;

            assert(call.as().flags.cmpxchgStrong(pastFlags, flags, .acquire, .monotonic) == null);
        },
        .notFound => Report.incompatibleReturnType(reports, retType.asConst(), expectedType.asConst(), call.asConst(), func.asConst()),
    };
}

fn checkFuncProtoType(self: *Self, funcProtoNode: *const Parser.Node.FuncProto, expectedType: *const Parser.Node.Types, reports: ?*Report.Reports) (Error)!void {
    const funcProto = funcProtoNode.asConst();

    const funcRetTypeIndex = funcProto.right.load(.acquire);

    std.debug.assert(expectedType.tag.load(.acquire) == .funcType);

    const retTypeIndex = expectedType.right.load(.acquire);

    const retType = self.tu.global.nodes.getPtr(retTypeIndex);
    const funcRetType = self.tu.global.nodes.getPtr(funcRetTypeIndex);

    switch (Type.compareActualsTypes(self.tu.global, funcRetType.asTypes(), retType.asTypes(), true, false)) {
        .notFound => return Report.incompatibleType(reports, retType, funcRetType, funcRetType, funcRetType),
        .found => {},
    }

    const argsI = funcProtoNode.args.load(.acquire);
    const typeArgsI = expectedType.left.load(.acquire);

    if (argsI == 0 and typeArgsI == 0) return;

    if (argsI == 0 or typeArgsI == 0) {
        return Report.incompatibleType(reports, funcProto, expectedType.asConst(), funcProto, funcProto);
    }

    var protoArg = self.tu.global.nodes.getConstPtr(argsI).asConstProtoArg();
    var typeArg = self.tu.global.nodes.getConstPtr(typeArgsI).asConstArgType();

    while (true) {
        const protoArgTypeIndex = protoArg.type.load(.acquire);
        const typeArgTypeIndex = typeArg.type_.load(.acquire);

        const protoArgType = self.tu.global.nodes.getPtr(protoArgTypeIndex).asTypes();
        const typeArgType = self.tu.global.nodes.getPtr(typeArgTypeIndex).asTypes();

        switch (Type.compareActualsTypes(self.tu.global, protoArgType, typeArgType, true, false)) {
            .notFound => return Report.incompatibleType(reports, typeArgType.as(), protoArgType.as(), protoArg.asConst(), protoArg.asConst()),
            .found => {},
        }

        const protoNextIndex = protoArg.next.load(.acquire);
        const typeNextIndex = typeArg.next.load(.acquire);

        if (protoNextIndex == 0 and typeNextIndex == 0) break;
        if (protoNextIndex == 0 or typeNextIndex == 0) {
            return Report.incompatibleType(reports, expectedType.asConst(), funcProto, funcProto, funcProto);
        }

        protoArg = self.tu.global.nodes.getConstPtr(protoNextIndex).asConstProtoArg();
        typeArg = self.tu.global.nodes.getConstPtr(typeNextIndex).asConstArgType();
    }
}

fn checkVarType(self: *Self, alloc: Allocator, load: *Parser.Node.Load, type_: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const id = load.getText(self.tu.global);

    const variable = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, load.asConst());

    const typeIndex = variable.type.load(.acquire);

    if (typeIndex == 0) {
        return addInferType(self, alloc, .inferedFromUse, load.as().asExpression(), variable.asVarConst(), type_, reports) catch |err| switch (err) {
            Error.IncompatibleType => {
                if (!try self.inferType(
                    alloc,
                    variable.asVarConst(),
                    self.tu.global.nodes.getConstPtr(variable.asVarConst().expr.load(.acquire)).asConstExpression(),
                    reports,
                )) return;
                return Report.incompatibleType(reports, self.tu.global.nodes.getConstPtr(variable.type.load(.acquire)), type_.asConst(), load.asConst(), variable.asConst());
            },
            else => return err,
        };
    }

    const variableType: *Parser.Node.Types = self.tu.global.nodes.getPtr(typeIndex).asTypes();
    const result = Type.compareActualsTypes(self.tu.global, variableType, type_, true, true);
    switch (result) {
        .found => return,
        .notFound, .coerce => {
            const tag = variable.tag.load(.acquire);
            if (tag == .constant)
                return addInferType(self, alloc, .inferedFromUse, load.as().asExpression(), variable.asVarConst(), type_, reports) catch |err| switch (err) {
                    Error.IncompatibleType => return Report.incompatibleType(
                        reports,
                        self.tu.global.nodes.getConstPtr(typeIndex),
                        type_.asConst(),
                        load.asConst(),
                        variable.asConst(),
                    ),
                    else => return err,
                };

            if (std.meta.activeTag(result) == .coerce) {
                const pastFlags = load.flags.load(.acquire);
                var flags = pastFlags;
                flags.implicitCast = true;

                assert(load.flags.cmpxchgStrong(pastFlags, flags, .acquire, .monotonic) == null);

                return;
            }
        },
    }

    return Report.incompatibleType(reports, variableType.asConst(), type_.asConst(), load.as(), variable.as());
}

fn addInferType(self: *Self, alloc: Allocator, comptime flag: std.meta.FieldEnum(Parser.Node.Flags), leaf: *const Parser.Node.Expression, variable: *Parser.Node.VarConst, type_: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    assert(flag == .inferedFromUse or flag == .inferedFromExpression);
    try self.push(alloc, variable.as(), .addInference);
    defer self.pop();

    const before = variable.type.load(.acquire);

    // Check Variable expression for that type
    try self.checkType(alloc, self.tu.global.nodes.getPtr(variable.expr.load(.acquire)).asExpression(), type_, null);

    const after = variable.type.load(.acquire);

    if (before != after) {
        switch (Type.compareActualsTypes(self.tu.global, self.tu.global.nodes.getPtr(after).asTypes(), type_, true, false)) {
            .found => |variableType| {
                var flags: Parser.Node.Flags = .{};
                @field(flags, @tagName(flag)) = true;
                variableType.flags.store(flags, .release);
                variableType.tokenIndex.store(leaf.tokenIndex.load(.acquire), .release);

                return;
            },
            .notFound => {},
        }
    }

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
    if (variable.type.cmpxchgStrong(nodeType.next.load(.acquire), x, .acq_rel, .monotonic) == null) {
        const id = variable.getText(self.tu.global);
        while (self.tu.scope.popDependant(id)) |dependant| {
            if (dependant.type.load(.acquire) == 0) {
                try Statement.checkVariable(self.tu, alloc, dependant, reports);
            }
        }
        return;
    }

    const variableType = self.tu.global.nodes.getPtr(variable.type.load(.acquire)).asTypes();
    switch (Type.compareActualsTypes(self.tu.global, variableType, type_, true, false)) {
        .found => return,
        .notFound => {},
    }

    @panic("Revaluete the way it is done");
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
const Statement = @import("Statements.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Report = @import("../Report/mod.zig");
const Parser = @import("../Parser/mod.zig");
const Scope = @import("Scope/mod.zig");
const Util = @import("../Util.zig");
const ArrayListThreadSafe = @import("../Util/ArrayListThreadSafe.zig").ArrayListThreadSafe;

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
