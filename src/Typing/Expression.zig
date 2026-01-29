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
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

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

            const variable = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, self.tu.global.nodes.indexOf(expr));

            const typeIndex = variable.data.@"0".load(.acquire);

            return if (typeIndex == 0) null else .{ .type = self.tu.global.nodes.getConstPtr(typeIndex), .place = expr };
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

                return Report.incompatibleType(
                    reports,
                    self.tu.global.nodes.indexOf(typeL.?.type),
                    self.tu.global.nodes.indexOf(typeR.?.type),
                    self.tu.global.nodes.indexOf(expr),
                    self.tu.global.nodes.indexOf(self.tu.scope.get(typeR.?.place.getText(self.tu.global)).?),
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
    assert(typeTag == .type);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

    try self.checkExpected(alloc, expr, expectedType, reports);
}

fn checkExpected(self: *Self, alloc: Allocator, expr: *Parser.Node, expectedType: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    assert(expectedType.tag.load(.acquire) == .type);

    const exprTag = expr.tag.load(.acquire);

    switch (exprTag) {
        .lit => try self.checkLitType(expr, expectedType, reports),
        .load => try self.checkVarType(alloc, expr, expectedType, reports),

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

fn checkVarType(self: *Self, alloc: Allocator, leaf: *Parser.Node, type_: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const id = leaf.getText(self.tu.global);

    const variable = self.tu.scope.get(id) orelse return Report.undefinedVariable(reports, self.tu.global.nodes.indexOf(leaf));

    const typeIndex = variable.data.@"0".load(.acquire);

    if (typeIndex == 0)
        return addInferType(self, alloc, .inferedFromUse, leaf, variable, type_);

    const tag = variable.tag.load(.acquire);

    const variableType = self.tu.global.nodes.getConstPtr(typeIndex);
    if (!Type.canTypeBeCoerced(variableType, type_)) {
        if (tag == .constant)
            return addInferType(self, alloc, .inferedFromUse, leaf, variable, type_);
        return Report.incompatibleType(reports, typeIndex, self.tu.global.nodes.indexOf(type_), self.tu.global.nodes.indexOf(leaf), self.tu.global.nodes.indexOf(variable));
    }

    if (!Type.typeEqual(variableType, type_)) {
        if (tag == .constant)
            return addInferType(self, alloc, .inferedFromUse, leaf, variable, type_);

        var x: ?Parser.Node.Flags = .{};
        while (x) |_| {
            const pastFlags = leaf.flags.load(.acquire);
            var flags = pastFlags;
            flags.implicitCast = true;

            x = leaf.flags.cmpxchgWeak(pastFlags, flags, .acquire, .monotonic);
        }
    }
}

fn addInferType(self: *Self, alloc: Allocator, comptime flag: std.meta.FieldEnum(Parser.Node.Flags), leaf: *const Parser.Node, variable: *Parser.Node, type_: *const Parser.Node) (Allocator.Error || Error)!void {
    assert(flag == .inferedFromUse or flag == .inferedFromExpression);
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
            const number = std.fmt.parseInt(u64, text, 10) catch return Report.incompatibleLiteral(reports, self.tu.global.nodes.indexOf(lit), self.tu.global.nodes.indexOf(expectedType));

            if (number < max) return;
            return Report.incompatibleLiteral(reports, self.tu.global.nodes.indexOf(lit), self.tu.global.nodes.indexOf(expectedType));
        },
        Parser.Node.Primitive.sint => {
            const max = std.math.pow(i64, 2, (size - 1)) - 1;
            const number = std.fmt.parseInt(i64, text, 10) catch
                return Report.incompatibleLiteral(reports, self.tu.global.nodes.indexOf(lit), self.tu.global.nodes.indexOf(expectedType));

            if (number < max) return;
            return Report.incompatibleLiteral(reports, self.tu.global.nodes.indexOf(lit), self.tu.global.nodes.indexOf(expectedType));
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
