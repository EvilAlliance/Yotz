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
    index: Parser.NodeIndex,
    reason: Reason,

    pub fn eql(a: CycleUnit, b: CycleUnit) bool {
        return a.index == b.index and a.reason == b.reason;
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

fn push(self: *Self, alloc: Allocator, varIndex: Parser.NodeIndex, reason: Reason) (Allocator.Error)!void {
    const unit: CycleUnit = .{ .index = varIndex, .reason = reason };
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
pub fn traceVariable(self: *Self, alloc: Allocator, varI: Parser.NodeIndex) Allocator.Error!void {
    try self.push(alloc, varI, .cycleGlobalTracing);
    defer self.pop();

    var variable = self.tu.global.nodes.get(varI);
    const exprI = variable.data.@"1".load(.acquire);

    try self._traceVariable(alloc, exprI);
}

fn _traceVariable(self: *Self, alloc: Allocator, exprI: Parser.NodeIndex) Allocator.Error!void {
    const expr = self.tu.global.nodes.get(exprI);
    switch (expr.tag.load(.acquire)) {
        .load => {
            try self.push(alloc, exprI, .cycleGlobalTracing);
            defer self.pop();

            try self.traceVariable(alloc, self.tu.scope.get(expr.getText(self.tu.global)) orelse return);
        },
        .neg => {
            const left = expr.data[0].load(.acquire);

            try self.traceVariable(alloc, left);
        },
        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.data[0].load(.acquire);
            const right = expr.data[1].load(.acquire);

            try self.traceVariable(alloc, left);
            try self.traceVariable(alloc, right);
        },
        else => {},
    }
}

pub fn inferType(self: *Self, alloc: Allocator, varI: Parser.NodeIndex, exprI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!bool {
    try self.push(alloc, exprI, .inference);
    defer self.pop();

    const expr = self.tu.global.nodes.get(exprI);
    const variableToInfer = self.tu.global.nodes.get(varI);

    const exprTag = expr.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

    const variableToInferTag = variableToInfer.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .variable, .constant }, variableToInferTag));

    const typeI = try self._inferType(alloc, exprI, reports);

    if (typeI == null) return false;

    try self.addInferType(alloc, .inferedFromExpression, typeI.?.placeI, varI, typeI.?.typeI);

    return true;
}

