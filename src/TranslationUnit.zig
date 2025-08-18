const ParseArgs = @import("ParseArgs.zig");
const Logger = @import("./Logger.zig");
const std = @import("std");

const Parser = @import("./Parser/Parser.zig");
const typeCheck = @import("./TypeCheck/TypeCheck.zig").typeCheck;

pub const Temp = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    subCommand: ParseArgs.SubCommand,
    path: []const u8,

    stdout: bool,

    pub fn init(alloc: std.mem.Allocator, args: ParseArgs.Arguments) Self {
        return Self{
            .alloc = alloc,

            .subCommand = args.subCom,
            .path = args.path,

            .stdout = args.stdout,
        };
    }

    pub fn start(self: *const Self) std.mem.Allocator.Error!struct { []const u8, u8 } {
        var parser = Parser.init(self.alloc, self.path) orelse return .{ "", 1 };
        defer parser.deinit();

        if (self.subCommand == .Lexer)
            return .{ try parser.lexerToString(self.alloc), 0 };

        var ast = try parser.parse();

        for (parser.errors.items) |e| {
            e.display(ast.getInfo());
        }

        if (self.subCommand == .Parser)
            return .{ try ast.toString(self.alloc), 0 };

        const err = try typeCheck(self.alloc, &ast);

        if (self.subCommand == .TypeCheck and self.stdout)
            return .{ try ast.toString(self.alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };

        if (err) return .{ "", 1 };
        if (parser.errors.items.len > 0) return .{ "", 1 };

        unreachable;
    }

    pub fn deinit(self: *const Self, bytes: []const u8) void {
        self.alloc.free(bytes);
    }
};

const Global = struct {};
const Function = struct {};
