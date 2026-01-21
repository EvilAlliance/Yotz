pub fn recordVariable(self: TranslationUnit, alloc: Allocator, varIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Scope.Error)!void {
    const variable = self.global.nodes.get(varIndex);

    self.scope.put(alloc, variable.getText(self.global), varIndex) catch |err| switch (err) {
        Scope.Error.KeyAlreadyExists => try Report.redefinition(alloc, reports, varIndex, self.scope.get(variable.getText(self.global)).?),
        else => return @errorCast(err),
    };
}

pub fn checkVariable(self: TranslationUnit, alloc: Allocator, nodeIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const node = self.global.nodes.get(nodeIndex);
    // NOTE: At the time being this is not changed so it should be fine;
    const expressionIndex = node.data.@"1".load(.acquire);
    const expressionNode = self.global.nodes.get(expressionIndex);
    const expressionTag = expressionNode.tag.load(.acquire);

    if (expressionIndex == 0 or expressionTag == .funcProto) {
        try checkFunctionOuter(self, alloc, nodeIndex, reports);
    } else {
        try checkPureVariable(self, alloc, nodeIndex, reports);
    }
}

fn checkFunctionOuter(self: TranslationUnit, alloc: Allocator, variableIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const variable = self.global.nodes.get(variableIndex);
    const funcIndex = variable.data.@"1".load(.acquire);

    // Return Type
    Type.transformType(self, self.global.nodes.get(funcIndex).data[1].load(.acquire));

    while (true) {
        const typeIndex = variable.data[0].load(.acquire);
        if (typeIndex != 0) {
            Type.transformType(self, typeIndex);
            try checkTypeFunction(self, alloc, typeIndex, funcIndex, reports);
            break;
        } else {
            const result = try inferTypeFunction(self, alloc, variableIndex, funcIndex);

            if (result)
                break;
        }
    }
}

fn inferTypeFunction(self: TranslationUnit, alloc: Allocator, variableIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex) Allocator.Error!bool {
    const proto = self.global.nodes.get(funcIndex);
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

    const nodePtr = self.global.nodes.getPtr(variableIndex);
    const result = nodePtr.data.@"0".cmpxchgStrong(0, functionTypeIndex, .acq_rel, .monotonic);

    return result == null;
}

fn checkTypeFunction(self: TranslationUnit, alloc: Allocator, funcTypeIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const funcProto = self.global.nodes.get(funcIndex);
    std.debug.assert(funcProto.tag.load(.acquire) == .funcProto);
    std.debug.assert(funcProto.data[0].load(.acquire) == 0);

    const funcRetTypeIndex = funcProto.data[1].load(.acquire);

    const funcType = self.global.nodes.get(funcTypeIndex);
    std.debug.assert(funcType.tag.load(.acquire) == .funcType);
    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);

    if (!Type.typeEqual(self, funcRetTypeIndex, retTypeIndex)) {
        return Report.incompatibleType(alloc, reports, retTypeIndex, funcRetTypeIndex, funcRetTypeIndex, 0);
    }
}

pub fn checkReturn(self: TranslationUnit, alloc: Allocator, nodeI: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const stmt = self.global.nodes.get(nodeI);
    try Expression.checkType(self, alloc, stmt.data[1].load(.acquire), typeI, reports);
}

fn checkPureVariable(self: TranslationUnit, alloc: Allocator, varIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    var variable = self.global.nodes.get(varIndex);

    const typeIndex = variable.data[0].load(.acquire);

    if (typeIndex == 0) {
        if (!try Expression.inferType(self, alloc, varIndex, variable.data.@"1".load(.acquire), reports)) return;
    } else {
        Type.transformType(self, typeIndex);
    }
    variable = self.global.nodes.get(varIndex);

    const typeIndex2 = variable.data.@"0".load(.acquire);
    std.debug.assert(typeIndex2 != 0);
    const exprI = variable.data.@"1".load(.acquire);

    try Expression.checkType(self, alloc, exprI, typeIndex2, reports);
}

const Expression = @import("Expression.zig");
const Type = @import("Type.zig");
const Scope = @import("Scope/mod.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
