pub const NodeIndex = u32;
pub const TokenIndex = u32;
pub const NodeList = std.ArrayList(Node);

tu: *const TranslationUnit,

index: TokenIndex = 0,

nodeList: NodeList,

errors: std.ArrayList(UnexpectedToken),

depth: NodeIndex = 0,

pub fn init(tu: *const TranslationUnit) Allocator.Error!@This() {
    return @This(){
        .tu = tu,

        .nodeList = .{},

        .errors = .{},
    };
}

pub fn deinit(self: *@This(), alloc: Allocator) void {
    self.errors.deinit(alloc);
}

pub fn expect(self: *@This(), alloc: Allocator, token: Lexer.Token, t: []const Lexer.TokenType) std.mem.Allocator.Error!bool {
    const is = Util.listContains(Lexer.TokenType, t, token.tag);
    if (!is) {
        const ex = try alloc.dupe(Lexer.TokenType, t);
        try self.errors.append(alloc, UnexpectedToken{
            .expected = ex,
            .found = token.tag,
            .loc = token.loc,
        });
    }

    return is;
}
fn peek(self: *@This()) struct { Lexer.Token, TokenIndex } {
    return self.peekMany(0);
}

fn peekMany(self: *@This(), n: NodeIndex) struct { Lexer.Token, TokenIndex } {
    std.debug.assert(self.index + n < self.tu.cont.tokens.len);
    return .{ self.tu.cont.tokens[self.index + n], self.index };
}

fn popIf(self: *@This(), t: Lexer.TokenType) ?struct { Lexer.Token, TokenIndex } {
    if (self.tu.cont.tokens[self.index].tag != t) return null;
    const tuple = .{ self.tu.cont.tokens[self.index], self.index };
    self.index += 1;
    return tuple;
}

fn pop(self: *@This()) struct { Lexer.Token, TokenIndex } {
    const tuple = .{ self.tu.cont.tokens[self.index], self.index };
    self.index += 1;
    return tuple;
}

pub fn parse(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error)!NodeList {
    try self.parseRoot(alloc);
    return self.nodeList;
}

