const Self = @This();

ast: *Parser.Ast,
message: Message,
tu: *TranslationUnit,

pub fn init(ast: *Parser.Ast, tu: *TranslationUnit) Self {
    return Self{
        .ast = ast,
        .message = Message.init(ast),
        .tu = tu,
    };
}

pub fn checkRoot(self: *Self, alloc: Allocator, rootIndex: Parser.NodeIndex) Allocator.Error!void {
    const root = self.ast.getNode(rootIndex);

    var nodeIndex = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (nodeIndex != endIndex) {
        const node = self.ast.getNode(nodeIndex);
        defer nodeIndex = node.next.load(.acquire);

        switch (node.tag.load(.acquire)) {
            .variable, .constant => try self.checkVariable(alloc, nodeIndex),
            else => unreachable,
        }
    }
}

pub fn dupe(self: *const Self, alloc: Allocator) Allocator.Error!*Self {
    const selfDupe = try Util.dupe(alloc, self.*);

    const ast = try alloc.create(Parser.Ast);
    ast.* = Parser.Ast.init(self.ast.nodeList, self.tu);
    selfDupe.ast = ast;
    selfDupe.message = Message.init(ast);

    return selfDupe;
}

pub fn destroyDupe(self: *const Self, alloc: Allocator) void {
    alloc.destroy(self.ast.nodeList);
    alloc.destroy(self.ast);
    alloc.destroy(self);
}

// TODO: I have to add this variable to the context
pub fn checkFunctionOuter(self: *Self, alloc: Allocator, variableIndex: Parser.NodeIndex) Allocator.Error!void {
    TranslationUnit.observer.mutex.lock();

    const variable = self.ast.getNode(variableIndex);
    const funcIndex = variable.data.@"1".load(.acquire);
    if (funcIndex == 0) {
        defer TranslationUnit.observer.mutex.unlock();
        const callBack = struct {
            fn callBack(args: ObserverParams) void {
                defer args[0].destroyDupe(args[1]);
                @call(.auto, checkFunctionOuter, args) catch {
                    TranslationUnit.failed = true;
                    std.log.err("Run Out of Memory", .{});
                };
            }
        }.callBack;

        try TranslationUnit.observer.pushUnlock(alloc, variableIndex, callBack, .{ try self.dupe(alloc), alloc, variableIndex });
        return;
    }

    TranslationUnit.observer.mutex.unlock();

    // Return Type
    Type.transformType(self, self.ast.getNode(funcIndex).data[1].load(.acquire));

    while (true) {
        const typeIndex = variable.data[0].load(.acquire);
        if (typeIndex != 0) {
            Type.transformType(self, typeIndex);
            self.checkTypeFunction(alloc, typeIndex, funcIndex);
            break;
        } else {
            const result = try self.inferTypeFunction(alloc, variableIndex, funcIndex);

            if (result)
                break;
        }
    }
}

pub fn checkTypeFunction(self: *const Self, alloc: Allocator, funcTypeIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex) void {
    _ = alloc;
    const funcProto = self.ast.getNode(funcIndex);
    std.debug.assert(funcProto.tag.load(.acquire) == .funcProto);
    std.debug.assert(funcProto.data[0].load(.acquire) == 0);

    const funcRetTypeIndex = funcProto.data[1].load(.acquire);

    const funcType = self.ast.getNode(funcTypeIndex);
    std.debug.assert(funcType.tag.load(.acquire) == .funcType);
    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);

    if (!Type.typeEqual(self, funcRetTypeIndex, retTypeIndex)) {
        self.message.err.incompatibleType(retTypeIndex, funcRetTypeIndex, self.ast.getNodeLocation(funcRetTypeIndex));
    }
}

pub fn inferTypeFunction(self: *Self, alloc: Allocator, variableIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex) Allocator.Error!bool {
    const proto = self.ast.getNode(funcIndex);
    std.debug.assert(proto.tag.load(.acquire) == .funcProto);

    const tIndex = proto.data[1].load(.acquire);
    std.debug.assert(tIndex != 0);
    std.debug.assert(self.ast.getNode(tIndex).tag.load(.acquire) == .type);

    const functionTypeIndex = try self.ast.nodeList.appendIndex(alloc, Parser.Node{
        .tag = .init(.funcType),
        .tokenIndex = .init(proto.tokenIndex.load(.acquire)),
        .data = .{ .init(0), .init(tIndex) },
        .flags = .init(.{ .inferedFromExpression = true }),
    });

    const nodePtr = self.ast.getNodePtr(variableIndex);
    const result = nodePtr.data.@"0".cmpxchgStrong(0, functionTypeIndex, .acq_rel, .monotonic);

    return result == null;
}

