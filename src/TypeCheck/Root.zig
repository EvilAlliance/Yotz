pub fn check(self: TranslationUnit, alloc: Allocator, rootIndex: Parser.NodeIndex, reports: ?*Report.Reports) Allocator.Error!void {
    const root = self.global.nodes.get(rootIndex);

    var nodeIndex = root.data.@"0".load(.acquire);
    const endIndex = root.data.@"1".load(.acquire);

    while (nodeIndex != endIndex) {
        const node = self.global.nodes.get(nodeIndex);
        defer nodeIndex = node.next.load(.acquire);

        switch (node.tag.load(.acquire)) {
            .variable, .constant => Statement.checkVariable(self, alloc, nodeIndex, reports) catch |err| switch (err) {
                Expression.Error.TooBig, Expression.Error.IncompatibleType => continue,
                else => return @errorCast(err),
            },
            else => unreachable,
        }
    }
}

const Expression = @import("Expression.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");
const Statement = @import("Statements.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
