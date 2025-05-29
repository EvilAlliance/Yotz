const std = @import("std");
const Set = @import("Set");
const Logger = @import("./Logger.zig");
const Util = @import("./Util.zig");
const Lexer = @import("Lexer/Lexer.zig");
const Parser = @import("Parser/Parser.zig");

pub const TypeLocation = struct { Parser.NodeIndex, Lexer.Location };

const Variable = struct {
    const VarTOset = std.AutoHashMap(
        Parser.NodeIndex,
        usize,
    );

    const SetTOvar = std.AutoArrayHashMap(
        usize,
        ?Tree,
    );

    const Tree = union(enum) {
        root: TypeLocation,
        paren: usize,
    };

    varTOset: VarTOset,
    setTOType: SetTOvar,
};

const Constant = struct {
    const VarTOset = std.AutoHashMap(
        Parser.NodeIndex,
        usize,
    );

    const SetTOvar = std.AutoArrayHashMap(
        usize,
        Set.ArraySetManaged(usize),
    );

    varTOset: VarTOset,
    setTOvar: SetTOvar,
};

ast: *Parser.Ast,

sets: usize = 0,
alloc: std.mem.Allocator,
variable: Variable,
constant: Constant,

pub fn init(alloc: std.mem.Allocator, ast: *Parser.Ast) @This() {
    return @This(){
        .alloc = alloc,
        .ast = ast,
        .variable = .{
            .varTOset = Variable.VarTOset.init(alloc),
            .setTOType = Variable.SetTOvar.init(alloc),
        },
        .constant = .{
            .varTOset = Constant.VarTOset.init(alloc),
            .setTOvar = Constant.SetTOvar.init(alloc),
        },
    };
}

