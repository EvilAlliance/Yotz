const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Util = @import("../Util.zig");

const Lexer = @import("../Lexer/Lexer.zig");

pub const Node = @import("Node.zig");
pub const UnexpectedToken = @import("UnexpectedToken.zig");
pub const nl = @import("./NodeListUtil.zig");
pub const Expression = @import("Expression.zig");
pub const Ast = @import("Ast.zig");

pub const NodeIndex = u32;
pub const TokenIndex = u32;

alloc: Allocator,

index: TokenIndex = 0,
tokens: []Lexer.Token,
source: [:0]const u8,

path: []const u8,

nodeList: Ast.NodeList,

errors: std.ArrayList(UnexpectedToken),

depth: NodeIndex = 0,

pub fn init(alloc: Allocator, path: []const u8) ?@This() {
    const resolvedPath, const source = Util.readEntireFile(alloc, path) catch |err| {
        switch (err) {
            error.couldNotResolvePath => std.log.err("Could not resolve path: {s}\n", .{path}),
            error.couldNotOpenFile => std.log.err("Could not open file: {s}\n", .{path}),
            error.couldNotReadFile => std.log.err("Could not read file: {s}]n", .{path}),
            error.couldNotGetFileSize => std.log.err("Could not get file ({s}) size\n", .{path}),
        }
        return null;
    };

    return @This(){
        .alloc = alloc,
        .tokens = Lexer.lex(alloc, source) catch {
            std.log.err("Out of memory", .{});
            return null;
        },

        .source = source,

        .path = resolvedPath,

        .nodeList = .{},

        .errors = .{},
    };
}

pub fn deinit(self: *@This()) void {
    self.alloc.free(self.source);
    self.alloc.free(self.tokens);
    self.alloc.free(self.path);

    self.nodeList.deinit(self.alloc);

    self.errors.deinit(self.alloc);
}

pub fn expect(self: *@This(), token: Lexer.Token, t: []const Lexer.TokenType) std.mem.Allocator.Error!bool {
    const is = Util.listContains(Lexer.TokenType, t, token.tag);
    if (!is) {
        const ex = try self.alloc.dupe(Lexer.TokenType, t);
        try self.errors.append(self.alloc, UnexpectedToken{
            .expected = ex,
            .found = token.tag,
            .loc = token.loc,
            .alloc = self.alloc,
        });
    }

    return is;
}
fn peek(self: *@This()) struct { Lexer.Token, TokenIndex } {
    return self.peekMany(0);
}

fn peekMany(self: *@This(), n: NodeIndex) struct { Lexer.Token, TokenIndex } {
    std.debug.assert(self.index + n < self.tokens.len);
    return .{ self.tokens[self.index + n], self.index };
}

fn popIf(self: *@This(), t: Lexer.TokenType) ?struct { Lexer.Token, TokenIndex } {
    if (self.tokens[self.index].tag != t) return null;
    const tuple = .{ self.tokens[self.index], self.index };
    self.index += 1;
    return tuple;
}

fn pop(self: *@This()) struct { Lexer.Token, TokenIndex } {
    const tuple = .{ self.tokens[self.index], self.index };
    self.index += 1;
    return tuple;
}

pub fn parse(self: *@This()) (std.mem.Allocator.Error)!Ast {
    try self.parseRoot();
    return Ast.init(self.alloc, &self.nodeList, self.tokens, self.path, self.source);
}

