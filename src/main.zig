const std = @import("std");
const Logger = @import("Logger.zig");

const ParseArguments = @import("ParseArgs.zig");
const typeCheck = @import("TypeCheck.zig").typeCheck;

const usage = @import("General.zig").usage;

const getArguments = ParseArguments.getArguments;
const Arguments = ParseArguments.Arguments;

// TODO: Do not exopse the parse, only afunction parse
const Parser = @import("./Parser/Parser.zig");

const by = @import("BollYotz");

fn getName(absPath: []const u8, extName: []const u8) []u8 {
    var buf: [5 * 1024]u8 = undefined;

    const fileName = std.mem.lastIndexOf(u8, absPath, "/").?;
    const ext = std.mem.lastIndexOf(u8, absPath, ".").?;
    if (extName.len > 0)
        return std.fmt.bufPrint(&buf, "{s}.{s}", .{ absPath[fileName + 1 .. ext], extName }) catch {
            Logger.log.err("Name is to larger than {}\n", .{5 * 1024});
            return "";
        }
    else
        return @constCast(absPath[fileName + 1 .. ext]);
}

fn writeAll(c: []const u8, arg: Arguments, name: []u8) void {
    var file: ?std.fs.File = null;
    defer {
        if (file) |f| f.close();
    }

    var writer: std.fs.File.Writer = undefined;

    if (arg.stdout) {
        writer = std.io.getStdOut().writer();
    } else {
        file = std.fs.cwd().createFile(name, .{}) catch |err| {
            Logger.log.err("could not open file ({s}) becuase {}\n", .{ arg.path, err });
            return;
        };

        writer = file.?.writer();
    }

    writer.writeAll(c) catch |err| {
        Logger.log.err("Could not write to file ({s}) becuase {}\n", .{ arg.path, err });
        return;
    };
}

// fn generateExecutable(alloc: std.mem.Allocator, m: tb.Module, a: *tb.Arena, path: []const u8) u8 {
//     const eb = m.objectExport(a, tb.DebugFormat.NONE);
//     if (!eb.toFile(("mainModule.o"))) {
//         Logger.log.err("Could not export object to file", .{});
//         return 1;
//     }
//
//     var cmdObj = Commnad.init(alloc, &[_][]const u8{ "ld", "mainModule.o", "-o", path }, false);
//     const resultObj = cmdObj.execute() catch {
//         Logger.log.err("Could not link the generated object file", .{});
//         return 1;
//     };
//
//     var cmdClean = Commnad.init(alloc, &[_][]const u8{ "rm", "mainModule.o" }, false);
//     _ = cmdClean.execute() catch {
//         Logger.log.err("Could not clean the generated object file", .{});
//     };
//
//     switch (resultObj) {
//         .Exited => |x| if (x != 0) Logger.log.err("Could not link generated object file", .{}),
//         else => Logger.log.err("Could not link generated object file", .{}),
//     }
//
//     return 0;
// }
//

pub fn main() u8 {
    var timer = std.time.Timer.start() catch unreachable;

    var generalPurpose: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = generalPurpose.allocator();
    defer _ = generalPurpose.deinit();

    const arguments = getArguments() orelse {
        usage();
        return 1;
    };

    Logger.silence = arguments.silence;

    if (arguments.run and arguments.stdout) {
        Logger.log.warn("Subcommand run wont print anything", .{});
    }

    if (arguments.bench)
        Logger.log.info("Lexing and Parsing", .{});

    var parser = Parser.init(gpa, arguments.path) orelse return 1;
    defer parser.deinit();

    if (arguments.lex) {
        const lexContent = parser.lexerToString(gpa) catch {
            Logger.log.err("Out of memory", .{});
            return 1;
        };
        defer lexContent.deinit();

        const name = getName(parser.absPath, "lex");
        writeAll(lexContent.items, arguments, name);

        return 0;
    }

    var ast = parser.parse() catch |err| switch (err) {
        error.OutOfMemory => {
            Logger.log.err("Out of memory", .{});
            return 1;
        },
    };
    for (parser.errors.items) |e| {
        e.display(ast.getInfo());
    }

    if (arguments.bench)
        Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});

    if (arguments.parse) {
        const cont = ast.toString(gpa) catch {
            Logger.log.err("Out of memory", .{});
            return 1;
        };
        defer cont.deinit();

        const name = getName(parser.absPath, "parse");
        writeAll(cont.items, arguments, name);

        return 0;
    }

    if (ast.nodeList.items.len == 0) return 1;

    if (arguments.bench)
        Logger.log.info("Type Checking", .{});

    const err = typeCheck(gpa, &ast) catch {
        Logger.log.err("out of memory", .{});
        return 1;
    };

    if (arguments.bench)
        Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});

    if (arguments.check and arguments.stdout) {
        const cont = ast.toString(gpa) catch {
            Logger.log.err("Out of memory", .{});
            return 1;
        };
        defer cont.deinit();

        const name = getName(parser.absPath, "check");
        writeAll(cont.items, arguments, name);

        return if (err or (parser.errors.items.len > 1)) 1 else 0;
    }

    if (err) return 1;
    if (parser.errors.items.len > 0) return 1;

    if (arguments.bench)
        Logger.log.info("Intermediate Represetation", .{});

    if (arguments.bench)
        Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});

    return 0;
}
