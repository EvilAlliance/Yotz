const std = @import("std");
const Lexer = @import("../Lexer/Lexer.zig");
const Logger = @import("../Logger.zig");
const Parser = @import("Parser.zig");

pub const NodeList = std.ArrayList(Parser.Node);
pub const FileInfo = struct { []const u8, [:0]const u8 };

alloc: std.mem.Allocator,

source: [:0]const u8,
absPath: []const u8,
path: []const u8,

tokens: []Lexer.Token,

nodeList: *NodeList,

pub fn init(alloc: std.mem.Allocator, nl: *NodeList, tl: []Lexer.Token, absPath: []const u8, path: []const u8, source: [:0]const u8) @This() {
    return @This(){
        .alloc = alloc,

        .absPath = absPath,
        .path = path,
        .source = source,
        .tokens = tl,

        .nodeList = nl,
    };
}

pub inline fn getToken(self: *@This(), i: Parser.TokenIndex) Lexer.Token {
    return self.tokens[i];
}

pub inline fn getNodeLocation(self: *@This(), i: Parser.NodeIndex) Lexer.Location {
    const node = self.nodeList.items[i];
    return self.getToken(node.tokenIndex).loc;
}

pub inline fn getNodeText(self: *@This(), i: Parser.NodeIndex) []const u8 {
    const node = self.nodeList.items[i];
    return self.getToken(node.tokenIndex).getText(self.source);
}

pub inline fn getNodeName(self: *@This(), i: Parser.NodeIndex) []const u8 {
    const node = self.nodeList.items[i];
    return self.getToken(node.tokenIndex).tag.getName();
}

pub inline fn getNode(self: *@This(), i: Parser.NodeIndex) Parser.Node {
    return self.nodeList.items[i];
}

pub inline fn getNodePtr(self: *@This(), i: Parser.NodeIndex) *Parser.Node {
    return &self.nodeList.items[i];
}

pub fn toString(self: *@This(), alloc: std.mem.Allocator) std.mem.Allocator.Error!std.ArrayList(u8) {
    var cont = std.ArrayList(u8).init(alloc);
    if (self.nodeList.items.len == 0) return cont;

    const root = self.nodeList.items[0];

    var i = root.data[0];
    const end = root.data[1];
    while (i < end) : (i = self.getNode(i).next) {
        try self.tostringVariable(&cont, 0, i);

        if (self.getNode(self.getNode(i).data[1]).tag != .funcProto) {
            try cont.appendSlice(";\n");
        }
    }

    return cont;
}

fn toStringFuncProto(self: *@This(), cont: *std.ArrayList(u8), d: u64, i: Parser.NodeIndex) std.mem.Allocator.Error!void {
    std.debug.assert(self.nodeList.items[i].tag == .funcProto);
    std.debug.assert(self.nodeList.items[i].data[0] == 0);

    // TODO : Put arguments
    try cont.appendSlice("() ");

    try self.toStringType(cont, d, self.nodeList.items[i].data[1]);

    try cont.append(' ');

    const proto = self.getNode(i);
    if (self.getNode(proto.next).tag == .scope) return try self.toStringScope(cont, d, proto.next);

    try self.toStringStatement(cont, d, proto.next);
}

fn toStringType(self: *@This(), cont: *std.ArrayList(u8), d: u64, i: Parser.NodeIndex) std.mem.Allocator.Error!void {
    _ = d;

    var index = i;

    while (true) {
        const t = self.nodeList.items[index];

        switch (t.tag) {
            .typeExpression => try cont.appendSlice(t.getTextAst(self)),
            .funcType => {
                std.debug.assert(t.data[0] == 0);
                try cont.appendSlice("() ");

                index = t.data[1];
                continue;
            },
            .type => {
                try cont.append(switch (@as(Parser.Node.Primitive, @enumFromInt(t.data[1]))) {
                    Parser.Node.Primitive.int => 'i',
                    Parser.Node.Primitive.uint => 'u',
                    Parser.Node.Primitive.float => 'f',
                });

                const size = try std.fmt.allocPrint(cont.allocator, "{}", .{t.data[0]});
                try cont.appendSlice(size);
                cont.allocator.free(size);
            },
            else => unreachable,
        }

        index = t.next;

        if (t.next != 0) {
            try cont.appendSlice(", ");
        } else {
            break;
        }
    }
}

fn toStringScope(self: *@This(), cont: *std.ArrayList(u8), d: u64, i: Parser.NodeIndex) std.mem.Allocator.Error!void {
    const scope = self.nodeList.items[i];
    std.debug.assert(scope.tag == .scope);

    try cont.appendSlice("{ \n");

    var j = scope.data[0];
    const end = scope.data[1];

    while (j < end) {
        const node = self.nodeList.items[j];

        try self.toStringStatement(cont, d + 4, j);

        j = node.next;
    }

    try cont.appendSlice("} \n");
}

fn toStringStatement(self: *@This(), cont: *std.ArrayList(u8), d: u64, i: Parser.NodeIndex) std.mem.Allocator.Error!void {
    for (0..d) |_| {
        try cont.append(' ');
    }

    const stmt = self.nodeList.items[i];

    switch (stmt.tag) {
        .ret => {
            try cont.appendSlice("return ");
            try self.toStringExpression(cont, d, stmt.data[0]);
        },
        .variable, .constant => {
            try self.tostringVariable(cont, d, i);
        },
        else => unreachable,
    }

    try cont.appendSlice(";\n");
}

fn tostringVariable(self: *@This(), cont: *std.ArrayList(u8), d: u64, i: Parser.NodeIndex) std.mem.Allocator.Error!void {
    const variable = self.nodeList.items[i];
    std.debug.assert(variable.tag == .constant or variable.tag == .variable);

    try cont.appendSlice(variable.getTextAst(self));

    if (variable.data[0] == 0)
        try cont.append(' ');

    try cont.append(':');
    if (variable.data[0] != 0) {
        try cont.append(' ');
        try self.toStringType(cont, d, variable.data[0]);
        try cont.append(' ');
    }

    if (variable.data[1] != 0) {
        switch (variable.tag) {
            .constant => try cont.appendSlice(": "),
            .variable => try cont.appendSlice("= "),
            else => unreachable,
        }
        try self.toStringExpression(cont, d, variable.data[1]);
    }
}

fn toStringExpression(self: *@This(), cont: *std.ArrayList(u8), d: u64, i: Parser.NodeIndex) std.mem.Allocator.Error!void {
    const node = self.nodeList.items[i];
    switch (node.tag) {
        .funcProto => try self.toStringFuncProto(cont, d, i),
        .addition, .subtraction, .multiplication, .division, .power => {
            try cont.append('(');

            const leftIndex = node.data[0];
            try self.toStringExpression(cont, d, leftIndex);

            try cont.append(' ');
            try cont.appendSlice(node.getTokenTagAst(self.*).toSymbol().?);
            try cont.append(' ');

            const rightIndex = node.data[1];
            try self.toStringExpression(cont, d, rightIndex);

            try cont.append(')');
        },
        .neg => {
            try cont.appendSlice(node.getTokenTagAst(self.*).toSymbol().?);
            try cont.append('(');
            const leftIndex = node.data[0];

            try self.toStringExpression(cont, d, leftIndex);
            try cont.append(')');
        },
        .load => {
            try cont.appendSlice(node.getTextAst(self));
        },
        .lit => {
            try cont.appendSlice(node.getTextAst(self));
        },
        else => unreachable,
    }
}

pub fn getInfo(self: *@This()) FileInfo {
    return .{ self.path, self.source };
}
