const std = @import("std");
const Util = @import("Util.zig");
const Logger = @import("Logger.zig");
const InferMachine = @import("InferMachine.zig");
const Lexer = @import("Lexer/Lexer.zig");

const Parser = @import("./Parser/Parser.zig");
const nl = @import("./Parser/NodeListUtil.zig");

const Scope = std.StringHashMap(Parser.NodeIndex);
const Scopes = std.ArrayList(Scope);

const TypeChecker = struct {
    const ScopeLevel = enum { global, local };
    const Self = @This();

    errs: usize = 0,

    alloc: std.mem.Allocator,

    inferMachine: InferMachine,

    ast: *Parser.Ast,
    scopes: Scopes,
    globalScope: Scope,

    foundMain: ?Parser.Node = null,

    pub fn init(alloc: std.mem.Allocator, ast: *Parser.Ast) std.mem.Allocator.Error!bool {
        var checker = @This(){
            .alloc = alloc,
            .inferMachine = InferMachine.init(alloc, ast),
            .ast = ast,
            .globalScope = Scope.init(alloc),
            .scopes = Scopes.init(alloc),
        };
        defer checker.deinit();

        try checker.checkGlobalScope();

        var itSet = checker.inferMachine.variable.varTOset.iterator();

        while (itSet.next()) |entry| {
            const nodeIndex = entry.key_ptr;
            const set = entry.value_ptr;

            const variable = ast.getNodePtr(nodeIndex.*);
            if (variable.data[0] != 0) continue;

            const typelocOP = checker.inferMachine.variable.setTOType.getPtr(set.*).?;

            if (typelocOP.*) |_| {
                const index, const locIndex = checker.inferMachine.getRoot(typelocOP).?;

                const errorCount = checker.errs;
                // CLEANUP: Check when its found instead of now
                checker.checkLiteralExpressionExpectedType(variable.data[1], index);

                if (errorCount != checker.errs) {
                    const t = ast.getNode(index);
                    Logger.logLocation.info(ast.path, ast.getNodeLocation(locIndex), "It was found unsing type {s} here: {s}", .{ t.getNameAst(ast.*), Logger.placeSlice(ast.getNodeLocation(locIndex), ast.source) });
                    continue;
                }
                variable.data[0] = index;

                continue;
            }

            const loc = variable.getLocationAst(ast.*);
            Logger.logLocation.warn(ast.path, loc, "Variable has ambiguos type {s}", .{Logger.placeSlice(loc, ast.source)});
        }

        var itConstant = checker.inferMachine.constant.varTOset.iterator();

        while (itConstant.next()) |entry| {
            const nodeIndex = entry.key_ptr;
            const set = entry.value_ptr;

            const variable = ast.getNode(nodeIndex.*);
            if (variable.data[0] != 0) continue;

            const setTypeLoc = checker.inferMachine.constant.setTOvar.get(set.*).?;

            var typeLoc = std.AutoArrayHashMap(Lexer.Token.TokenType, InferMachine.TypeLocation).init(alloc);
            // typeLoc.deinit();

            var itTypeLoc = setTypeLoc.iterator();

            while (itTypeLoc.next()) |entry1| {
                const typelocIndex = entry1.key_ptr;
                const typeloc = checker.inferMachine.variable.setTOType.getPtr(typelocIndex.*).?;
                const root = checker.inferMachine.getRoot(typeloc).?;
                const typeNode = ast.getNode(root[0]);
                const t = ast.getToken(typeNode.tokenIndex);

                try typeLoc.put(t.tag, root);
            }

            var uniqueIt = typeLoc.iterator();

            const start = ast.nodeList.items.len;

            while (uniqueIt.next()) |entry1| {
                const index, const locIndex = entry1.value_ptr.*;

                const errorCount = checker.errs;
                // CLEANUP: Check when its found instead of now
                checker.checkLiteralExpressionExpectedType(variable.data[1], index);

                if (errorCount != checker.errs) {
                    const t = ast.getNode(index);
                    Logger.logLocation.info(ast.path, ast.getNodeLocation(locIndex), "It was found unsing type {s} here: {s}", .{ t.getNameAst(ast.*), Logger.placeSlice(ast.getNodeLocation(locIndex), ast.source) });
                    continue;
                }

                _ = try nl.addNode(&ast.nodeList, ast.getNode(index));
            }

            const end = ast.nodeList.items.len;

            if (start == end) {
                const loc = variable.getLocationAst(ast.*);
                Logger.logLocation.warn(ast.path, loc, "Variable has ambiguos type {s}", .{Logger.placeSlice(loc, ast.source)});
            }

            const p = try nl.addNode(&ast.nodeList, .{
                .tag = .typeGroup,
                .data = .{ @intCast(start), @intCast(end) },
            });
            ast.getNodePtr(nodeIndex.*).data[0] = p;
        }

        // TODO: Pass this to the new format

        if (checker.searchVariableScope("main")) |mainVariableI| {
            const mainVariable = ast.getNode(mainVariableI);
            const expr = ast.getNode(mainVariable.data[1]);
            if (expr.tag == .funcProto) {
                const mainProto = expr;
                const t = ast.nodeList.items[mainProto.data[1]];
                std.debug.assert(t.tag == .type);

                if (t.getTokenTagAst(ast.*) != .unsigned8) {
                    const loc = t.getLocationAst(ast.*);
                    Logger.logLocation.err(ast.path, loc, "Main must return u8 instead of {s} {s}", .{ t.getNameAst(ast.*), Logger.placeSlice(loc, ast.source) });
                    checker.errs += 1;
                }
            } else {
                const loc = mainVariable.getLocationAst(ast.*);
                Logger.logLocation.err(ast.path, loc, "Main must be a function: {s}", .{Logger.placeSlice(loc, ast.source)});
            }
        } else {
            Logger.log.err("Main function is missing, Expected: \n{s}", .{
                \\ fn main() u8{
                \\     return 0;
                \\ }
            });
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

            if (self.searchVariableScope(variable.getTextAst(self.ast.*))) |variableJ| {
                const locStmt = variable.getLocationAst(self.ast.*);
                const varia = self.ast.getNode(variableJ);

                Logger.logLocation.err(self.ast.path, locStmt, "Identifier {s} is already in use {s}", .{ varia.getTextAst(self.ast.*), Logger.placeSlice(locStmt, self.ast.source) });
                const locVar = varia.getLocationAst(self.ast.*);
                Logger.logLocation.err(self.ast.path, locVar, "{s} is declared in use {s}", .{ varia.getTextAst(self.ast.*), Logger.placeSlice(locVar, self.ast.source) });
                self.errs += 1;
                return;
            }

            try self.addVariableScope(variable.getTextAst(self.ast.*), variableI, .global);

            switch (expr.tag) {
                .funcProto => try self.checkFunction(exprI),
                .addition,
                .subtraction,
                .multiplication,
                .division,
                .power,
                .neg,
                .load,
                .lit,
                => {
                    _ = try self.inferMachine.add(variableI);
                    if (variable.tag == .constant) _ = try self.inferMachine.toConstant(variableI);
                    if (tI != 0) {
                        try self.inferMachine.found(variableI, tI, variableI);

                        try self.checkExpressionExpectedType(exprI, tI);
                    } else {
                        if (variable.tag == .constant) _ = try self.inferMachine.toConstant(variableI);
                        if (try self.checkExpressionInferType(exprI)) |bS| {
                            _ = self.inferMachine.merge(variableI, bS) catch |err| switch (err) {
                                error.IncompatibleType => unreachable,
                                error.OutOfMemory => return error.OutOfMemory,
                            };
                        }
                    }
                },
                else => {
                    Logger.log.err("Unknown Node {s}", .{@tagName(expr.tag)});
                    unreachable;
                },
            }
        }
    }

    pub fn searchVariableScope(self: *Self, name: []const u8) ?Parser.NodeIndex {
        var i: usize = self.scopes.items.len;
        while (i > 0) {
            i -= 1;

            var dic = self.scopes.items[i];
            if (dic.get(name)) |n| return n;
        }

        if (self.globalScope.get(name)) |n| return n;

        return null;
    }

    pub fn addVariableScope(self: *Self, name: []const u8, nodeI: Parser.NodeIndex, level: ScopeLevel) std.mem.Allocator.Error!void {
        switch (level) {
            .local => {
                const scope = &self.scopes.items[self.scopes.items.len - 1];
                try scope.put(name, nodeI);
            },
            .global => {
                try self.globalScope.put(name, nodeI);
            },
        }
    }

    pub fn deinit(self: *Self) void {
        for (self.scopes.items) |*s|
            s.deinit();

        self.scopes.deinit();
        self.inferMachine.deinit();
    }

    fn checkFunction(self: *Self, nodeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const node = self.ast.getNode(nodeI);
        std.debug.assert(node.tag == .funcProto);

        const name = node.getTextAst(self.ast.*);

        if (std.mem.eql(u8, name, "_start")) {
            const loc = node.getLocationAst(self.ast.*);
            Logger.logLocation.err(self.ast.path, loc, "_start is an identifier not available {s}", .{Logger.placeSlice(loc, self.ast.source)});
            self.errs += 1;
        } else if (self.foundMain == null and std.mem.eql(u8, name, "main")) self.foundMain = node;

        const tIndex = node.data[1];

        const stmtORscopeIndex = node.next;
        const stmtORscope = self.ast.getNode(stmtORscopeIndex);

        if (stmtORscope.tag == .scope) {
            try self.checkScope(stmtORscopeIndex, tIndex);
        } else {
            try self.scopes.append(Scope.init(self.alloc));
            try self.checkStatements(stmtORscopeIndex, tIndex);
            {
                var x = self.scopes.pop().?;
                x.deinit();
            }
        }
    }

    fn checkScope(self: *Self, scopeI: Parser.NodeIndex, retTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const scope = self.ast.getNode(scopeI);
        const retType = self.ast.getNode(retTypeI);

        std.debug.assert(scope.tag == .scope and retType.tag == .type);

        try self.scopes.append(Scope.init(self.alloc));

        var i = scope.data[0];
        const end = scope.data[1];

        while (i < end) {
            const stmt = self.ast.getNode(i);

            try self.checkStatements(i, retTypeI);

            i = stmt.next;
        }

        {
            var x = self.scopes.pop().?;
            x.deinit();
        }
    }

    fn checkStatements(self: *Self, stmtI: Parser.NodeIndex, retTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const stmt = self.ast.getNode(stmtI);

        switch (stmt.tag) {
            .ret => {
                try self.checkExpressionExpectedType(stmt.data[0], retTypeI);
            },
            .variable, .constant => {
                if (self.searchVariableScope(stmt.getTextAst(self.ast.*))) |variableI| {
                    const locStmt = stmt.getLocationAst(self.ast.*);
                    const variable = self.ast.getNode(variableI);

                    Logger.logLocation.err(self.ast.path, locStmt, "Identifier {s} is already in use {s}", .{ variable.getTextAst(self.ast.*), Logger.placeSlice(locStmt, self.ast.source) });
                    const locVar = variable.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, locVar, "{s} is declared in use {s}", .{ variable.getTextAst(self.ast.*), Logger.placeSlice(locVar, self.ast.source) });
                    self.errs += 1;
                    return;
                }

                try self.addVariableScope(stmt.getTextAst(self.ast.*), stmtI, .local);

                _ = try self.inferMachine.add(stmtI);

                if (stmt.data[0] != 0) {
                    const tI = stmt.data[0];
                    const exprI = stmt.data[1];

                    try self.inferMachine.found(stmtI, tI, stmtI);

                    try self.checkExpressionExpectedType(exprI, tI);
                } else {
                    const exprI = stmt.data[1];
                    if (stmt.tag == .constant) _ = try self.inferMachine.toConstant(stmtI);
                    if (try self.checkExpressionInferType(exprI)) |bS| {
                        _ = self.inferMachine.merge(stmtI, bS) catch |err| switch (err) {
                            error.IncompatibleType => unreachable,
                            error.OutOfMemory => return error.OutOfMemory,
                        };
                    }
                }
            },
            else => unreachable,
        }
    }
    fn checkExpressionInferType(self: *Self, exprI: Parser.NodeIndex) std.mem.Allocator.Error!?Parser.NodeIndex {
        const expr = self.ast.getNode(exprI);

        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));
        switch (expr.tag) {
            .lit => {
                return null;
            },
            .load => {
                const variable = self.searchVariableScope(expr.getTextAst(self.ast.*)) orelse {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Unknown identifier in expression \'{s}\' {s}", .{ expr.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;

                    return null;
                };

                return variable;
            },
            .neg => {
                const leftI = expr.data[0];

                return try self.checkExpressionInferType(leftI);
            },
            .addition, .subtraction, .multiplication, .division, .power => {
                const leftI = expr.data[0];
                const rightI = expr.data[1];

                const a = try self.checkExpressionInferType(leftI);
                const b = try self.checkExpressionInferType(rightI);

                if (a != null and b != null) {
                    const aS = a.?;
                    const bS = b.?;

                    return self.inferMachine.merge(aS, bS) catch |err| switch (err) {
                        error.IncompatibleType => {
                            unreachable;
                            // const tLeft = self.inferMachine.setTOvar.get(aS).?[0].?;
                            // const tRight = self.inferMachine.setTOvar.get(bS).?[0].?;
                            // const loc = expr.getLocationAst(self.ast.tokens);
                            // Logger.logLocation.err(
                            //     self.ast.path,
                            //     loc,
                            //     "To the left of this operation has {s} and to the right has {s}, they must be the same {s}",
                            //     .{ tLeft[0].getNameAst(self.ast.tokens), tRight[0].getNameAst(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) },
                            // );
                            //
                            // self.errs += 1;
                            //
                            // return null;
                        },
                        error.OutOfMemory => return error.OutOfMemory,
                    };
                }

                if (a) |aS| {
                    return aS;
                } else {
                    return b;
                }
            },
            else => {
                const loc = expr.getLocationAst(self.ast.*);
                Logger.logLocation.err(
                    self.ast.path,
                    loc,
                    "Node not supported {} {s}",
                    .{ expr.tag, Logger.placeSlice(loc, self.ast.source) },
                );
                unreachable;
            },
        }

        unreachable;
    }

    fn checkExpressionExpectedType(self: *Self, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const expr = self.ast.getNode(exprI);
        const expectedType = self.ast.getNode(expectedTypeI);

        std.debug.assert(expectedType.tag == .type);
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));

        switch (expr.tag) {
            .lit => {
                self.checkValueForType(exprI, expectedTypeI);
            },
            .load => {
                const variableI = self.searchVariableScope(expr.getTextAst(self.ast.*)) orelse {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Unknown identifier in expression \'{s}\' {s}", .{ expr.getTextAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;

                    return;
                };

                const variable = self.ast.getNode(variableI);

                if (variable.data[0] != 0) {
                    const t = self.ast.nodeList.items[variable.data[0]];

                    if (t.getTokenTagAst(self.ast.*) != expectedType.getTokenTagAst(self.ast.*)) {
                        const locVar = variable.getLocationAst(self.ast.*);
                        Logger.logLocation.err(
                            self.ast.path,
                            locVar,
                            "This variable declared here with type {s} {s}",
                            .{ t.getNameAst(self.ast.*), Logger.placeSlice(locVar, self.ast.source) },
                        );
                        const locExpr = expr.getLocationAst(self.ast.*);
                        Logger.logLocation.err(
                            self.ast.path,
                            locExpr,
                            "Is use here with another type {s}, these types are incompatible {s}",
                            .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(locExpr, self.ast.source) },
                        );
                        self.errs += 1;
                    }
                } else {
                    if (self.inferMachine.includes(variableI)) {
                        try self.inferMachine.found(variableI, expectedTypeI, exprI);
                    } else {
                        // CLEANUP: The Generic varialble is checked every time
                        const prevError = self.errs;
                        try self.checkExpressionExpectedType(variable.data[1], expectedTypeI);
                        if (prevError != self.errs) {
                            const loc = expr.getLocationAst(self.ast.*);
                            Logger.logLocation.info(
                                self.ast.path,
                                loc,
                                "Generic type is not compatible with: {s} {s}",
                                .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) },
                            );
                        }
                    }
                }
            },
            .neg => {
                const leftI = expr.data[0];

                try self.checkExpressionExpectedType(leftI, expectedTypeI);
            },
            .addition, .subtraction, .multiplication, .division, .power => {
                const leftI = expr.data[0];
                const rightI = expr.data[1];

                try self.checkExpressionExpectedType(leftI, expectedTypeI);
                try self.checkExpressionExpectedType(rightI, expectedTypeI);
            },
            else => {
                const loc = expr.getLocationAst(self.ast.*);
                Logger.logLocation.err(
                    self.ast.path,
                    loc,
                    "Node not supported {} {s}",
                    .{ expr.tag, Logger.placeSlice(loc, self.ast.source) },
                );
                unreachable;
            },
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
                const loc = expr.getLocationAst(self.ast.*);
                Logger.logLocation.err(self.ast.path, loc, "Node not supported {} {s}", .{ expr.tag, Logger.placeSlice(loc, self.ast.source) });
                unreachable;
            },
        }
    }

    fn checkValueForType(self: *Self, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) void {
        const expr = self.ast.getNode(exprI);
        const expectedType = self.ast.getNode(expectedTypeI);

        const text = expr.getTextAst(self.ast.*);
        switch (expectedType.getTokenTagAst(self.ast.*)) {
            .unsigned8 => {
                _ = std.fmt.parseUnsigned(u8, text, 10) catch {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .unsigned16 => {
                _ = std.fmt.parseUnsigned(u16, text, 10) catch {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(
                        self.ast.path,
                        loc,
                        "Number literal is too large for the expected type {s} {s}",
                        .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) },
                    );
                    self.errs += 1;
                };
            },
            .unsigned32 => {
                _ = std.fmt.parseUnsigned(u32, text, 10) catch {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .unsigned64 => {
                _ = std.fmt.parseUnsigned(u64, text, 10) catch {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },

            .signed8 => {
                _ = std.fmt.parseInt(i8, text, 10) catch {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .signed16 => {
                _ = std.fmt.parseInt(i16, text, 10) catch {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .signed32 => {
                _ = std.fmt.parseInt(i32, text, 10) catch {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .signed64 => {
                _ = std.fmt.parseInt(i64, text, 10) catch {
                    const loc = expr.getLocationAst(self.ast.*);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            else => unreachable,
        }
    }
};

pub fn typeCheck(p: *Parser.Ast) std.mem.Allocator.Error!bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    return try TypeChecker.init(alloc, p);
}
