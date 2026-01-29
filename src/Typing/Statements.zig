pub fn recordVariable(self: *const TranslationUnit, alloc: Allocator, variable: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Scope.Error)!void {
    const varIndex = self.global.nodes.indexOf(variable);

    self.scope.put(alloc, variable.getText(self.global), varIndex) catch |err| switch (err) {
        Scope.Error.KeyAlreadyExists => {
            Report.redefinition(reports, varIndex, self.scope.get(variable.getText(self.global)).?);
            return Scope.Error.KeyAlreadyExists;
        },
        else => return @errorCast(err),
    };
}

pub fn traceVariable(self: *const TranslationUnit, alloc: Allocator, variable: *const Parser.Node) Allocator.Error!void {
    const expressionIndex = variable.data.@"1".load(.acquire);
    const expressionNode = self.global.nodes.get(expressionIndex);
    const expressionTag = expressionNode.tag.load(.acquire);

    if (expressionIndex == 0 or expressionTag == .funcProto) {
        return;
    } else {
        var expr = try Expression.init(alloc, self);
        defer expr.deinit(alloc);

        try expr.traceVariable(alloc, variable);
    }
}

pub fn checkVariable(self: *const TranslationUnit, alloc: Allocator, node: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    // NOTE: At the time being this is not changed so it should be fine;
    const expressionIndex = node.data.@"1".load(.acquire);
    const expressionNode = self.global.nodes.get(expressionIndex);
    const expressionTag = expressionNode.tag.load(.acquire);

    if (expressionIndex == 0 or expressionTag == .funcProto) {
        try checkFunctionOuter(self, alloc, node, reports);
    } else {
        try checkPureVariable(self, alloc, node, reports);
    }
}

fn checkFunctionOuter(self: *const TranslationUnit, alloc: Allocator, variable: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const funcIndex = variable.data.@"1".load(.acquire);
    const funcProto = self.global.nodes.getPtr(funcIndex);

    // Return Type
    Type.transformType(self, funcProto.data[1].load(.acquire));

    while (true) {
        const typeIndex = variable.data[0].load(.acquire);
        if (typeIndex != 0) {
            Type.transformType(self, typeIndex);
            try checkTypeFunction(self, self.global.nodes.getPtr(typeIndex), funcProto, reports);
            break;
        } else {
            const result = try inferTypeFunction(self, alloc, variable, funcProto);

            if (result)
                break;
        }
    }
}

fn inferTypeFunction(self: *const TranslationUnit, alloc: Allocator, variable: *const Parser.Node, proto: *const Parser.Node) Allocator.Error!bool {
    std.debug.assert(proto.tag.load(.acquire) == .funcProto);

    const tIndex = proto.data[1].load(.acquire);
    std.debug.assert(tIndex != 0);
    std.debug.assert(self.global.nodes.get(tIndex).tag.load(.acquire) == .type);

    const functionTypeIndex = try self.global.nodes.appendIndex(alloc, Parser.Node{
        .tag = .init(.funcType),
        .tokenIndex = .init(proto.tokenIndex.load(.acquire)),
        .data = .{ .init(0), .init(tIndex) },
        .flags = .init(.{ .inferedFromExpression = true }),
    });

    const variableIndex = self.global.nodes.indexOf(variable);
    const nodePtr = self.global.nodes.getPtr(variableIndex);
    const result = nodePtr.data.@"0".cmpxchgStrong(0, functionTypeIndex, .acq_rel, .monotonic);

    return result == null;
}

fn checkTypeFunction(self: *const TranslationUnit, funcType: *const Parser.Node, funcProto: *const Parser.Node, reports: ?*Report.Reports) (Expression.Error)!void {
    std.debug.assert(funcProto.tag.load(.acquire) == .funcProto);
    std.debug.assert(funcProto.data[0].load(.acquire) == 0);

    const funcRetTypeIndex = funcProto.data[1].load(.acquire);

    std.debug.assert(funcType.tag.load(.acquire) == .funcType);
    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);

    if (!Type.typeEqual(self, funcRetTypeIndex, retTypeIndex)) {
        return Report.incompatibleType(reports, retTypeIndex, funcRetTypeIndex, funcRetTypeIndex, 0);
    }
}

pub fn checkReturn(self: *const TranslationUnit, alloc: Allocator, stmt: *const Parser.Node, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    var expr = try Expression.init(alloc, self);
    defer expr.deinit(alloc);
    try expr.checkType(alloc, stmt.data[1].load(.acquire), typeI, reports);
}

fn checkPureVariable(self: *const TranslationUnit, alloc: Allocator, variable: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const typeIndex = variable.data[0].load(.acquire);

    var expr = try Expression.init(alloc, self);
    defer expr.deinit(alloc);

    if (typeIndex == 0) {
        if (!try expr.inferType(alloc, variable, variable.data.@"1".load(.acquire), reports)) return;
        expr.reset();
    } else {
        Type.transformType(self, typeIndex);
    }

    const typeIndex2 = variable.data.@"0".load(.acquire);
    std.debug.assert(typeIndex2 != 0);
    const exprI = variable.data.@"1".load(.acquire);

    try expr.checkType(alloc, exprI, typeIndex2, reports);
}

const Expression = @import("Expression.zig");
const Type = @import("Type.zig");
const Scope = @import("Scope/mod.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
