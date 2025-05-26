const std = @import("std");
const Set = @import("ziglangSet");
const Logger = @import("./Logger.zig");
const Util = @import("./Util.zig");
const Lexer = @import("Lexer/Lexer.zig");
const Parser = @import("Parser/Parser.zig");

const Variable = struct {
    const VarTOset = std.AutoHashMap(
        Parser.NodeIndex,
        usize,
    );

    const SetTOvar = std.AutoArrayHashMap(
        usize,
        struct {
            ?TypeLocation,
            std.ArrayList(Parser.NodeIndex),
        },
    );

    const TypeLocation = struct { Parser.NodeIndex, Lexer.Location };

    varTOset: VarTOset,
    setTOvar: SetTOvar,
};

const Constant = struct {
    const VarTOset = std.AutoHashMap(
        Parser.NodeIndex,
        usize,
    );

    const SetTOvar = std.AutoArrayHashMap(
        usize,
        Set.ArraySetManaged(TypeLocation),
    );

    const TypeLocation = struct { Parser.NodeIndex, Lexer.Location };

    varTOset: VarTOset,
    setTOvar: SetTOvar,
};

ast: *Parser.Ast,

reuse: std.BoundedArray(usize, 256),
sets: usize = 0,
alloc: std.mem.Allocator,
variable: Variable,
constant: Constant,

pub fn init(alloc: std.mem.Allocator, ast: *Parser.Ast) @This() {
    return @This(){
        .reuse = std.BoundedArray(usize, 256).init(0) catch unreachable,
        .alloc = alloc,
        .ast = ast,
        .variable = .{
            .varTOset = Variable.VarTOset.init(alloc),
            .setTOvar = Variable.SetTOvar.init(alloc),
        },
        .constant = .{
            .varTOset = Constant.VarTOset.init(alloc),
            .setTOvar = Constant.SetTOvar.init(alloc),
        },
    };
}

pub fn deinit(self: *@This()) void {
    {
        var it = self.variable.setTOvar.iterator();

        while (it.next()) |entry| {
            const tuple = entry.value_ptr;
            tuple[1].deinit();
        }

        self.variable.varTOset.deinit();
        self.variable.setTOvar.deinit();
    }
    {
        var it = self.constant.setTOvar.iterator();

        while (it.next()) |entry| {
            const tuple = entry.value_ptr;
            tuple.deinit();
        }

        self.constant.varTOset.deinit();
        self.constant.setTOvar.deinit();
    }
}

pub fn add(self: *@This(), node: Parser.NodeIndex) std.mem.Allocator.Error!usize {
    if (self.variable.varTOset.get(node)) |index| return index;
    const sets = self.reuse.pop() orelse set: {
        const index = self.sets;
        self.sets += 1;
        break :set index;
    };

    try self.variable.varTOset.put(node, sets);

    if (self.variable.setTOvar.getPtr(sets)) |set| {
        try set[1].append(node);
    } else {
        var set = std.ArrayList(Parser.NodeIndex).init(self.alloc);
        try set.append(node);
        try self.variable.setTOvar.put(sets, .{ null, set });
    }

    return sets;
}

pub fn merge(self: *@This(), a: usize, b: usize) (std.mem.Allocator.Error || error{IncompatibleType})!usize {
    if (a == b) return a;
    const ta = self.variable.setTOvar.getPtr(a).?;
    const tb = self.variable.setTOvar.getPtr(b).?;

    if (ta[0]) |aTypeI| if (tb[0]) |bTypeI| {
        const aType = self.ast.getNode(aTypeI[0]);
        const bType = self.ast.getNode(bTypeI[0]);
        if (aType.getTokenTag(self.ast.tokens) != bType.getTokenTag(self.ast.tokens)) return error.IncompatibleType;
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
        try self.variable.varTOset.put(x, destIndex);
    }

    org[1].clearRetainingCapacity();
    org[0] = null;

    return destIndex;
}

pub fn found(self: *@This(), aI: Parser.NodeIndex, tI: Parser.NodeIndex, loc: Lexer.Location) std.mem.Allocator.Error!void {
    const i = self.variable.varTOset.get(aI).?;
    const ta = self.variable.setTOvar.getPtr(i).?;
    if (ta[0]) |oldTI| {
        const oldT = self.ast.getNode(oldTI[0]);
        const t = self.ast.getNode(tI);
        if (oldT.getTokenTag(self.ast.tokens) != t.getTokenTag(self.ast.tokens)) {
            const a = self.ast.getNode(aI);
            Logger.logLocation.err(self.ast.path, a.getLocation(self.ast.tokens), "Found this variable used in 2 different contexts (ambiguous typing) {s}", .{Logger.placeSlice(a.getLocation(self.ast.tokens), self.ast.source)});
            Logger.logLocation.info(self.ast.path, oldTI[1], "Type inferred is: {s}, found here {s}", .{ oldT.getName(self.ast.tokens), Logger.placeSlice(oldTI[1], self.ast.source) });
            Logger.logLocation.info(self.ast.path, loc, "But later found here used in an other context: {s} {s}", .{ t.getName(self.ast.tokens), Logger.placeSlice(loc, self.ast.source) });
        }
    } else {
        ta[0] = .{ tI, loc };
    }
}

pub fn includes(self: @This(), a: Parser.NodeIndex) bool {
    return self.variable.varTOset.contains(a);
}

pub fn printState(self: @This()) void {
    var it = self.variable.setTOvar.keyIterator();

    while (it.next()) |setIndex| {
        if (Util.listContains(usize, self.reuse.buffer[0..self.reuse.len], setIndex.*)) continue;
        Logger.log.info("{}:", .{setIndex.*});
        const set = self.variable.setTOvar.get(setIndex.*).?;

        if (set[0]) |t| {
            Logger.log.info("{s}", .{self.ast.getNode(t[0]).getName(self.ast.tokens)});
            Logger.logLocation.info(self.ast.path, t[1], "Found here: {s}", .{Logger.placeSlice(t[1], self.ast.source)});
        }

        for (set[1].items) |value| {
            Logger.logLocation.info(self.ast.path, self.ast.getNode(value).getLocation(self.ast.tokens), "{s}", .{Logger.placeSlice(self.ast.getNode(value).getLocation(self.ast.tokens), self.ast.source)});
        }
    }
}
