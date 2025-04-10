const std = @import("std");
const Logger = @import("Logger.zig");

const Util = @import("Util.zig");
const Lexer = @import("./Lexer/Lexer.zig");
const ParseArguments = @import("ParseArgs.zig");
const typeCheck = @import("TypeCheck.zig").typeCheck;

const usage = @import("General.zig").usage;

const Commnad = @import("./Util/Command.zig");

const getArguments = ParseArguments.getArguments;
const Arguments = ParseArguments.Arguments;
const lex = Lexer.lex;
const Parser = @import("./Parser/Parser.zig");
const IR = @import("IR/IR.zig");

const tb = @import("./libs/tb/tb.zig");

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

        const name = getName(arguments.path, "lex");
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
        e.display();
    }

    if (arguments.bench)
        Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});

    if (arguments.parse) {
        const cont = ast.toString(gpa) catch {
            Logger.log.err("Out of memory", .{});
            return 1;
        };
        defer cont.deinit();

        const name = getName(arguments.path, "parse");
        writeAll(cont.items, arguments, name);

        return 0;
    }

    if (arguments.bench)
        Logger.log.info("Type Checking", .{});

    const err = typeCheck(&ast) catch {
        Logger.log.err("out of memory", .{});
        return 1;
    };

    if (arguments.bench)
        Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});

    if (err) return 1;
    if (parser.errors.items.len > 0) return 1;

    return 0;
    //
    // if (arguments.bench)
    //     Logger.log.info("Intermediate Represetation", .{});
    // var ir = IR.init(&parser.program, alloc);
    // defer ir.deinit();
    //
    // const m = tb.Module.create(tb.Arch.X86_64, tb.System.LINUX, arguments.run);
    //
    // ir.toIR(m) catch {
    //     Logger.log.err("out of memory", .{});
    //     return 1;
    // };
    //
    // if (arguments.bench)
    //     Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});
    //
    // if (arguments.ir) {
    //     const cont = ir.toString(alloc) catch {
    //         Logger.log.err("Out of memory", .{});
    //         return 1;
    //     };
    //     defer cont.deinit();
    //
    //     const name = getName(arguments.path, "ir");
    //     writeAll(cont.items, arguments, name);
    //
    //     return 0;
    // }
    //
    // if (arguments.bench)
    //     Logger.log.info("CodeGen", .{});
    //
    // const path = getName(arguments.path, "");
    //
    // var a: tb.Arena = undefined;
    // tb.Arena.create(&a, "For main Module");
    // defer a.destroy();
    //
    // const startF = ir.codeGen(m) catch {
    //     Logger.log.err("Out of memory", .{});
    //     return 1;
    // };
    //
    // if (arguments.bench)
    //     Logger.log.info("Finished in {}", .{std.fmt.fmtDuration(timer.lap())});
    //
    // if (!arguments.run and arguments.stdout) {
    //     startF.print();
    //     var funcsIterator = ir.ir.funcs.valueIterator();
    //     while (funcsIterator.next()) |func| {
    //         func.func.print();
    //     }
    //     return 0;
    // }
    //
    // {
    //     const ws = tb.Worklist.alloc();
    //     defer ws.free();
    //
    //     var funcIterator = ir.ir.funcs.valueIterator();
    //     {
    //         var feature: tb.FeatureSet = undefined;
    //         _ = startF.codeGen(ws, &a, &feature, false);
    //     }
    //
    //     while (funcIterator.next()) |func| {
    //         var feature: tb.FeatureSet = undefined;
    //         _ = func.func.codeGen(ws, &a, &feature, false);
    //     }
    // }
    //
    // if (arguments.build) {
    //     const r = generateExecutable(alloc, m, &a, path);
    //     if (r != 0) return r;
    // } else {
    //     const jit = tb.Jit.begin(m, 1024 ^ 3);
    //     const func = jit.placeFunction(ir.ir.funcs.get("main").?.func);
    //     const mainf: *fn () u8 = @ptrCast(func.?);
    //     return mainf();
    // }
    //
    // return 0;
}
