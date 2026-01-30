const Self = @This();

message: union(enum) {
    unexpectedToken: mod.UnexpectedToken,
    incompatibleType: mod.IncompatibleType,
    incompatibleLiteral: mod.IncompatibleLiteral,
    missingMain: mod.MissingMain,
    undefinedVariable: mod.UndefinedVariable,
    redefinition: mod.Redefinition,
    definedLater: mod.DefinedLater,
    dependencyCycle: mod.DependencyCycle,
    mustReturnU8: mod.MustReturnU8,
    missingReturn: mod.MissingReturn,
    unreachableStatement: mod.UnreachableStatement,
    expectedFunction: mod.ExpectedFunction,
    incompatibleReturnType: mod.IncompatibleReturnType,
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
        .dependencyCycle => |dc| dc.display(message),
        .mustReturnU8 => |mru| mru.display(message),
        .missingReturn => |mr| mr.display(message),
        .unreachableStatement => |us| us.display(message),
        .expectedFunction => |ef| ef.display(message),
        .incompatibleReturnType => |irt| irt.display(message),
    }
}

pub fn expect(reports: ?*mod.Reports, token: Lexer.Token, t: []const Lexer.Token.Type) (Parser.Parser.Error)!void {
    const is = Util.listContains(Lexer.Token.Type, t, token.tag);
    if (is) return;
    if (reports) |rs| {
        const ex = t;
        rs.appendBounded(.{
            .message = .{
                .unexpectedToken = mod.UnexpectedToken{
                    .expected = ex,
                    .found = token.tag,
                    .loc = token.loc,
                },
            },
        }) catch {};
    }

    return Parser.Parser.Error.UnexpectedToken;
}

pub fn incompatibleLiteral(reports: ?*mod.Reports, literal: *const Parser.Node, expectedType: *const Parser.Node) (Typing.Expression.Error) {
    if (reports) |rs| rs.appendBounded(.{
        .message = .{
            .incompatibleLiteral = .{
                .literal = literal,
                .expectedType = expectedType,
            },
        },
    }) catch {};

    return Typing.Expression.Error.TooBig;
}

pub fn incompatibleType(reports: ?*mod.Reports, actualType: *const Parser.Node, expectedType: *const Parser.Node, place: *const Parser.Node, declared: *const Parser.Node) (Typing.Expression.Error) {
    if (reports) |rs| rs.appendBounded(.{
        .message = .{
            .incompatibleType = .{
                .actualType = actualType,
                .expectedType = expectedType,

                .place = place,
                .declared = declared,
            },
        },
    }) catch {};

    return Typing.Expression.Error.IncompatibleType;
}

pub fn missingMain(reports: ?*mod.Reports) void {
    if (reports) |rs| rs.appendBounded(.{
        .message = .{
            .missingMain = .{},
        },
    }) catch {};
}

pub fn undefinedVariable(reports: ?*mod.Reports, name: *const Parser.Node) (Typing.Expression.Error) {
    if (reports) |rs| {
        rs.appendBounded(.{
            .message = .{
                .undefinedVariable = .{
                    .name = name,
                },
            },
        }) catch {};
    }

    return Typing.Expression.Error.UndefVar;
}

pub fn redefinition(reports: ?*mod.Reports, name: *const Parser.Node, original: *const Parser.Node) void {
    if (reports) |rs| {
        rs.appendBounded(.{
            .message = .{
                .redefinition = .{
                    .name = name,
                    .original = original,
                },
            },
        }) catch {};
    }
}

pub fn definedLater(reports: ?*mod.Reports, name: *const Parser.Node, definition: *const Parser.Node) (Typing.Expression.Error) {
    if (reports) |rs| {
        try rs.appendBounded(.{
            .message = .{
                .definedLater = .{
                    .name = name,
                    .definition = definition,
                },
            },
        }) catch {};
    }

    return Typing.Expression.Error.UndefVar;
}

pub fn dependencyCycle(alloc: Allocator, cycle: []const Typing.Expression.CycleUnit) Allocator.Error!Self {
    const cycleCopy = try alloc.dupe(Typing.Expression.CycleUnit, cycle);
    return .{
        .message = .{
            .dependencyCycle = .{
                .cycle = cycleCopy,
            },
        },
    };
}

pub fn mustReturnU8(reports: ?*mod.Reports, name: []const u8, type_: *const Parser.Node) void {
    if (reports) |rs| {
        rs.appendBounded(.{
            .message = .{
                .mustReturnU8 = .{
                    .functionName = name,
                    .type_ = type_,
                },
            },
        }) catch {};
    }
}

pub fn missingReturn(reports: ?*mod.Reports, returnType: *const Parser.Node) void {
    if (reports) |rs| {
        rs.appendBounded(.{
            .message = .{
                .missingReturn = .{
                    .returnType = returnType,
                },
            },
        }) catch {};
    }
}

pub fn unreachableStatement(reports: ?*mod.Reports, statement: *const Parser.Node) void {
    if (reports) |rs| {
        rs.appendBounded(.{
            .message = .{
                .unreachableStatement = .{
                    .statement = statement,
                },
            },
        }) catch {};
    }
}

pub fn expectedFunction(reports: ?*mod.Reports, variable: *const Parser.Node, declared: *const Parser.Node) (Typing.Expression.Error) {
    if (reports) |rs| {
        rs.appendBounded(.{
            .message = .{
                .expectedFunction = .{
                    .variable = variable,
                    .declared = declared,
                },
            },
        }) catch {};
    }

    return Typing.Expression.Error.IncompatibleType;
}

pub fn incompatibleReturnType(reports: ?*mod.Reports, actualReturnType: *const Parser.Node, expectedReturnType: *const Parser.Node, place: *const Parser.Node, declared: *const Parser.Node) (Typing.Expression.Error) {
    if (reports) |rs| {
        rs.appendBounded(.{
            .message = .{
                .incompatibleReturnType = .{
                    .actualReturnType = actualReturnType,
                    .expectedReturnType = expectedReturnType,
                    .place = place,
                    .declared = declared,
                },
            },
        }) catch {};
    }

    return Typing.Expression.Error.IncompatibleType;
}

const mod = @import("mod.zig");

const Util = @import("../Util.zig");
const Lexer = @import("../Lexer/mod.zig");
const Parser = @import("../Parser/mod.zig");
const Typing = @import("../Typing/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
