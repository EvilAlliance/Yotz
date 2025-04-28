const std = @import("std");
const Util = @import("Util.zig");
const Logger = @import("Logger.zig");
const InferMachine = @import("InferMachine.zig");

const Parser = @import("./Parser/Parser.zig");
const nl = @import("./Parser/NodeListUtil.zig");

const Scope = std.StringHashMap(Parser.Node);
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
            .inferMachine = InferMachine.init(alloc, ast.tokens, ast.getInfo()),
            .ast = ast,
            .scopes = Scopes.init(alloc),
        };
        defer checker.deinit();

        var funcIndex = ast.getNode(0).data[0];
        while (funcIndex != ast.getNode(0).data[1]) : (funcIndex = ast.getNode(funcIndex).next) {
            const func = ast.getNode(funcIndex);
            const varProto = ast.getNode(func.data[0]);
            const funcProto = ast.getNode(varProto.data[1]);

            try checker.checkFunction(funcProto);
        }

        var itSet = checker.inferMachine.setTOvar.valueIterator();

        while (itSet.next()) |set| {
            if (set[0]) |v| {
                const t, const loc = v;
                const index = try nl.addNode(&checker.ast.nodeList, t);
                for (set[1].items) |variable| {
                    const proto = &ast.nodeList.items[variable.data[0]];
                    if (proto.data[0] != 0) continue;

                    const errorCount = checker.errs;
                    // CLEANUP: Check when its found instead of now
                    checker.checkLiteralExpressionExpectedType(ast.nodeList.items[proto.data[1]], t);

                    if (errorCount != checker.errs) {
                        Logger.logLocation.info(ast.path, loc, "It was found unsing type {s} here: {s}", .{ t.getName(ast.tokens), Logger.placeSlice(loc, ast.source) });
                    }
                    proto.data[0] = index;
                }
            } else {
                for (set[1].items) |variable| {
                    const loc = variable.getLocation(ast.tokens);
                    Logger.logLocation.err(ast.path, loc, "Variable has ambiguos type {s}", .{Logger.placeSlice(loc, ast.source)});
                }
            }
        }

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

    pub fn searchVariableScope(self: *Self, name: []const u8) ?Parser.Node {
        var i: usize = self.scopes.items.len;
        while (i > 0) {
            i -= 1;

            var dic = self.scopes.items[i];
            if (dic.get(name)) |n| return n;
        }

        return null;
    }

    pub fn addVariableScope(self: *Self, name: []const u8, node: Parser.Node) std.mem.Allocator.Error!void {
        const scope = &self.scopes.items[self.scopes.items.len - 1];
        try scope.put(name, node);
    }

    pub fn deinit(self: *Self) void {
        for (self.scopes.items) |*s|
            s.deinit();

        self.scopes.deinit();
        self.inferMachine.deinit();
    }

    fn checkFunction(self: *Self, node: Parser.Node) std.mem.Allocator.Error!void {
        std.debug.assert(node.tag == .funcProto);

        const name = node.getText(self.ast.tokens, self.ast.source);

        if (std.mem.eql(u8, name, "_start")) {
            const loc = node.getLocation(self.ast.tokens);
            Logger.logLocation.err(self.ast.path, loc, "_start is an identifier not available {s}", .{Logger.placeSlice(loc, self.ast.source)});
            self.errs += 1;
        } else if (self.foundMain == null and std.mem.eql(u8, name, "main")) self.foundMain = node;

        const t = self.ast.nodeList.items[node.data[1]];

        const stmtORscope = self.ast.nodeList.items[node.next];

        if (stmtORscope.tag == .scope) {
            try self.checkScope(stmtORscope, t);
        } else {
            try self.scopes.append(Scope.init(self.alloc));
            try self.checkStatements(stmtORscope, t);
            {
                var x = self.scopes.pop().?;
                x.deinit();
            }
        }
    }

    fn checkScope(self: *Self, scope: Parser.Node, retType: Parser.Node) std.mem.Allocator.Error!void {
        std.debug.assert(scope.tag == .scope and retType.tag == .type);

        try self.scopes.append(Scope.init(self.alloc));

        var i = scope.data[0];
        const end = scope.data[1];

        while (i < end) {
            const stmt = self.ast.nodeList.items[i];

            try self.checkStatements(stmt, retType);

            i = stmt.next;
        }

        {
            var x = self.scopes.pop().?;
            x.deinit();
        }
    }

    fn checkStatements(self: *Self, stmt: Parser.Node, retType: Parser.Node) std.mem.Allocator.Error!void {
        switch (stmt.tag) {
            .ret => {
                const expr = self.ast.nodeList.items[stmt.data[0]];

                try self.checkExpressionExpectedType(expr, retType);
            },
            .variable, .constant => {
                if (self.searchVariableScope(stmt.getText(self.ast.tokens, self.ast.source))) |variable| {
                    const locStmt = stmt.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, locStmt, "Identifier {s} is already in use {s}", .{ variable.getText(self.ast.tokens, self.ast.source), Logger.placeSlice(locStmt, self.ast.source) });
                    const locVar = variable.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, locVar, "{s} is declared in use {s}", .{ variable.getText(self.ast.tokens, self.ast.source), Logger.placeSlice(locVar, self.ast.source) });
                    self.errs += 1;
                    return;
                }

                try self.addVariableScope(stmt.getText(self.ast.tokens, self.ast.source), stmt);

                const proto = self.ast.nodeList.items[stmt.data[0]];

                if (proto.data[0] != 0) {
                    const t = self.ast.nodeList.items[proto.data[0]];
                    const expr = self.ast.nodeList.items[proto.data[1]];

                    _ = try self.inferMachine.add(stmt);
                    try self.inferMachine.found(stmt, t, stmt.getLocation(self.ast.tokens));

                    try self.checkExpressionExpectedType(expr, t);
                } else {
                    const expr = self.ast.nodeList.items[proto.data[1]];
                    if (try self.checkExpressionInferType(expr)) |bS| {
                        const a = try self.inferMachine.add(stmt);

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
    fn checkExpressionInferType(self: *Self, expr: Parser.Node) std.mem.Allocator.Error!?usize {
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
                const left = self.ast.nodeList.items[expr.data[0]];

                return try self.checkExpressionInferType(left);
            },
            .addition, .subtraction, .multiplication, .division, .power => {
                const left = self.ast.nodeList.items[expr.data[0]];
                const right = self.ast.nodeList.items[expr.data[1]];

                const a = try self.checkExpressionInferType(left);
                const b = try self.checkExpressionInferType(right);

                if (a != null and b != null) {
                    const aS = a.?;
                    const bS = b.?;

                    return self.inferMachine.merge(aS, bS) catch |err| switch (err) {
                        error.IncompatibleType => {
                            const tLeft = self.inferMachine.setTOvar.get(aS).?[0].?;
                            const tRight = self.inferMachine.setTOvar.get(bS).?[0].?;
                            const loc = expr.getLocation(self.ast.tokens);
                            Logger.logLocation.err(
                                self.ast.path,
                                loc,
                                "To the left of this operation has {s} and to the right has {s}, they must be the same {s}",
                                .{ tLeft[0].getName(self.ast.tokens), tRight[0].getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) },
                            );

                            self.errs += 1;

                            return null;
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

    fn checkExpressionExpectedType(self: *Self, expr: Parser.Node, expectedType: Parser.Node) std.mem.Allocator.Error!void {
        std.debug.assert(expectedType.tag == .type);
        std.debug.assert(Util.listContains(Parser.Node.Tag, &.{ .lit, .load, .neg, .parentesis, .power, .division, .multiplication, .subtraction, .addition }, expr.tag));

        switch (expr.tag) {
            .lit => {
                self.checkValueForType(expr, expectedType);
            },
            .load => {
                const variable = self.searchVariableScope(expr.getText(self.ast.tokens, self.ast.source)) orelse {
                    const loc = expr.getLocation(self.ast.tokens);
                    Logger.logLocation.err(self.ast.path, loc, "Unknown identifier in expression \'{s}\' {s}", .{ expr.getText(self.ast.tokens, self.ast.source), Logger.placeSlice(loc, self.ast.source) });
                    self.errs += 1;

                    return;
                };

                const proto = self.ast.nodeList.items[variable.data[0]];
                if (proto.data[0] != 0) {
                    const t = self.ast.nodeList.items[proto.data[0]];

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
                    if (self.inferMachine.includes(variable)) {
                        try self.inferMachine.found(variable, expectedType, expr.getLocation(self.ast.tokens));
                    } else {
                        // CLEANUP: The Generic varialble is checked every time
                        const prevError = self.errs;
                        try self.checkExpressionExpectedType(self.ast.getNode(proto.data[1]), expectedType);
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
                const left = self.ast.nodeList.items[expr.data[0]];

                try self.checkExpressionExpectedType(left, expectedType);
            },
            .addition, .subtraction, .multiplication, .division, .power => {
                const left = self.ast.nodeList.items[expr.data[0]];
                const right = self.ast.nodeList.items[expr.data[1]];

                try self.checkExpressionExpectedType(left, expectedType);
                try self.checkExpressionExpectedType(right, expectedType);
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

    fn checkLiteralExpressionExpectedType(self: *Self, expr: Parser.Node, expectedType: Parser.Node) void {
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

    fn checkValueForType(self: *Self, expr: Parser.Node, expectedType: Parser.Node) void {
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
