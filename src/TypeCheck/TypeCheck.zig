const Self = @This();

ast: *Parser.Ast,
message: Message,
tu: *const TranslationUnit,

pub fn init(ast: *Parser.Ast, tu: *const TranslationUnit) Self {
    return Self{
        .ast = ast,
        .message = Message.init(ast),
        .tu = tu,
    };
}

pub fn checkRoot(self: *Self, alloc: Allocator, rootIndex: Parser.NodeIndex) Allocator.Error!void {
    const root = self.ast.getNode(.Bound, rootIndex);

    var nodeIndex = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (nodeIndex != endIndex) {
        const node = self.ast.getNode(.Bound, nodeIndex);
        defer nodeIndex = node.next.load(.acquire);

        switch (node.tag.load(.acquire)) {
            .variable, .constant => try self.checkVariable(alloc, nodeIndex),
            else => unreachable,
        }
    }
}

fn dupe(self: *const Self, alloc: Allocator) Allocator.Error!*Self {
    const selfDupe = try Util.dupe(alloc, self.*);
    const chunk = try alloc.create(Parser.NodeList.Chunk);
    chunk.* = try Parser.NodeList.Chunk.init(alloc, self.ast.nodeList.base);

    const ast = try alloc.create(Parser.Ast);
    ast.* = Parser.Ast.init(chunk, self.tu);
    selfDupe.ast = ast;

    return selfDupe;
}

fn destroyDupe(self: *const Self, alloc: Allocator) void {
    alloc.destroy(self.ast.nodeList);
    alloc.destroy(self.ast);
    alloc.destroy(self);
}

