pub fn check(self: TranslationUnit, alloc: Allocator, funcIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const func = self.global.nodes.get(funcIndex);
    std.debug.assert(func.tag.load(.acquire) == .funcProto);

    const tIndex = func.data[1].load(.acquire);
    Type.transformType(self, tIndex);

    const stmtORscopeIndex = func.next.load(.acquire);
    const stmtORscope = self.global.nodes.get(stmtORscopeIndex);

    try self.scope.push(alloc);
    defer self.scope.pop(alloc);
    if (stmtORscope.tag.load(.acquire) == .scope) {
        try checkScope(self, alloc, stmtORscopeIndex, tIndex, reports);
    } else {
        checkStatements(self, alloc, stmtORscopeIndex, tIndex, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType => return,
            else => return @errorCast(err),
        };
    }
}

// TODO: Add scope to this
fn checkScope(self: TranslationUnit, alloc: Allocator, scopeIndex: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const scope = self.global.nodes.get(scopeIndex);
    const retType = self.global.nodes.get(typeI);

    std.debug.assert(scope.tag.load(.acquire) == .scope and retType.tag.load(.acquire) == .type);

    var i = scope.data[0].load(.acquire);

    while (i != 0) {
        const stmt = self.global.nodes.get(i);
        defer i = stmt.next.load(.acquire);

        checkStatements(self, alloc, i, typeI, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType => continue,
            else => return @errorCast(err),
        };
    }
}

fn checkStatements(self: TranslationUnit, alloc: Allocator, stmtI: Parser.NodeIndex, retTypeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    _ = .{ alloc, retTypeI };
    const stmt = self.global.nodes.get(stmtI);

    switch (stmt.tag.load(.acquire)) {
        .ret => try Statement.checkReturn(self, alloc, stmtI, retTypeI, reports),
        .variable, .constant => try Statement.checkVariable(self, alloc, stmtI, reports),
        else => unreachable,
    }
}

const Expression = @import("Expression.zig");
const Type = @import("Type.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");
const Statement = @import("Statements.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
