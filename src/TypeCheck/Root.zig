pub fn typing(self: TranslationUnit, alloc: Allocator, rootIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    try record(self, alloc, rootIndex, reports);

    assert(self.global.readyTu.getPtr(self.id).cmpxchgStrong(false, true, .acq_rel, .monotonic) == null);
    self.global.readyTu.unlock();
    try self.global.observer.alert(alloc, self.id);

    try check(self, alloc, rootIndex, reports);
}

fn record(self: TranslationUnit, alloc: Allocator, rootIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const root = self.global.nodes.get(rootIndex);

    var stmtI = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (stmtI != endIndex) {
        const stmt = self.global.nodes.get(stmtI);
        defer stmtI = stmt.next.load(.acquire);

        const tag = stmt.tag.load(.acquire);

        assert(tag == .variable or tag == .constant);
        Statement.recordVariable(self, alloc, stmtI, reports) catch |err| switch (err) {
            Scope.Error.KeyAlreadyExists => try Report.redefinition(alloc, reports, stmtI, self.scope.get(stmt.getText(self.global)).?),
            else => return @errorCast(err),
        };
    }
}

fn check(self: TranslationUnit, alloc: Allocator, rootIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const root = self.global.nodes.get(rootIndex);

    var stmtI = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (stmtI != endIndex) {
        const stmt = self.global.nodes.get(stmtI);
        defer stmtI = stmt.next.load(.acquire);

        const tag = stmt.tag.load(.acquire);

        assert(tag == .variable or tag == .constant);
        Statement.checkVariable(self, alloc, stmtI, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType, Expression.Error.UndefVar => continue,
            else => return @errorCast(err),
        };
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
