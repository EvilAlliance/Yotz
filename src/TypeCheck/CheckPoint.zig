const Self = @This();

const std = @import("std");

const TypeCheck = @import("./TypeCheck.zig").TypeChecker;

const Scopes = @import("./Scopes.zig");
const Context = @import("./Context.zig");
const Parser = @import("./../Parser/Parser.zig");

const FlattenExpression = std.ArrayList(Parser.NodeIndex);

pub const Type = enum {
    unknownIdentifier,
};

scopes: Scopes,

t: Type,

dep: Parser.NodeIndex,
state: ?*FlattenExpression,

expectedTypeI: Parser.NodeIndex,

pub fn resolve(self: *Self, checker: *TypeCheck) std.mem.Allocator.Error!bool {
    switch (self.t) {
        .unknownIdentifier => {
            const node = checker.ast.getNode(self.dep);
            _ = checker.ctx.searchVariableScope(node.getTextAst(checker.ast)) orelse return false;

            const temp = checker.ctx.swap(self.scopes);

            try checker.checkFlattenExpression(self.state.?, self.expectedTypeI);

            checker.ctx.restore(temp);

            self.scopes.deinit();
        },
    }

    return true;
}

pub fn report(self: *Self, checker: *TypeCheck) void {
    switch (self.t) {
        .unknownIdentifier => {
            checker.message.err.unknownIdentifier(self.dep);
        },
    }
}
