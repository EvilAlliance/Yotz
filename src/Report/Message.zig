pub fn placeSlice(location: Lexer.Location, content: [:0]const u8) struct { beg: usize, end: usize, pad: usize } {
    var beg = location.start;

    while (beg > 1 and content[beg - 1] != '\n') : (beg -= 1) {}
    if (beg > 0)
        beg -= 1;
    if (beg != 0)
        beg += 1;

    var end = location.start;

    while (end < content.len and content[end + 1] != '\n') : (end += 1) {}
    end += 1;

    return .{
        .beg = beg,
        .end = end,
        .pad = location.col,
    };
}

const Self = @This();

const Error = struct {
    global: *Global,

    pub fn init(global: *Global) @This() {
        return .{ .global = global };
    }

    pub inline fn funcReturnsU8(self: @This(), functionName: []const u8, typeNode: *const Parser.Node) void {
        const loc = typeNode.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: {s} must return u8 instead of {c}{}\n{s}\n{[7]c: >[8]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                functionName,
                typeNode.typeToString(),
                typeNode.left.load(.acquire),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn funcExpect0Args(self: @This(), functionName: *const Parser.Node.Declarator) void {
        const loc = functionName.asConst().getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: {s} must have 0 arguments\n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                functionName.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn variableMustBeFunction(self: @This(), functionName: []const u8, variableI: Parser.NodeIndex) void {
        const loc = self.global.getNodeLocation(variableI);
        const where = placeSlice(loc, self.global.cont.source);
        std.log.err(
            "{s}:{}:{}: {s} must be a function: \n{s}\n{[5]c: >[6]}",
            .{
                self.global.cont.path,
                loc.row,
                loc.col,
                functionName,
                self.global.cont.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn mainFunctionMissing(self: @This()) void {
        _ = self;
        std.log.err("Main function is missing, Expected: \n{s}", .{
            \\ main :: () u8 {
            \\     return 0;
            \\ }
        });
    }

    pub inline fn missingReturn(self: @This(), alloc: Allocator, returnType: *const Parser.Node) Allocator.Error!void {
        const loc = returnType.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);

        var expectedStr = std.ArrayList(u8){};
        defer expectedStr.deinit(alloc);
        try returnType.asConstTypes().toString(self.global, alloc, &expectedStr, 0, false);

        std.log.err(
            "{s}:{}:{}: Function must return type {s} but has no return statement \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                expectedStr.items,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn expectedFunction(self: @This(), variable: *const Parser.Node) void {
        const loc = variable.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Expected a function but got a different type \n{s}\n{[4]c: >[5]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn expectedExpression(self: @This(), returnNode: *const Parser.Node) void {
        const loc = returnNode.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Expected an expression after return statement \n{s}\n{[4]c: >[5]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn invalidOperatorForVoid(self: @This(), expr: *const Parser.Node) void {
        const loc = expr.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Invalid operator for void type \n{s}\n{[4]c: >[5]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn incompatibleReturnType(self: @This(), alloc: Allocator, actual: *const Parser.Node.Types, expected: *const Parser.Node.Types, loc: Lexer.Location, kind: ?[]const u8) Allocator.Error!void {
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);

        var actualStr = std.ArrayList(u8){};
        defer actualStr.deinit(alloc);
        try actual.toString(self.global, alloc, &actualStr, 0, false);

        var expectedStr = std.ArrayList(u8){};
        defer expectedStr.deinit(alloc);
        try expected.toString(self.global, alloc, &expectedStr, 0, false);

        const kindStr = if (kind) |k| k else "";
        const separator = if (kind != null) " " else "";

        std.log.err(
            "{s}:{}:{}: Incompatible return type {s}, expected {s}{s}{s}\n{s}\n{[8]c: >[9]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                actualStr.items,
                expectedStr.items,
                separator,
                kindStr,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn identifierIsUsed(self: @This(), reDef: *const Parser.Node) void {
        const locStmt = reDef.getLocation(self.global);
        const fileInfo = self.global.files.get(locStmt.source);
        const where = placeSlice(locStmt, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Identifier {s} is already in use \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                locStmt.row,
                locStmt.col,
                reDef.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn identifierIsReserved(self: @This(), declarator: *const Parser.Node.Declarator) void {
        const loc = declarator.asConst().getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Identifier '{s}' is reserved and cannot be used as a variable name \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                declarator.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn argumentsAreConstant(self: @This(), argument: *const Parser.Node.Assignment) void {
        const loc = argument.asConst().getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Cannot assign to argument '{s}' (arguments are constant) \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                argument.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn assignmentToConstant(self: @This(), constant: *const Parser.Node.Assignment) void {
        const loc = constant.asConst().getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Cannot assign to constant '{s}' \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                constant.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn unknownIdentifier(self: @This(), unknownNode: *const Parser.Node) void {
        const loc = unknownNode.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Unknown identifier '{s}' \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                unknownNode.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn usedBeforeDefined(self: @This(), nameNode: *const Parser.Node) void {
        const loc = nameNode.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Identifier '{s}' is used before it is defined \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                nameNode.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn identifierNotAvailable(self: @This(), iden: []const u8, loc: Lexer.Location) void {
        const where = placeSlice(loc, self.global.cont.source);
        std.log.err(
            "{s}:{}:{}: {s} is an identifier not available \n{s}\n{[5]c: >[6]}",
            .{
                self.global.cont.path,
                loc.row,
                loc.col,
                iden,
                self.global.cont.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn incompatibleFunctionType(self: @This(), t1: Parser.NodeIndex, t2: Parser.NodeIndex, loc: Lexer.Location) void {
        const typeNode1 = self.global.getNode(.UnCheck, t1);
        const typeNode2 = self.global.getNode(.UnCheck, t2);
        const where = placeSlice(loc, self.global.tu.cont.source);
        std.log.err(
            "{s}:{}:{}: Type {c}{}, is incompatible with {c}{} \n{s}\n{[8]c: >[9]}",
            .{
                self.global.tu.cont.path,
                loc.row,
                loc.col,
                typeNode1.typeToString(),
                typeNode1.left.load(.acquire),
                typeNode2.typeToString(),
                typeNode2.left.load(.acquire),
                self.global.tu.cont.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn incompatibleType(self: @This(), alloc: std.mem.Allocator, actual: *const Parser.Node.Types, expected: *const Parser.Node.Types, loc: Lexer.Location, kind: ?[]const u8) std.mem.Allocator.Error!void {
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);

        var actualStr = std.ArrayList(u8){};
        defer actualStr.deinit(alloc);
        try actual.toString(self.global, alloc, &actualStr, 0, false);

        var expectedStr = std.ArrayList(u8){};
        defer expectedStr.deinit(alloc);
        try expected.toString(self.global, alloc, &expectedStr, 0, false);

        const kindStr = if (kind) |k| k else "";
        const separator = if (kind != null) " " else "";

        std.log.err(
            "{s}:{}:{}: Type {s}, is incompatible with {s}{s}{s}\n{s}\n{[8]c: >[9]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                actualStr.items,
                expectedStr.items,
                separator,
                kindStr,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn argumentCountMismatch(self: @This(), actualCount: u64, expectedCount: u64, loc: Lexer.Location) void {
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Function has {} arguments but expected {} \n{s}\n{[6]c: >[7]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                actualCount,
                expectedCount,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn nodeNotSupported(self: @This(), nodeI: Parser.NodeIndex) void {
        const node = self.global.nodes.get(nodeI);
        const loc = node.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);

        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Unknown or Not Supported Node {s} \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                @tagName(node.tag.load(.acquire)),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn numberDoesNotFit(self: @This(), expr: *const Parser.Node, expectedType: *const Parser.Node) void {
        const loc = expr.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);

        const size = expectedType.left.load(.acquire);
        const max = std.math.pow(u64, 2, size) - 1;
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Number does not fit into for type {c}{}, range: 0 - {} \n{s}\n{[7]c: >[8]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                expectedType.typeToString(),
                size,
                max,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn unexpectedToken(self: @This(), actual: Lexer.Token.Type, expected: []const Lexer.Token.Type, loc: Lexer.Location) void {
        var buff: [256]u8 = undefined;
        var arr = std.ArrayList(u8).initBuffer(&buff);

        arr.appendBounded('\"') catch return;
        arr.appendSliceBounded(expected[0].getName()) catch return;
        arr.appendBounded('\"') catch return;
        for (expected[1..]) |e| {
            arr.appendSliceBounded(", ") catch return;
            arr.appendBounded('\"') catch return;
            arr.appendSliceBounded(e.getName()) catch return;
            arr.appendBounded('\"') catch return;
        }

        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Expected: {s} but found: \'{s}\' \n{s}\n{[6]c: >[7]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                arr.items,
                actual.getName(),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn dependencyCycle(self: @This(), cycle: []const Typing.Expression.CycleUnit) void {
        var node = cycle[0].node;
        var loc = node.getLocation(self.global);
        var fileInfo = self.global.files.get(loc.source);
        var where = placeSlice(loc, fileInfo.source);

        std.log.err("{s}:{}:{}: Dependency cycle detected with length {}:", .{
            fileInfo.path,
            loc.row,
            loc.col,
            cycle.len,
        });

        for (cycle, 0..) |unit, i| {
            node = unit.node;
            loc = node.getLocation(self.global);
            fileInfo = self.global.files.get(loc.source);
            where = placeSlice(loc, fileInfo.source);

            std.log.info(
                "{}. {s}:{}:{}: {s}\n     {s}\n     {[6]c: >[7]}",
                .{
                    i + 1,
                    fileInfo.path,
                    loc.row,
                    loc.col,
                    unit.reason.toString(),
                    fileInfo.source[where.beg..where.end],
                    '^',
                    where.pad,
                },
            );
        }
    }
};

const Info = struct {
    global: *Global,

    pub fn init(global: *Global) @This() {
        return .{ .global = global };
    }

    pub inline fn isDeclaredHere(self: @This(), varia: *const Parser.Node) void {
        const locVar = varia.getLocation(self.global);
        const fileInfo = self.global.files.get(locVar.source);
        const where = placeSlice(locVar, fileInfo.source);
        std.log.info(
            "{s}:{}:{}: {s} is declared here \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                locVar.row,
                locVar.col,
                varia.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn inferedType(self: @This(), typeNode: *const Parser.Node) void { // type
        const inferedLoc = typeNode.getLocation(self.global);
        const fileInfo = self.global.files.get(inferedLoc.source);
        const where = placeSlice(inferedLoc, fileInfo.source);
        std.log.info(
            "{s}:{}:{}: Infered Type {c}{} here: \n{s}\n{[6]c: >[7]}",
            .{
                fileInfo.path,
                inferedLoc.row,
                inferedLoc.col,
                typeNode.typeToString(),
                typeNode.left.load(.acquire),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }
};

const Warn = struct {
    global: *Global,

    pub fn init(global: *Global) @This() {
        return .{ .global = global };
    }

    pub inline fn unreachableStatement(self: @This(), statement: *const Parser.Node) void {
        const loc = statement.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.warn(
            "{s}:{}:{}: Unreachable statement detected \n{s}\n{[4]c: >[5]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn unusedVariable(self: @This(), variable: *const Parser.Node.Declarator) void {
        const loc = variable.asConst().getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.warn(
            "{s}:{}:{}: Variable '{s}' is declared but never used \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                variable.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }
};

global: *Global,
err: Error,
info: Info,
warn: Warn,

pub fn init(global: *Global) Self {
    return .{
        .global = global,
        .err = Error.init(global),
        .info = Info.init(global),
        .warn = Warn.init(global),
    };
}

const Lexer = @import("../Lexer/mod.zig");
const Parser = @import("../Parser/mod.zig");
const Global = @import("../Global.zig");

const Typing = @import("../Typing/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
