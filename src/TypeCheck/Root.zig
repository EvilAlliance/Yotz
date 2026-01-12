pub fn check(self: TranslationUnit, alloc: Allocator, rootIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const root = self.global.nodes.get(rootIndex);
    var tryAgain = false;

    var stmtI = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (stmtI != endIndex) {
        const stmt = self.global.nodes.get(stmtI);
        defer stmtI = stmt.next.load(.acquire);

        const tag = stmt.tag.load(.acquire);

        assert(tag == .variable or tag == .constant);
        Statement.checkVariable(self, alloc, stmtI, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType => continue,
            Expression.Error.UndefVar => tryAgain = true,
            else => return @errorCast(err),
        };
    }

    if (tryAgain)
        try reTry(self, alloc, rootIndex, reports)
    else
        try self.global.observer.alert(alloc, self.id);
}

fn reTry(self: TranslationUnit, alloc: Allocator, rootIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const State = enum {
        Unchanged,
        Changed,
        ToReport,
    };

    var state: State = State.Changed;

    const root = self.global.nodes.get(rootIndex);

    var stmtI = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (state == State.Changed) {
        try self.global.observer.alert(alloc, self.id);
        state = State.Unchanged;

        while (stmtI != endIndex) {
            const stmt = self.global.nodes.get(stmtI);
            defer stmtI = stmt.next.load(.acquire);

            const tag = stmt.tag.load(.acquire);
            assert(tag == .variable or tag == .constant);

            if (self.scope.get(stmt.getText(self.global))) |_| continue;

            Statement.checkVariable(self, alloc, stmtI, reports) catch |err| switch (err) {
                Expression.Error.TooBig, Expression.Error.IncompatibleType => continue,
                Expression.Error.UndefVar => {
                    if (state == State.Unchanged) state = State.ToReport;
                },
                else => return @errorCast(err),
            };

            state = State.Changed;
        }
    }

    if (state == State.ToReport) @panic("TODO:");
}

const Expression = @import("Expression.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");
const Statement = @import("Statements.zig");

const std = @import("std");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
