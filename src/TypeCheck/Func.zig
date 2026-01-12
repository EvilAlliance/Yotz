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
        try _checkScope(self, alloc, stmtORscopeIndex, tIndex, reports);
    }
}

// TODO: Add scope to this
fn checkScope(self: TranslationUnit, alloc: Allocator, scopeIndex: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const scope = self.global.nodes.get(scopeIndex);
    const retType = self.global.nodes.get(typeI);

    std.debug.assert(scope.tag.load(.acquire) == .scope and retType.tag.load(.acquire) == .type);

    const i = scope.data[0].load(.acquire);

    try _checkScope(self, alloc, i, typeI, reports);
}

fn _checkScope(self: TranslationUnit, alloc: Allocator, stmtI: Parser.NodeIndex, typeI: Parser.NodeIndex, reports: ?*Report.Reports) (Allocator.Error)!void {
    var i = stmtI;

    while (i != 0) {
        const stmt = self.global.nodes.get(i);

        checkStatements(self, alloc, i, typeI, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType => {},
            Expression.Error.UndefVar => {
                self.global.observer.mutex.lock();
                defer self.global.observer.mutex.unlock();

                if (!try Expression.hasUndef(self, alloc, stmt.data[1].load(.acquire))) continue;

                try self.global.observer.pushUnlock(alloc, self.id, resumeScopeCheck, .{ try Util.dupe(alloc, try self.acquire(alloc)), alloc, i, typeI, reports });
                return;
            },
            else => return @errorCast(err),
        };

        i = stmt.next.load(.acquire);
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

comptime {
    if (@typeInfo(@TypeOf(resumeScopeCheck)).@"fn".return_type != void) @compileError("resumeScopeCheck must not return an error");
}
pub fn resumeScopeCheck(args: Global.Args) void {
    const tu, const alloc, const stmtI, const retTypeI, const reports = args;

    _checkScope(tu.*, alloc, stmtI, retTypeI, reports) catch {
        std.debug.panic("Run Ouf of Memory", .{});
    };
}

const Expression = @import("Expression.zig");
const Type = @import("Type.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");
const Statement = @import("Statements.zig");
const Global = @import("../Global.zig");

const Util = @import("../Util.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
