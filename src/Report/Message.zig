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

    pub inline fn funcReturnsU8(self: @This(), functionName: []const u8, typeIndex: Parser.NodeIndex) void {
        const loc = self.global.getNodeLocation(typeIndex);
        const typeNode = self.global.getNode(typeIndex);
        const where = placeSlice(loc, self.global.cont.source);
        std.log.err(
            "{s}:{}:{}: {s} must return u8 instead of {c}{}\n{s}\n{[7]c: >[8]}",
            .{
                self.global.cont.path,
                loc.row,
                loc.col,
                functionName,
                typeNode.typeToString(),
                typeNode.data[0],
                self.global.cont.source[where.beg..where.end],
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

    pub inline fn identifierIsUsed(self: @This(), reDefI: Parser.NodeIndex) void {
        const locStmt = self.global.nodes.get(reDefI).getLocation(self.global);
        const varia = self.global.nodes.get(reDefI);
        const fileInfo = self.global.files.get(locStmt.source);
        const where = placeSlice(locStmt, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Identifier {s} is already in use \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                locStmt.row,
                locStmt.col,
                varia.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn unknownIdentifier(self: @This(), unkownNode: Parser.NodeIndex) void {
        const stmt = self.global.nodes.get(unkownNode);
        const loc = stmt.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Unknown identifier '{s}' \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                stmt.getText(self.global),
                fileInfo.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn usedBeforeDefined(self: @This(), nameNode: Parser.NodeIndex) void {
        const stmt = self.global.nodes.get(nameNode);
        const loc = stmt.getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Identifier '{s}' is used before it is defined \n{s}\n{[5]c: >[6]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                stmt.getText(self.global),
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
                typeNode1.data[0].load(.acquire),
                typeNode2.typeToString(),
                typeNode2.data[0].load(.acquire),
                self.global.tu.cont.source[where.beg..where.end],
                '^',
                where.pad,
            },
        );
    }

    pub inline fn incompatibleType(self: @This(), actualI: Parser.NodeIndex, expectedI: Parser.NodeIndex, loc: Lexer.Location) void {
        const actual = self.global.nodes.get(actualI);
        const expected = self.global.nodes.get(expectedI);
        const fileInfo = self.global.files.get(loc.source);
        const where = placeSlice(loc, fileInfo.source);
        std.log.err(
            "{s}:{}:{}: Type {c}{}, is incompatible with {c}{} \n{s}\n{[8]c: >[9]}",
            .{
                fileInfo.path,
                loc.row,
                loc.col,
                actual.typeToString(),
                actual.data[0].load(.acquire),
                expected.typeToString(),
                expected.data[0].load(.acquire),
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

    pub inline fn numberDoesNotFit(self: @This(), exprI: Parser.NodeIndex, expectedTypeI: Parser.NodeIndex) void {
        const expectedType = self.global.nodes.get(expectedTypeI);
        const loc = self.global.nodes.get(exprI).getLocation(self.global);
        const fileInfo = self.global.files.get(loc.source);

        const size = expectedType.data[0].load(.acquire);
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
};

const Info = struct {
    global: *Global,

    pub fn init(global: *Global) @This() {
        return .{ .global = global };
    }

    pub inline fn isDeclaredHere(self: @This(), varI: Parser.NodeIndex) void {
        const varia = self.global.nodes.get(varI);
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

    pub inline fn inferedType(self: @This(), t: Parser.NodeIndex) void { // type
        const typeNode = self.global.nodes.get(t);
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
                typeNode.data[0].load(.acquire),
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

pub fn init(global: *Global) Self {
    return .{
        .global = global,
        .err = Error.init(global),
        .info = Info.init(global),
    };
}

const Lexer = @import("../Lexer/mod.zig");
const Parser = @import("../Parser/mod.zig");
const Global = @import("../Global.zig");

const std = @import("std");