pub fn _inferType(self: *Self, alloc: Allocator, exprI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!?struct { typeI: Parser.NodeIndex, placeI: Parser.NodeIndex } {
    const expr = self.tu.global.nodes.get(exprI);
    const exprTag = expr.tag.load(.acquire);

    switch (exprTag) {
        .lit => return null,
        .load => {
            const leaf = expr;
            const id = leaf.getText(self.tu.global);

            const variableI = self.tu.scope.get(id) orelse return Report.undefinedVariable(alloc, reports, exprI);

            const variable = self.tu.global.nodes.get(variableI);
            const typeIndex = variable.data.@"0".load(.acquire);

            return if (typeIndex == 0) null else .{ .typeI = typeIndex, .placeI = exprI };
        },

        .neg => {
            const left = expr.data[0].load(.acquire);

            return self._inferType(alloc, left, reports);
        },

        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.data[0].load(.acquire);
            const right = expr.data[1].load(.acquire);

            const typeLI = try self._inferType(alloc, left, reports);
            const typeRI = try self._inferType(alloc, right, reports);

            if (typeLI == null and typeRI == null) return null;
            if (typeLI == null or typeRI == null) return if (typeLI == null) typeRI else typeLI;

            if (typeLI != null and typeRI != null) {
                if (Type.canTypeBeCoerced(self.tu.*, typeLI.?.typeI, typeRI.?.typeI)) return typeRI;
                if (Type.canTypeBeCoerced(self.tu.*, typeRI.?.typeI, typeLI.?.typeI)) return typeLI;

                return Report.incompatibleType(
                    alloc,
                    reports,
                    typeLI.?.typeI,
                    typeRI.?.typeI,
                    exprI,
                    self.tu.scope.get(self.tu.global.nodes.get(typeRI.?.placeI).getText(self.tu.global)).?,
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

pub fn checkType(self: *Self, alloc: Allocator, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    try self.push(alloc, exprI, .check);
    defer self.pop();

    const expr = self.tu.global.nodes.get(exprI);
    const expectedType = self.tu.global.nodes.get(expectedTypeI);

    const typeTag = expectedType.tag.load(.acquire);
    const exprTag = expr.tag.load(.acquire);
    assert(typeTag == .type);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

    try self.checkExpected(alloc, exprI, expectedTypeI, reports);
}

fn checkExpected(self: *Self, alloc: Allocator, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const expectedType = self.tu.global.nodes.get(expectedTypeI);
    assert(expectedType.tag.load(.acquire) == .type);

    const expr = self.tu.global.nodes.get(exprI);
    const exprTag = expr.tag.load(.acquire);

    switch (exprTag) {
        .lit => try self.checkLitType(alloc, exprI, expectedTypeI, reports),
        .load => try self.checkVarType(alloc, exprI, expectedTypeI, reports),

        .neg => {
            const left = expr.data[0].load(.acquire);

            try self.checkExpected(alloc, left, expectedTypeI, reports);
        },

        .addition,
        .subtraction,
        .multiplication,
        .division,
        .power,
        => {
            const left = expr.data[0].load(.acquire);
            const right = expr.data[1].load(.acquire);

            try self.checkExpected(alloc, left, expectedTypeI, reports);
            try self.checkExpected(alloc, right, expectedTypeI, reports);
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

fn checkVarType(self: *Self, alloc: Allocator, leafI: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const leaf = self.tu.global.nodes.get(leafI);
    const id = leaf.getText(self.tu.global);

    const varia = self.tu.scope.get(id) orelse return Report.undefinedVariable(alloc, reports, leafI);

    const variable = self.tu.global.nodes.get(varia);
    const typeIndex = variable.data.@"0".load(.acquire);

    if (typeIndex == 0)
        return addInferType(self, alloc, .inferedFromUse, leafI, varia, typeI);

    const tag = variable.tag.load(.acquire);

    if (!Type.canTypeBeCoerced(self.tu.*, typeIndex, typeI)) {
        if (tag == .constant)
            return addInferType(self, alloc, .inferedFromUse, leafI, varia, typeI);
        return Report.incompatibleType(alloc, reports, typeIndex, typeI, leafI, varia);
    }

    if (!Type.typeEqual(self.tu.*, typeIndex, typeI)) {
        if (tag == .constant)
            return addInferType(self, alloc, .inferedFromUse, leafI, varia, typeI);

        var x: ?Parser.Node.Flags = .{};
        while (x) |_| {
            const pastFlags = leaf.flags.load(.acquire);
            var flags = pastFlags;
            flags.implicitCast = true;

            x = self.tu.global.nodes.getPtr(leafI).flags.cmpxchgWeak(pastFlags, flags, .acquire, .monotonic);
        }
    }
}

fn addInferType(self: *Self, alloc: Allocator, comptime flag: std.meta.FieldEnum(Parser.Node.Flags), leafI: Parser.NodeIndex, varI: Parser.NodeIndex, typeI: Parser.NodeIndex) (Allocator.Error || Error)!void {
    assert(flag == .inferedFromUse or flag == .inferedFromExpression);
    try self.push(alloc, varI, .addInference);
    defer self.pop();

    const leaf = self.tu.global.nodes.get(leafI);
    const variable = self.tu.global.nodes.get(varI);

    // Check Variable expression for that type
    try self.checkType(alloc, variable.data.@"1".load(.acquire), typeI, null);

    // Reset data
    var nodeType = self.tu.global.nodes.get(typeI);
    nodeType.tokenIndex.store(leaf.tokenIndex.load(.acquire), .release);

    nodeType.next.store(variable.data.@"0".load(.acquire), .release);
    var flags: Parser.Node.Flags = .{};
    @field(flags, @tagName(flag)) = true;
    nodeType.flags.store(flags, .release);

    // Add to list
    const x = try self.tu.global.nodes.appendIndex(alloc, nodeType);
    // Make the variable be that type
    // TODO: Do a compare and exchange, this may be a race condition with other funcion
    self.tu.global.nodes.getPtr(varI).data.@"0".store(x, .release);
}

fn checkLitType(self: *Self, alloc: Allocator, litI: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const lit = self.tu.global.nodes.get(litI);
    const expectedType = self.tu.global.nodes.get(typeI);

    std.debug.assert(expectedType.tag.load(.acquire) == .type);

    const primitive = expectedType.data[1].load(.acquire);
    const size = expectedType.data[0].load(.acquire);

    const text = lit.getText(self.tu.global);
    switch (@as(Parser.Node.Primitive, @enumFromInt(primitive))) {
        Parser.Node.Primitive.uint => {
            const max = std.math.pow(u64, 2, size) - 1;
            const number = std.fmt.parseInt(u64, text, 10) catch return Report.incompatibleLiteral(alloc, reports, litI, typeI);

            if (number < max) return;
            return Report.incompatibleLiteral(alloc, reports, litI, typeI);
        },
        Parser.Node.Primitive.sint => {
            const max = std.math.pow(i64, 2, (size - 1)) - 1;
            const number = std.fmt.parseInt(i64, text, 10) catch
                return Report.incompatibleLiteral(alloc, reports, litI, typeI);

            if (number < max) return;
            return Report.incompatibleLiteral(alloc, reports, litI, typeI);
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
