pub const Error = error{
    UnexpectedToken,
};

tu: *const TranslationUnit,

index: mod.TokenIndex = 0,

depth: mod.NodeIndex = 0,

pub fn init(tu: *const TranslationUnit) Allocator.Error!@This() {
    return @This(){
        .tu = tu,
    };
}

fn peek(self: *const @This()) struct { Lexer.Token, mod.TokenIndex } {
    return self.peekMany(0);
}

fn peekMany(self: *const @This(), n: mod.NodeIndex) struct { Lexer.Token, mod.TokenIndex } {
    assert(self.index + n < self.tu.global.tokens.len());
    return .{ self.tu.global.tokens.get(self.index + n), self.index };
}

fn popIf(self: *@This(), t: Lexer.Token.Type) ?struct { Lexer.Token, mod.TokenIndex } {
    if (self.tu.global.tokens.get(self.index).tag != t) return null;
    const tuple = .{ self.tu.global.tokens.get(self.index), self.index };
    self.index += 1;
    return tuple;
}

fn pop(self: *@This()) struct { Lexer.Token, mod.TokenIndex } {
    const tuple = .{ self.tu.global.tokens.get(self.index), self.index };
    self.index += 1;
    return tuple;
}

fn popUnil(self: *@This(), tokenType: Lexer.Token.Type) void {
    _ = self.pop();

    var peeked = self.peek()[0].tag;
    while (peeked != tokenType and peeked != .EOF) : (peeked = self.peek()[0].tag) {
        _ = self.pop();
    }
}

pub fn parseFunction(self: *@This(), alloc: Allocator, start: mod.TokenIndex, placeHolder: mod.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    self.index = start;

    const index = if (self.peek()[0].tag == .openBrace) try self.parseScope(alloc, reports) else try self.parseStatement(alloc, reports);

    if (self.tu.global.nodes.getPtr(placeHolder).next.cmpxchgStrong(0, index, .acq_rel, .monotonic) != null) @panic("This belongs to this thread and currently is not being passed to another thread");
}

pub fn parseRoot(self: *@This(), alloc: Allocator, start: mod.TokenIndex, placeHolder: mod.NodeIndex, reports: ?*Report.Reports) (std.mem.Allocator.Error)!void {
    self.index = start;

    const index = try self._parseRoot(alloc, reports);

    if (self.tu.global.nodes.getPtr(placeHolder).data[1].cmpxchgStrong(0, index, .acq_rel, .monotonic) != null) @panic("This belongs to this thread and currently is not being passed to another thread");
}

