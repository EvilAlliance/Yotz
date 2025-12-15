const std = @import("std");
const Lexer = @import("../Lexer/mod.zig");
const Logger = @import("../Logger.zig");
const mod = @import("mod.zig");
const TranslationUnit = @import("../TranslationUnit.zig");

pub const FileInfo = struct { []const u8, [:0]const u8 };

pub const Mode = enum {
    Bound,
    UnBound,
    UnCheck,
};

nodeList: *mod.NodeList.Chunk,
tu: *const TranslationUnit,

pub fn init(nl: *mod.NodeList.Chunk, tu: *const TranslationUnit) @This() {
    return @This(){
        .nodeList = nl,
        .tu = tu,
    };
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    self.nodeList.deinit(alloc);
}

pub inline fn getToken(self: *const @This(), i: mod.TokenIndex) Lexer.Token {
    return self.tu.cont.tokens[i];
}

pub inline fn getNodeLocation(self: *const @This(), comptime mode: Mode, i: mod.NodeIndex) Lexer.Location {
    const node = self.getNode(mode, i);
    return self.getToken(node.tokenIndex.load(.acquire)).loc;
}

pub inline fn getNodeText(self: *const @This(), comptime mode: Mode, i: mod.NodeIndex) []const u8 {
    const node = self.getNode(mode, i);
    return self.getToken(node.tokenIndex.load(.acquire)).getText(self.tu.cont.source);
}

pub inline fn getNodeName(self: *const @This(), comptime mode: Mode, i: mod.NodeIndex) []const u8 {
    const node = self.getNode(mode, i);
    return self.getToken(node.tokenIndex).tag.getName();
}

pub fn getNode(self: *const @This(), comptime mode: Mode, i: mod.NodeIndex) mod.Node {
    return switch (mode) {
        .Bound => self.getNode(.UnCheck, i),
        .UnBound => self.nodeList.getOutChunk(i),
        .UnCheck => self.nodeList.getUncheck(i),
    };
}

pub inline fn getNodePtr(self: *@This(), comptime mode: Mode, i: mod.NodeIndex) *mod.Node {
    return switch (mode) {
        .Bound => self.getNodePtr(.UnCheck, i),
        .UnBound => self.nodeList.getPtrOutChunk(i),
        .UnCheck => self.nodeList.getPtrUnCheck(i),
    };
}

pub inline fn unlockShared(self: *@This()) void {
    self.nodeList.unlockShared();
}

pub fn toString(self: *const @This(), alloc: std.mem.Allocator, rootIndex: mod.NodeIndex) std.mem.Allocator.Error![]const u8 {
    var cont = std.ArrayList(u8){};

    const root = self.getNode(.UnCheck, rootIndex);

    var i = root.data[0].load(.acquire);
    while (i != 0) : (i = self.getNode(.UnCheck, i).next.load(.acquire)) {
        try self.tostringVariable(alloc, &cont, 0, i);

        if (self.getNode(.UnCheck, self.getNode(.UnCheck, i).data[1].load(.acquire)).tag.load(.acquire) != .funcProto) {
            try cont.appendSlice(alloc, ";\n");
        }
    }

    return cont.toOwnedSlice(alloc);
}

fn toStringFuncProto(self: *const @This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, i: mod.NodeIndex) std.mem.Allocator.Error!void {
    std.debug.assert(self.getNode(.UnCheck, i).tag.load(.acquire) == .funcProto);
    std.debug.assert(self.getNode(.UnCheck, i).data[0].load(.acquire) == 0);

    // TODO : Put arguments
    try cont.appendSlice(alloc, "() ");

    try self.toStringType(alloc, cont, d, self.getNode(.UnCheck, i).data[1].load(.acquire));

    try cont.append(alloc, ' ');

    const protoNext = self.getNode(.UnCheck, i).next.load(.acquire);
    if (self.getNode(.UnCheck, protoNext).tag.load(.acquire) == .scope) return try self.toStringScope(alloc, cont, d, protoNext);

    try self.toStringStatement(alloc, cont, d, protoNext);
}

