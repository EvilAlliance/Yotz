pub const TypeCheck = @import("TypeCheck.zig");
pub const Expression = @import("Expression.zig");

pub const Observer = @import("../Util/Observer.zig").Observer(Parser.NodeIndex, TypeCheck.ObserverParams);

const Parser = @import("../Parser/mod.zig");
