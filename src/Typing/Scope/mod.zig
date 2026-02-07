pub const Scope = @import("Scope.zig");
pub const Global = @import("ScopeGlobal.zig");
pub const Func = @import("ScopeFunc.zig");

pub const ObserverParams = Global.ObserverParams;

pub const Dependant = struct {
    node: std.SinglyLinkedList.Node,
    variable: *Parser.Node.VarConst,
};

pub const Error = error{
    KeyAlreadyExists,
};

const Parser = @import("../../Parser/mod.zig");

const std = @import("std");