fn toStringType(self: *const @This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, i: mod.NodeIndex) std.mem.Allocator.Error!void {
    _ = d;

    var index = i;

    while (true) {
        const t = self.getNode(.UnCheck, index);

        switch (t.tag.load(.acquire)) {
            .funcType => {
                std.debug.assert(t.data[0].load(.acquire) == 0);
                try cont.appendSlice(alloc, "() ");

                index = t.data[1].load(.acquire);
                continue;
            },
            .type => {
                try cont.append(alloc, switch (@as(mod.Node.Primitive, @enumFromInt(t.data[1].load(.acquire)))) {
                    mod.Node.Primitive.int => 'i',
                    mod.Node.Primitive.uint => 'u',
                    mod.Node.Primitive.float => 'f',
                });

                const size = try std.fmt.allocPrint(alloc, "{}", .{t.data[0].load(.acquire)});
                try cont.appendSlice(alloc, size);
                alloc.free(size);
            },
            .fakeType => {
                const x = self.getNodeText(.UnCheck, index);
                try cont.appendSlice(alloc, x);
            },
            else => unreachable,
        }

        index = t.next.load(.acquire);

        if (index != 0) {
            try cont.appendSlice(alloc, ", ");
        } else {
            break;
        }
    }
}

fn toStringScope(self: *const @This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, i: mod.NodeIndex) std.mem.Allocator.Error!void {
    const scope = self.getNode(.UnCheck, i);
    std.debug.assert(scope.tag.load(.acquire) == .scope);

    try cont.appendSlice(alloc, "{ \n");

    var j = scope.data[0].load(.acquire);

    while (j != 0) {
        const node = self.getNode(.UnCheck, j);

        try self.toStringStatement(alloc, cont, d + 4, j);

        j = node.next.load(.acquire);
    }

    try cont.appendSlice(alloc, "} \n");
}

fn toStringStatement(self: *const @This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, i: mod.NodeIndex) std.mem.Allocator.Error!void {
    for (0..d) |_| {
        try cont.append(alloc, ' ');
    }

    const stmt = self.getNode(.UnCheck, i);

    switch (stmt.tag.load(.acquire)) {
        .ret => {
            try cont.appendSlice(alloc, "return ");
            try self.toStringExpression(alloc, cont, d, stmt.data[1].load(.acquire));
        },
        .variable, .constant => {
            try self.tostringVariable(alloc, cont, d, i);
        },
        else => unreachable,
    }

    try cont.appendSlice(alloc, ";\n");
}

fn tostringVariable(self: *const @This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, i: mod.NodeIndex) std.mem.Allocator.Error!void {
    const variable = self.getNode(.UnCheck, i);
    std.debug.assert(variable.tag.load(.acquire) == .constant or variable.tag.load(.acquire) == .variable);

    try cont.appendSlice(alloc, variable.getTextAst(self));

    const variableLeft = variable.data[0].load(.acquire);
    if (variableLeft == 0)
        try cont.append(alloc, ' ');

    try cont.append(alloc, ':');
    if (variableLeft != 0) {
        try cont.append(alloc, ' ');
        try self.toStringType(alloc, cont, d, variableLeft);
        try cont.append(alloc, ' ');
    }

    if (variable.data[1].load(.acquire) != 0) {
        switch (variable.tag.load(.acquire)) {
            .constant => try cont.appendSlice(alloc, ": "),
            .variable => try cont.appendSlice(alloc, "= "),
            else => unreachable,
        }
        try self.toStringExpression(alloc, cont, d, variable.data[1].load(.acquire));
    }
}

fn toStringExpression(self: *const @This(), alloc: std.mem.Allocator, cont: *std.ArrayList(u8), d: u64, i: mod.NodeIndex) std.mem.Allocator.Error!void {
    const node = self.getNode(.UnCheck, i);
    switch (node.tag.load(.acquire)) {
        .funcProto => try self.toStringFuncProto(alloc, cont, d, i),
        .addition, .subtraction, .multiplication, .division, .power => {
            try cont.append(alloc, '(');

            const leftIndex = node.data[0].load(.acquire);
            try self.toStringExpression(alloc, cont, d, leftIndex);

            try cont.append(alloc, ' ');
            try cont.appendSlice(alloc, node.getTokenTagAst(self.*).toSymbol().?);
            try cont.append(alloc, ' ');

            const rightIndex = node.data[1].load(.acquire);
            try self.toStringExpression(alloc, cont, d, rightIndex);

            try cont.append(alloc, ')');
        },
        .neg => {
            try cont.appendSlice(alloc, node.getTokenTagAst(self.*).toSymbol().?);
            try cont.append(alloc, '(');
            const leftIndex = node.data[0].load(.acquire);

            try self.toStringExpression(alloc, cont, d, leftIndex);
            try cont.append(alloc, ')');
        },
        .load => {
            try cont.appendSlice(alloc, node.getTextAst(self));
        },
        .lit => {
            try cont.appendSlice(alloc, node.getTextAst(self));
        },
        else => unreachable,
    }
}
