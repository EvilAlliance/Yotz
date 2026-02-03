pub const Error = error{
    ReserveIdentifier,
    AssignmentConstant,
};

pub fn recordVariable(self: *const TranslationUnit, alloc: Allocator, variable: *Parser.Node.VarConst, reports: ?*Report.Reports) (Allocator.Error || Scope.Error || Error)!void {
    if (Type.isIdenType(self.global, variable.as().asDeclarator()))
        return Report.reservedIdentifier(reports, variable.as().asDeclarator());
    self.scope.put(alloc, variable.getText(self.global), variable.as().asDeclarator()) catch |err| switch (err) {
        Scope.Error.KeyAlreadyExists => {
            const original = self.scope.get(variable.getText(self.global)).?;
            Report.redefinition(reports, variable.as(), original.as());
            return Scope.Error.KeyAlreadyExists;
        },
        else => return @errorCast(err),
    };
}

pub fn recordFunctionArgs(self: *const TranslationUnit, alloc: Allocator, args_: *Parser.Node.ProtoArg, reports: ?*Report.Reports) (Allocator.Error)!void {
    var args = args_;
    while (true) {
        self.scope.put(alloc, args.getText(self.global), args.as().asDeclarator()) catch |err| switch (err) {
            Scope.Error.KeyAlreadyExists => {
                const original = self.scope.get(args.getText(self.global)).?;
                Report.redefinition(reports, args.asConst(), original.as());
            },
            else => return @errorCast(err),
        };

        const argsI = args.next.load(.acquire);
        if (argsI == 0) break;
        args = self.global.nodes.getPtr(argsI).asProtoArg();
    }
}

pub fn traceVariable(self: *const TranslationUnit, alloc: Allocator, variable: *const Parser.Node.VarConst) Allocator.Error!void {
    const expressionIndex = variable.expr.load(.acquire);
    const expression = self.global.nodes.getConstPtr(expressionIndex).asConstExpression();
    const expressionTag = expression.tag.load(.acquire);

    if (expressionIndex == 0 or expressionTag == .funcProto) {
        return;
    } else {
        var expr = try Expression.init(alloc, self);
        defer expr.deinit(alloc);

        try expr.traceVariable(alloc, variable);
    }
}

pub fn checkAssignment(self: *const TranslationUnit, alloc: Allocator, assignment: *Parser.Node.Assignment, reports: ?*Report.Reports) (Allocator.Error || Expression.Error || Error)!void {
    const id = assignment.getText(self.global);
    const variable = self.scope.get(id) orelse return Report.undefinedVariable(reports, assignment.asConst());

    if (variable.tag.load(.acquire) == .protoArg) return Report.argumentsAreConstant(reports, assignment, variable.asConstProtoArg());
    if (variable.tag.load(.acquire) == .constant) return Report.assignmentToConstant(reports, assignment, variable.asVarConst());

    var exprChecker = try Expression.init(alloc, self);
    defer exprChecker.deinit(alloc);

    const exprI = assignment.expr.load(.acquire);
    const typeI = variable.type.load(.acquire);

    const expr =
        self.global.nodes.getPtr(exprI).asExpression();

    if (typeI == 0) {
        _ = try exprChecker.inferType(alloc, variable.asVarConst(), expr, reports);
        return;
    }
    try exprChecker.checkType(
        alloc,
        expr,
        self.global.nodes.getConstPtr(typeI).asConstTypes(),
        reports,
    );
}

pub fn checkVariable(self: *const TranslationUnit, alloc: Allocator, variable: *Parser.Node.VarConst, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    const typeIndex = variable.type.load(.acquire);

    var expr = try Expression.init(alloc, self);
    defer expr.deinit(alloc);

    if (typeIndex == 0) {
        _ = try expr.inferType(alloc, variable, self.global.nodes.getConstPtr(variable.expr.load(.acquire)).asConstExpression(), reports);
        return;
    }

    const typeIndex2 = variable.type.load(.acquire);
    std.debug.assert(typeIndex2 != 0);
    const exprI = variable.expr.load(.acquire);

    try expr.checkType(alloc, self.global.nodes.getPtr(exprI).asExpression(), self.global.nodes.getConstPtr(typeIndex2).asConstTypes(), reports);
}

pub fn checkReturn(self: *const TranslationUnit, alloc: Allocator, stmt: *const Parser.Node.Return, type_: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error || Expression.Error)!void {
    var expr = try Expression.init(alloc, self);
    defer expr.deinit(alloc);
    try expr.checkType(alloc, self.global.nodes.getPtr(stmt.expr.load(.acquire)).asExpression(), type_, reports);
}

const Expression = @import("Expression.zig");
const Type = @import("Type.zig");
const Scope = @import("Scope/mod.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
