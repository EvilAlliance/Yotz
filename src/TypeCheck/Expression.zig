const Flatten = std.ArrayList(Parser.NodeIndex);

pub fn inferType(self: *const TypeCheck, alloc: Allocator, varI: Parser.NodeIndex, exprI: Parser.NodeIndex) Allocator.Error!bool {
    const expr = self.ast.getNode(exprI);
    const variableToInfer = self.ast.getNode(varI);

    const exprTag = expr.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

    const variableToInferTag = variableToInfer.tag.load(.acquire);
    assert(Util.listContains(Parser.Node.Tag, &.{ .variable, .constant }, variableToInferTag));

    var flat = Flatten{};
    defer flat.deinit(alloc);

    try flatten(self, alloc, &flat, exprI);

    var firstSelected: Parser.NodeIndex = 0;
    var typeIndex: Parser.NodeIndex = 0;
    var type_: Parser.Node = .{};

    while (flat.items.len > 0) {
        const firstI = flat.pop().?;
        const first = self.ast.getNode(firstI);

        if (first.tag.load(.acquire) != .load) continue;

        const callBack = struct {
            fn callBack(args: ObserverParams) void {
                defer args[0].destroyDupe(args[1]);
                @call(.auto, toInferLater, args) catch {
                    TranslationUnit.failed = true;
                    std.log.err("Run Out of Memory", .{});
                };
            }
        }.callBack;

        const id = first.getTextAst(self.ast);
        const variableI = try self.tu.scope.getOrWait(alloc, id, callBack, .{ try self.dupe(alloc), alloc, varI, firstI }) orelse continue;

        const variable = self.ast.getNode(variableI);
        const typeI = variable.data.@"0".load(.acquire);
        if (typeI == 0) continue;

        const newType = self.ast.getNode(typeI);
        if (typeIndex == 0 or !Type.canTypeBeCoerced(self, typeI, typeIndex)) {
            firstSelected = firstI;
            typeIndex = typeI;
            type_ = newType;
        } else {
            self.message.err.incompatibleType(typeI, typeIndex, first.getLocationAst(self.ast.*));
            return false;
        }
    }

    if (typeIndex == 0) return false;

    try addInferType(self, alloc, .inferedFromExpression, firstSelected, varI, typeIndex);

    return true;
}

pub fn toInferLater(self: *const TypeCheck, alloc: Allocator, varI: Parser.NodeIndex, waitedI: Parser.NodeIndex) Allocator.Error!void {
    const waited = self.ast.getNode(waitedI);
    const waitedTag = waited.tag.load(.acquire);
    std.debug.assert(waitedTag == .load);

    const id = waited.getTextAst(self.ast);
    const orgWaitedI = self.tu.scope.get(id) orelse unreachable;

    const orgWaited = self.ast.getNode(orgWaitedI);
    const orgWaitedTag = waited.tag.load(.acquire);
    std.debug.assert(orgWaitedTag == .constant or orgWaitedTag == .variable);

    const typeI = orgWaited.data.@"0".load(.acquire);

    const variable = self.ast.getNode(varI);

    const typeIndex = variable.data.@"0".load(.acquire);

    std.debug.assert(typeI != 0 or typeIndex != 0);

    if (typeI == 0 and typeIndex != 0) {
        try addInferType(self, alloc, .inferedFromUse, waitedI, orgWaitedI, typeIndex);
    }

    if (typeIndex == 0 or !Type.canTypeBeCoerced(self, typeI, typeIndex)) {
        try addInferType(self, alloc, .inferedFromExpression, waitedI, varI, typeI);
    } else {
        self.message.err.incompatibleType(typeI, typeIndex, waited.getLocationAst(self.ast.*));
        TranslationUnit.failed = true;
    }
}

pub fn checkType(self: *const TypeCheck, alloc: Allocator, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) Allocator.Error!void {
    const expr = self.ast.getNode(exprI);
    const expectedType = self.ast.getNode(expectedTypeI);

    const typeTag = expectedType.tag.load(.acquire);
    const exprTag = expr.tag.load(.acquire);
    assert(typeTag == .type);
    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, exprTag));

    var flat = Flatten{};

    try flatten(self, alloc, &flat, exprI);

    try checkFlatten(self, alloc, &flat, expectedTypeI);
}

fn flatten(self: *const TypeCheck, alloc: Allocator, stack: *Flatten, exprI: Parser.NodeIndex) std.mem.Allocator.Error!void {
    const expr = self.ast.getNode(exprI);
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
            self.message.err.nodeNotSupported(exprI);
            unreachable;
        },
    }
}

fn checkFlatten(self: *const TypeCheck, alloc: Allocator, flat: *Flatten, expectedTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
    const expectedType = self.ast.getNode(expectedTypeI);
    assert(expectedType.tag.load(.acquire) == .type);

    while (flat.items.len > 0) {
        const firstI = flat.getLast();
        const first = self.ast.getNode(firstI);

        if (first.tag.load(.acquire) != .neg) {
            try checkLeaf(self, alloc, firstI, expectedTypeI);
            _ = flat.pop();
        }

        while (flat.items.len > 0) {
            const opI = flat.pop().?;
            const op = self.ast.getNode(opI);
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
                    const x = self.ast.getNode(xI);

                    if (x.tag.load(.acquire) == .neg) break;

                    try checkLeaf(self, alloc, xI, expectedTypeI);
                    _ = flat.pop();
                },
                else => unreachable,
            }
        }
    }

    flat.deinit(alloc);
}

