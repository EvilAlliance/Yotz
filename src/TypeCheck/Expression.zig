const Flatten = std.ArrayList(Parser.NodeIndex);

pub const Error = error{
    TooBig,
    IncompatibleType,
};

pub fn inferType(self: TranslationUnit, alloc: Allocator, varI: Parser.NodeIndex, exprI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!bool {
    const expr = self.global.nodes.get(exprI);
    const variableToInfer = self.global.nodes.get(varI);

    const exprTag = expr.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

    const variableToInferTag = variableToInfer.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .variable, .constant }, variableToInferTag));

    var flat = Flatten{};
    defer flat.deinit(alloc);

    try flatten(self, alloc, &flat, exprI);

    var firstSelected: Parser.NodeIndex = 0;
    var oldTypeIndex: Parser.NodeIndex = 0;
    var type_: Parser.Node = .{};

    while (flat.items.len > 0) {
        const firstI = flat.pop().?;
        const first = self.global.nodes.get(firstI);

        if (first.tag.load(.acquire) != .load) continue;

        const callBack = struct {
            fn callBack(args: Scope.ObserverParams) void {
                @call(.auto, toInferLater, .{ args[0].*, args[1], args[2], args[3], args[4] }) catch {
                    TranslationUnit.failed = true;
                    std.log.err("Run Out of Memory", .{});
                };
            }
        }.callBack;

        const id = first.getText(self.global);
        const variableI = try self.scope.getOrWait(alloc, id, callBack, .{ try Util.dupe(alloc, try self.reserve(alloc)), alloc, varI, firstI, reports }) orelse continue;

        const variable = self.global.nodes.get(variableI);
        const newTypeI = variable.data.@"0".load(.acquire);
        if (newTypeI == 0) continue;

        const newType = self.global.nodes.get(newTypeI);
        if (oldTypeIndex == 0 or (!Type.canTypeBeCoerced(self, newTypeI, oldTypeIndex) and Type.canTypeBeCoerced(self, oldTypeIndex, newTypeI))) {
            firstSelected = firstI;
            oldTypeIndex = newTypeI;
            type_ = newType;
        } else {
            try Report.incompatibleType(alloc, reports, newTypeI, oldTypeIndex, firstI, variableI);
            return false;
        }
    }

    if (oldTypeIndex == 0) return false;

    try addInferType(self, alloc, .inferedFromExpression, firstSelected, varI, oldTypeIndex);

    return true;
}

pub fn toInferLater(self: TranslationUnit, alloc: Allocator, varI: Parser.NodeIndex, waitedI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const waited = self.global.nodes.get(waitedI);
    const waitedTag = waited.tag.load(.acquire);
    std.debug.assert(waitedTag == .load);

    const id = waited.getText(self.global);
    const orgWaitedI = self.scope.get(id) orelse unreachable;

    const orgWaited = self.global.nodes.get(orgWaitedI);
    const orgWaitedTag = waited.tag.load(.acquire);
    std.debug.assert(orgWaitedTag == .constant or orgWaitedTag == .variable);

    const typeI = orgWaited.data.@"0".load(.acquire);

    const variable = self.global.nodes.get(varI);

    const typeIndex = variable.data.@"0".load(.acquire);

    std.debug.assert(typeI != 0 or typeIndex != 0);

    if (typeI == 0 and typeIndex != 0) {
        try addInferType(self, alloc, .inferedFromUse, waitedI, orgWaitedI, typeIndex);
    }

    if (typeIndex == 0 or !Type.canTypeBeCoerced(self, typeI, typeIndex)) {
        try addInferType(self, alloc, .inferedFromExpression, waitedI, varI, typeI);
    } else {
        try Report.incompatibleType(alloc, reports, typeI, typeIndex, waitedI, varI);
    }
}

pub fn checkType(self: TranslationUnit, alloc: Allocator, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const expr = self.global.nodes.get(exprI);
    const expectedType = self.global.nodes.get(expectedTypeI);

    const typeTag = expectedType.tag.load(.acquire);
    const exprTag = expr.tag.load(.acquire);
    assert(typeTag == .type);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

    var flat = Flatten{};
    defer flat.deinit(alloc);

    try flatten(self, alloc, &flat, exprI);

    try checkFlatten(self, alloc, &flat, expectedTypeI, reports);
}

