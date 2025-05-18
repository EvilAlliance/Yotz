const std = @import("std");
const Util = @import("Util.zig");
const Logger = @import("Logger.zig");
const InferMachine = @import("InferMachine.zig");

const Parser = @import("./Parser/Parser.zig");
const nl = @import("./Parser/NodeListUtil.zig");

const Scope = std.StringHashMap(Parser.NodeIndex);
const Scopes = std.ArrayList(Scope);

const TypeChecker = struct {
    const Self = @This();

    errs: usize = 0,

    alloc: std.mem.Allocator,

    inferMachine: InferMachine,

    ast: *Parser.Ast,
    scopes: Scopes,

    foundMain: ?Parser.Node = null,

    pub fn init(alloc: std.mem.Allocator, ast: *Parser.Ast) std.mem.Allocator.Error!bool {
        var checker = @This(){
            .alloc = alloc,
            .inferMachine = InferMachine.init(alloc, ast),
            .ast = ast,
            .scopes = Scopes.init(alloc),
        };
        defer checker.deinit();

        var funcIndex = ast.getNode(0).data[0];
        while (funcIndex != ast.getNode(0).data[1]) : (funcIndex = ast.getNode(funcIndex).next) {
            const func = ast.getNode(funcIndex);

            try checker.checkFunction(func.data[1]);
        }

        // var itSet = checker.inferMachine.setTOvar.valueIterator();

        // TODO: This check if everything is compatible but does not inserts it in the program

        // while (itSet.next()) |set| {
        //     if (set[0]) |v| {
        //         const t, const loc = v;
        //         const index = try nl.addNode(&checker.ast.nodeList, t);
        //         for (set[1].items) |*variable| {
        //             if (variable.data[0] != 0) continue;
        //
        //             const errorCount = checker.errs;
        //             // CLEANUP: Check when its found instead of now
        //             checker.checkLiteralExpressionExpectedType(ast.nodeList.items[variable.data[1]], t);
        //
        //             if (errorCount != checker.errs) {
        //                 Logger.logLocation.info(ast.path, loc, "It was found unsing type {s} here: {s}", .{ t.getName(ast.tokens), Logger.placeSlice(loc, ast.source) });
        //             }
        //             variable.data[0] = index;
        //         }
        //     } else {
        //         for (set[1].items) |variable| {
        //             const loc = variable.getLocation(ast.tokens);
        //             Logger.logLocation.err(ast.path, loc, "Variable has ambiguos type {s}", .{Logger.placeSlice(loc, ast.source)});
        //         }
        //     }
        // }
        //
        // TODO: Pass this to the new format

        if (checker.foundMain) |mainProto| {
            std.debug.assert(mainProto.tag == .funcProto);
            const t = ast.nodeList.items[mainProto.data[1]];
            std.debug.assert(t.tag == .type);

            if (t.getTokenTag(ast.tokens) != .unsigned8) {
                const loc = t.getLocation(ast.tokens);
                Logger.logLocation.err(ast.path, loc, "Main must return u8 instead of {s} {s}", .{ t.getName(ast.tokens), Logger.placeSlice(loc, ast.source) });
                checker.errs += 1;
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

    pub fn searchVariableScope(self: *Self, name: []const u8) ?Parser.NodeIndex {
        var i: usize = self.scopes.items.len;
        while (i > 0) {
            i -= 1;

            var dic = self.scopes.items[i];
            if (dic.get(name)) |n| return n;
        }

        return null;
    }

    pub fn addVariableScope(self: *Self, name: []const u8, nodeI: Parser.NodeIndex) std.mem.Allocator.Error!void {
        const scope = &self.scopes.items[self.scopes.items.len - 1];
        try scope.put(name, nodeI);
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

        const name = node.getText(self.ast.tokens, self.ast.source);

        if (std.mem.eql(u8, name, "_start")) {
            const loc = node.getLocation(self.ast.tokens);
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
                if (self.searchVariableScope(stmt.getText(self.ast.tokens, self.ast.source))) |variableI| {
                    const locStmt = stmt.getLocation(self.ast.tokens);
                    const variable = self.ast.getNode(variableI);

                    Logger.logLocation.err(self.ast.path, locStmt, "Identifier {s} is already in use {s}", .{ variable.getText(self.ast.tokens, self.ast.source), Logger.placeSlice(locStmt, self.ast.source) });
                    const locVar = variable.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, locVar, "{s} is declared in use {s}", .{ variable.getText(self.ast.tokens, self.ast.source), Logger.placeSlice(locVar, self.ast.source) });
                    self.errs += 1;
                    return;
                }

                try self.addVariableScope(stmt.getText(self.ast.tokens, self.ast.source), stmtI);

                if (stmt.data[0] != 0) {
                    const tI = stmt.data[0];
                    const exprI = stmt.data[1];

                    _ = try self.inferMachine.add(stmtI);
                    try self.inferMachine.found(stmtI, tI, stmt.getLocation(self.ast.tokens));

                    try self.checkExpressionExpectedType(exprI, tI);
                } else {
                    const exprI = stmt.data[1];
                    if (stmt.tag == .variable) _ = try self.inferMachine.add(stmtI);
                    if (try self.checkExpressionInferType(exprI)) |bS| {
                        const a = try self.inferMachine.add(stmtI);

                        _ = self.inferMachine.merge(a, bS) catch |err| switch (err) {
                            error.IncompatibleType => unreachable,
                            error.OutOfMemory => return error.OutOfMemory,
                        };
                    }
                }
            },
            else => unreachable,
        }
    }
    fn checkExpressionInferType(self: *Self, exprI: Parser.NodeIndex) std.mem.Allocator.Error!?usize {
        const expr = self.ast.getNode(exprI);

        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .parentesis, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));
        switch (expr.tag) {
            .lit => {
                return null;
            },
            .load => {
                const variable = self.searchVariableScope(expr.getText(self.ast.tokens, self.ast.source)) orelse {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Unknown identifier in expression \'{s}\' {s}", .{ expr.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;

                    return null;
                };

                if (!self.inferMachine.includes(variable))
                    return null;

                return try self.inferMachine.add(variable);
            },
            .parentesis, .neg => {
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
                            // const loc = expr.getLocation(self.ast.tokens);
                            // Logger.logLocation.err(
                            //     self.ast.path,
                            //     loc,
                            //     "To the left of this operation has {s} and to the right has {s}, they must be the same {s}",
                            //     .{ tLeft[0].getName(self.ast.tokens), tRight[0].getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) },
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
                const loc = expr.getLocation(self.ast.tokens);
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
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .parentesis, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));

        switch (expr.tag) {
            .lit => {
                self.checkValueForType(exprI, expectedTypeI);
            },
            .load => {
                const variableI = self.searchVariableScope(expr.getText(self.ast.tokens, self.ast.source)) orelse {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Unknown identifier in expression \'{s}\' {s}", .{ expr.getText(self.ast.tokens, self.ast.source), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;

                    return;
                };

                const variable = self.ast.getNode(variableI);

                if (variable.data[0] != 0) {
                    const t = self.ast.nodeList.items[variable.data[0]];

                    if (t.getTokenTag(self.ast.tokens) != expectedType.getTokenTag(self.ast.tokens)) {
                        const locVar = variable.getLocation(self.ast.tokens);
                        Logger.logLocation.err(
                            self.ast.path,
                            locVar,
                            "This variable declared here with type {s} {s}",
                            .{ t.getName(self.ast.tokens), Logger.placeSlice(locVar, self.ast.source) },
                        );
                        const locExpr = expr.getLocation(self.ast.tokens);
                        Logger.logLocation.err(
                            self.ast.path,
                            locExpr,
                            "Is use here with another type {s}, these types are incompatible {s}",
                            .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(locExpr, self.ast.source) },
                        );
                        self.errs += 1;
                    }
                } else {
                    if (self.inferMachine.includes(variableI)) {
                        try self.inferMachine.found(variableI, expectedTypeI, expr.getLocation(self.ast.tokens));
                    } else {
                        // CLEANUP: The Generic varialble is checked every time
                        const prevError = self.errs;
                        try self.checkExpressionExpectedType(variable.data[1], expectedTypeI);
                        if (prevError != self.errs) {
                            const loc = expr.getLocation(self.ast.tokens);
                            Logger.logLocation.info(
                                self.ast.path,
                                loc,
                                "Generic type is not compatible with: {s} {s}",
                                .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) },
                            );
                        }
                    }
                }
            },
            .parentesis, .neg => {
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
                const loc = expr.getLocation(self.ast.tokens);
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
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .parentesis, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));

        switch (expr.tag) {
            .lit => {
                self.checkValueForType(expr, expectedType);
            },
            .load => {},
            .parentesis, .neg => {
                const left = self.ast.nodeList.items[expr.data[0]];

                self.checkLiteralExpressionExpectedType(left, expectedType);
            },
            .addition, .subtraction, .multiplication, .division, .power => {
                const left = self.ast.nodeList.items[expr.data[0]];
                const right = self.ast.nodeList.items[expr.data[1]];

                self.checkLiteralExpressionExpectedType(left, expectedType);
                self.checkLiteralExpressionExpectedType(right, expectedType);
            },
            else => {
                const loc = expr.getLocation(self.ast.tokens);
                Logger.logLocation.err(self.ast.path, loc, "Node not supported {} {s}", .{ expr.tag, Logger.placeSlice(loc, self.ast.source) });
                unreachable;
            },
        }
    }

    fn checkValueForType(self: *Self, exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) void {
        const expr = self.ast.getNode(exprI);
        const expectedType = self.ast.getNode(expectedTypeI);

        const text = expr.getText(self.ast.tokens, self.ast.source);
        switch (expectedType.getTokenTag(self.ast.tokens)) {
            .unsigned8 => {
                _ = std.fmt.parseUnsigned(u8, text, 10) catch {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .unsigned16 => {
                _ = std.fmt.parseUnsigned(u16, text, 10) catch {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(
                        self.ast.path,
                        loc,
                        "Number literal is too large for the expected type {s} {s}",
                        .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) },
                    );
                    self.errs += 1;
                };
            },
            .unsigned32 => {
                _ = std.fmt.parseUnsigned(u32, text, 10) catch {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .unsigned64 => {
                _ = std.fmt.parseUnsigned(u64, text, 10) catch {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },

            .signed8 => {
                _ = std.fmt.parseInt(i8, text, 10) catch {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .signed16 => {
                _ = std.fmt.parseInt(i16, text, 10) catch {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .signed32 => {
                _ = std.fmt.parseInt(i32, text, 10) catch {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;
                };
            },
            .signed64 => {
                _ = std.fmt.parseInt(i64, text, 10) catch {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Number literal is too large for the expected type {s} {s}", .{ expectedType.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
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
