tu: *const TranslationUnit,

index: mod.TokenIndex = 0,

nodeList: *mod.NodeList,

errors: std.ArrayList(UnexpectedToken),

depth: mod.NodeIndex = 0,

pub fn init(tu: *const TranslationUnit, chunk: *mod.NodeList) Allocator.Error!@This() {
    return @This(){
        .tu = tu,

        .nodeList = chunk,

        .errors = .{},
    };
}

pub fn deinit(self: *@This(), alloc: Allocator) void {
    self.errors.deinit(alloc);
}

pub fn expect(self: *@This(), alloc: Allocator, token: Lexer.Token, t: []const Lexer.Token.Type) std.mem.Allocator.Error!bool {
    const is = Util.listContains(Lexer.Token.Type, t, token.tag);
    if (!is) {
        const ex = try alloc.dupe(Lexer.Token.Type, t);
        try self.errors.append(alloc, UnexpectedToken{
            .expected = ex,
            .found = token.tag,
            .loc = token.loc,
        });
    }

    return is;
}
fn peek(self: *const @This()) struct { Lexer.Token, mod.TokenIndex } {
    return self.peekMany(0);
}

fn peekMany(self: *const @This(), n: mod.NodeIndex) struct { Lexer.Token, mod.TokenIndex } {
    std.debug.assert(self.index + n < self.tu.cont.tokens.len);
    return .{ self.tu.cont.tokens[self.index + n], self.index };
}

fn popIf(self: *@This(), t: Lexer.Token.Type) ?struct { Lexer.Token, mod.TokenIndex } {
    if (self.tu.cont.tokens[self.index].tag != t) return null;
    const tuple = .{ self.tu.cont.tokens[self.index], self.index };
    self.index += 1;
    return tuple;
}

fn pop(self: *@This()) struct { Lexer.Token, mod.TokenIndex } {
    const tuple = .{ self.tu.cont.tokens[self.index], self.index };
    self.index += 1;
    return tuple;
}

pub fn parseFunction(self: *@This(), alloc: Allocator, start: mod.TokenIndex, placeHolder: mod.NodeIndex) (Allocator.Error)!void {
    self.index = start;
    std.debug.assert(self.isFunction());

    const index = self.parseFuncDecl(alloc) catch |err| {
        switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            // TODO: Error Recovery
            // I think error recovery when reaches here is must fail;
            else => @panic("Do not know what to do"),
        }
    };

    if (self.nodeList.getPtr(placeHolder).data[1].cmpxchgStrong(0, index, .acq_rel, .monotonic) != null) @panic("This belongs to this thread and currently is not being passed to another thread");

    std.debug.assert(self.nodeList.get(placeHolder).data.@"1".load(.acquire) == index);
}

pub fn parseRoot(self: *@This(), alloc: Allocator, start: mod.TokenIndex, placeHolder: mod.NodeIndex) (std.mem.Allocator.Error)!void {
    self.index = start;

    const index = try self._parseRoot(alloc);

    if (self.nodeList.getPtr(placeHolder).data[1].cmpxchgStrong(0, index, .acq_rel, .monotonic) != null) @panic("This belongs to this thread and currently is not being passed to another thread");
}

