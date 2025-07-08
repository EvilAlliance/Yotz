const std = @import("std");
const Lexer = @import("./../Lexer/Lexer.zig");
const Parser = @import("./../Parser/Parser.zig");
const Logger = @import("./../Logger.zig");

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
    ast: *Parser.Ast,

    pub fn init(ast: *Parser.Ast) @This() {
        return .{ .ast = ast };
    }

    pub inline fn funcReturnsU8(self: @This(), functionName: []const u8, typeIndex: Parser.NodeIndex) void {
        const loc = self.ast.getNodeLocation(typeIndex);
        const typeNode = self.ast.getNode(typeIndex);
        const where = placeSlice(loc, self.ast.source);
        Logger.log.err(
            "{s}:{}:{}: {s} must return u8 instead of {c}{}\n{s}\n{[7]c: >[8]}",
            .{
                self.ast.path,
                loc.row,
                loc.col,
                functionName,
                typeNode.typeToString(),
                typeNode.data[0],
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn variableMustBeFunction(self: @This(), functionName: []const u8, variableI: Parser.NodeIndex) void {
        const loc = self.ast.getNodeLocation(variableI);
        const where = placeSlice(loc, self.ast.source);
        Logger.log.err(
            "{s}:{}:{}: {s} must be a function: \n{s}\n{[5]c: >[6]}",
            .{
                self.ast.path,
                loc.row,
                loc.col,
                functionName,
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn mainFunctionMissing(self: @This()) void {
        _ = self;
        Logger.log.err("Main function is missing, Expected: \n{s}", .{
            \\ fn main() u8{
            \\     return 0;
            \\ }
        });
    }

    pub inline fn identifierIsUsed(self: @This(), reDefI: Parser.NodeIndex, varI: Parser.NodeIndex) void {
        const locStmt = self.ast.getNode(reDefI).getLocationAst(self.ast.*);
        const varia = self.ast.getNode(varI);
        const where = placeSlice(locStmt, self.ast.source);
        Logger.log.err(
            "{s}:{}:{}: Identifier {s} is already in use \n{s}\n{[5]c: >[6]}",
            .{
                self.ast.path,
                locStmt.row,
                locStmt.col,
                varia.getTextAst(self.ast),
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn unknownIdentifier(self: @This(), nodeI: Parser.NodeIndex) void {
        const stmt = self.ast.getNode(nodeI);
        const locStmt = stmt.getLocationAst(self.ast.*);
        const where = placeSlice(locStmt, self.ast.source);
        Logger.log.err(
            "{s}:{}:{}: Unknown identifier {s} is already in use \n{s}\n{[5]c: >[6]}",
            .{
                self.ast.path,
                locStmt.row,
                locStmt.col,
                stmt.getTextAst(self.ast),
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn identifierNotAvailable(self: @This(), iden: []const u8, loc: Lexer.Location) void {
        const where = placeSlice(loc, self.ast.source);
        Logger.log.err(
            "{s}:{}:{}: {s} is an identifier not available \n{s}\n{[5]c: >[6]}",
            .{
                self.ast.path,
                loc.row,
                loc.col,
                iden,
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn incompatibleType(self: @This(), t1: Parser.NodeIndex, t2: Parser.NodeIndex, loc: Lexer.Location) void {
        const typeNode1 = self.ast.getNode(t1);
        const typeNode2 = self.ast.getNode(t2);
        const where = placeSlice(loc, self.ast.source);
        Logger.log.err(
            "{s}:{}:{}: Type {c}{}, is incompatible with {c}{} \n{s}\n{[8]c: >[9]}",
            .{
                self.ast.path,
                loc.row,
                loc.col,
                typeNode1.typeToString(),
                typeNode1.data[0],
                typeNode2.typeToString(),
                typeNode2.data[0],
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn nodeNotSupported(self: @This(), nodeI: Parser.NodeIndex) void {
        const node = self.ast.getNode(nodeI);
        const loc = node.getLocationAst(self.ast.*);

        const where = placeSlice(loc, self.ast.source);
        Logger.log.err(
            "{s}:{}:{}: Unknown or Not Supported Node {s} \n{s}\n{[5]c: >[6]}",
            .{
                self.ast.path,
                loc.row,
                loc.col,
                @tagName(node.tag),
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn numberDoesNotFit(self: @This(), exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) void {
        const expectedType = self.ast.getNode(expectedTypeI);
        const loc = self.ast.getNodeLocation(exprI);
        const max = std.math.pow(u64, 2, expectedType.data[0]) - 1;
        const where = placeSlice(loc, self.ast.source);
        Logger.logLocation.err(
            self.ast.path,
            loc,
            "Number does not fit into for type {c}{}, range: 0 - {} \n{s}\n{[4]c: >[5]}",
            .{
                expectedType.typeToString(),
                expectedType.data[0],
                max,
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }
};

const Info = struct {
    ast: *Parser.Ast,

    pub fn init(ast: *Parser.Ast) @This() {
        return .{ .ast = ast };
    }

    pub inline fn isDeclaredHere(self: @This(), varI: Parser.NodeIndex) void {
        const varia = self.ast.getNode(varI);
        const locVar = varia.getLocationAst(self.ast.*);
        const where = placeSlice(locVar, self.ast.source);
        Logger.log.info(
            "{s}:{}:{}: {s} is declared in use \n{s}\n{[5]c: >[6]}",
            .{
                self.ast.path,
                locVar.row,
                locVar.col,
                varia.getTextAst(self.ast),
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn inferedType(self: @This(), t: Parser.NodeIndex) void { // type
        const typeNode = self.ast.getNode(t);
        const inferedLoc = typeNode.getLocationAst(self.ast.*);
        const where = placeSlice(inferedLoc, self.ast.source);
        Logger.log.info(
            "{s}:{}:{}: Infered Type {c}{} here: \n{s}\n{[6]c: >[7]}",
            .{
                self.ast.path,
                inferedLoc.row,
                inferedLoc.col,
                typeNode.typeToString(),
                typeNode.data[0],
                self.ast.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }
};

ast: *Parser.Ast,
err: Error,
info: Info,

pub fn init(ast: *Parser.Ast) Self {
    return .{
        .ast = ast,
        .err = Error.init(ast),
        .info = Info.init(ast),
    };
}
