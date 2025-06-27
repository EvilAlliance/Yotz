const std = @import("std");
const SubCommand = @import("SubCommand.zig").SubCommand;
const File = @import("File.zig");
const Test = @import("Test.zig");
const Tests = std.ArrayList(Test);

absolute: []const u8,
relative: []const u8,
subCommand: SubCommand,
alloc: std.mem.Allocator,
pool: *std.Thread.Pool,
generateCheck: bool,
tests: *Tests,
coverage: bool,

pub fn init(alloc: std.mem.Allocator, abs: []const u8, rel: []const u8, pool: *std.Thread.Pool, tests: *Tests, subCommand: SubCommand, generateCheck: bool, coverage: bool) @This() {
    return .{
        .pool = pool,

        .alloc = alloc,

        .absolute = abs,
        .relative = rel,

        .tests = tests,
        .subCommand = subCommand,
        .generateCheck = generateCheck,

        .coverage = coverage,
    };
}

pub fn initCopy(self: @This(), abs: []const u8, rel: []const u8) @This() {
    var new = self;
    new.relative = rel;
    new.absolute = abs;
    return new;
}

pub fn testIt(self: @This()) void {
    const children = std.fs.openDirAbsolute(self.absolute, .{
        .access_sub_paths = true,
        .iterate = true,
    }) catch return;

    var iterator = children.iterate();

    while (iterator.next() catch return) |child| {
        switch (child.kind) {
            .directory => {
                if (child.name[0] == '.') continue;
                self.pool.spawn(testIt, .{
                    self.initCopy(
                        std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ self.absolute, child.name }) catch return,
                        std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ self.relative, child.name }) catch return,
                    ),
                }) catch return;
            },
            .file => self.pool.spawn(
                File.testIt,
                .{
                    File.init(
                        self.alloc,
                        std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ self.absolute, child.name }) catch return,
                        std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ self.relative, child.name }) catch return,
                        self.pool,
                        self.tests,
                        self.subCommand,
                        self.generateCheck,
                        self.coverage,
                    ),
                },
            ) catch return,
            else => std.debug.print("Not handle kind {} \n", .{child.kind}),
        }
    }
}
