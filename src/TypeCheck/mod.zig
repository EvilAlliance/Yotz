pub const TypeCheck = @import("TypeCheck.zig");

pub const Observer = @import("./Observer.zig").Observer(Parser.NodeIndex, TypeCheck.ObserverParams);

const std = @import("std");
const Parser = @import("./../Parser/mod.zig");