fn _parseRoot(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error)!mod.NodeIndex {
    var firstIndex: mod.NodeIndex = 0;
    var lastNodeParsed: mod.NodeIndex = 0;

    var t, _ = self.peek();

    t, _ = self.peek();

    while (t.tag != .EOF) : (t, _ = self.peek()) {
        if (!try self.expect(alloc, t, &.{.iden})) @panic("Error recovery");

        const nodeIndex = switch (t.tag) {
            .iden => self.parseVariableDecl(alloc),
            else => unreachable,
        } catch |err| switch (err) {
            error.UnexpectedToken => {
                @panic("Can not do this when is multithreaded");
                // self.nodeList.shrinkRetainingCapacity(top);
                // continue;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };

        if (firstIndex == 0) {
            firstIndex = nodeIndex;
        } else {
            if (self.nodeList.getPtr(lastNodeParsed).next.cmpxchgStrong(0, nodeIndex, .acq_rel, .monotonic) != null) @panic("This is controlled by this thread and it should not be influenced by others");
        }

        lastNodeParsed = nodeIndex;
        _ = self.popIf(.semicolon);
    }

    return try self.nodeList.appendIndex(
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

fn skipFunction(self: *@This()) void {
    std.debug.assert(self.isFunction());

    //TODO: Error Recovery
    _ = self.popIf(.openParen) orelse unreachable;
    // TODO: Arguments
    _ = self.popIf(.closeParen) orelse unreachable;

    self.skipType();

    if (self.peek()[0].tag == .openBrace) {
        const depth = self.depth;

        _ = self.pop();
        self.depth += 1;

        while (depth != self.depth) {
            const token = self.pop();
            switch (token[0].tag) {
                .openBrace => self.depth += 1,
                .closeBrace => self.depth -= 1,
                else => {},
            }
        }
    } else {
        while (self.peek()[0].tag != .semicolon) : (_ = self.pop()) {}
        _ = self.pop();
    }
}

fn skipType(self: *@This()) void {
    //TODO: Error Recovery

    if (!Util.listContains(Lexer.Token.Type, &.{ .openParen, .iden }, self.peek()[0].tag)) unreachable;

    if (self.peek()[0].tag == .openParen) {
        _ = self.popIf(.openParen) orelse unreachable;
        // TODO: Arguments types
        _ = self.popIf(.closeParen) orelse unreachable;

        _ = self.pop();
    } else {
        _ = self.pop();
    }
}

// TODO: Join fuction parseFuncDecl and ParseFuncProto
fn parseFuncDecl(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    var funcProtoNode = self.parseFuncProto(alloc) catch |err| switch (err) {
        error.UnexpectedToken => {
            if (self.peek()[0].tag != .openBrace) {
                var depth: usize = 1;
                while (depth > 0) {
                    const token, _ = self.pop();
                    switch (token.tag) {
                        .openBrace => depth += 1,
                        .closeBrace => depth -= 1,
                        else => {},
                    }
                }
            } else {
                while (self.peek()[0].tag != .semicolon) : (_ = self.pop()) {}
                _ = self.pop();
            }
            return error.UnexpectedToken;
        },
        else => return error.OutOfMemory,
    };

    funcProtoNode.next.store(
        if (self.peek()[0].tag == .openBrace) try self.parseScope(alloc) else try self.parseStatement(alloc),
        .release,
    );

    return self.nodeList.appendIndex(alloc, funcProtoNode);
}

fn parseFuncProto(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!Node {
    if (!try self.expect(alloc, self.pop()[0], &.{.openParen})) return error.UnexpectedToken;
    // TODO: Parse arguments
    if (!try self.expect(alloc, self.pop()[0], &.{.closeParen})) return error.UnexpectedToken;

    const p = self.parseType(alloc) catch |err| switch (err) {
        error.UnexpectedToken => {
            _ = self.pop();
            return err;
        },
        else => return err,
    };

    const nodeIndex: Node = .{ .tag = .init(.funcProto), .data = .{ .init(0), .init(p) } };

    return nodeIndex;
}

fn parseTypeFunction(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    std.debug.assert(Util.listContains(Lexer.Token.Type, &.{.openParen}, self.peek()[0].tag));

    if (!try self.expect(alloc, self.peek()[0], &.{.openParen})) return error.UnexpectedToken;
    _, const initI = self.pop();
    if (!try self.expect(alloc, self.peek()[0], &.{.closeParen})) return error.UnexpectedToken;
    _ = self.pop();

    const x = try self.parseType(alloc);

    const node = Node{
        .tag = .init(.funcType),
        .data = .{ .init(0), .init(x) },
        .tokenIndex = .init(initI),
    };

    return try self.nodeList.appendIndex(alloc, node);
}

fn parseType(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    if (!try self.expect(alloc, self.peek()[0], &.{ .openParen, .iden })) return error.UnexpectedToken;
    if (self.peek()[0].tag == .openParen) {
        return try self.parseTypeFunction(alloc);
    } else {
        _, const tokenIndex = self.pop();
        return try self.nodeList.appendIndex(alloc, .{
            .tag = .init(.fakeType),
            .tokenIndex = .init(tokenIndex),
        });
    }
}

fn parseScope(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    var firstIndex: mod.NodeIndex = 0;
    var lastNodeParsed: mod.NodeIndex = 0;

    _ = self.popIf(.openBrace) orelse unreachable;

    while (self.peek()[0].tag != .closeBrace) {
        const nodeIndex = self.parseStatement(alloc) catch |err| switch (err) {
            error.UnexpectedToken => {
                @panic("Can not do this when is multithreaded");
                // self.nodeList.shrinkRetainingCapacity(top);
                // while (self.peek()[0].tag != .semicolon) : (_ = self.pop()) {}
                // _ = self.pop();
            },
            error.OutOfMemory => return error.OutOfMemory,
        };

        if (firstIndex == 0) {
            firstIndex = nodeIndex;
        } else {
            if (self.nodeList.getPtr(lastNodeParsed).next.cmpxchgStrong(0, nodeIndex, .acq_rel, .monotonic) != null) @panic("This is controlled by this thread and it should not be influenced by others");
        }

        lastNodeParsed = nodeIndex;
    }

    if (!try self.expect(alloc, self.peek()[0], &.{.closeBrace})) return error.UnexpectedToken;
    _ = self.pop();

    const nodeIndex = try self.nodeList.appendIndex(alloc, .{
        .tag = .init(.scope),
        .data = .{ .init(firstIndex), .init(0) },
    });

    return nodeIndex;
}

fn parseStatement(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    if (!try self.expect(alloc, self.peek()[0], &.{ .ret, .iden })) return error.UnexpectedToken;

    const nodeIndex = switch (self.peek()[0].tag) {
        .ret => try self.parseReturn(alloc),
        .iden => try self.parseVariableDecl(alloc),
        else => unreachable,
    };

    if (!try self.expect(alloc, self.peek()[0], &.{.semicolon})) return error.UnexpectedToken;
    _ = self.pop();

    return nodeIndex;
}

fn parseVariableDecl(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    _, const nameIndex = self.popIf(.iden) orelse unreachable;

    const index = try self.nodeList.appendIndex(alloc, .{
        .tag = .init(Node.Tag.variable),
        .tokenIndex = .init(nameIndex),
    });

    const node = self.nodeList.getPtr(index);

    if (!try self.expect(alloc, self.peek()[0], &.{.colon})) return error.UnexpectedToken;
    _ = self.pop();

    const possibleType = self.peek()[0];

    if (possibleType.tag != .colon and possibleType.tag != .equal)
        node.data[0].store(try self.parseType(alloc), .release);

    const possibleExpr = self.peek()[0];

    var expr: mod.NodeIndex = 0;

    if (possibleExpr.tag == .colon or possibleExpr.tag == .equal) {
        if (self.pop()[0].tag == .colon)
            node.tag = .init(.constant);

        expr = try self.parseExpression(alloc, index);

        if (expr != 0)
            node.data[1].store(expr, .release);
    }

    if (expr != 0 and !try self.expect(alloc, self.peek()[0], &.{.semicolon}))
        return error.UnexpectedToken;

    return index;
}

fn parseReturn(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    _, const retIndex = self.popIf(.ret) orelse unreachable;

    const nodeIndex = try self.nodeList.appendIndex(alloc, .{
        .tag = .init(.ret),
        .tokenIndex = .init(retIndex),
    });
    const exp = try self.parseExpression(alloc, nodeIndex);

    const node = self.nodeList.getPtr(nodeIndex);

    node.data[1].store(exp, .release);

    if (exp != 0 and !try self.expect(alloc, self.peek()[0], &.{.semicolon})) return error.UnexpectedToken;

    return nodeIndex;
}

// NOTE: Returns 0 if is a function
fn parseExpression(self: *@This(), alloc: Allocator, index: mod.NodeIndex) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    if (self.isFunction()) {
        assert(index != 0);
        const start = self.index;

        self.skipFunction();

        try (try self.tu.initFunc(alloc)).startFunction(alloc, self.nodeList, start, index);

        return 0;
    } else {
        return self.parseExpr(alloc, 1);
    }
}

fn parseExpr(self: *@This(), alloc: Allocator, minPrecedence: u8) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    var nextToken = self.peek()[0];
    if (nextToken.tag == .semicolon) @panic("Void return is not implemented");

    var leftIndex = try self.parseTerm(alloc);
    nextToken = self.peek()[0];

    while (nextToken.tag != .semicolon and nextToken.tag != .closeParen) : (nextToken = self.peek()[0]) {
        const op, const opIndex = self.peek();
        if (!try self.expect(alloc, op, &.{ .plus, .minus, .asterik, .slash, .caret })) return error.UnexpectedToken;

        const tag: Node.Tag = Expression.tokenTagToNodeTag(op.tag);
        const prec = Expression.operandPresedence(tag);
        if (prec < minPrecedence) break;

        _ = self.pop();

        const nextMinPrec = if (Expression.operandAssociativity(tag) == Expression.Associativity.left) prec + 1 else prec;

        const right = try self.parseExpr(alloc, nextMinPrec);

        leftIndex = try self.nodeList.appendIndex(alloc, Node{
            .tag = .init(tag),
            .tokenIndex = .init(opIndex),
            .data = .{ .init(leftIndex), .init(right) },
        });
    }

    return leftIndex;
}

fn parseTerm(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!mod.NodeIndex {
    const nextToken = self.peek()[0];

    if (!try self.expect(alloc, nextToken, &[_]Lexer.Token.Type{ .numberLiteral, .openParen, .minus, .iden })) return error.UnexpectedToken;

    switch (nextToken.tag) {
        .numberLiteral => {
            return try self.nodeList.appendIndex(alloc, .{
                .tag = .init(.lit),
                .tokenIndex = .init(self.pop()[1]),
            });
        },
        .iden => {
            return try self.nodeList.appendIndex(alloc, .{
                .tag = .init(.load),
                .tokenIndex = .init(self.pop()[1]),
            });
        },
        .minus => {
            const op, const opIndex = self.pop();

            const expr = try self.parseTerm(alloc);

            return try self.nodeList.appendIndex(alloc, .{
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

            const expr = try self.parseExpression(alloc, 0);
            if (!try self.expect(alloc, self.peek()[0], &.{.closeParen})) return error.UnexpectedToken;

            _ = self.pop();

            std.debug.assert(self.depth != 0);
            self.depth -= 1;

            return expr;
        },
        else => unreachable,
    }
}

pub fn lexerToString(self: *@This(), alloc: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    var al = std.ArrayList(u8){};

    for (self.tu.cont.tokens) |value| {
        try value.toString(alloc, &al, self.tu.cont.path, self.tu.cont.source);
    }

    return al.toOwnedSlice(alloc);
}

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Util = @import("../Util.zig");

const Lexer = @import("../Lexer/mod.zig");

const TranslationUnit = @import("../TranslationUnit.zig");

const Node = @import("Node.zig");
const UnexpectedToken = @import("UnexpectedToken.zig");
const Expression = @import("Expression.zig");
const Ast = @import("Ast.zig");

pub const mod = @import("mod.zig");