fn parseRoot(self: *@This()) (std.mem.Allocator.Error)!void {
    try self.nodeList.insert(self.alloc, 0, .{ .tag = .root, .data = .{ 1, 0 } });

    var t, _ = self.peek();
    while (t.tag != .EOF) : (t, _ = self.peek()) {
        if (!try self.expect(t, &.{.iden})) return;
        const top = self.nodeList.items.len;

        const nodeIndex = switch (t.tag) {
            .iden => self.parseVariableDecl(),
            // .let => unreachable,
            else => unreachable,
        } catch |err| switch (err) {
            error.UnexpectedToken => {
                self.nodeList.shrinkRetainingCapacity(top);
                continue;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        self.nodeList.items[nodeIndex].next = @intCast(self.nodeList.items.len);

        _ = self.popIf(.semicolon);
    }

    self.nodeList.items[0].data[1] = @intCast(self.nodeList.items.len);
}

fn parseFuncDecl(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!?NodeIndex {
    if (self.peek()[0].tag != .openParen or self.peekMany(1)[0].tag != .closeParen) return null;

    const funcProto = self.parseFuncProto() catch |err| switch (err) {
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
        try self.parseStatement();
    } else {
        const p = try self.parseScope();
        self.nodeList.items[funcProto].next = p;
    }

    return funcProto;
}

fn parseFuncProto(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    const nodeIndex = try nl.addNode(self.alloc, &self.nodeList, .{
        .tag = .funcProto,
        .data = .{ 0, 0 },
    });

    _ = self.pop();
    // TODO: Parse arguments
    _ = self.pop();

    {
        const p = self.parseType() catch |err| switch (err) {
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

fn parseTypeFunction(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    std.debug.assert(Util.listContains(Lexer.TokenType, &.{.openParen}, self.peek()[0].tag));

    if (!try self.expect(self.peek()[0], &.{.openParen})) return error.UnexpectedToken;
    _, const initI = self.pop();
    if (!try self.expect(self.peek()[0], &.{.closeParen})) return error.UnexpectedToken;
    _ = self.pop();

    const x = try self.parseType();

    const node = Node{
        .tag = .funcType,
        .data = .{ 0, x },
        .tokenIndex = initI,
    };

    return try nl.addNode(self.alloc, &self.nodeList, node);
}

fn parseTypePrimitive(self: *@This()) std.mem.Allocator.Error!NodeIndex {
    std.debug.assert(Util.listContains(Lexer.TokenType, &.{ .unsigned8, .unsigned16, .unsigned32, .unsigned64, .signed8, .signed16, .signed32, .signed64 }, self.peek()[0].tag));
    _, const mainIndex = self.pop();

    const nodeIndex = try nl.addNode(self.alloc, &self.nodeList, .{
        .tokenIndex = mainIndex,
        .tag = .typeExpression,
        .data = .{ 0, 0 },
    });

    return nodeIndex;
}
fn parseType(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    if (!try self.expect(self.peek()[0], &.{ .openParen, .unsigned8, .unsigned16, .unsigned32, .unsigned64, .signed8, .signed16, .signed32, .signed64 })) return error.UnexpectedToken;
    if (self.peek()[0].tag == .openParen) {
        return try self.parseTypeFunction();
    } else {
        return try self.parseTypePrimitive();
    }
}

fn parseScope(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    _ = self.popIf(.openBrace) orelse unreachable;

    const nodeIndex = try nl.addNode(self.alloc, &self.nodeList, .{
        .tag = .scope,
        .data = .{ 0, 0 },
    });

    self.nodeList.items[nodeIndex].data[0] = nodeIndex + 1;

    while (self.peek()[0].tag != .closeBrace) {
        const top = self.nodeList.items.len;
        self.parseStatement() catch |err| switch (err) {
            error.UnexpectedToken => {
                self.nodeList.shrinkRetainingCapacity(top);
                while (self.peek()[0].tag != .semicolon) : (_ = self.pop()) {}
                _ = self.pop();
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    if (!try self.expect(self.peek()[0], &.{.closeBrace})) return error.UnexpectedToken;
    _ = self.pop();

    self.nodeList.items[nodeIndex].data[1] = @intCast(self.nodeList.items.len);

    return nodeIndex;
}

fn parseStatement(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!void {
    if (!try self.expect(self.peek()[0], &.{ .ret, .iden })) return error.UnexpectedToken;

    const nodeIndex = switch (self.peek()[0].tag) {
        .ret => try self.parseReturn(),
        .iden => try self.parseVariableDecl(),
        else => unreachable,
    };

    if (!try self.expect(self.peek()[0], &.{.semicolon})) return error.UnexpectedToken;
    _ = self.pop();

    self.nodeList.items[nodeIndex].next = @intCast(self.nodeList.items.len);
    return;
}

fn parseVariableDecl(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    _, const nameIndex = self.popIf(.iden) orelse unreachable;

    const index = try nl.reserveNode(self.alloc, &self.nodeList, .{
        .tag = Node.Tag.variable,
        .tokenIndex = nameIndex,
        .data = .{ 0, 0 },
    });

    if (!try self.expect(self.peek()[0], &.{.colon})) return error.UnexpectedToken;
    _ = self.pop();

    const possibleType = self.peek()[0];

    if (possibleType.tag != .colon and possibleType.tag != .equal) {
        {
            const p = try self.parseType();
            self.nodeList.items[index].data[0] = p;
        }
    }

    const possibleExpr = self.peek()[0];
    var func = false;

    if (possibleExpr.tag == .colon or possibleExpr.tag == .equal) {
        if (self.pop()[0].tag == .colon)
            self.nodeList.items[index].tag = .constant;

        {
            const p = try self.parseExpression();
            self.nodeList.items[index].data[1] = p;
        }

        func = self.nodeList.items[self.nodeList.items[index].data[1]].tag == .funcProto;
    }

    if (!func and !try self.expect(self.peek()[0], &.{.semicolon})) return error.UnexpectedToken;

    return index;
}

fn parseReturn(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    _, const retIndex = self.popIf(.ret) orelse unreachable;

    const nodeIndex = try nl.addNode(self.alloc, &self.nodeList, .{
        .tag = .ret,
        .tokenIndex = retIndex,
        .data = .{ 0, 0 },
    });

    std.debug.assert(self.depth == 0);
    const exp = try self.parseExpression();
    std.debug.assert(self.depth == 0);

    self.nodeList.items[nodeIndex].data[0] = exp;

    if (!try self.expect(self.peek()[0], &.{.semicolon})) return error.UnexpectedToken;

    return nodeIndex;
}

fn parseExpression(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    if (try self.parseFuncDecl()) |index| return index;
    return self.parseExpr(1);
}

fn parseExpr(self: *@This(), minPrecedence: u8) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    var nextToken = self.peek()[0];
    if (nextToken.tag == .semicolon) @panic("Void return is not implemented");

    var leftIndex = try self.parseTerm();
    nextToken = self.peek()[0];

    while (nextToken.tag != .semicolon and nextToken.tag != .closeParen) : (nextToken = self.peek()[0]) {
        const op, const opIndex = self.peek();
        if (!try self.expect(op, &.{ .plus, .minus, .asterik, .slash, .caret })) return error.UnexpectedToken;

        const tag: Node.Tag = Expression.tokenTagToNodeTag(op.tag);
        const prec = Expression.operandPresedence(tag);
        if (prec < minPrecedence) break;

        _ = self.pop();

        const nextMinPrec = if (Expression.operandAssociativity(tag) == Expression.Associativity.left) prec + 1 else prec;

        const right = try self.parseExpr(nextMinPrec);

        leftIndex = try nl.addNode(self.alloc, &self.nodeList, Node{
            .tag = tag,
            .tokenIndex = opIndex,
            .data = .{ leftIndex, right },
        });
    }

    return leftIndex;
}

fn parseTerm(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!NodeIndex {
    const nextToken = self.peek()[0];

    if (!try self.expect(nextToken, &[_]Lexer.TokenType{ .numberLiteral, .openParen, .minus, .iden })) return error.UnexpectedToken;

    switch (nextToken.tag) {
        .numberLiteral => {
            return try nl.addNode(self.alloc, &self.nodeList, .{
                .tag = .lit,
                .tokenIndex = self.pop()[1],
                .data = .{ 0, 0 },
            });
        },
        .iden => {
            return try nl.addNode(self.alloc, &self.nodeList, .{
                .tag = .load,
                .tokenIndex = self.pop()[1],
                .data = .{ 0, 0 },
            });
        },
        .minus => {
            const op, const opIndex = self.pop();

            const expr = try self.parseTerm();

            return try nl.addNode(self.alloc, &self.nodeList, .{
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

            const expr = try self.parseExpression();
            if (!try self.expect(self.peek()[0], &.{.closeParen})) return error.UnexpectedToken;

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

    for (self.tokens) |value| {
        try value.toString(alloc, &al, self.path, self.source);
    }

    return al.toOwnedSlice(alloc);
}
