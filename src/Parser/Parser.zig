const std = @import("std");
const Logger = @import("../Logger.zig");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Util = @import("../Util.zig");
const gen = @import("../General.zig");
const tb = @import("../libs/tb/tb.zig");
const tbHelper = @import("../TBHelper.zig");

const getType = tbHelper.getType;

const message = gen.message;

const Lexer = @import("../Lexer/Lexer.zig");

pub const Node = @import("Node.zig");
pub const UnexpectedToken = @import("UnexpectedToken.zig");
pub const nl = @import("./NodeListUtil.zig");
pub const Expression = @import("Expression.zig");
pub const Ast = @import("Ast.zig");

alloc: Allocator,

index: usize = 0,
tokens: []Lexer.Token,
source: [:0]const u8,

path: []const u8,
absPath: []const u8,

functions: Ast.Program,
nodeList: Ast.NodeList,
temp: Ast.NodeList,

errors: std.ArrayList(UnexpectedToken),

depth: usize = 0,

pub fn init(alloc: Allocator, path: []const u8) ?@This() {
    const absPath, const source = Util.readEntireFile(alloc, path) catch |err| {
        switch (err) {
            error.couldNotOpenFile => Logger.log.err("Could not open file: {s}\n", .{path}),
            error.couldNotReadFile => Logger.log.err("Could not read file: {s}]n", .{path}),
            error.couldNotGetFileSize => Logger.log.err("Could not get file ({s}) size\n", .{path}),
            error.couldNotGetAbsolutePath => Logger.log.err("Could not get absolute path of file ({s})\n", .{path}),
        }
        return null;
    };

    return @This(){
        .alloc = alloc,
        .tokens = Lexer.lex(alloc, path, absPath, source) catch {
            Logger.log.err("Out of memory", .{});
            return null;
        },

        .source = source,

        .path = path,
        .absPath = absPath,

        .functions = Ast.Program.init(alloc),
        .nodeList = Ast.NodeList.init(alloc),
        .temp = Ast.NodeList.init(alloc),

        .errors = std.ArrayList(UnexpectedToken).init(alloc),
    };
}

pub fn deinit(self: *@This()) void {
    for (self.errors.items) |value| {
        value.deinit();
    }

    self.errors.deinit();
    self.temp.deinit();
}

pub fn expect(self: *@This(), token: Lexer.Token, t: []const Lexer.TokenType) std.mem.Allocator.Error!bool {
    const ex = try self.alloc.dupe(Lexer.TokenType, t);
    const is = Util.listContains(Lexer.TokenType, ex, token.tag);
    if (!is) {
        try self.errors.append(UnexpectedToken{
            .expected = ex,
            .found = token.tag,
            .loc = token.loc,
            .alloc = self.alloc,
        });
    }

    return is;
}

fn peek(self: *@This()) Lexer.Token {
    return self.tokens[self.index];
}

fn popIf(self: *@This(), t: Lexer.TokenType) ?Lexer.Token {
    if (self.tokens[self.index].tag != t) return null;
    const token = self.tokens[self.index];
    self.index += 1;
    return token;
}

fn pop(self: *@This()) Lexer.Token {
    const token = self.tokens[self.index];
    self.index += 1;
    return token;
}

pub fn parse(self: *@This()) (std.mem.Allocator.Error)!Ast {
    self.parseRoot() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {},
    };

    return Ast.init(self.alloc, self.functions, self.nodeList, self.source);
}

