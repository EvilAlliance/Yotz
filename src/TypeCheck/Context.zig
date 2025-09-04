const Self = @This();

const std = @import("std");

const Parser = @import("./../Parser/Parser.zig");
const Scopes = @import("./Scopes.zig");

const Allocator = std.mem.Allocator;

pub const Level = enum { global, local };

scopes: Scopes,
globalScope: Scopes.Scope,

pub fn init() Self {
    return .{
        .globalScope = Scopes.Scope{},
        .scopes = Scopes.init(),
    };
}

pub fn deinit(self: *Self, alloc: Allocator) void {
    self.scopes.deinit(alloc);
    self.globalScope.deinit(alloc);
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

pub fn addVariableScope(self: *Self, alloc: Allocator, name: []const u8, nodeI: Parser.NodeIndex, level: Level) std.mem.Allocator.Error!void {
    switch (level) {
        .local => {
            const scope = self.scopes.getLastPtr();
            try scope.put(alloc, name, nodeI);
        },
        .global => {
            try self.globalScope.put(alloc, name, nodeI);
        },
    }
}

pub fn addScope(self: *Self, alloc: Allocator) std.mem.Allocator.Error!void {
    try self.scopes.append(alloc, Scopes.Scope{});
}

pub fn popScope(self: *Self, alloc: Allocator) void {
    var x = self.scopes.pop().?;
    x.deinit(alloc);
}
