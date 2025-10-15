const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Parser = @import("./../Parser/Parser.zig");
const Scopes = @import("./Scopes.zig");
const TypeChecker = @import("TypeCheck.zig").TypeChecker;

pub const FlattenExpression = std.ArrayList(Parser.NodeIndex);

pub const Type = enum {
    unknownIdentifier,
};

scopes: Scopes,

t: Type,

dep: Parser.NodeIndex,
state: ?*FlattenExpression,

expectedTypeI: Parser.NodeIndex,

pub fn resolve(self: *Self, alloc: Allocator, checker: *TypeChecker) std.mem.Allocator.Error!bool {
    switch (self.t) {
        .unknownIdentifier => {
            const node = checker.ast.getNode(self.dep);
            _ = checker.ctx.searchVariableScope(node.getTextAst(checker.ast)) orelse return false;

            const temp = checker.ctx.swap(self.scopes);

            try checker.checkFlattenExpression(alloc, self.state.?, self.expectedTypeI);

            checker.ctx.restore(temp);

            self.scopes.deinit(alloc);
        },
    }
    return true;
}

pub fn report(self: *Self, alloc: Allocator, checker: *TypeChecker) void {
    checker.message.err.unknownIdentifier(self.dep);
    self.scopes.deinit(alloc);
}
