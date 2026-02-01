pub fn typing(self: *const TranslationUnit, alloc: Allocator, func: *const Parser.Node.FuncProto, reports: ?*Report.Reports) Allocator.Error!void {
    std.debug.assert(func.tag.load(.acquire) == .funcProto);

    const tIndex = func.retType.load(.acquire);
    const t = self.global.nodes.getPtr(tIndex);
    if (Parser.Node.isFakeTypes(t.tag.load(.acquire))) Type.transformType(self, t.asFakeTypes());
    assert(Parser.Node.isTypes(t.tag.load(.acquire)));

    try self.scope.push(alloc);
    defer self.scope.pop(alloc);

    const argsI = func.args.load(.acquire);
    if (argsI != 0) try Statement.recordFunctionArgs(self, alloc, self.global.nodes.getPtr(argsI).asProtoArg(), reports);

    const stmtORscopeIndex = func.scope.load(.acquire);
    const stmtORscope = self.global.nodes.get(stmtORscopeIndex);

    try self.scope.push(alloc);
    defer self.scope.pop(alloc);

    const type_ = self.global.nodes.getConstPtr(tIndex).asConstTypes();
    {
        self.global.observer.mutex.lock();
        defer self.global.observer.mutex.unlock();
        if (!self.global.readyTu.get(self.id).load(.acquire)) {
            const i = if (stmtORscope.tag.load(.acquire) == .scope) stmtORscope.left.load(.acquire) else stmtORscopeIndex;
            try self.global.observer.pushUnlock(alloc, self.id, resumeScopeCheck, .{ try Util.dupe(alloc, try self.acquire(alloc)), alloc, i, type_, reports });
            return;
        }
    }
    const ret = if (stmtORscope.tag.load(.acquire) == .scope)
        try checkScope(self, alloc, stmtORscopeIndex, type_, reports)
    else
        try _checkScope(self, alloc, stmtORscopeIndex, type_, reports);

    if (!ret) Report.missingReturn(reports, type_.asConst());
}

fn checkScope(self: *const TranslationUnit, alloc: Allocator, scopeIndex: Parser.NodeIndex, retType: *const Parser.Node.Types, reports: ?*Report.Reports) Allocator.Error!bool {
    const scope = self.global.nodes.get(scopeIndex);

    const retTypeTag = retType.tag.load(.acquire);
    std.debug.assert(scope.tag.load(.acquire) == .scope and retTypeTag == .type or retTypeTag == .funcType);

    const i = scope.left.load(.acquire);

    return try _checkScope(self, alloc, i, retType, reports);
}

fn _checkScope(self: *const TranslationUnit, alloc: Allocator, stmtI: Parser.NodeIndex, type_: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error)!bool {
    var ret = false;
    var i = stmtI;

    while (i != 0) {
        const stmt = self.global.nodes.getPtr(i);

        checkStatements(self, alloc, stmt.asStatement(), type_, reports) catch |err| switch (err) {
            Expression.Error.TooBig, Expression.Error.IncompatibleType, Expression.Error.UndefVar => {},
            Scope.Error.KeyAlreadyExists => {},
            else => return @errorCast(err),
        };

        if (ret) Report.unreachableStatement(reports, stmt);

        const tag = stmt.tag.load(.acquire);
        if (tag == .ret) ret = true;

        i = stmt.next.load(.acquire);
    }

    return ret;
}

fn checkStatements(self: *const TranslationUnit, alloc: Allocator, stmt: *Parser.Node.Statement, retType: *const Parser.Node.Types, reports: ?*Report.Reports) (Allocator.Error || Expression.Error || Scope.Error)!void {
    const tag = stmt.tag.load(.acquire);
    switch (tag) {
        .ret => try Statement.checkReturn(self, alloc, stmt.asConstReturn(), retType, reports),
        .variable, .constant => {
            Statement.checkVariable(self, alloc, stmt.asVarConst(), reports) catch |err| {
                try Statement.recordVariable(self, alloc, stmt.asVarConst(), reports);
                return err;
            };
            try Statement.recordVariable(self, alloc, stmt.asVarConst(), reports);
        },
        else => unreachable,
    }
}

comptime {
    if (@typeInfo(@TypeOf(resumeScopeCheck)).@"fn".return_type != void) @compileError("resumeScopeCheck must not return an error");
}
pub fn resumeScopeCheck(args: Global.Args) void {
    const tu, const alloc, const stmtI, const retTypeI, const reports = args;

    const ret = _checkScope(tu, alloc, stmtI, retTypeI, reports) catch {
        std.debug.panic("Run Ouf of Memory", .{});
    };

    if (!ret) Report.missingReturn(reports, retTypeI.asConst());
}

const Expression = @import("Expression.zig");
const Type = @import("Type.zig");
const Scope = @import("Scope/mod.zig");

const TranslationUnit = @import("../TranslationUnit.zig");
const Parser = @import("../Parser/mod.zig");
const Report = @import("../Report/mod.zig");
const Statement = @import("Statements.zig");
const Global = @import("../Global.zig");

const Util = @import("../Util.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
