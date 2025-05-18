const std = @import("std");
const Lexer = @import("../Lexer/Lexer.zig");
const Parser = @import("Parser.zig");

pub const NodeList = std.ArrayList(Parser.Node);
pub const FileInfo = struct { []const u8, [:0]const u8 };

alloc: std.mem.Allocator,

source: [:0]const u8,
absPath: []const u8,
path: []const u8,

tokens: []Lexer.Token,

nodeList: NodeList,

pub fn init(alloc: std.mem.Allocator, nl: NodeList, tl: []Lexer.Token, absPath: []const u8, path: []const u8, source: [:0]const u8) @This() {
    return @This(){
        .alloc = alloc,

        .absPath = absPath,
        .path = path,
        .source = source,
        .tokens = tl,

        .nodeList = nl,
    };
}

pub fn getToken(self: *@This(), i: usize) Lexer.Token {
    return self.tokens[i];
}

pub fn getNode(self: *@This(), i: usize) Parser.Node {
    return self.nodeList.items[i];
}

pub fn toString(self: *@This(), alloc: std.mem.Allocator) std.mem.Allocator.Error!std.ArrayList(u8) {
    var cont = std.ArrayList(u8).init(alloc);
    if (self.nodeList.items.len == 0) return cont;

    const root = self.nodeList.items[0];

    var i = root.data[0];
    const end = root.data[1];
    while (i < end) : (i = self.getNode(i).next) {
        try self.tostringVariable(&cont, 0, i);
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

fn toStringType(self: @This(), cont: *std.ArrayList(u8), d: u64, i: Parser.NodeIndex) std.mem.Allocator.Error!void {
    _ = d;
    try cont.appendSlice(self.nodeList.items[i].getText(self.tokens, self.source));
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

    try cont.appendSlice(variable.getText(self.tokens, self.source));

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
            try cont.appendSlice(node.getTokenTag(self.tokens).toSymbol().?);
            try cont.append(' ');

            const rightIndex = node.data[1];
            try self.toStringExpression(cont, d, rightIndex);

            try cont.append(')');
        },
        .parentesis => {
            const leftIndex = node.data[0];

            try self.toStringExpression(cont, d, leftIndex);
        },
        .neg => {
            try cont.appendSlice(node.getTokenTag(self.tokens).toSymbol().?);
            try cont.append('(');
            const leftIndex = node.data[0];

            try self.toStringExpression(cont, d, leftIndex);
            try cont.append(')');
        },
        .load => {
            try cont.appendSlice(node.getText(self.tokens, self.source));
        },
        .lit => {
            try cont.appendSlice(node.getText(self.tokens, self.source));
        },
        else => unreachable,
    }
}

pub fn getInfo(self: *@This()) FileInfo {
    return .{ self.path, self.source };
}