pub fn checkFunction(self: *Self, alloc: Allocator, funcIndex: Parser.NodeIndex) Allocator.Error!void {
    const func = self.ast.getNode(funcIndex);
    std.debug.assert(func.tag.load(.acquire) == .funcProto);

    const tIndex = func.data[1].load(.acquire);
    Type.transformType(self, tIndex);

    const stmtORscopeIndex = func.next.load(.acquire);
    const stmtORscope = self.ast.getNode(stmtORscopeIndex);

    try self.tu.scope.push(alloc);
    defer self.tu.scope.pop(alloc);
    if (stmtORscope.tag.load(.acquire) == .scope) {
        try self.checkScope(alloc, stmtORscopeIndex, tIndex);
    } else {
        try self.checkStatements(alloc, stmtORscopeIndex, tIndex);
    }
}

// TODO: Add scope to this
fn checkScope(self: *Self, alloc: Allocator, scopeIndex: Parser.NodeIndex, typeI: Parser.NodeIndex) Allocator.Error!void {
    const scope = self.ast.getNode(scopeIndex);
    const retType = self.ast.getNode(typeI);

    std.debug.assert(scope.tag.load(.acquire) == .scope and retType.tag.load(.acquire) == .type);

    var i = scope.data[0].load(.acquire);

    while (i != 0) {
        const stmt = self.ast.getNode(i);

        try self.checkStatements(alloc, i, typeI);

        i = stmt.next.load(.acquire);
    }
}

fn checkStatements(self: *Self, alloc: Allocator, stmtI: Parser.NodeIndex, retTypeI: Parser.NodeIndex) Allocator.Error!void {
    _ = .{ alloc, retTypeI };
    const stmt = self.ast.getNode(stmtI);

    switch (stmt.tag.load(.acquire)) {
        .ret => try self.checkReturn(alloc, stmtI, retTypeI),
        .variable, .constant => try self.checkVariable(alloc, stmtI),
        else => unreachable,
    }
}

fn checkReturn(self: *const Self, alloc: Allocator, nodeI: Parser.NodeIndex, typeI: Parser.NodeIndex) Allocator.Error!void {
    const stmt = self.ast.getNode(nodeI);
    try Expression.checkType(self, alloc, stmt.data[1].load(.acquire), typeI);
}

fn checkVariable(self: *Self, alloc: Allocator, nodeIndex: Parser.NodeIndex) Allocator.Error!void {
    const node = self.ast.getNode(nodeIndex);
    // NOTE: At the time being this is not changed so it should be fine;
    const expressionIndex = node.data.@"1".load(.acquire);
    const expressionNode = self.ast.getNode(expressionIndex);
    const expressionTag = expressionNode.tag.load(.acquire);

    if (expressionIndex == 0 or expressionTag == .funcProto) {
        try self.checkFunctionOuter(alloc, nodeIndex);
    } else {
        try self.checkPureVariable(alloc, nodeIndex);
    }
}

// TODO:: If type is established chcek if the expression is valid
fn checkPureVariable(self: *Self, alloc: Allocator, varIndex: Parser.NodeIndex) Allocator.Error!void {
    var variable = self.ast.getNode(varIndex);

    const typeIndex = variable.data[0].load(.acquire);

    // NOTE: This case if for variables that do not have type and cannot be inferred from the expression itself
    if (typeIndex == 0) {
        if (!try Expression.inferType(self, alloc, varIndex, variable.data.@"1".load(.acquire))) {
            try self.tu.scope.put(alloc, variable.getTextAst(self.ast), varIndex);
            return;
        }
    } else {
        Type.transformType(self, typeIndex);
    }
    variable = self.ast.getNode(varIndex);

    const typeIndex2 = variable.data.@"0".load(.acquire);
    std.debug.assert(typeIndex2 != 0);
    const exprI = variable.data.@"1".load(.acquire);

    try Expression.checkType(self, alloc, exprI, typeIndex2);

    try self.tu.scope.put(alloc, variable.getTextAst(self.ast), varIndex);
}

pub const ObserverParams = std.meta.Tuple(&.{ *Self, Allocator, Parser.NodeIndex });

comptime {
    const Expected = Util.getTupleFromParams(checkFunctionOuter);
    if (ObserverParams != Expected) {
        @compileError("ObserverParams type mismatch with checkFunctionOuter signature");
    }
}

const Type = @import("Type.zig");
const Expression = @import("Expression.zig");

const Parser = @import("./../Parser/mod.zig");
const Message = @import("../Message/Message.zig");
const TranslationUnit = @import("../TranslationUnit.zig");

const Util = @import("../Util.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
