const std = @import("std");

const ParseArguments = @import("ParseArgs.zig");
const typeCheck = @import("./TypeCheck/TypeCheck.zig").typeCheck;

const getArguments = ParseArguments.getArguments;
const Arguments = ParseArguments.Arguments;

const TranslationUnit = @import("./TranslationUnit.zig");

// TODO: Do not exopse the parse, only afunction parse
const Parser = @import("./Parser/Parser.zig");

const Logger = @import("Logger.zig");

const by = @import("BollYotz");

fn getName(absPath: []const u8, extName: []const u8, buf: []u8) []u8 {
    const fileName = std.mem.lastIndexOf(u8, absPath, "/") orelse 0;
    const ext = std.mem.lastIndexOf(u8, absPath, ".").?;
    if (extName.len > 0)
        return std.fmt.bufPrint(buf, "{s}.{s}", .{ absPath[fileName + 1 .. ext], extName }) catch {
            std.log.err("Name is to larger than {}\n", .{5 * 1024});
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
        writer = std.fs.File.stdout().writer(&.{});
    } else {
        file = std.fs.cwd().createFile(name, .{}) catch |err| {
            std.log.err("could not open file ({s}) becuase {}\n", .{ arg.path, err });
            return;
        };

        writer = file.?.writer(&.{});
    }

    writer.interface.writeAll(c) catch |err| {
        std.log.err("Could not write to file ({s}) becuase {}\n", .{ arg.path, err });
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

pub const std_options = std.Options{
    .log_level = .debug,

    .logFn = Logger.l,
};

pub fn main() u8 {
    // var generalPurpose: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
    // const alloc = generalPurpose.allocator();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const gpa = arena.allocator();
    // defer _ = generalPurpose.deinit();
    defer _ = arena.deinit();

    const arguments = getArguments(gpa);

    if (arguments.subCom == .Run and arguments.stdout) {
        std.log.warn("Subcommand run wont print anything", .{});
    }

    var threadPool: std.Thread.Pool = undefined;
    threadPool.init(.{
        .allocator = gpa,
        .n_jobs = 20,
    }) catch {
        std.log.err("Run Out of Memory", .{});
        return 1;
    };

    var cont = TranslationUnit.Content{
        .subCom = arguments.subCom,
        .path = arguments.path,
    };
    defer gpa.free(cont.path);

    if (!TranslationUnit.readTokens(gpa, &cont)) return 1;
    defer {
        gpa.free(cont.tokens);
        gpa.free(cont.source);
    }

    const tu = TranslationUnit.initGlobal(&cont, &threadPool);

    var nodes = Parser.NodeList.init();
    defer nodes.deinit(gpa);
    const bytes, const ret = tu.startEntry(gpa, &nodes) catch {
        std.log.err("Run Out of Memory", .{});
        return 1;
    };

    defer tu.deinit(gpa, bytes);

    var buf: [5 * 1024]u8 = undefined;

    writeAll(
        bytes,
        arguments,
        getName(arguments.path, arguments.subCom.getExt(), &buf),
    );

    return ret;
}