fn parseRoot(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error)!void {
    try self.nodeList.append(alloc, .{ .tag = .root, .data = .{ 1, 0 } });

    var t, _ = self.peek();
    while (t.tag != .EOF) : (t, _ = self.peek()) {
        if (!try self.expect(alloc, t, &.{.iden})) return;
        const top = self.nodeList.items.len;

        const nodeIndex = switch (t.tag) {
            .iden => self.parseVariableDecl(alloc),
            // .let => unreachable,
            else => unreachable,
        } catch |err| switch (err) {
            error.UnexpectedToken => {
                _ = top;
                @panic("Can not do this when is multithreaded");
                // self.nodeList.shrinkRetainingCapacity(top);
                // continue;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        self.nodeList.items[nodeIndex].next = @intCast(self.nodeList.items.len);

        _ = self.popIf(.semicolon);
    }

    self.nodeList.items[0].data[1] = @intCast(self.nodeList.items.len);
}

fn parseFuncDecl(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!?NodeIndex {
    if (self.peek()[0].tag != .openParen or self.peekMany(1)[0].tag != .closeParen) return null;

    const funcProto = self.parseFuncProto(alloc) catch |err| switch (err) {
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

    if (self.peek()[0].tag != .openBrace) {
        self.nodeList.items[funcProto].next = @intCast(self.nodeList.items.len);
        try self.parseStatement(alloc);
    } else {
        const p = try self.parseScope(alloc);
        self.nodeList.items[funcProto].next = p;
    }

    return funcProto;
}

fn parseFuncProto(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    const nodeIndex = try nl.addNode(alloc, &self.nodeList, .{
        .tag = .funcProto,
        .data = .{ 0, 0 },
    });

    _ = self.pop();
    // TODO: Parse arguments
    _ = self.pop();

    {
        const p = self.parseType(alloc) catch |err| switch (err) {
            error.UnexpectedToken => {
                _ = self.pop();
                return err;
            },
            else => return err,
        };
        self.nodeList.items[nodeIndex].data[1] = p;
    }

    return nodeIndex;
}

fn parseTypeFunction(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    std.debug.assert(Util.listContains(Lexer.TokenType, &.{.openParen}, self.peek()[0].tag));

    if (!try self.expect(alloc, self.peek()[0], &.{.openParen})) return error.UnexpectedToken;
    _, const initI = self.pop();
    if (!try self.expect(alloc, self.peek()[0], &.{.closeParen})) return error.UnexpectedToken;
    _ = self.pop();

    const x = try self.parseType(alloc);

    const node = Node{
        .tag = .funcType,
        .data = .{ 0, x },
        .tokenIndex = initI,
    };

    return try nl.addNode(alloc, &self.nodeList, node);
}

fn parseTypePrimitive(self: *@This(), alloc: Allocator) std.mem.Allocator.Error!NodeIndex {
    std.debug.assert(Util.listContains(Lexer.TokenType, &.{ .unsigned8, .unsigned16, .unsigned32, .unsigned64, .signed8, .signed16, .signed32, .signed64 }, self.peek()[0].tag));
    _, const mainIndex = self.pop();

    const nodeIndex = try nl.addNode(alloc, &self.nodeList, .{
        .tokenIndex = mainIndex,
        .tag = .typeExpression,
        .data = .{ 0, 0 },
    });

    return nodeIndex;
}
fn parseType(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    if (!try self.expect(alloc, self.peek()[0], &.{ .openParen, .unsigned8, .unsigned16, .unsigned32, .unsigned64, .signed8, .signed16, .signed32, .signed64 })) return error.UnexpectedToken;
    if (self.peek()[0].tag == .openParen) {
        return try self.parseTypeFunction(alloc);
    } else {
        return try self.parseTypePrimitive(alloc);
    }
}

fn parseScope(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    _ = self.popIf(.openBrace) orelse unreachable;

    const nodeIndex = try nl.addNode(alloc, &self.nodeList, .{
        .tag = .scope,
        .data = .{ 0, 0 },
    });

    self.nodeList.items[nodeIndex].data[0] = nodeIndex + 1;

    while (self.peek()[0].tag != .closeBrace) {
        const top = self.nodeList.items.len;
        self.parseStatement(alloc) catch |err| switch (err) {
            error.UnexpectedToken => {
                _ = top;
                @panic("Can not do this when is multithreaded");
                // self.nodeList.shrinkRetainingCapacity(top);
                // while (self.peek()[0].tag != .semicolon) : (_ = self.pop()) {}
                // _ = self.pop();
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    if (!try self.expect(alloc, self.peek()[0], &.{.closeBrace})) return error.UnexpectedToken;
    _ = self.pop();

    self.nodeList.items[nodeIndex].data[1] = @intCast(self.nodeList.items.len);

    return nodeIndex;
}

fn parseStatement(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!void {
    if (!try self.expect(alloc, self.peek()[0], &.{ .ret, .iden })) return error.UnexpectedToken;

    const nodeIndex = switch (self.peek()[0].tag) {
        .ret => try self.parseReturn(alloc),
        .iden => try self.parseVariableDecl(alloc),
        else => unreachable,
    };

    if (!try self.expect(alloc, self.peek()[0], &.{.semicolon})) return error.UnexpectedToken;
    _ = self.pop();

    self.nodeList.items[nodeIndex].next = @intCast(self.nodeList.items.len);
    return;
}

fn parseVariableDecl(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    _, const nameIndex = self.popIf(.iden) orelse unreachable;

    const index = try nl.reserveNode(alloc, &self.nodeList, .{
        .tag = Node.Tag.variable,
        .tokenIndex = nameIndex,
        .data = .{ 0, 0 },
    });

    if (!try self.expect(alloc, self.peek()[0], &.{.colon})) return error.UnexpectedToken;
    _ = self.pop();

    const possibleType = self.peek()[0];

    if (possibleType.tag != .colon and possibleType.tag != .equal) {
        {
            const p = try self.parseType(alloc);
            self.nodeList.items[index].data[0] = p;
        }
    }

    const possibleExpr = self.peek()[0];
    var func = false;

    if (possibleExpr.tag == .colon or possibleExpr.tag == .equal) {
        if (self.pop()[0].tag == .colon)
            self.nodeList.items[index].tag = .constant;

        {
            const p = try self.parseExpression(alloc);
            self.nodeList.items[index].data[1] = p;
        }

        func = self.nodeList.items[self.nodeList.items[index].data[1]].tag == .funcProto;
    }

    if (!func and !try self.expect(alloc, self.peek()[0], &.{.semicolon})) return error.UnexpectedToken;

    return index;
}

fn parseReturn(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    _, const retIndex = self.popIf(.ret) orelse unreachable;

    const nodeIndex = try nl.addNode(alloc, &self.nodeList, .{
        .tag = .ret,
        .tokenIndex = retIndex,
        .data = .{ 0, 0 },
    });

    std.debug.assert(self.depth == 0);
    const exp = try self.parseExpression(alloc);
    std.debug.assert(self.depth == 0);

    self.nodeList.items[nodeIndex].data[0] = exp;

    if (!try self.expect(alloc, self.peek()[0], &.{.semicolon})) return error.UnexpectedToken;

    return nodeIndex;
}

fn parseExpression(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    if (try self.parseFuncDecl(alloc)) |index| return index;
    return self.parseExpr(alloc, 1);
}

fn parseExpr(self: *@This(), alloc: Allocator, minPrecedence: u8) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
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

        leftIndex = try nl.addNode(alloc, &self.nodeList, Node{
            .tag = tag,
            .tokenIndex = opIndex,
            .data = .{ leftIndex, right },
        });
    }

    return leftIndex;
}

fn parseTerm(self: *@This(), alloc: Allocator) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    const nextToken = self.peek()[0];

    if (!try self.expect(alloc, nextToken, &[_]Lexer.TokenType{ .numberLiteral, .openParen, .minus, .iden })) return error.UnexpectedToken;

    switch (nextToken.tag) {
        .numberLiteral => {
            return try nl.addNode(alloc, &self.nodeList, .{
                .tag = .lit,
                .tokenIndex = self.pop()[1],
                .data = .{ 0, 0 },
            });
        },
        .iden => {
            return try nl.addNode(alloc, &self.nodeList, .{
                .tag = .load,
                .tokenIndex = self.pop()[1],
                .data = .{ 0, 0 },
            });
        },
        .minus => {
            const op, const opIndex = self.pop();

            const expr = try self.parseTerm(alloc);

            return try nl.addNode(alloc, &self.nodeList, .{
                .tag = switch (op.tag) {
                    .minus => .neg,
                    else => unreachable,
                },
                .tokenIndex = opIndex,
                .data = .{ expr, 0 },
            });
        },
        .openParen => {
            self.depth += 1;

            _ = self.pop();

            const expr = try self.parseExpression(alloc);
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

const Lexer = @import("../Lexer/Lexer.zig");

const TranslationUnit = @import("../TranslationUnit.zig");

pub const Node = @import("Node.zig");
pub const UnexpectedToken = @import("UnexpectedToken.zig");
pub const nl = @import("./NodeListUtil.zig");
pub const Expression = @import("Expression.zig");
pub const Ast = @import("Ast.zig");
