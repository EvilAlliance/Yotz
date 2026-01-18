const Self = @This();

message: union(enum) {
    unexpectedToken: mod.UnexpectedToken,
    incompatibleType: mod.IncompatibleType,
    incompatibleLiteral: mod.IncompatibleLiteral,
    missingMain: mod.MissingMain,
    undefinedVariable: mod.UndefinedVariable,
    redefinition: mod.Redefinition,
    definedLater: mod.DefinedLater,
},

pub fn display(self: *const Self, message: mod.Message) void {
    switch (self.message) {
        .unexpectedToken => |ut| ut.display(message),
        .incompatibleType => |it| it.display(message),
        .incompatibleLiteral => |il| il.display(message),
        .missingMain => |mm| mm.display(message),
        .undefinedVariable => |uv| uv.display(message),
        .redefinition => |rd| rd.display(message),
        .definedLater => |dl| dl.display(message),
    }
}

pub fn expect(alloc: Allocator, reports: ?*mod.Reports, token: Lexer.Token, t: []const Lexer.Token.Type) (Allocator.Error || Parser.Parser.Error)!void {
    const is = Util.listContains(Lexer.Token.Type, t, token.tag);
    if (is) return;
    if (reports) |rs| {
        const ex = t;
        try rs.append(alloc, .{
            .message = .{
                .unexpectedToken = mod.UnexpectedToken{
                    .expected = ex,
                    .found = token.tag,
                    .loc = token.loc,
                },
            },
        });
    }

    return Parser.Parser.Error.UnexpectedToken;
}

pub fn incompatibleLiteral(alloc: Allocator, reports: ?*mod.Reports, literal: Parser.NodeIndex, expectedType: Parser.NodeIndex) (Allocator.Error || TypeCheck.Expression.Error) {
    if (reports) |rs| try rs.append(alloc, .{
        .message = .{
            .incompatibleLiteral = .{
                .literal = literal,
                .expectedType = expectedType,
            },
        },
    });

    return TypeCheck.Expression.Error.TooBig;
}

pub fn incompatibleType(alloc: Allocator, reports: ?*mod.Reports, actualType: Parser.NodeIndex, expectedType: Parser.NodeIndex, place: Parser.NodeIndex, declared: Parser.NodeIndex) (Allocator.Error || TypeCheck.Expression.Error) {
    if (reports) |rs| try rs.append(alloc, .{
        .message = .{
            .incompatibleType = .{
                .actualType = actualType,
                .expectedType = expectedType,

                .place = place,
                .declared = declared,
            },
        },
    });

    return TypeCheck.Expression.Error.IncompatibleType;
}

pub fn missingMain(alloc: Allocator, reports: ?*mod.Reports) Allocator.Error!void {
    if (reports) |rs| try rs.append(alloc, .{
        .message = .{
            .missingMain = .{},
        },
    });
}

pub fn undefinedVariable(alloc: Allocator, reports: ?*mod.Reports, name: Parser.NodeIndex) (Allocator.Error || TypeCheck.Expression.Error) {
    if (reports) |rs| {
        try rs.append(alloc, .{
            .message = .{
                .undefinedVariable = .{
                    .name = name,
                },
            },
        });
    }

    return TypeCheck.Expression.Error.UndefVar;
}

pub fn redefinition(alloc: Allocator, reports: ?*mod.Reports, name: Parser.NodeIndex, original: Parser.NodeIndex) (Allocator.Error)!void {
    if (reports) |rs| {
        try rs.append(alloc, .{
            .message = .{
                .redefinition = .{
                    .name = name,
                    .original = original,
                },
            },
        });
    }
}

pub fn definedLater(alloc: Allocator, reports: ?*mod.Reports, name: Parser.NodeIndex, definition: Parser.NodeIndex) (Allocator.Error || TypeCheck.Expression.Error) {
    if (reports) |rs| {
        try rs.append(alloc, .{
            .message = .{
                .definedLater = .{
                    .name = name,
                    .definition = definition,
                },
            },
        });
    }

    return TypeCheck.Expression.Error.UndefVar;
}

const mod = @import("mod.zig");

const Util = @import("../Util.zig");
const Lexer = @import("../Lexer/mod.zig");
const Parser = @import("../Parser/mod.zig");
const TypeCheck = @import("../TypeCheck/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
