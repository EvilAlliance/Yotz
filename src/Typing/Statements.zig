pub fn recordVariable(self: *const TranslationUnit, alloc: Allocator, variable: *Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Scope.Error)!void {
    self.scope.put(alloc, variable.getText(self.global), variable) catch |err| switch (err) {
        Scope.Error.KeyAlreadyExists => {
            const original = self.scope.get(variable.getText(self.global)).?;
            Report.redefinition(reports, variable, original);
            return Scope.Error.KeyAlreadyExists;
        },
        else => return @errorCast(err),
    };
}

pub fn recordFunctionArgs(self: *const TranslationUnit, alloc: Allocator, args_: *Parser.Node, reports: ?*Report.Reports) (Allocator.Error)!void {
    var args = args_;
    while (true) {
        self.scope.put(alloc, args.getText(self.global), args) catch |err| switch (err) {
            Scope.Error.KeyAlreadyExists => {
                const original = self.scope.get(args.getText(self.global)).?;
                Report.redefinition(reports, args, original);
            },
            else => return @errorCast(err),
        };

        const argsI = args.next.load(.acquire);
        if (argsI == 0) break;
        args = self.global.nodes.getPtr(argsI);
    }
}

pub fn traceVariable(self: *const TranslationUnit, alloc: Allocator, variable: *const Parser.Node) Allocator.Error!void {
    const expressionIndex = variable.data.@"1".load(.acquire);
    const expressionNode = self.global.nodes.get(expressionIndex);
    const expressionTag = expressionNode.tag.load(.acquire);

    if (expressionIndex == 0 or expressionTag == .funcProto) {
        return;
    } else {
        var expr = try Expression.init(alloc, self);
        defer expr.deinit(alloc);

        try expr.traceVariable(alloc, variable);
    }
}

pub fn checkVariable(self: *const TranslationUnit, alloc: Allocator, node: *Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const typeIndex = node.data[0].load(.acquire);

    var expr = try Expression.init(alloc, self);
    defer expr.deinit(alloc);

    if (typeIndex == 0) {
        if (!try expr.inferType(alloc, node, self.global.nodes.getConstPtr(node.data.@"1".load(.acquire)), reports)) return;
        expr.reset();
    } else {
        const t = self.global.nodes.getPtr(typeIndex);
        Type.transformType(self, t);
    }

    const typeIndex2 = node.data.@"0".load(.acquire);
    std.debug.assert(typeIndex2 != 0);
    const exprI = node.data.@"1".load(.acquire);

    try expr.checkType(alloc, self.global.nodes.getPtr(exprI), self.global.nodes.getConstPtr(typeIndex2), reports);
}

pub fn checkReturn(self: *const TranslationUnit, alloc: Allocator, stmt: *const Parser.Node, type_: *const Parser.Node, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    var expr = try Expression.init(alloc, self);
    defer expr.deinit(alloc);
    try expr.checkType(alloc, self.global.nodes.getPtr(stmt.data[1].load(.acquire)), type_, reports);
}

const Expression = @import("Expression.zig");
const Type = @import("Type.zig");
const Scope = @import("Scope/mod.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
