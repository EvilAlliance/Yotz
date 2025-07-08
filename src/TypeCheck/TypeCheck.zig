const std = @import("std");
const Util = @import("./../Util.zig");
const Logger = @import("./../Logger.zig");
const Lexer = @import("./../Lexer/Lexer.zig");
const Message = @import("./../Message/Message.zig");

const Parser = @import("./../Parser/Parser.zig");
const nl = @import("./../Parser/NodeListUtil.zig");

const Scopes = @import("./Scopes.zig");
const Context = @import("./Context.zig");

const FlattenExpression = std.ArrayList(Parser.NodeIndex);

const CheckPoint = struct {
    const Type = enum {
        unknownIdentifier,
    };

    scopes: Scopes,

    t: Type,

    dep: Parser.NodeIndex,
    state: ?*FlattenExpression,

    expectedTypeI: Parser.NodeIndex,
};

const TypeChecker = struct {
    const Self = @This();

    message: Message,

    errs: usize = 0,

    alloc: std.mem.Allocator,

    ast: *Parser.Ast,

    foundMain: ?Parser.Node = null,

    ctx: Context,

    checkPoints: std.ArrayList(CheckPoint),

    pub fn init(alloc: std.mem.Allocator, ast: *Parser.Ast) std.mem.Allocator.Error!bool {
        var checker = @This(){
            .alloc = alloc,
            .ast = ast,
            .checkPoints = std.ArrayList(CheckPoint).init(alloc),
            .ctx = Context.init(alloc),
            .message = Message.init(ast),
        };

        defer checker.deinit();

        try checker.checkGlobalScope();
        var changed = true;

        while (changed) {
            changed = false;
            var i: usize = 0;
            while (i < checker.checkPoints.items.len) {
                var checkPoint = checker.checkPoints.items[i];
                switch (checkPoint.t) {
                    .unknownIdentifier => {
                        const node = ast.getNode(checkPoint.dep);
                        _ = checker.ctx.searchVariableScope(node.getTextAst(ast)) orelse {
                            i += 1;
                            continue;
                        };
                        changed = true;

                        const temp = checker.ctx.swap(checkPoint.scopes);

                        _ = checker.checkPoints.swapRemove(i);

                        try checker.checkFlattenExpression(checkPoint.state.?, checkPoint.expectedTypeI);

                        checker.ctx.restore(temp);

                        checkPoint.scopes.deinit();
                    },
                    // .inferVariableType => {
                    //     const node = ast.getNode(checkPoint.dep);
                    //
                    //     if (node.data[0] == 0) {
                    //         i += 1;
                    //         continue;
                    //     }
                    //
                    //     const temp = checker.scopes;
                    //     checker.scopes = checkPoint.scopes;
                    //
                    //     _ = checker.checkPoints.swapRemove(i);
                    //
                    //     var t = node.data[0];
                    //     while (t != 0) : (t = ast.getNode(t).next) {
                    //         try checker.checkExpressionExpectedType(node.data[1], t);
                    //     }
                    //
                    //     checker.scopes = temp;
                    //     checkPoint.scopes.deinit();
                    // },
                }
            }
        }

        for (checker.checkPoints.items) |checkPoint| {
            _ = checkPoint;
            unreachable;
        }

        if (checker.ctx.searchVariableScope("main")) |mainVariableI| {
            const mainVariable = ast.getNode(mainVariableI);
            const expr = ast.getNode(mainVariable.data[1]);
            if (expr.tag == .funcProto) {
                const mainProto = expr;
                const t = ast.nodeList.items[mainProto.data[1]];
                std.debug.assert(t.tag == .type);

                if (t.data[0] != 8 or t.data[1] != @intFromEnum(Parser.Node.Primitive.uint)) {
                    checker.message.err.funcReturnsU8("Main", mainProto.data[1]);
                    checker.errs += 1;
                }
            } else {
                checker.message.err.variableMustBeFunction("main", mainVariableI);
                checker.errs += 1;
            }
        } else {
            checker.message.err.mainFunctionMissing();
            checker.errs += 1;
        }

        if (checker.ctx.searchVariableScope("_start")) |_startVariableI| {
            const _start = ast.getNode(_startVariableI);
            const loc = _start.getLocationAst(ast.*);
            checker.message.err.identifierNotAvailable("_start", loc);
            checker.errs += 1;
        }

        return checker.errs > 0;
    }

    fn checkGlobalScope(self: *Self) std.mem.Allocator.Error!void {
        var variableI = self.ast.getNode(0).data[0];
        while (variableI != self.ast.getNode(0).data[1]) : (variableI = self.ast.getNode(variableI).next) {
            const variable = self.ast.getNode(variableI);
            const tI = variable.data[0];
            const exprI = variable.data[1];
            const expr = self.ast.getNode(exprI);

            if (self.ctx.searchVariableScope(variable.getTextAst(self.ast))) |variableJ| {
                self.message.err.identifierIsUsed(variableI, variableJ);
                self.message.info.isDeclaredHere(variableJ);

                self.errs += 1;
                return;
            }

            try self.ctx.addVariableScope(variable.getTextAst(self.ast), variableI, .global);

            switch (expr.tag) {
                .funcProto => {
                    const typeI = result: {
                        if (variable.data[0] != 0) {
                            self.transformType(variable.data[0]);
                            break :result variable.data[0];
                        }
                        const t = try self.inferFunctionType(variable.data[1]);
                        self.ast.getNodePtr(variableI).data[0] = t;
                        break :result t;
                    };
                    try self.checkFunction(exprI, typeI);
                },
                .addition,
                .subtraction,
                .multiplication,
                .division,
                .power,
                .neg,
                .load,
                .lit,
                => {
                    if (tI != 0) {
                        try self.checkExpressionExpectedType(exprI, tI);
                    }
                    // WARNING: This can cause that this is not infered and cause problems
                },
                else => {
                    self.message.err.nodeNotSupported(variableI);
                    unreachable;
                },
            }
        }
    }

    pub fn deinit(self: *Self) void {
        self.ctx.deinit();
    }

    fn _transformType(t: Lexer.Token) struct { Parser.NodeIndex, Parser.NodeIndex } {
        return .{
            switch (t.tag) {
                .unsigned8, .signed8 => 8,
                .unsigned16, .signed16 => 16,
                .unsigned32, .signed32 => 32,
                .unsigned64, .signed64 => 64,
                else => unreachable,
            },
            @intFromEnum(switch (t.tag) {
                .signed8, .signed16, .signed32, .signed64 => Parser.Node.Primitive.int,
                .unsigned8, .unsigned16, .unsigned32, .unsigned64 => Parser.Node.Primitive.uint,
                else => unreachable,
            }),
        };
    }

    fn transformType(self: *Self, tI: Parser.NodeIndex) void {
        const t = self.ast.getNodePtr(tI);
        if (t.tag == .funcType) {
            self.transformType(t.data[1]);
        } else {
            const token = self.ast.getToken(t.tokenIndex);
            t.tag = .type;
            t.data = _transformType(token);
            t.next = 0;
        }
    }

    fn inferFunctionType(self: *Self, protoI: Parser.NodeIndex) std.mem.Allocator.Error!Parser.NodeIndex {
        const proto = self.ast.getNode(protoI);
        std.debug.assert(proto.tag == .funcProto);

        const tIndex = proto.data[1];
        self.transformType(tIndex);

        return try nl.addNode(self.ast.nodeList, .{
            .tag = .funcType,
            .data = .{ 0, tIndex },
        });
    }

    fn checkFunction(self: *Self, nodeI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const node = self.ast.getNode(nodeI);
        std.debug.assert(node.tag == .funcProto);

        const tIndex = node.data[1];
        self.transformType(tIndex);

        if (!self.typeEqual(tIndex, self.ast.getNode(expectedTypeI).data[1])) {
            unreachable;
        }

        const stmtORscopeIndex = node.next;
        const stmtORscope = self.ast.getNode(stmtORscopeIndex);

        if (stmtORscope.tag == .scope) {
            try self.checkScope(stmtORscopeIndex, tIndex);
        } else {
            try self.ctx.addScope();
            try self.checkStatements(stmtORscopeIndex, tIndex);

            self.ctx.popScope();
        }
    }

    fn checkScope(self: *Self, scopeI: Parser.NodeIndex, retTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const scope = self.ast.getNode(scopeI);
        const retType = self.ast.getNode(retTypeI);

        std.debug.assert(scope.tag == .scope and retType.tag == .type);

        try self.ctx.addScope();

        var i = scope.data[0];
        const end = scope.data[1];

        while (i < end) {
            const stmt = self.ast.getNode(i);

            try self.checkStatements(i, retTypeI);

            i = stmt.next;
        }

        self.ctx.popScope();
    }

    fn checkStatements(self: *Self, stmtI: Parser.NodeIndex, retTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const stmt = self.ast.getNode(stmtI);

        switch (stmt.tag) {
            .ret => {
                try self.checkExpressionExpectedType(stmt.data[0], retTypeI);
            },
            .variable, .constant => {
                if (self.ctx.searchVariableScope(stmt.getTextAst(self.ast))) |variableI| {
                    self.message.err.identifierIsUsed(stmtI, variableI);
                    self.message.info.isDeclaredHere(variableI);

                    self.errs += 1;

                    return;
                }

                try self.ctx.addVariableScope(stmt.getTextAst(self.ast), stmtI, .local);

                const exprI = stmt.data[1];

                if (stmt.data[0] != 0) {
                    const tI = stmt.data[0];
                    self.transformType(tI);

                    try self.checkExpressionExpectedType(exprI, tI);
                } else {
                    const posibleType, const loc = try self.getTypeFromExpression(exprI);
                    if (posibleType == 0) return;

                    var nodeType = self.ast.getNode(posibleType);
                    nodeType.tokenIndex = loc;
                    nodeType.flags |= @intFromEnum(Parser.Node.Flag.inferedFromExpression);
                    const x = try nl.addNode(self.ast.nodeList, nodeType);

                    self.ast.getNodePtr(stmtI).data[0] = x;

                    try self.checkExpressionExpectedType(exprI, x);
                }
            },
            else => unreachable,
        }
    }

    fn flattenExpression(self: *Self, stack: *FlattenExpression, exprI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const expr = self.ast.getNode(exprI);
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));

        switch (expr.tag) {
            .lit => {
                try stack.append(exprI);
            },
            .load => {
                try stack.append(exprI);
            },
            .neg => {
                const left = expr.data[0];

                try self.flattenExpression(stack, left);

                try stack.append(exprI);
            },
            .addition, .subtraction, .multiplication, .division, .power => {
                const left = expr.data[0];
                const right = expr.data[1];

                try self.flattenExpression(stack, left);
                try stack.append(exprI);
                try self.flattenExpression(stack, right);
            },
            else => {
                self.message.err.nodeNotSupported(exprI);
                unreachable;
            },
        }
    }

    fn checkExpressionLeaf(self: *Self, leafI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) std.mem.Allocator.Error!?CheckPoint.Type {
        const leaf = self.ast.getNode(leafI);
        const expectedType = self.ast.getNode(expectedTypeI);
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load }, leaf.tag) and expectedType.tag == .type);

        switch (leaf.tag) {
            .lit => self.checkValueForType(leafI, expectedTypeI),
            .load => {
                const variableI = self.ctx.searchVariableScope(leaf.getTextAst(self.ast)) orelse return .unknownIdentifier;

                const variable = self.ast.getNode(variableI);
                const t = self.ast.nodeList.items[variable.data[0]];

                if (variable.data[0] != 0 and (t.flags == 0 or (t.flags & @intFromEnum(Parser.Node.Flag.inferedFromExpression)) != 0)) {
                    if (!self.canTypeBeCoerced(variable.data[0], expectedTypeI)) {
                        const locExpr = leaf.getLocationAst(self.ast.*);
                        self.message.err.incompatibleType(expectedTypeI, variable.data[0], locExpr);
                        self.message.info.isDeclaredHere(variableI);
                        if ((t.flags & @intFromEnum(Parser.Node.Flag.inferedFromUse)) | (t.flags & @intFromEnum(Parser.Node.Flag.inferedFromExpression)) != 0) {
                            self.message.info.inferedType(variable.data[0]);
                        } else {
                            self.message.info.isDeclaredHere(variableI);
                        }
                        self.errs += 1;
                    } else {
                        if (!self.typeEqual(variable.data[0], expectedTypeI)) self.ast.getNodePtr(leafI).flags |= @intFromEnum(Parser.Node.Flag.implicitCast);
                    }
                } else {
                    var tIndex = variable.data[0];
                    while (variable.tag == .constant and tIndex != 0 and self.canTypeBeCoerced(tIndex, expectedTypeI) and !self.typeEqual(tIndex, expectedTypeI)) : (tIndex = self.ast.getNode(tIndex).next) {}
                    if (tIndex == 0) {
                        try self.checkExpressionExpectedType(variable.data[1], expectedTypeI);
                        const err = self.errs;
                        if (self.errs == err) {
                            var nodeType = self.ast.getNode(expectedTypeI);
                            nodeType.flags = 0;
                            nodeType.tokenIndex = leaf.tokenIndex;
                            nodeType.flags |= @intFromEnum(Parser.Node.Flag.inferedFromUse);
                            const x = try nl.addNode(self.ast.nodeList, nodeType);
                            self.ast.getNodePtr(x).next = variable.data[0];
                            self.ast.getNodePtr(variableI).data[0] = x;
                        }
                    } else {
                        if (variable.tag == .variable) {
                            const locExpr = leaf.getLocationAst(self.ast.*);
                            self.message.err.incompatibleType(expectedTypeI, tIndex, locExpr);
                            self.message.info.isDeclaredHere(variableI);

                            if ((t.flags & @intFromEnum(Parser.Node.Flag.inferedFromUse)) | (t.flags & @intFromEnum(Parser.Node.Flag.inferedFromExpression)) != 0) {
                                self.message.info.inferedType(variable.data[0]);
                            } else {
                                self.message.info.isDeclaredHere(variableI);
                            }
                        }

                        const err = self.errs;
                        try self.checkExpressionExpectedType(variable.data[1], expectedTypeI);
                        if (self.errs == err) {
                            const typeNode = self.ast.getNodePtr(variable.data[0]);
                            typeNode.tokenIndex = leaf.tokenIndex;
                            typeNode.data = expectedType.data;
                        }
                    }
                }
            },
            else => unreachable,
        }

        return null;
    }
    fn getTypeFromExpression(self: *Self, exprI: Parser.NodeIndex) std.mem.Allocator.Error!struct { Parser.NodeIndex, Parser.TokenIndex } {
        const expr = self.ast.getNode(exprI);
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));

        const flat = try self.alloc.create(FlattenExpression);
        flat.* = FlattenExpression.init(self.alloc);

        try self.flattenExpression(flat, exprI);

        defer {
            flat.deinit();
            self.alloc.destroy(flat);
        }

        while (flat.items.len > 0) {
            const firstI = flat.pop().?;
            const first = self.ast.getNode(firstI);

            if (first.tag != .load) continue;

            const variableOP = self.ctx.searchVariableScope(self.ast.getNodeText(firstI));
            if (variableOP == null) continue;
            const variable = self.ast.getNode(variableOP.?);

            return .{ variable.data[0], first.tokenIndex };
        }

        return .{ 0, 0 };
    }

    fn typeEqual(self: *Self, actualI: Parser.NodeIndex, expectedI: Parser.NodeIndex) bool {
        const actual = self.ast.getNode(actualI);
        const expected = self.ast.getNode(expectedI);
        return expected.data[1] == actual.data[1] and expected.data[0] == actual.data[0];
    }

    fn canTypeBeCoerced(self: *Self, actualI: Parser.NodeIndex, expectedI: Parser.NodeIndex) bool {
        const actual = self.ast.getNode(actualI);
        const expected = self.ast.getNode(expectedI);
        return expected.data[1] == actual.data[1] and expected.data[0] >= actual.data[0];
    }

    fn checkExpressionExpectedType(self: *Self, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const expr = self.ast.getNode(exprI);
        const expectedType = self.ast.getNode(expectedTypeI);

        std.debug.assert(expectedType.tag == .type);
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));

        // deinit int checkFlattenExpression
        const flat = try self.alloc.create(FlattenExpression);
        flat.* = FlattenExpression.init(self.alloc);

        try self.flattenExpression(flat, exprI);

        try self.checkFlattenExpression(flat, expectedTypeI);
    }

    pub fn checkFlattenExpression(self: *Self, flat: *FlattenExpression, expectedTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const expectedType = self.ast.getNode(expectedTypeI);
        defer if (flat.items.len == 0) {
            flat.deinit();
            self.alloc.destroy(flat);
        };

        std.debug.assert(expectedType.tag == .type);

        while (flat.items.len > 0) {
            const firstI = flat.getLast();
            const first = self.ast.getNode(firstI);

            if (first.tag != .neg) {
                if (try self.checkExpressionLeaf(firstI, expectedTypeI)) |t| {
                    switch (t) {
                        .unknownIdentifier => return try self.checkPoints.append(.{
                            .t = .unknownIdentifier,
                            .state = flat,
                            .dep = firstI,
                            .scopes = try self.ctx.scopes.deepClone(),
                            .expectedTypeI = expectedTypeI,
                        }),
                        // else => unreachable,
                    }
                } else {
                    _ = flat.pop().?;
                }
            }

            while (flat.items.len > 0) {
                const opI = flat.pop().?;
                const op = self.ast.getNode(opI);

                std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .neg, .power, .division, .multiplication, .subtraction, .addition }, op.tag));

                switch (op.tag) {
                    .neg => break,
                    .power,
                    .division,
                    .multiplication,
                    .subtraction,
                    .addition,
                    => {
                        const xI = flat.getLast();
                        const x = self.ast.getNode(xI);

                        if (x.tag == .neg) break;

                        if (try self.checkExpressionLeaf(xI, expectedTypeI)) |t| {
                            switch (t) {
                                .unknownIdentifier => return try self.checkPoints.append(.{
                                    .t = .unknownIdentifier,
                                    .state = flat,
                                    .dep = xI,
                                    .scopes = try self.ctx.scopes.deepClone(),
                                    .expectedTypeI = expectedTypeI,
                                }),

                                // else => unreachable,
                            }
                        } else {
                            _ = flat.pop().?;
                        }
                    },
                    else => unreachable,
                }
            }
        }
    }

    fn checkLiteralExpressionExpectedType(self: *Self, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) void {
        const expr = self.ast.getNode(exprI);
        const expectedType = self.ast.getNode(expectedTypeI);

        std.debug.assert(expectedType.tag == .type);
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));

        switch (expr.tag) {
            .lit => {
                self.checkValueForType(exprI, expectedTypeI);
            },
            .load => {},
            .neg => {
                const left = expr.data[0];

                self.checkLiteralExpressionExpectedType(left, expectedTypeI);
            },
            .addition, .subtraction, .multiplication, .division, .power => {
                const left = expr.data[0];
                const right = expr.data[1];

                self.checkLiteralExpressionExpectedType(left, expectedTypeI);
                self.checkLiteralExpressionExpectedType(right, expectedTypeI);
            },
            else => {
                self.message.err.nodeNotSupported(exprI);
                unreachable;
            },
        }
    }

    fn checkValueForType(self: *Self, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) void {
        const expr = self.ast.getNode(exprI);
        const expectedType = self.ast.getNode(expectedTypeI);
        std.debug.assert(expectedType.tag == .type);

        const text = expr.getTextAst(self.ast);
        switch (@as(Parser.Node.Primitive, @enumFromInt(expectedType.data[1]))) {
            Parser.Node.Primitive.uint => {
                const max = std.math.pow(u64, 2, expectedType.data[0]) - 1;
                const number = std.fmt.parseInt(u64, text, 10) catch {
                    self.message.err.numberDoesNotFit(exprI, expectedTypeI);
                    if ((expectedType.flags & @intFromEnum(Parser.Node.Flag.inferedFromExpression)) |
                        (expectedType.flags & @intFromEnum(Parser.Node.Flag.inferedFromUse)) != 0)
                    {
                        self.message.info.inferedType(exprI);
                    }
                    return;
                };

                if (number < max) return;
                self.message.err.numberDoesNotFit(exprI, expectedTypeI);
                if ((expectedType.flags & @intFromEnum(Parser.Node.Flag.inferedFromExpression)) |
                    (expectedType.flags & @intFromEnum(Parser.Node.Flag.inferedFromUse)) != 0)
                {
                    self.message.info.inferedType(exprI);
                }
            },
            Parser.Node.Primitive.int => {
                const max = std.math.pow(i64, 2, (expectedType.data[0] - 1)) - 1;
                const min = std.math.pow(i64, 2, (expectedType.data[0] - 1)) - 1;
                const number = std.fmt.parseInt(i64, text, 10) catch {
                    self.message.err.numberDoesNotFit(exprI, expectedTypeI);
                    if ((expectedType.flags & @intFromEnum(Parser.Node.Flag.inferedFromExpression)) |
                        (expectedType.flags & @intFromEnum(Parser.Node.Flag.inferedFromUse)) != 0)
                    {
                        self.message.info.inferedType(exprI);
                    }
                    return;
                };

                if (min < number and number < max) return;
                self.message.err.numberDoesNotFit(exprI, expectedTypeI);
                if ((expectedType.flags & @intFromEnum(Parser.Node.Flag.inferedFromExpression)) |
                    (expectedType.flags & @intFromEnum(Parser.Node.Flag.inferedFromUse)) != 0)
                {
                    self.message.info.inferedType(exprI);
                }
            },
            Parser.Node.Primitive.float => unreachable,
        }
    }
};

pub fn typeCheck(alloc: std.mem.Allocator, p: *Parser.Ast) std.mem.Allocator.Error!bool {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arenaAlloc = arena.allocator();
    return try TypeChecker.init(arenaAlloc, p);
}
