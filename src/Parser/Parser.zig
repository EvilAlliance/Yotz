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

fn popUnil(self: *@This(), tokenType: []const Lexer.Token.Type) void {
    var peeked = self.peek()[0].tag;
    while (!Util.listContains(Lexer.Token.Type, tokenType, peeked) and peeked != .EOF) : (peeked = self.peek()[0].tag) {
        _ = self.pop();
    }
}

pub fn parseFunction(self: *@This(), alloc: Allocator, start: mod.TokenIndex, placeHolder: *Parser.Node.FuncProto, reports: ?*Report.Reports) (Allocator.Error || Error)!void {
    self.index = start;

    const index = if (self.peek()[0].tag == .openBrace) try self.parseScope(alloc, reports) else try self.parseStatement(alloc, reports);

    if (placeHolder.scope.cmpxchgStrong(0, index, .acq_rel, .monotonic) != null) @panic("This belongs to this thread and currently is not being passed to another thread");
}

pub fn parseRoot(self: *@This(), alloc: Allocator, start: mod.TokenIndex, placeHolder: *Parser.Node.Entry, reports: ?*Report.Reports) (std.mem.Allocator.Error)!void {
    self.index = start;

    const index = try self._parseRoot(alloc, reports);

    if (placeHolder.firstRoot.cmpxchgStrong(0, index, .acq_rel, .monotonic) != null) @panic("This belongs to this thread and currently is not being passed to another thread");
}

