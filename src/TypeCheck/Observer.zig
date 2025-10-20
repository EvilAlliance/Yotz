fn Observer(key: type) type {
    return struct {
        const Handler = struct {
            func: fn (anyopaque) anyerror!void,
            args: anyopaque,

            pub fn call(self: Handler) void {
                // Call func with args using @call and catch errors inside
                return @call(.auto, self.func, self.args);
            }
        };

        eventToFunc: std.AutoHashMap(
            key,
            Handler,
        ),
    };
}

const std = @import("std");

