const Self = @This();

message: union(enum) {
    unexpectedToken: mod.UnexpectedToken,
    incompatibleType: mod.IncompatibleType,
    incompatibleLiteral: mod.IncompatibleLiteral,
},

pub fn display(self: *const Self, message: mod.Message) void {
    switch (self.message) {
        .unexpectedToken => |ut| ut.display(message),
        .incompatibleType => |it| it.display(message),
        .incompatibleLiteral => |il| il.display(message),
    }
}

pub fn expect(alloc: Allocator, reports: ?*mod.Reports, token: Lexer.Token, t: []const Lexer.Token.Type) (Allocator.Error || Parser.Parser.Error)!void {
    const is = Util.listContains(Lexer.Token.Type, t, token.tag);
    if (is) return;
    if (reports) |rs| {
        const ex = try alloc.dupe(Lexer.Token.Type, t);
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

pub fn incompatibleLiteral(alloc: Allocator, reports: ?*mod.Reports, literal: Parser.NodeIndex, expectedType: Parser.NodeIndex) (Allocator.Error || TypeCheck.Expression.Error)!void {
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

pub fn incompatibleType(alloc: Allocator, reports: ?*mod.Reports, actualType: Parser.NodeIndex, expectedType: Parser.NodeIndex, place: Parser.NodeIndex, declared: Parser.NodeIndex) (Allocator.Error || TypeCheck.Expression.Error)!Self {
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

const mod = @import("mod.zig");

const Util = @import("../Util.zig");

const Lexer = @import("../Lexer/mod.zig");
const Parser = @import("../Parser/mod.zig");
const TypeCheck = @import("../TypeCheck/mod.zig");

const std = @import("std");

const Allocator = std.mem.Allocator;
