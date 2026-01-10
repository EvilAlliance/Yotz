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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocArena = arena.allocator();
    var allocSafe = std.heap.ThreadSafeAllocator{
        .child_allocator = allocArena,
        .mutex = std.Thread.Mutex{},
    };
    const alloc = allocSafe.allocator();
    defer _ = arena.deinit();

    // var generalPurpose: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
    // const alloc = generalPurpose.allocator();
    // defer _ = generalPurpose.deinit();

    const arguments = getArguments(alloc);

    if (arguments.subCom == .Run and arguments.stdout) {
        std.log.warn("Subcommand run wont print anything", .{});
    }

    const bytes, const ret = TranslationUnit.startEntry(alloc, &arguments) catch {
        std.log.err("Run Out of Memory", .{});
        return 1;
    };
    defer TranslationUnit.deinitStatic(alloc, bytes);

    var buf: [5 * 1024]u8 = undefined;

    writeAll(
        bytes,
        arguments,
        getName(arguments.path, arguments.subCom.getExt(), &buf),
    );

    return ret;
}

const ParseArguments = @import("ParseArgs.zig");
const getArguments = ParseArguments.getArguments;
const Arguments = ParseArguments.Arguments;
const TranslationUnit = @import("TranslationUnit.zig");
const Global = @import("Global.zig");
const TypeCheck = @import("TypeCheck/mod.zig");
const Report = @import("Report/mod.zig");
const Logger = @import("Logger.zig");

const std = @import("std");
