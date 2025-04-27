const std = @import("std");
const Logger = @import("./Logger.zig");
const Util = @import("./Util.zig");
const Lexer = @import("Lexer/Lexer.zig");
const Parser = @import("Parser/Parser.zig");

const VarTOset = std.HashMap(
    Parser.Node,
    usize,
    struct {
        pub fn hash(self: @This(), a: Parser.Node) u64 {
            _ = self;
            return std.hash.int(a.tokenIndex);
        }
        pub fn eql(self: @This(), a: Parser.Node, b: Parser.Node) bool {
            _ = self;
            return a.tokenIndex == b.tokenIndex;
        }
    },
    70,
);

const SetTOvar = std.AutoHashMap(
    usize,
    struct {
        ?struct { Parser.Node, Lexer.Location },
        std.ArrayList(Parser.Node),
    },
);

tokens: []Lexer.Token,

reuse: std.BoundedArray(usize, 256),
sets: usize = 0,
alloc: std.mem.Allocator,
varTOset: VarTOset,
setTOvar: SetTOvar,
pub fn init(alloc: std.mem.Allocator, tokens: []Lexer.Token) @This() {
    return @This(){
        .reuse = std.BoundedArray(usize, 256).init(0) catch unreachable,
        .alloc = alloc,
        .tokens = tokens,
        .varTOset = VarTOset.init(alloc),
        .setTOvar = SetTOvar.init(alloc),
    };
}

pub fn deinit(self: *@This()) void {
    var it = self.setTOvar.valueIterator();

    while (it.next()) |tuple| {
        tuple[1].deinit();
    }

    self.varTOset.deinit();
    self.setTOvar.deinit();
}

pub fn add(self: *@This(), node: Parser.Node) std.mem.Allocator.Error!usize {
    std.debug.assert(node.tag == .variable or node.tag == .constant);
    if (self.varTOset.get(node)) |index| return index;
    const sets = self.reuse.pop() orelse set: {
        const index = self.sets;
        self.sets += 1;
        break :set index;
    };

    try self.varTOset.put(node, sets);

    if (self.setTOvar.getPtr(sets)) |set| {
        try set[1].append(node);
    } else {
        var set = std.ArrayList(Parser.Node).init(self.alloc);
        try set.append(node);
        try self.setTOvar.put(sets, .{ null, set });
    }

    return sets;
}

pub fn merge(self: *@This(), a: usize, b: usize) (std.mem.Allocator.Error || error{IncompatibleType})!usize {
    if (a == b) return a;
    const ta = self.setTOvar.getPtr(a).?;
    const tb = self.setTOvar.getPtr(b).?;

    if (ta[0]) |aType| if (tb[0]) |bType| {
        if (aType[0].getTokenTag(self.tokens) != bType[0].getTokenTag(self.tokens)) return error.IncompatibleType;
    };

    const dest = if (ta[0] != null) ta else tb;
    const org = if (ta[0] != null) tb else ta;
    const destIndex = if (ta[0] != null) a else b;

    if (ta[0] != null)
        self.reuse.append(b) catch {}
    else
        self.reuse.append(a) catch {};

    try dest[1].appendSlice(org[1].items);

    for (org[1].items) |x| {
        try self.varTOset.put(x, destIndex);
    }

    org[1].clearRetainingCapacity();
    org[0] = null;

    return destIndex;
}

pub fn found(self: *@This(), a: Parser.Node, t: Parser.Node, loc: Lexer.Location) std.mem.Allocator.Error!void {
    std.debug.assert(t.tag == .type);
    std.debug.assert(a.tag == .constant or a.tag == .variable);
    const i = self.varTOset.get(a).?;
    const ta = self.setTOvar.getPtr(i).?;
    if (ta[0]) |oldT| {
        if (oldT[0].getTokenTag(self.tokens) != t.getTokenTag(self.tokens)) {
            Logger.logLocation.err(a.getLocation(self.tokens), "Found this variable used in 2 different contexts (ambiguous typing)", .{});
            Logger.logLocation.info(oldT[1], "Type inferred is: {s}, found here", .{oldT[0].getName(self.tokens)});
            Logger.logLocation.info(loc, "But later found here used in an other context: {s}", .{t.getName(self.tokens)});
        }
    } else {
        ta[0] = .{ t, loc };
    }
}

pub fn includes(self: @This(), a: Parser.Node) bool {
    return self.varTOset.contains(a);
}

pub fn printState(self: @This()) void {
    var it = self.setTOvar.keyIterator();

    while (it.next()) |setIndex| {
        if (Util.listContains(usize, self.reuse.buffer[0..self.reuse.len], setIndex.*)) continue;
        Logger.log.info("{}:", .{setIndex.*});
        const set = self.setTOvar.get(setIndex.*).?;

        if (set[0]) |t| {
            Logger.log.info("{s}", .{t[0].token.?.tag.getName()});
            Logger.logLocation.info(t[1], "Found here", .{});
        }

        for (set[1].items) |value| {
            Logger.logLocation.info(value.token.?.loc, "", .{});
        }
    }
}
