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

pub fn incompatibleLiteral(reports: ?*mod.Reports, literal: Parser.NodeIndex, expectedType: Parser.NodeIndex) (Typing.Expression.Error) {
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

pub fn incompatibleType(reports: ?*mod.Reports, actualType: Parser.NodeIndex, expectedType: Parser.NodeIndex, place: Parser.NodeIndex, declared: Parser.NodeIndex) (Typing.Expression.Error) {
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

pub fn undefinedVariable(reports: ?*mod.Reports, name: Parser.NodeIndex) (Typing.Expression.Error) {
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

pub fn redefinition(reports: ?*mod.Reports, name: Parser.NodeIndex, original: Parser.NodeIndex) void {
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

pub fn definedLater(reports: ?*mod.Reports, name: Parser.NodeIndex, definition: Parser.NodeIndex) (Typing.Expression.Error) {
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

const mod = @import("mod.zig");

const Util = @import("../Util.zig");
const Lexer = @import("../Lexer/mod.zig");
const Parser = @import("../Parser/mod.zig");
const Typing = @import("../Typing/mod.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