fn _parseRoot(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error)!mod.NodeIndex {
    var firstIndex: mod.NodeIndex = 0;
    var lastNodeParsed: mod.NodeIndex = 0;

    var t, _ = self.peek();

    while (t.tag != .EOF) : (t, _ = self.peek()) {
        Report.expect(alloc, reports, t, &.{.iden}) catch |err|
            switch (err) {
                Error.UnexpectedToken => {
                    self.popUnil(.iden);
                    continue;
                },
                else => return @errorCast(err),
            };

        const nodeIndex = switch (t.tag) {
            .iden => self.parseVariableDecl(alloc, reports),
            else => std.debug.panic("Found {}", .{t}),
        } catch |err| switch (err) {
            error.UnexpectedToken => {
                self.popUnil(.iden);
                continue;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };

        if (firstIndex == 0) {
            firstIndex = nodeIndex;
        } else {
            if (self.tu.global.nodes.getPtr(lastNodeParsed).next.cmpxchgStrong(0, nodeIndex, .acq_rel, .monotonic) != null) @panic("This is controlled by this thread and it should not be influenced by others");
        }

        lastNodeParsed = nodeIndex;
        _ = self.popIf(.semicolon);
    }

    return try self.tu.global.nodes.appendIndex(
        alloc,
        .{
            .tag = .init(.root),
            .data = .{ .init(firstIndex), .init(0) },
        },
    );
}

fn isFunction(self: *const @This()) bool {
    // TODO: When arguments are implemented this must be changeed
    return self.peek()[0].tag == .openParen and self.peekMany(1)[0].tag == .closeParen;
}

fn skipBlock(self: *@This()) void {
    assert(self.peek()[0].tag == .openBrace);

    var braceDepth: u32 = 0;

    while (self.peek()[0].tag != .EOF) {
        const token = self.pop()[0];

        switch (token.tag) {
            .openBrace => {
                braceDepth += 1;
            },
            .closeBrace => {
                braceDepth -= 1;
                if (braceDepth == 0) return;
            },
            else => {},
        }
    }
}

fn parseFuncProto(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    try Report.expect(alloc, reports, self.pop()[0], &.{.openParen});
    // TODO: Parse arguments
    try Report.expect(alloc, reports, self.pop()[0], &.{.closeParen});

    const p = try self.parseType(alloc, reports);

    const nodeIndex = try self.tu.global.nodes.appendIndex(alloc, .{ .tag = .init(.funcProto), .data = .{ .init(0), .init(p) } });

    return nodeIndex;
}

fn parseTypeFunction(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    assert(Util.listContains(Lexer.Token.Type, &.{.openParen}, self.peek()[0].tag));

    try Report.expect(alloc, reports, self.peek()[0], &.{.openParen});
    _, const initI = self.pop();
    try Report.expect(alloc, reports, self.peek()[0], &.{.closeParen});
    _ = self.pop();

    const x = try self.parseType(alloc, reports);

    const node = Node{
        .tag = .init(.funcType),
        .data = .{ .init(0), .init(x) },
        .tokenIndex = .init(initI),
    };

    return try self.tu.global.nodes.appendIndex(alloc, node);
}

fn parseType(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    try Report.expect(alloc, reports, self.peek()[0], &.{ .openParen, .iden });
    if (self.peek()[0].tag == .openParen) {
        return try self.parseTypeFunction(alloc, reports);
    } else {
        _, const tokenIndex = self.pop();
        return try self.tu.global.nodes.appendIndex(alloc, .{
            .tag = .init(.fakeType),
            .tokenIndex = .init(tokenIndex),
        });
    }
}

fn parseScope(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    var firstIndex: mod.NodeIndex = 0;
    var lastNodeParsed: mod.NodeIndex = 0;

    _ = self.popIf(.openBrace) orelse unreachable;

    var peeked = self.peek()[0].tag;
    while (peeked != .closeBrace and peeked != .EOF) : (peeked = self.peek()[0].tag) {
        const nodeIndex = self.parseStatement(alloc, reports) catch |err| switch (err) {
            error.UnexpectedToken => {
                self.popUnil(.semicolon);
                _ = self.popIf(.semicolon);
                continue;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };

        if (firstIndex == 0) {
            firstIndex = nodeIndex;
        } else {
            if (self.tu.global.nodes.getPtr(lastNodeParsed).next.cmpxchgStrong(0, nodeIndex, .acq_rel, .monotonic) != null) @panic("This is controlled by this thread and it should not be influenced by others");
        }

        lastNodeParsed = nodeIndex;
    }

    try Report.expect(alloc, reports, self.peek()[0], &.{.closeBrace});
    _ = self.pop();

    const nodeIndex = try self.tu.global.nodes.appendIndex(alloc, .{
        .tag = .init(.scope),
        .data = .{ .init(firstIndex), .init(0) },
    });

    return nodeIndex;
}

fn parseStatement(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    try Report.expect(alloc, reports, self.peek()[0], &.{ .ret, .iden });

    const nodeIndex = switch (self.peek()[0].tag) {
        .ret => try self.parseReturn(alloc, reports),
        .iden => try self.parseVariableDecl(alloc, reports),
        else => unreachable,
    };

    _ = self.popIf(.semicolon);

    return nodeIndex;
}

fn parseVariableDecl(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    _, const nameIndex = self.popIf(.iden) orelse unreachable;

    const index = try self.tu.global.nodes.appendIndex(alloc, .{
        .tag = .init(Node.Tag.variable),
        .tokenIndex = .init(nameIndex),
    });

    const node = self.tu.global.nodes.getPtr(index);

    try Report.expect(alloc, reports, self.peek()[0], &.{.colon});
    _ = self.pop();

    const possibleType = self.peek()[0];

    if (possibleType.tag != .colon and possibleType.tag != .equal)
        node.data[0].store(try self.parseType(alloc, reports), .release);

    const possibleExpr = self.peek()[0];

    if (possibleExpr.tag == .colon or possibleExpr.tag == .equal) {
        if (self.pop()[0].tag == .colon)
            node.tag = .init(.constant);

        const expr = try self.parseExpression(alloc, reports);

        node.data[1].store(expr, .release);
    }

    _ = self.popIf(.semicolon);

    return index;
}

fn parseReturn(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    _, const retIndex = self.popIf(.ret) orelse unreachable;

    const nodeIndex = try self.tu.global.nodes.appendIndex(alloc, .{
        .tag = .init(.ret),
        .tokenIndex = .init(retIndex),
    });
    const exp = try self.parseExpression(alloc, reports);

    const node = self.tu.global.nodes.getPtr(nodeIndex);

    node.data[1].store(exp, .release);

    _ = self.popIf(.semicolon);

    return nodeIndex;
}

fn parseExpression(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    if (self.isFunction()) {
        const index = try self.parseFuncProto(alloc, reports);

        const start = self.index;

        if (self.peek().@"0".tag == .openBrace) {
            self.skipBlock();
        } else {
            self.popUnil(.semicolon);
            _ = self.popIf(.semicolon);
        }

        try (try self.tu.initFunc(alloc)).startFunction(alloc, start, index, reports);

        return index;
    } else {
        return self.parseExpr(alloc, 1, reports);
    }
}

fn parseExpr(self: *@This(), alloc: Allocator, minPrecedence: u8, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    var nextToken = self.peek()[0];

    var leftIndex = try self.parseTerm(alloc, reports);
    nextToken = self.peek()[0];

    while (Util.listContains(Lexer.Token.Type, &.{ .plus, .minus, .asterik, .slash, .caret }, nextToken.tag)) : (nextToken = self.peek()[0]) {
        const op, const opIndex = self.peek();
        try Report.expect(alloc, reports, op, &.{ .plus, .minus, .asterik, .slash, .caret, .semicolon, .closeParen });

        const tag: Node.Tag = Expression.tokenTagToNodeTag(op.tag);
        const prec = Expression.operandPresedence(tag);
        if (prec < minPrecedence) break;

        _ = self.pop();

        const nextMinPrec = if (Expression.operandAssociativity(tag) == Expression.Associativity.left) prec + 1 else prec;

        const right = try self.parseExpr(alloc, nextMinPrec, reports);

        leftIndex = try self.tu.global.nodes.appendIndex(alloc, Node{
            .tag = .init(tag),
            .tokenIndex = .init(opIndex),
            .data = .{ .init(leftIndex), .init(right) },
        });
    }

    return leftIndex;
}

fn parseTerm(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    const nextToken = self.peek()[0];

    try Report.expect(alloc, reports, nextToken, &[_]Lexer.Token.Type{ .numberLiteral, .openParen, .minus, .iden });

    switch (nextToken.tag) {
        .numberLiteral => {
            return try self.tu.global.nodes.appendIndex(alloc, .{
                .tag = .init(.lit),
                .tokenIndex = .init(self.pop()[1]),
            });
        },
        .iden => {
            return try self.tu.global.nodes.appendIndex(alloc, .{
                .tag = .init(.load),
                .tokenIndex = .init(self.pop()[1]),
            });
        },
        .minus => {
            const op, const opIndex = self.pop();

            const expr = try self.parseTerm(alloc, reports);

            return try self.tu.global.nodes.appendIndex(alloc, .{
                .tag = .init(switch (op.tag) {
                    .minus => .neg,
                    else => unreachable,
                }),
                .tokenIndex = .init(opIndex),
                .data = .{ .init(expr), .init(0) },
            });
        },
        .openParen => {
            self.depth += 1;

            _ = self.pop();

            const expr = try self.parseExpression(alloc, reports);
            try Report.expect(alloc, reports, self.peek()[0], &.{.closeParen});

            _ = self.pop();

            assert(self.depth != 0);
            self.depth -= 1;

            return expr;
        },
        else => unreachable,
    }
}

const Node = @import("Node.zig");
const Expression = @import("Expression.zig");
pub const mod = @import("mod.zig");

const Util = @import("../Util.zig");
const Lexer = @import("../Lexer/mod.zig");
const Report = @import("../Report/mod.zig");
const TranslationUnit = @import("../TranslationUnit.zig");

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
