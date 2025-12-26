const std = @import("std");
const Lexer = @import("../Lexer/mod.zig");
const Logger = @import("../Logger.zig");
const mod = @import("mod.zig");
const TranslationUnit = @import("../TranslationUnit.zig");

pub const FileInfo = struct { []const u8, [:0]const u8 };

nodeList: *mod.NodeList,
tu: *const TranslationUnit,

pub fn init(nl: *mod.NodeList, tu: *const TranslationUnit) @This() {
    return @This(){
        .nodeList = nl,
        .tu = tu,
    };
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    self.nodeList.deinit(alloc);
}

pub inline fn getToken(self: *const @This(), i: mod.TokenIndex) Lexer.Token {
    return self.tu.global.tokens.get(i);
}

pub inline fn getNodeLocation(self: *const @This(), i: mod.NodeIndex) Lexer.Location {
    const node = self.getNode(i);
    return self.getToken(node.tokenIndex.load(.acquire)).loc;
}

pub inline fn getNodeText(self: *const @This(), i: mod.NodeIndex) []const u8 {
    const node = self.getNode(i);
    const token = self.getToken(node.tokenIndex.load(.acquire));
    return token.getText(self.tu.global.files.get(token.loc.source).source);
}

pub inline fn getNodeName(self: *const @This(), i: mod.NodeIndex) []const u8 {
    const node = self.getNode(i);
    return self.getToken(node.tokenIndex).tag.getName();
}

pub fn getNode(self: *const @This(), i: mod.NodeIndex) mod.Node {
    return self.nodeList.get(i);
}

pub inline fn getNodePtr(self: *@This(), i: mod.NodeIndex) *mod.Node {
    return self.nodeList.getPtr(i);
}
