pub fn typing(self: *const TranslationUnit, alloc: Allocator, root: *const Parser.Node, reports: ?*Report.Reports) Allocator.Error!void {
    try record(self, alloc, root, reports);

    assert(self.global.readyTu.getPtr(self.id).cmpxchgStrong(false, true, .acq_rel, .monotonic) == null);
    self.global.readyTu.unlock();

    try self.global.observer.alert(self.id);

    try check(self, alloc, root, reports);

    try cycleCheck(self, alloc, root);
}

fn record(self: *const TranslationUnit, alloc: Allocator, root: *const Parser.Node, reports: ?*Report.Reports) Allocator.Error!void {
    var stmtI = root.left.load(.acquire);
    const endIndex = root.right.load(.acquire);

    while (stmtI != endIndex) {
        const stmt = self.global.nodes.getPtr(stmtI);
        defer stmtI = stmt.next.load(.acquire);

        const tag = stmt.tag.load(.acquire);

        assert(tag == .variable or tag == .constant);
        Statement.recordVariable(self, alloc, stmt, reports) catch |err| switch (err) {
            Scope.Error.KeyAlreadyExists => {},
            else => return @errorCast(err),
        };
    }
}

fn check(self: *const TranslationUnit, alloc: Allocator, root: *const Parser.Node, reports: ?*Report.Reports) Allocator.Error!void {
    var stmtI = root.left.load(.acquire);
    const endIndex = root.right.load(.acquire);

    while (stmtI != endIndex) {
        const stmt = self.global.nodes.getPtr(stmtI);
        defer stmtI = stmt.next.load(.acquire);

        const tag = stmt.tag.load(.acquire);

        assert(tag == .variable or tag == .constant);
        Statement.checkVariable(self, alloc, stmt, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType, Expression.Error.UndefVar => continue,
            else => return @errorCast(err),
        };
    }
}

fn cycleCheck(self: *const TranslationUnit, alloc: Allocator, root: *const Parser.Node) Allocator.Error!void {
    var stmtI = root.left.load(.acquire);
    const endIndex = root.right.load(.acquire);

    while (stmtI != endIndex) {
        const stmt = self.global.nodes.getPtr(stmtI);
        defer stmtI = stmt.next.load(.acquire);

        const tag = stmt.tag.load(.acquire);

        assert(tag == .variable or tag == .constant);
        try Statement.traceVariable(self, alloc, stmt);
    }
}

const Expression = @import("Expression.zig");
const Scope = @import("Scope/mod.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");
const Statement = @import("Statements.zig");

const std = @import("std");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
