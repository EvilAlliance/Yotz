const Self = @This();

const std = @import("std");

const Parser = @import("./../Parser/Parser.zig");
const Scopes = @import("./Scopes.zig");

pub const Level = enum { global, local };

alloc: std.mem.Allocator,

scopes: Scopes,
globalScope: Scopes.Scope,

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .alloc = alloc,

        .globalScope = Scopes.Scope.init(alloc),
        .scopes = Scopes.init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    self.scopes.deinit();
    self.globalScope.deinit();
}

pub fn swap(self: *Self, s: Scopes) Scopes {
    const t = self.scopes;
    self.scopes = s;
    return t;
}

pub fn restore(self: *Self, s: Scopes) void {
    self.scopes = s;
}

pub fn searchVariableScope(self: *Self, name: []const u8) ?Parser.NodeIndex {
    if (self.globalScope.get(name)) |n| return n;

    var i: usize = self.scopes.len();
    while (i > 0) {
        i -= 1;

        var dic = self.scopes.items()[i];
        if (dic.get(name)) |n| return n;
    }

    return null;
}

pub fn addVariableScope(self: *Self, name: []const u8, nodeI: Parser.NodeIndex, level: Level) std.mem.Allocator.Error!void {
    switch (level) {
        .local => {
            const scope = self.scopes.getLastPtr();
            try scope.put(name, nodeI);
        },
        .global => {
            try self.globalScope.put(name, nodeI);
        },
    }
}

pub fn addScope(self: *Self) std.mem.Allocator.Error!void {
    try self.scopes.append(Scopes.Scope.init(self.alloc));
}

pub fn popScope(self: *Self) void {
    var x = self.scopes.pop().?;
    x.deinit();
}