fn _parseRoot(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error)!mod.NodeIndex {
    var firstIndex: mod.NodeIndex = 0;
    var lastNodeParsed: mod.NodeIndex = 0;

    var t, _ = self.peek();

    while (t.tag != .EOF) : (t, _ = self.peek()) {
        Report.expect(reports, t, &.{.iden}) catch |err|
            switch (err) {
                Error.UnexpectedToken => {
                    self.popUnil(&.{.iden});
                    continue;
                },
            };

        const nodeIndex = switch (t.tag) {
            .iden => self.parseVariableDecl(alloc, reports),
            else => std.debug.panic("Found {}", .{t}),
        } catch |err| switch (err) {
            error.UnexpectedToken => {
                self.popUnil(&.{.iden});
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

    const root: Node.Root = .{
        .firstStmt = .init(firstIndex),
        .endStmt = .init(0),
    };

    return try self.tu.global.nodes.appendIndex(alloc, root.asConst().*);
}

fn isFunction(self: *const @This()) bool {
    if (self.peek()[0].tag != .openParen) return false;
    if (self.peekMany(1)[0].tag == .closeParen) return true;

    const i: mod.TokenIndex = 1;

    const idenI = i;
    const colonI = i + 1;

    if (self.peekMany(idenI)[0].tag != .iden or
        self.peekMany(colonI)[0].tag != .colon) return false;

    return true;
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
    const token, const tokenIndex = self.pop();
    try Report.expect(reports, token, &.{.openParen});
    const args = try self.parseArgs(alloc, reports);
    try Report.expect(reports, self.pop()[0], &.{.closeParen});

    const p = try self.parseType(alloc, reports);
    const funcProto: Node.FuncProto = .{
        .args = .init(args),
        .tokenIndex = .init(tokenIndex),
        .retType = .init(p),
    };

    const nodeIndex = try self.tu.global.nodes.appendIndex(alloc, funcProto.asConst().*);

    return nodeIndex;
}

fn parseArgs(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (Allocator.Error || Error)!mod.NodeIndex {
    if (self.peek().@"0".tag == .closeParen) return 0;

    const firstArg = try self.tu.global.nodes.reserve(alloc);
    var currentArg = firstArg;

    var count: Parser.NodeIndex = 0;

    while (true) {
        count += 1;

        try Report.expect(reports, self.peek()[0], &.{.iden});
        _, const nameI = self.pop();
        try Report.expect(reports, self.peek()[0], &.{.colon});
        _ = self.pop();

        const protoArg: Node.ProtoArg = .{
            .tokenIndex = .init(nameI),
            .type = .init(try self.parseType(alloc, reports)),
        };
        currentArg.* = protoArg.asConst().*;

        if (self.peek().@"0".tag != .coma) break;
        _ = self.pop();

        if (self.peek().@"0".tag == .closeParen) break;

        const nextArg = try self.tu.global.nodes.reserve(alloc);
        currentArg.next.store(self.tu.global.nodes.indexOf(nextArg), .release);
        currentArg = nextArg;
    }

    var it = firstArg.asProtoArg().iterate(self.tu.global);

    while (it.next()) |arg| : (count -= 1)
        arg.count.store(count, .release);

    return self.tu.global.nodes.indexOf(firstArg);
}

fn parseTypeFunction(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    assert(Util.listContains(Lexer.Token.Type, &.{.openParen}, self.peek()[0].tag));

    try Report.expect(reports, self.peek()[0], &.{.openParen});
    _, const initI = self.pop();
    const args = try self.parseTypeFunctionArgs(alloc, reports);
    try Report.expect(reports, self.peek()[0], &.{.closeParen});
    _ = self.pop();

    const x = try self.parseType(alloc, reports);

    const node = Node.FakeFuncType{
        .tokenIndex = .init(initI),

        .fakeArgsType = .init(args),
        .fakeRetType = .init(x),
    };

    return try self.tu.global.nodes.appendIndex(alloc, node.asConst().*);
}

fn parseTypeFunctionArgs(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (Allocator.Error || Error)!mod.NodeIndex {
    if (self.peek().@"0".tag == .closeParen) return 0;

    const firstArg = try self.tu.global.nodes.reserve(alloc);
    var currentArg = firstArg;

    var count: Parser.NodeIndex = 0;

    while (true) {
        count += 1;
        const nameToken = self.peek();
        try Report.expect(reports, nameToken.@"0", &.{.iden});

        const hasName = self.peekMany(1).@"0".tag == .colon;
        const typeIndex = if (hasName) blk: {
            _ = self.pop(); // consume name
            _ = self.pop(); // consume colon
            break :blk try self.parseType(alloc, reports);
        } else try self.parseType(alloc, reports);

        const argType = Node.FakeArgType{
            .tag = .init(.fakeArgType),
            .tokenIndex = .init(nameToken.@"1"),
            .count = .init(0),
            .fakeType = .init(typeIndex),
            .flags = .init(.{ .hasName = hasName }),
        };
        currentArg.* = argType.asConst().*;

        if (self.peek().@"0".tag != .coma) break;
        _ = self.pop();

        if (self.peek().@"0".tag == .closeParen) break;

        const nextArg = try self.tu.global.nodes.reserve(alloc);
        currentArg.next.store(self.tu.global.nodes.indexOf(nextArg), .release);
        currentArg = nextArg;
    }
    var it = firstArg.asFakeArgType().iterate(self.tu.global);

    while (it.next()) |arg| : (count -= 1)
        arg.count.store(count, .release);

    return self.tu.global.nodes.indexOf(firstArg);
}

fn parseType(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    try Report.expect(reports, self.peek()[0], &.{ .openParen, .iden });
    var index: mod.NodeIndex = 0;
    if (self.peek()[0].tag == .openParen) {
        index = try self.parseTypeFunction(alloc, reports);
    } else {
        _, const tokenIndex = self.pop();
        index = try self.tu.global.nodes.appendIndex(alloc, (Node.FakeType{
            .tokenIndex = .init(tokenIndex),
        }).asConst().*);
    }

    Typing.Type.transformType(self.tu.global, self.tu.global.nodes.getPtr(index).asFakeTypes());

    return index;
}

fn parseScope(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    var firstIndex: mod.NodeIndex = 0;
    var lastNodeParsed: mod.NodeIndex = 0;

    _ = self.popIf(.openBrace) orelse unreachable;

    var peeked = self.peek()[0].tag;
    while (peeked != .closeBrace and peeked != .EOF) : (peeked = self.peek()[0].tag) {
        const nodeIndex = self.parseStatement(alloc, reports) catch |err| switch (err) {
            error.UnexpectedToken => {
                _ = self.popIf(.ret) orelse self.popIf(.iden);
                self.popUnil(&.{ .ret, .iden, .closeBrace });
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

    try Report.expect(reports, self.peek()[0], &.{.closeBrace});
    _ = self.pop();

    const scope: Node.Scope = .{
        .firstStmt = .init(firstIndex),
    };

    const nodeIndex = try self.tu.global.nodes.appendIndex(alloc, scope.asConst().*);

    return nodeIndex;
}

fn parseStatement(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || Error)!mod.NodeIndex {
    try Report.expect(reports, self.peek()[0], &.{ .ret, .iden });

    const nodeIndex = switch (self.peek()[0].tag) {
        .ret => try self.parseReturn(alloc, reports),
        .iden => blk: {
            try Report.expect(reports, self.peekMany(1)[0], &.{ .colon, .equal });

            break :blk switch (self.peekMany(1).@"0".tag) {
                .colon => try self.parseVariableDecl(alloc, reports),
                .equal => try self.parseAssigment(alloc, reports),
                else => unreachable,
            };
        },
        else => unreachable,
    };

    _ = self.popIf(.semicolon);

    return nodeIndex;
}

fn parseVariableDecl(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    _, const nameIndex = self.popIf(.iden) orelse unreachable;

    const index = try self.tu.global.nodes.appendIndex(alloc, (Node.VarConst{
        .tag = .init(Node.Tag.variable),
        .tokenIndex = .init(nameIndex),
    }).asConst().*);

    const node = self.tu.global.nodes.getPtr(index);

    try Report.expect(reports, self.peek()[0], &.{.colon});
    _ = self.pop();

    const possibleType = self.peek()[0];

    if (possibleType.tag != .colon and possibleType.tag != .equal)
        node.left.store(try self.parseType(alloc, reports), .release);

    const possibleExpr = self.peek()[0];

    if (possibleExpr.tag == .colon or possibleExpr.tag == .equal) {
        if (self.pop()[0].tag == .colon)
            node.tag = .init(.constant);

        const expr = try self.parseExpression(alloc, reports);

        node.right.store(expr, .release);
    }

    _ = self.popIf(.semicolon);

    return index;
}

fn parseAssigment(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    _, const nameIndex = self.popIf(.iden) orelse unreachable;

    try Report.expect(reports, self.peek()[0], &.{.equal});
    _ = self.pop();

    const expr = try self.parseExpression(alloc, reports);

    const index = try self.tu.global.nodes.appendIndex(alloc, (Node.Assignment{
        .tokenIndex = .init(nameIndex),
        .expr = .init(expr),
    }).asConst().*);

    return index;
}

fn parseReturn(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    _, const retIndex = self.popIf(.ret) orelse unreachable;

    const ret: Node.Return = .{
        .tokenIndex = .init(retIndex),
    };
    const nodeIndex = try self.tu.global.nodes.appendIndex(alloc, ret.asConst().*);
    const exp = try self.parseExpression(alloc, reports);

    const node = self.tu.global.nodes.getPtr(nodeIndex).asRet();

    node.expr.store(exp, .release);

    _ = self.popIf(.semicolon);

    return nodeIndex;
}

fn parseCall(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (Allocator.Error || Error)!?mod.NodeIndex {
    if (self.peek().@"0".tag != .iden or self.peekMany(1).@"0".tag != .openParen) return null;

    const nameI = self.pop().@"1";
    _ = self.pop();

    const args = try self.parseCallArgs(alloc, reports);

    try Report.expect(reports, self.peek().@"0", &.{.closeParen});
    _ = self.pop();

    const firstCall = try self.tu.global.nodes.reserve(alloc);
    const call: Node.Call = .{
        .tokenIndex = .init(nameI),
        .firstArg = .init(args),
    };
    firstCall.* = call.asConst().*;

    var currentCall = firstCall.asCall();

    // Handle chained calls like ()()()
    while (self.peek().@"0".tag == .openParen) {
        const parenI = self.pop().@"1";

        const chainedArgs = try self.parseCallArgs(alloc, reports);

        try Report.expect(reports, self.peek().@"0", &.{.closeParen});
        _ = self.pop();

        const nextCall = try self.tu.global.nodes.reserve(alloc);
        const nextCallNode: Node.Call = .{
            .tokenIndex = .init(parenI),
            .firstArg = .init(chainedArgs),
        };
        nextCall.* = nextCallNode.asConst().*;
        currentCall.next.store(self.tu.global.nodes.indexOf(nextCall), .release);
        currentCall = nextCall.asCall();
    }

    return self.tu.global.nodes.indexOf(firstCall);
}

fn parseCallArgs(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (Allocator.Error || Error)!mod.NodeIndex {
    if (self.peek().@"0".tag == .closeParen) return 0;

    const firstArg = try self.tu.global.nodes.reserve(alloc);
    var currentArg = firstArg;

    var count: Parser.NodeIndex = 0;

    while (true) {
        count += 1;

        const argTokenIndex = self.peek().@"1";
        const expr = try self.parseExpression(alloc, reports);

        const callArg: Node.CallArg = .{
            .tokenIndex = .init(argTokenIndex),
            .expr = .init(expr),
        };
        currentArg.* = callArg.asConst().*;

        if (self.peek().@"0".tag == .closeParen) break;

        try Report.expect(reports, self.peek().@"0", &.{.coma});
        _ = self.pop();

        if (self.peek().@"0".tag == .closeParen) break;

        const nextArg = try self.tu.global.nodes.reserve(alloc);
        currentArg.next.store(self.tu.global.nodes.indexOf(nextArg), .release);
        currentArg = nextArg;
    }

    var it = firstArg.asCallArg().iterate(self.tu.global);

    while (it.next()) |arg| : (count -= 1)
        arg.count.store(count, .release);

    return self.tu.global.nodes.indexOf(firstArg);
}

fn parseExpression(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    if (self.isFunction()) {
        const index = try self.parseFuncProto(alloc, reports);

        const start = self.index;

        if (self.peek().@"0".tag == .openBrace) {
            self.skipBlock();
        } else {
            self.popUnil(&.{ .semicolon, .coma });
            _ = self.popIf(.semicolon);
        }

        try (try self.tu.initFunc(alloc)).startFunction(alloc, start, self.tu.global.nodes.getPtr(index).asFuncProto(), reports);

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
        try Report.expect(reports, op, &.{ .plus, .minus, .asterik, .slash, .caret, .semicolon, .closeParen });

        const tag: Node.Tag = Expression.tokenTagToNodeTag(op.tag);
        const prec = Expression.operandPresedence(tag);
        if (prec < minPrecedence) break;

        _ = self.pop();

        const nextMinPrec = if (Expression.operandAssociativity(tag) == Expression.Associativity.left) prec + 1 else prec;

        const right = try self.parseExpr(alloc, nextMinPrec, reports);

        leftIndex = try self.tu.global.nodes.appendIndex(alloc, (Node.BinaryOp{
            .tag = .init(tag),
            .tokenIndex = .init(opIndex),
            .left = .init(leftIndex),
            .right = .init(right),
        }).asConst().*);
    }

    return leftIndex;
}

fn parseTerm(self: *@This(), alloc: Allocator, reports: ?*Report.Reports) (std.mem.Allocator.Error || Error)!mod.NodeIndex {
    const nextToken = self.peek()[0];

    try Report.expect(reports, nextToken, &[_]Lexer.Token.Type{ .numberLiteral, .openParen, .minus, .iden });

    switch (nextToken.tag) {
        .numberLiteral => {
            return try self.tu.global.nodes.appendIndex(alloc, (Node.Literal{
                .tokenIndex = .init(self.pop()[1]),
            }).asConst().*);
        },
        .iden => {
            if (try self.parseCall(alloc, reports)) |i| return i;
            return try self.tu.global.nodes.appendIndex(alloc, (Node.Load{
                .tokenIndex = .init(self.pop()[1]),
            }).asConst().*);
        },
        .minus => {
            const op, const opIndex = self.pop();

            const expr = try self.parseTerm(alloc, reports);

            return try self.tu.global.nodes.appendIndex(alloc, (Node.UnaryOp{
                .tag = .init(switch (op.tag) {
                    .minus => .neg,
                    else => unreachable,
                }),
                .tokenIndex = .init(opIndex),
                .left = .init(expr),
                .right = .init(0),
            }).asConst().*);
        },
        .openParen => {
            self.depth += 1;

            _ = self.pop();

            const expr = try self.parseExpression(alloc, reports);
            try Report.expect(reports, self.peek()[0], &.{.closeParen});

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
const Parser = mod;

const Util = @import("../Util.zig");
const Lexer = @import("../Lexer/mod.zig");
const Report = @import("../Report/mod.zig");
const TranslationUnit = @import("../TranslationUnit.zig");
const Typing = @import("../Typing/mod.zig");

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