// TODO: Booble Up the error, or see how to manage it
fn checkLeaf(self: *const TypeCheck, alloc: Allocator, leafI: Parser.NodeIndex, typeI: Parser.NodeIndex) Allocator.Error!void {
    const leaf = self.ast.getNode(leafI);
    const expectedType = self.ast.getNode(typeI);
    const leafTag = leaf.tag.load(.acquire);

    assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load }, leafTag) and expectedType.tag.load(.acquire) == .type);

    switch (leafTag) {
        .lit => checkLitType(self, leafI, typeI),
        .load => try checkVarType(self, alloc, leafI, typeI),
        else => unreachable,
    }
}

fn checkVarType(self: *const TypeCheck, alloc: Allocator, leafI: Parser.NodeIndex, typeI: Parser.NodeIndex) Allocator.Error!void {
    const leaf = self.ast.getNode(leafI);
    const id = leaf.getTextAst(self.ast);

    const callBack = struct {
        fn callBack(args: ObserverParams) void {
            defer args[0].destroyDupe(args[1]);
            @call(.auto, checkVarType, args) catch {
                TranslationUnit.failed = true;
                std.log.err("Run Out of Memory", .{});
            };
        }
    }.callBack;

    const variableI =
        try self.tu.scope.getOrWait(
            alloc,
            id,
            callBack,
            .{ try self.dupe(alloc), alloc, leafI, typeI },
        ) orelse return;

    const variable = self.ast.getNode(variableI);
    const typeIndex = variable.data.@"0".load(.acquire);

    if (typeIndex == 0) {
        try addInferType(self, alloc, .inferedFromUse, leafI, variableI, typeI);
    } else {
        if (!Type.typeEqual(self, typeIndex, typeI)) {
            const tag = variable.tag.load(.acquire);
            if (tag == .variable) {
                self.message.err.incompatibleType(typeIndex, typeI, self.ast.getNodeLocation(leafI));
                const flags = self.ast.getNode(typeIndex).flags.load(.acquire);
                self.message.info.isDeclaredHere(variableI);
                if (flags.inferedFromExpression or flags.inferedFromUse) {
                    self.message.info.inferedType(typeIndex);
                }
                return;
            } else {
                assert(tag == .constant);
                try addInferType(self, alloc, .inferedFromUse, leafI, variableI, typeI);
            }
        }
    }
}

fn addInferType(self: *const TypeCheck, alloc: Allocator, comptime flag: std.meta.FieldEnum(Parser.Node.Flags), leafI: Parser.NodeIndex, varI: Parser.NodeIndex, typeI: Parser.NodeIndex) Allocator.Error!void {
    assert(flag == .inferedFromUse or flag == .inferedFromExpression);

    const leaf = self.ast.getNode(leafI);
    const variable = self.ast.getNode(varI);

    // Check Variable expression for that type
    // TODO: Check if this was successful
    try checkType(self, alloc, variable.data.@"1".load(.acquire), typeI);

    // Reset data
    var nodeType = self.ast.getNode(typeI);
    nodeType.tokenIndex.store(leaf.tokenIndex.load(.acquire), .release);

    nodeType.next.store(variable.data.@"0".load(.acquire), .release);
    var flags: Parser.Node.Flags = .{};
    @field(flags, @tagName(flag)) = true;
    nodeType.flags.store(flags, .release);

    // Add to list
    const x = try self.ast.nodeList.appendIndex(alloc, nodeType);
    // Make the variable be that type
    self.ast.getNodePtr(varI).data.@"0".store(x, .release);
}

fn checkLitType(self: *const TypeCheck, litI: Parser.NodeIndex, typeI: Parser.NodeIndex) void {
    const lit = self.ast.getNode(litI);
    const expectedType = self.ast.getNode(typeI);

    std.debug.assert(expectedType.tag.load(.acquire) == .type);

    const primitive = expectedType.data[1].load(.acquire);
    const size = expectedType.data[0].load(.acquire);
    const flags = expectedType.flags.load(.acquire);

    const text = lit.getTextAst(self.ast);
    switch (@as(Parser.Node.Primitive, @enumFromInt(primitive))) {
        Parser.Node.Primitive.uint => {
            const max = std.math.pow(u64, 2, size) - 1;
            const number = std.fmt.parseInt(u64, text, 10) catch {
                self.message.err.numberDoesNotFit(litI, typeI);
                if (flags.inferedFromExpression or flags.inferedFromUse) {
                    self.message.info.inferedType(litI);
                }
                return;
            };

            if (number < max) return;
            self.message.err.numberDoesNotFit(litI, typeI);
            if (flags.inferedFromExpression or flags.inferedFromUse) {
                self.message.info.inferedType(litI);
            }
        },
        Parser.Node.Primitive.int => {
            const max = std.math.pow(i64, 2, (size - 1)) - 1;
            const min = std.math.pow(i64, 2, (size - 1)) - 1;
            const number = std.fmt.parseInt(i64, text, 10) catch {
                self.message.err.numberDoesNotFit(litI, typeI);
                if (flags.inferedFromExpression or flags.inferedFromUse) {
                    self.message.info.inferedType(litI);
                }
                return;
            };

            if (min < number and number < max) return;
            self.message.err.numberDoesNotFit(litI, typeI);
            if (flags.inferedFromExpression or flags.inferedFromUse) {
                self.message.info.inferedType(litI);
            }
        },
        Parser.Node.Primitive.float => unreachable,
    }
}

pub const ObserverParams = std.meta.Tuple(&.{ *const TypeCheck, Allocator, Parser.NodeIndex, Parser.NodeIndex });

comptime {
    const Expected = Util.getTupleFromParams(toInferLater);
    const Expected1 = Util.getTupleFromParams(checkVarType);
    if (ObserverParams != Expected or ObserverParams != Expected1) {
        @compileError("ObserverParams type mismatch with toInferLater signature");
    }
}

const TypeCheck = @import("TypeCheck.zig");
const Type = @import("Type.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Util = @import("../Util.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
