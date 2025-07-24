const ParseArgs = @import("ParseArgs.zig");
const Logger = @import("./Logger.zig");
const std = @import("std");

const Parser = @import("./Parser/Parser.zig");
const typeCheck = @import("./TypeCheck/TypeCheck.zig").typeCheck;

pub const Temp = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    subCommand: ParseArgs.SubCommamd,
    path: []const u8,

    bench: bool,
    stdout: bool,

    pub fn init(alloc: std.mem.Allocator, args: ParseArgs.Arguments) Self {
        return Self{
            .alloc = alloc,

            .subCommand = args.subCom,
            .path = args.path,

            .bench = args.bench,
            .stdout = args.stdout,
        };
    }

    pub fn start(self: *const Self) std.mem.Allocator.Error!struct { []const u8, u8 } {
        var timer = std.time.Timer.start() catch unreachable;

        if (self.bench)
            Logger.log.info("Lexing and Parsing", .{});

        var parser = Parser.init(self.alloc, self.path) orelse return .{ "", 1 };
        defer parser.deinit();

        if (self.subCommand == .Lexer)
            return .{ try parser.lexerToString(self.alloc), 0 };

        var ast = try parser.parse();

        for (parser.errors.items) |e| {
            e.display(ast.getInfo());
        }

        if (self.bench)
            Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});

        if (self.subCommand == .Parser)
            return .{ try ast.toString(self.alloc), 0 };

        if (self.bench)
            Logger.log.info("Type Checking", .{});

        const err = try typeCheck(self.alloc, &ast);

        if (self.bench)
            Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});

        if (self.subCommand == .TypeCheck and self.stdout)
            return .{ try ast.toString(self.alloc), if (err or (parser.errors.items.len > 1)) 1 else 0 };

        if (err) return .{ "", 1 };
        if (parser.errors.items.len > 0) return .{ "", 1 };

        if (self.bench)
            Logger.log.info("Intermediate Represetation", .{});

        if (self.bench)
            Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});

        unreachable;
    }

    pub fn deinit(self: *const Self, bytes: []const u8) void {
        self.alloc.free(bytes);
    }
};

const Global = struct {};
const Function = struct {};
