pub fn checkRoot(self: TranslationUnit, alloc: Allocator, rootIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const root = self.global.nodes.get(rootIndex);

    var nodeIndex = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (nodeIndex != endIndex) {
        const node = self.global.nodes.get(nodeIndex);
        defer nodeIndex = node.next.load(.acquire);

        switch (node.tag.load(.acquire)) {
            .variable, .constant => checkVariable(self, alloc, nodeIndex, reports) catch |err| switch (err) {
                Expression.Error.TooBig, Expression.Error.IncompatibleType => continue,
                else => return @errorCast(err),
            },
            else => unreachable,
        }
    }
}

pub fn checkFunctionOuter(self: TranslationUnit, alloc: Allocator, variableIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
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

    try self.scope.put(alloc, variable.getText(self.global), variableIndex);
}

pub fn checkTypeFunction(self: TranslationUnit, alloc: Allocator, funcTypeIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const funcProto = self.global.nodes.get(funcIndex);
    std.debug.assert(funcProto.tag.load(.acquire) == .funcProto);
    std.debug.assert(funcProto.data[0].load(.acquire) == 0);

    const funcRetTypeIndex = funcProto.data[1].load(.acquire);

    const funcType = self.global.nodes.get(funcTypeIndex);
    std.debug.assert(funcType.tag.load(.acquire) == .funcType);
    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);

    if (!Type.typeEqual(self, funcRetTypeIndex, retTypeIndex)) {
        try Report.incompatibleType(alloc, reports, retTypeIndex, funcRetTypeIndex, funcRetTypeIndex, 0);
    }
}

pub fn inferTypeFunction(self: TranslationUnit, alloc: Allocator, variableIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex) Allocator.Error!bool {
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

pub fn checkFunction(self: TranslationUnit, alloc: Allocator, funcIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const func = self.global.nodes.get(funcIndex);
    std.debug.assert(func.tag.load(.acquire) == .funcProto);

    const tIndex = func.data[1].load(.acquire);
    Type.transformType(self, tIndex);

    const stmtORscopeIndex = func.next.load(.acquire);
    const stmtORscope = self.global.nodes.get(stmtORscopeIndex);

    try self.scope.push(alloc);
    defer self.scope.pop(alloc);
    if (stmtORscope.tag.load(.acquire) == .scope) {
        try checkScope(self, alloc, stmtORscopeIndex, tIndex, reports);
    } else {
        checkStatements(self, alloc, stmtORscopeIndex, tIndex, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType => return,
            else => return @errorCast(err),
        };
    }
}

// TODO: Add scope to this
fn checkScope(self: TranslationUnit, alloc: Allocator, scopeIndex: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const scope = self.global.nodes.get(scopeIndex);
    const retType = self.global.nodes.get(typeI);

    std.debug.assert(scope.tag.load(.acquire) == .scope and retType.tag.load(.acquire) == .type);

    var i = scope.data[0].load(.acquire);

    while (i != 0) {
        const stmt = self.global.nodes.get(i);
        defer i = stmt.next.load(.acquire);

        checkStatements(self, alloc, i, typeI, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType => continue,
            else => return @errorCast(err),
        };
    }
}

fn checkStatements(self: TranslationUnit, alloc: Allocator, stmtI: Parser.NodeIndex, retTypeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    _ = .{ alloc, retTypeI };
    const stmt = self.global.nodes.get(stmtI);

    switch (stmt.tag.load(.acquire)) {
        .ret => try checkReturn(self, alloc, stmtI, retTypeI, reports),
        .variable, .constant => try checkVariable(self, alloc, stmtI, reports),
        else => unreachable,
    }
}

fn checkReturn(self: TranslationUnit, alloc: Allocator, nodeI: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const stmt = self.global.nodes.get(nodeI);
    try Expression.checkType(self, alloc, stmt.data[1].load(.acquire), typeI, reports);
}

fn checkVariable(self: TranslationUnit, alloc: Allocator, nodeIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
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

fn checkPureVariable(self: TranslationUnit, alloc: Allocator, varIndex: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    var variable = self.global.nodes.get(varIndex);

    const typeIndex = variable.data[0].load(.acquire);

    if (typeIndex == 0) {
        if (!try Expression.inferType(self, alloc, varIndex, variable.data.@"1".load(.acquire), reports)) {
            try self.scope.put(alloc, variable.getText(self.global), varIndex);
            return;
        }
    } else {
        Type.transformType(self, typeIndex);
    }
    variable = self.global.nodes.get(varIndex);

    const typeIndex2 = variable.data.@"0".load(.acquire);
    std.debug.assert(typeIndex2 != 0);
    const exprI = variable.data.@"1".load(.acquire);

    try Expression.checkType(self, alloc, exprI, typeIndex2, reports);

    try self.scope.put(alloc, variable.getText(self.global), varIndex);
}

pub const ObserverParams = std.meta.Tuple(&.{ TranslationUnit, Allocator, Parser.NodeIndex, ?*Report.Reports });

comptime {
    const Expected = Util.getTupleFromParams(checkFunctionOuter);
    if (ObserverParams != Expected) {
        @compileError("ObserverParams type mismatch with checkFunctionOuter signature");
    }
}

const Type = @import("Type.zig");
const Expression = @import("Expression.zig");

const Parser = @import("./../Parser/mod.zig");
const Report = @import("../Report/mod.zig");
const TranslationUnit = @import("../TranslationUnit.zig");

const Util = @import("../Util.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
