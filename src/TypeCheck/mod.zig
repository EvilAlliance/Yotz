pub const TypeCheck = @import("TypeCheck.zig");

pub const ScopeGlobal = @import("./Scope/ScopeGlobal.zig");
pub const ScopeFunc = @import("./Scope/ScopeFunc.zig");
pub const Scope = @import("./Scope/Scope.zig");
pub const Observer = @import("../Util/Observer.zig").Observer(Parser.NodeIndex, TypeCheck.ObserverParams);

const std = @import("std");
const Parser = @import("./../Parser/mod.zig");