pub fn deinit(self: *@This()) void {
    {
        self.variable.varTOset.deinit();
        self.variable.setTOType.deinit();
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
    const sets = self.sets;
    self.sets += 1;

    try self.variable.varTOset.put(node, sets);

    try self.variable.setTOType.put(sets, null);

    return sets;
}

pub fn toConstant(self: *@This(), node: Parser.NodeIndex) std.mem.Allocator.Error!?usize {
    if (self.variable.varTOset.get(node)) |index| {
        try self.constant.varTOset.put(node, index);
        try self.constant.setTOvar.put(index, Set.ArraySetManaged(usize).init(self.alloc));
        _ = self.variable.varTOset.remove(node);

        return index;
    }

    return null;
}

pub fn setRoot(self: *@This(), t: *?Variable.Tree, typeloc: TypeLocation) void {
    if (t.* == null) {
        t.* = .{
            .root = typeloc,
        };

        return;
    }

    return switch (t.*.?) {
        .paren => |i| self.setRoot(self.variable.setTOType.getPtr(i).?, typeloc),
        else => {},
    };
}

pub fn getRoot(self: *@This(), t: *?Variable.Tree) ?TypeLocation {
    if (t.* == null) return null;

    return switch (t.*.?) {
        .paren => |i| {
            const treeOP = self.variable.setTOType.getPtr(i).?;
            if (treeOP.*) |tree| {
                switch (tree) {
                    .paren => |iP| t.*.?.paren = iP,
                    else => {},
                }
            }

            return self.getRoot(treeOP);
        },
        .root => |r| r,
    };
}

fn mergeWithConstant(self: *@This(), aN: Parser.NodeIndex, bN: Parser.NodeIndex) (std.mem.Allocator.Error || error{IncompatibleType})!Parser.NodeIndex {
    if (self.includesConstant(aN) and self.includesConstant(bN)) {
        const a = self.constant.varTOset.get(aN).?;
        const b = self.constant.varTOset.get(bN).?;

        const setA = self.constant.setTOvar.getPtr(a).?;
        const setB = self.constant.setTOvar.getPtr(b).?;

        try setA.unionUpdate(setB.*);
        try setB.unionUpdate(setA.*);

        return aN;
    }

    const cN = if (self.includesConstant(aN)) aN else bN;
    const vN = if (self.includesVariable(bN)) bN else aN;

    const c = self.constant.varTOset.get(cN).?;
    const v = self.variable.varTOset.get(vN).?;

    const set = self.constant.setTOvar.getPtr(c).?;
    const tree = self.variable.setTOType.getPtr(v).?;

    _ = self.getRoot(tree);

    _ = try set.add(if (tree.*) |_| switch (tree.*.?) {
        .root => v,
        .paren => |i| i,
    } else v);

    return vN;
}

pub fn merge(self: *@This(), aN: Parser.NodeIndex, bN: Parser.NodeIndex) (std.mem.Allocator.Error || error{IncompatibleType})!Parser.NodeIndex {
    if (self.includesConstant(aN) or self.includesConstant(bN)) return self.mergeWithConstant(aN, bN);

    const a = self.variable.varTOset.get(aN).?;
    const b = self.variable.varTOset.get(bN).?;
    if (a == b) return aN;
    const ta = self.variable.setTOType.getPtr(a).?;
    const tb = self.variable.setTOType.getPtr(b).?;

    if (ta.*) |_| if (tb.*) |_| {
        const aType = self.ast.getNode(self.getRoot(ta).?[0]);
        const bType = self.ast.getNode(self.getRoot(tb).?[0]);
        if (aType.getTokenTagAst(self.ast.*) != bType.getTokenTagAst(self.ast.*)) return error.IncompatibleType;
        return aN;
    };

    if (ta.* != null) {
        tb.* = .{
            .paren = a,
        };
        return aN;
    } else {
        ta.* = .{
            .paren = b,
        };

        return bN;
    }
}

fn foundConstant(self: *@This(), aI: Parser.NodeIndex, tI: Parser.NodeIndex, loc: Lexer.Location) std.mem.Allocator.Error!void {
    const i = self.constant.varTOset.get(aI).?;
    const ta = self.constant.setTOvar.getPtr(i).?;

    const set = self.sets;
    self.sets += 1;

    try self.variable.setTOType.put(set, .{
        .root = .{
            tI,
            loc,
        },
    });
    _ = try ta.add(set);
}

pub fn found(self: *@This(), aI: Parser.NodeIndex, tI: Parser.NodeIndex, loc: Lexer.Location) std.mem.Allocator.Error!void {
    if (self.includesConstant(aI)) return self.foundConstant(aI, tI, loc);
    const i = self.variable.varTOset.get(aI).?;
    const ta = self.variable.setTOType.getPtr(i).?;
    if (ta.*) |_| {
        const oldTuOP = self.getRoot(ta);
        if (oldTuOP) |oldTu| {
            const oldT = self.ast.getNode(oldTu[0]);
            const t = self.ast.getNode(tI);
            if (oldT.getTokenTagAst(self.ast.*) != t.getTokenTagAst(self.ast.*)) {
                const a = self.ast.getNode(aI);
                Logger.logLocation.err(self.ast.path, a.getLocationAst(self.ast.*), "Found this variable used in 2 different contexts (ambiguous typing) {s}", .{Logger.placeSlice(a.getLocationAst(self.ast.*), self.ast.source)});
                Logger.logLocation.info(self.ast.path, oldTu[1], "Type inferred is: {s}, found here {s}", .{ oldT.getNameAst(self.ast.*), Logger.placeSlice(oldTu[1], self.ast.source) });
                Logger.logLocation.info(self.ast.path, loc, "But later found here used in an other context: {s} {s}", .{ t.getNameAst(self.ast.*), Logger.placeSlice(loc, self.ast.source) });
            }
        } else {
            self.setRoot(ta, .{
                tI,
                loc,
            });
        }
    } else {
        ta.* = .{
            .root = .{
                tI,
                loc,
            },
        };
    }
}

pub fn includesVariable(self: @This(), a: Parser.NodeIndex) bool {
    return self.variable.varTOset.contains(a);
}

pub fn includesConstant(self: @This(), a: Parser.NodeIndex) bool {
    return self.constant.varTOset.contains(a);
}

pub fn includes(self: @This(), a: Parser.NodeIndex) bool {
    return self.includesConstant(a) or self.includesVariable(a);
}

pub fn printState(self: *@This()) void {
    var it = self.variable.varTOset.iterator();

    while (it.next()) |entry| {
        const setIndex = entry.value_ptr;
        Logger.log.info("Set {}:", .{setIndex.*});
        const set = self.variable.setTOType.getPtr(setIndex.*).?;

        if (self.getRoot(set)) |t| {
            Logger.log.info("{s}", .{self.ast.getNode(t[0]).getNameAst(self.ast.tokens)});
            Logger.logLocation.info(self.ast.path, t[1], "Found here: {s}", .{Logger.placeSlice(t[1], self.ast.source)});
        }

        const value = entry.key_ptr.*;
        Logger.logLocation.info(self.ast.path, self.ast.getNode(value).getLocationAst(self.ast.tokens), "{}: {s}", .{ value, Logger.placeSlice(self.ast.getNode(value).getLocationAst(self.ast.tokens), self.ast.source) });
    }

    var itConstant = self.constant.varTOset.iterator();

    while (itConstant.next()) |entry| {
        const setIndex = entry.value_ptr;
        Logger.log.info("Set {}:", .{setIndex.*});
        const set = self.constant.setTOvar.get(setIndex.*).?;
        var setIt = set.iterator();

        while (setIt.next()) |indexTypeLoc| {
            const r = self.variable.setTOType.getPtr(indexTypeLoc.key_ptr.*).?;
            if (self.getRoot(r)) |t| {
                Logger.log.info("{s}", .{self.ast.getNode(t[0]).getNameAst(self.ast.tokens)});
                Logger.logLocation.info(self.ast.path, t[1], "Found here: {s}", .{Logger.placeSlice(t[1], self.ast.source)});
            }

            const value = entry.key_ptr.*;
            Logger.logLocation.info(self.ast.path, self.ast.getNode(value).getLocationAst(self.ast.tokens), "{}: {s}", .{ value, Logger.placeSlice(self.ast.getNode(value).getLocationAst(self.ast.tokens), self.ast.source) });
        }
    }
}