// TODO: I have to add this variable to the context
pub fn checkFunctionOuter(self: *Self, alloc: Allocator, variableIndex: Parser.NodeIndex) Allocator.Error!void {
    const variable = self.ast.getNode(.Bound, variableIndex);
    const funcIndex = variable.data.@"1".load(.acquire);
    if (funcIndex == 0) {
        const callBack = struct {
            fn callBack(args: getTupleFromParams(checkFunctionOuter)) void {
                defer args[0].destroyDupe(args[1]);
                @call(.auto, checkFunctionOuter, args) catch {
                    TranslationUnit.failed = true;
                    std.log.err("Run Out of Memory", .{});
                };
            }
        }.callBack;

        try TranslationUnit.observer.push(alloc, variableIndex, callBack, .{ try self.dupe(alloc), alloc, variableIndex });

        return;
    }

    while (true) {
        // Return Type
        Type.transformType(self, self.ast.getNode(.UnBound, funcIndex).data[1].load(.acquire));

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
    const funcProto = self.ast.getNode(.UnBound, funcIndex);
    std.debug.assert(funcProto.tag.load(.acquire) == .funcProto);
    std.debug.assert(funcProto.data[0].load(.acquire) == 0);

    const funcRetTypeIndex = funcProto.data[1].load(.acquire);

    const funcType = self.ast.getNode(.Bound, funcTypeIndex);
    std.debug.assert(funcType.tag.load(.acquire) == .funcType);
    std.debug.assert(funcType.data[0].load(.acquire) == 0);

    const retTypeIndex = funcType.data[1].load(.acquire);

    if (!Type.typeEqual(self, funcRetTypeIndex, retTypeIndex)) {
        self.message.err.incompatibleType(retTypeIndex, funcRetTypeIndex, self.ast.getNodeLocation(.UnBound, funcRetTypeIndex));
    }
}

pub fn inferTypeFunction(self: *Self, alloc: Allocator, variableIndex: Parser.NodeIndex, funcIndex: Parser.NodeIndex) Allocator.Error!bool {
    const proto = self.ast.getNode(.UnBound, funcIndex);
    std.debug.assert(proto.tag.load(.acquire) == .funcProto);

    const tIndex = proto.data[1].load(.acquire);
    std.debug.assert(tIndex != 0);
    std.debug.assert(self.ast.getNode(.UnBound, tIndex).tag.load(.acquire) == .type);

    const functionTypeIndex = try self.ast.nodeList.appendIndex(alloc, Parser.Node{
        .tag = .init(.funcType),
        .tokenIndex = .init(proto.tokenIndex.load(.acquire)),
        .data = .{ .init(0), .init(tIndex) },
        .flags = .init(.{ .inferedFromExpression = true }),
    });

    const nodePtr = self.ast.getNodePtr(.Bound, variableIndex);
    const result = nodePtr.data.@"0".cmpxchgWeak(0, functionTypeIndex, .acq_rel, .monotonic);
    self.ast.unlockShared();

    return result == null;
}

pub fn checkFunction(self: *Self, alloc: Allocator, funcIndex: Parser.NodeIndex) Allocator.Error!void {
    const func = self.ast.getNode(.Bound, funcIndex);
    std.debug.assert(func.tag.load(.acquire) == .funcProto);

    const tIndex = func.data[1].load(.acquire);
    Type.transformType(self, tIndex);

    const stmtORscopeIndex = func.next.load(.acquire);
    const stmtORscope = self.ast.getNode(.Bound, stmtORscopeIndex);

    if (stmtORscope.tag.load(.acquire) == .scope) {
        try self.checkScope(alloc, stmtORscopeIndex, tIndex);
    } else {
        try self.checkStatements(alloc, stmtORscopeIndex, tIndex);
    }
}

// TODO: Add scope to this
fn checkScope(self: *Self, alloc: Allocator, scopeIndex: Parser.NodeIndex, typeI: Parser.NodeIndex) Allocator.Error!void {
    const scope = self.ast.getNode(.Bound, scopeIndex);
    const retType = self.ast.getNode(.Bound, typeI);

    std.debug.assert(scope.tag.load(.acquire) == .scope and retType.tag.load(.acquire) == .type);

    var i = scope.data[0].load(.acquire);

    while (i != 0) {
        const stmt = self.ast.getNode(.Bound, i);

        try self.checkStatements(alloc, i, typeI);

        i = stmt.next.load(.acquire);
    }
}

fn checkStatements(self: *Self, alloc: Allocator, stmtI: Parser.NodeIndex, retTypeI: Parser.NodeIndex) Allocator.Error!void {
    _ = .{ alloc, retTypeI };
    const stmt = self.ast.getNode(.Bound, stmtI);

    switch (stmt.tag.load(.acquire)) {
        .ret => try self.checkReturn(alloc, stmtI, retTypeI),
        .variable, .constant => try self.checkVariable(alloc, stmtI),
        else => unreachable,
    }
}

fn checkReturn(self: *const Self, alloc: Allocator, nodeI: Parser.NodeIndex, typeI: Parser.NodeIndex) Allocator.Error!void {
    const stmt = self.ast.getNode(.Bound, nodeI);
    try Expression.checkExpressionType(self, alloc, stmt.data[1].load(.acquire), typeI);
}

fn checkVariable(self: *Self, alloc: Allocator, nodeIndex: Parser.NodeIndex) Allocator.Error!void {
    const node = self.ast.getNode(.Bound, nodeIndex);
    // NOTE: At the time being this is not changed so it should be fine;
    const expressionIndex = node.data.@"1".load(.acquire);
    const expressionNode = self.ast.getNode(.UnCheck, expressionIndex);
    const expressionTag = expressionNode.tag.load(.acquire);

    if (expressionIndex == 0 or expressionTag == .funcProto) {
        try self.checkFunctionOuter(alloc, nodeIndex);
    } else {
        try self.checkPureVariable(alloc, nodeIndex);
    }
}

// TODO : InferType if is not established
// TODO:: If type is established chcek if the expression is valid
// TODO: After all this, add it to the context (Which does not exist yet)
fn checkPureVariable(self: *Self, alloc: Allocator, varIndex: Parser.NodeIndex) Allocator.Error!void {
    _ = .{ self, alloc, varIndex };
    var variable = self.ast.getNode(.Bound, varIndex);

    const typeIndex = variable.data[0].load(.acquire);

    if (typeIndex == 0 and !try self.inferTypeExpression(alloc, varIndex))
        return
    else
        Type.transformType(self, typeIndex);

    variable = self.ast.getNode(.Bound, varIndex);

    const exprI = variable.data.@"1".load(.acquire);
    const typeIndex2 = variable.data.@"0".load(.acquire);

    try Expression.checkExpressionType(self, alloc, exprI, typeIndex2);
}

// TODO: The only way to infer the type in the expression itself is with a funciton call (return type) or the types of predeclared variable types
fn inferTypeExpression(self: *const Self, alloc: Allocator, varIndex: Parser.NodeIndex) Allocator.Error!bool {
    _ = .{ self, alloc, varIndex };
    return false;
}

fn getTupleFromParams(comptime func: anytype) type {
    const typeFunc = @TypeOf(func);
    const typeInfo = @typeInfo(typeFunc);

    const params = typeInfo.@"fn".params;
    // var fieldArr: [params.len]std.builtin.Type.StructField = undefined;
    // for (params, 0..) |param, i| {
    //     const name = std.fmt.comptimePrint("f{}", .{i});
    //
    //     fieldArr[i] = .{
    //         .name = name,
    //         .type = param.type.?,
    //         .default_value_ptr = null,
    //         .is_comptime = false,
    //         .alignment = @alignOf(param.type.?),
    //     };
    // }
    //
    // return @Type(.{
    //     .@"struct" = .{
    //         .fields = &fieldArr,
    //         .layout = .auto,
    //         .decls = &.{},
    //         .is_tuple = false,
    //         .backing_integer = null,
    //     },
    // });

    var typeArr: [params.len]type = undefined;

    for (params, 0..) |param, i|
        typeArr[i] = param.type.?;

    return std.meta.Tuple(&typeArr);
}

pub const ObserverParams = getTupleFromParams(checkFunctionOuter);

const Type = @import("Type.zig");
const Expression = @import("Expression.zig");

const Parser = @import("./../Parser/mod.zig");
const Message = @import("../Message/Message.zig");
const TranslationUnit = @import("../TranslationUnit.zig");

const Util = @import("../Util.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