fn parseRoot(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!void {
    const top = self.temp.items.len;
    defer self.temp.shrinkRetainingCapacity(top);

    try self.temp.insert(0, .{ .tag = .root, .token = null, .data = .{ 1, 0 } });

    var t = self.peek();
    while (t.tag != .EOF) : (t = self.peek()) {
        if (!try self.expect(t, &.{.func})) return error.UnexpectedToken;

        switch (t.tag) {
            .func => try self.parseFuncDecl(),
            // .let => unreachable,
            else => unreachable,
        }
    }

    self.temp.items[0].data[1] = self.temp.items.len;

    try self.nodeList.appendSlice(self.temp.items);
}

fn parseFuncDecl(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!void {
    _ = self.popIf(.func) orelse unreachable;

    if (!try self.expect(self.peek(), &.{.iden})) return error.UnexpectedToken;
    const mainToken = self.pop();

    const nodeIndex = try nl.addNode(&self.temp, .{
        .token = mainToken,
        .tag = .funcDecl,
        .data = .{ 0, 0 },
    });

    if (!try self.expect(self.peek(), &.{.openParen})) return error.UnexpectedToken;
    {
        const p = try self.parseFuncProto();
        self.temp.items[nodeIndex].data[0] = p;
    }

    if (self.peek().tag != .openBrace) {
        self.temp.items[nodeIndex].data[1] = self.temp.items.len;
        try self.parseStatement();
    } else {
        const p = try self.parseScope();
        self.temp.items[nodeIndex].data[1] = p;
    }

    try self.functions.put(mainToken.getText(), nodeIndex);
}

fn parseFuncProto(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!usize {
    const nodeIndex = try nl.addNode(&self.temp, .{
        .token = null,
        .tag = .funcProto,
        .data = .{ 0, 0 },
    });

    if (!try self.expect(self.peek(), &.{.openParen})) return error.UnexpectedToken;
    _ = self.pop();
    // TODO: Parse arguments
    if (!try self.expect(self.peek(), &.{.closeParen})) return error.UnexpectedToken;
    _ = self.pop();

    {
        const p = try self.parseType();
        self.temp.items[nodeIndex].data[1] = p;
    }

    return nodeIndex;
}

fn parseType(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!usize {
    if (!try self.expect(self.peek(), &.{ .unsigned8, .unsigned16, .unsigned32, .unsigned64, .signed8, .signed16, .signed32, .signed64 })) return error.UnexpectedToken;
    const mainToken = self.pop();

    const nodeIndex = try nl.addNode(&self.temp, .{
        .token = mainToken,
        .tag = .type,
        .data = .{ 0, 0 },
    });

    return nodeIndex;
}

fn parseScope(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!usize {
    _ = self.popIf(.openBrace) orelse unreachable;

    const nodeIndex = try nl.addNode(&self.temp, .{
        .token = null,
        .tag = .scope,
        .data = .{ 0, 0 },
    });

    self.temp.items[nodeIndex].data[0] = nodeIndex + 1;

    while (self.peek().tag != .closeBrace) {
        const top = self.temp.items.len;
        self.parseStatement() catch |err| switch (err) {
            error.UnexpectedToken => {
                self.temp.shrinkRetainingCapacity(top);
                while (self.peek().tag != .semicolon) : (_ = self.pop()) {}
                _ = self.pop();
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    if (!try self.expect(self.peek(), &.{.closeBrace})) return error.UnexpectedToken;
    _ = self.pop();

    self.temp.items[nodeIndex].data[1] = self.temp.items.len;

    return nodeIndex;
}

fn parseStatement(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!void {
    if (!try self.expect(self.peek(), &.{ .ret, .iden })) return error.UnexpectedToken;

    const nodeIndex = switch (self.peek().tag) {
        .ret => try self.parseReturn(),
        .iden => try self.parseVariableDecl(),
        else => unreachable,
    };

    if (!try self.expect(self.peek(), &.{.semicolon})) return error.UnexpectedToken;
    _ = self.pop();

    self.temp.items[nodeIndex].data[1] = self.temp.items.len;
    return;
}

fn parseVariableDecl(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!usize {
    const name = self.popIf(.iden) orelse unreachable;

    if (!try self.expect(self.peek(), &.{.colon})) return error.UnexpectedToken;

    const variable = try nl.addNode(&self.temp, .{
        .tag = Node.Tag.variable,
        .token = name,
        .data = .{ 0, 0 },
    });

    {
        const p, const v = try self.parseVariableProto();
        self.temp.items[variable].tag = v;
        self.temp.items[variable].data[0] = p;
    }

    return variable;
}

fn parseVariableProto(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!struct { usize, Node.Tag } {
    var constant: Node.Tag = .variable;

    const proto = try nl.addNode(&self.temp, .{
        .tag = .VarProto,
        .token = null,
        .data = .{ 0, 0 },
    });

    if (!try self.expect(self.peek(), &.{.colon})) return error.UnexpectedToken;
    _ = self.pop();

    const possibleType = self.peek();

    if (possibleType.tag != .colon and possibleType.tag != .equal) {
        const p = try self.parseType();
        self.temp.items[proto].data[0] = p;
    }

    if (!try self.expect(self.peek(), &.{ .colon, .equal, .semicolon })) return error.UnexpectedToken;

    const possibleExpr = self.peek();

    if (possibleExpr.tag == .colon or possibleExpr.tag == .equal) {
        if (self.pop().tag == .colon)
            constant = .constant;

        const p = try self.parseExpression();
        self.temp.items[proto].data[1] = p;
    }

    if (!try self.expect(self.peek(), &.{.semicolon})) return error.UnexpectedToken;

    return .{ proto, constant };
}

fn parseReturn(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!usize {
    const ret = self.popIf(.ret) orelse unreachable;

    const nodeIndex = try nl.addNode(&self.temp, .{
        .tag = .ret,
        .token = ret,
        .data = .{ 0, 0 },
    });

    std.debug.assert(self.depth == 0);
    const exp = try self.parseExpression();
    std.debug.assert(self.depth == 0);

    self.temp.items[nodeIndex].data[0] = exp;

    if (!try self.expect(self.peek(), &.{.semicolon})) return error.UnexpectedToken;

    return nodeIndex;
}

fn parseExpression(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!usize {
    return self.parseExpr(1);
}

fn parseExpr(self: *@This(), minPrecedence: u8) (std.mem.Allocator.Error || error{UnexpectedToken})!usize {
    var nextToken = self.peek();
    if (nextToken.tag == .semicolon) @panic("Void return is not implemented");

    var leftIndex = try self.parseTerm();
    nextToken = self.peek();

    while (nextToken.tag != .semicolon and nextToken.tag != .closeParen) : (nextToken = self.peek()) {
        const op = self.peek();
        if (!try self.expect(op, &.{ .plus, .minus, .asterik, .slash, .caret })) return error.UnexpectedToken;

        const tag: Node.Tag = switch (op.tag) {
            .minus => .subtraction,
            .plus => .addition,
            .asterik => .multiplication,
            .slash => .division,
            .caret => .power,
            else => unreachable,
        };

        const prec = Expression.operandPresedence(tag);
        if (prec < minPrecedence) break;

        _ = self.pop();

        const nextMinPrec = if (Expression.operandAssociativity(tag) == Expression.Associativity.left) prec + 1 else prec;

        const right = try self.parseExpr(nextMinPrec);

        leftIndex = try nl.addNode(&self.temp, Node{
            .tag = tag,
            .token = op,
            .data = .{ leftIndex, right },
        });
    }

    return leftIndex;
}

fn parseTerm(self: *@This()) (std.mem.Allocator.Error || error{UnexpectedToken})!usize {
    const nextToken = self.peek();

    if (!try self.expect(nextToken, &[_]Lexer.TokenType{ .numberLiteral, .openParen, .minus, .iden })) return error.UnexpectedToken;

    switch (nextToken.tag) {
        .numberLiteral => {
            return try nl.addNode(&self.temp, .{
                .tag = .lit,
                .token = self.pop(),
                .data = .{ 0, 0 },
            });
        },
        .iden => {
            return try nl.addNode(&self.temp, .{
                .tag = .load,
                .token = self.pop(),
                .data = .{ 0, 0 },
            });
        },
        .minus => {
            const op = self.pop();

            const expr = try self.parseTerm();

            return try nl.addNode(&self.temp, .{
                .tag = switch (op.tag) {
                    .minus => .neg,
                    else => unreachable,
                },
                .token = op,
                .data = .{ expr, 0 },
            });
        },
        .openParen => {
            self.depth += 1;

            _ = self.pop();

            const expr = try self.parseExpression();
            if (!try self.expect(self.peek(), &.{.closeParen})) return error.UnexpectedToken;

            _ = self.pop();

            std.debug.assert(self.depth != 0);
            self.depth -= 1;

            try self.temp.append(.{
                .tag = .parentesis,
                .token = null,
                .data = .{ expr, 0 },
            });

            return self.temp.items.len - 1;
        },
        else => unreachable,
    }
}

pub fn lexerToString(self: *@This(), alloc: std.mem.Allocator) std.mem.Allocator.Error!std.ArrayList(u8) {
    var al = std.ArrayList(u8).init(alloc);

    for (self.tokens) |value| {
        try value.toString(alloc, &al, self.path);
    }

    return al;
}