fn flatten(self: TranslationUnit, alloc: Allocator, stack: *Flatten, exprI: Parser.NodeIndex) std.mem.Allocator.Error!void {
    const expr = self.global.nodes.get(exprI);
    const exprTag = expr.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

    switch (exprTag) {
        .lit => {
            try stack.append(alloc, exprI);
        },
        .load => {
            try stack.append(alloc, exprI);
        },
        .neg => {
            const left = expr.data[0].load(.acquire);

            try flatten(self, alloc, stack, left);

            try stack.append(alloc, exprI);
        },
        .addition, .subtraction, .multiplication, .division, .power => {
            const left = expr.data[0].load(.acquire);
            const right = expr.data[1].load(.acquire);

            try flatten(self, alloc, stack, left);
            try stack.append(alloc, exprI);
            try flatten(self, alloc, stack, right);
        },
        else => {
            const loc = expr.getLocation(self.global);
            const fileInfo = self.global.files.get(loc.source);
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

fn checkFlatten(self: TranslationUnit, alloc: Allocator, flat: *Flatten, expectedTypeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    var err: ?(Allocator.Error || Error) = null;
    const expectedType = self.global.nodes.get(expectedTypeI);
    assert(expectedType.tag.load(.acquire) == .type);

    while (flat.items.len > 0) {
        const firstI = flat.getLast();
        const first = self.global.nodes.get(firstI);

        if (first.tag.load(.acquire) != .neg) {
            checkLeaf(self, alloc, firstI, expectedTypeI, reports) catch |e| switch (e) {
                Error.IncompatibleType, Error.TooBig => err = e,
                else => return @errorCast(e),
            };
            _ = flat.pop();
        }

        while (flat.items.len > 0) {
            const opI = flat.pop().?;
            const op = self.global.nodes.get(opI);
            const opTag = op.tag.load(.acquire);

            assert(Util.listContains(Parser.Node.Tag, &.{ .neg, .power, .division, .multiplication, .subtraction, .addition }, opTag));

            switch (opTag) {
                .neg => break,
                .power,
                .division,
                .multiplication,
                .subtraction,
                .addition,
                => {
                    const xI = flat.getLast();
                    const x = self.global.nodes.get(xI);

                    if (x.tag.load(.acquire) == .neg) break;

                    checkLeaf(self, alloc, xI, expectedTypeI, reports) catch |e| switch (e) {
                        Error.IncompatibleType, Error.TooBig => err = e,
                        else => return @errorCast(e),
                    };

                    _ = flat.pop();
                },
                else => unreachable,
            }
        }
    }

    if (err) |e| return e;
}

fn checkLeaf(self: TranslationUnit, alloc: Allocator, leafI: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const leaf = self.global.nodes.get(leafI);
    const expectedType = self.global.nodes.get(typeI);
    const leafTag = leaf.tag.load(.acquire);

    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load }, leafTag) and expectedType.tag.load(.acquire) == .type);

    switch (leafTag) {
        .lit => try checkLitType(self, alloc, leafI, typeI, reports),
        .load => try checkVarType(self, alloc, leafI, typeI, reports),
        else => unreachable,
    }
}

fn checkVarType(self: TranslationUnit, alloc: Allocator, leafI: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const leaf = self.global.nodes.get(leafI);
    const id = leaf.getText(self.global);

    const callBack = struct {
        fn callBack(args: Scope.ObserverParams) void {
            @call(.auto, checkVarType, .{ args[0].*, args[1], args[2], args[3], args[4] }) catch {
                TranslationUnit.failed = true;
                std.log.err("Run Out of Memory", .{});
            };
        }
    }.callBack;

    const variableI =
        try self.scope.getOrWait(
            alloc,
            id,
            callBack,
            .{ try Util.dupe(alloc, try self.reserve(alloc)), alloc, leafI, typeI, reports },
        ) orelse return;

    const variable = self.global.nodes.get(variableI);
    const typeIndex = variable.data.@"0".load(.acquire);

    if (typeIndex == 0) {
        try addInferType(self, alloc, .inferedFromUse, leafI, variableI, typeI);
    } else {
        if (!Type.typeEqual(self, typeIndex, typeI)) {
            const tag = variable.tag.load(.acquire);
            if (tag == .variable) {
                try Report.incompatibleType(alloc, reports, typeIndex, typeI, leafI, variableI);
            } else {
                assert(tag == .constant);
                try addInferType(self, alloc, .inferedFromUse, leafI, variableI, typeI);
            }
        }
    }
}

fn addInferType(self: TranslationUnit, alloc: Allocator, comptime flag: std.meta.FieldEnum(Parser.Node.Flags), leafI: Parser.NodeIndex, varI: Parser.NodeIndex, typeI: Parser.NodeIndex) (Allocator.Error || Error)!void {
    assert(flag == .inferedFromUse or flag == .inferedFromExpression);

    const leaf = self.global.nodes.get(leafI);
    const variable = self.global.nodes.get(varI);

    // Check Variable expression for that type
    try checkType(self, alloc, variable.data.@"1".load(.acquire), typeI, null);

    // Reset data
    var nodeType = self.global.nodes.get(typeI);
    nodeType.tokenIndex.store(leaf.tokenIndex.load(.acquire), .release);

    nodeType.next.store(variable.data.@"0".load(.acquire), .release);
    var flags: Parser.Node.Flags = .{};
    @field(flags, @tagName(flag)) = true;
    nodeType.flags.store(flags, .release);

    // Add to list
    const x = try self.global.nodes.appendIndex(alloc, nodeType);
    // Make the variable be that type
    self.global.nodes.getPtr(varI).data.@"0".store(x, .release);
}

fn checkLitType(self: TranslationUnit, alloc: Allocator, litI: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    const lit = self.global.nodes.get(litI);
    const expectedType = self.global.nodes.get(typeI);

    std.debug.assert(expectedType.tag.load(.acquire) == .type);

    const primitive = expectedType.data[1].load(.acquire);
    const size = expectedType.data[0].load(.acquire);

    const text = lit.getText(self.global);
    switch (@as(Parser.Node.Primitive, @enumFromInt(primitive))) {
        Parser.Node.Primitive.uint => {
            const max = std.math.pow(u64, 2, size) - 1;
            const number = std.fmt.parseInt(u64, text, 10) catch return try Report.incompatibleLiteral(alloc, reports, litI, typeI);

            if (number < max) return;
            try Report.incompatibleLiteral(alloc, reports, litI, typeI);
        },
        Parser.Node.Primitive.sint => {
            const max = std.math.pow(i64, 2, (size - 1)) - 1;
            const number = std.fmt.parseInt(i64, text, 10) catch
                return try Report.incompatibleLiteral(alloc, reports, litI, typeI);

            if (number < max) return;
            try Report.incompatibleLiteral(alloc, reports, litI, typeI);
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

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
