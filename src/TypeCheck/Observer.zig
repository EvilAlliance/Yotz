pub fn Observer(Key: type, Args: type) type {
    return struct {
        const Self = @This();
        const Handler = struct {
            func: *const fn (Args) void,
            args: Args,
            node: std.SinglyLinkedList.Node = .{},
        };

        nodeList: std.ArrayList(*std.SinglyLinkedList.Node),

        pool: *std.Thread.Pool,
        mutex: std.Thread.Mutex = .{},

        eventToFunc: std.AutoHashMapUnmanaged(
            Key,
            std.SinglyLinkedList,
        ),

        // PERF: Later check if listHandler is worth it
        pub fn init(alloc: Allocator, pool: *std.Thread.Pool) Self {
            return .{
                .nodeList = .initCapacity(alloc, std.math.pow(2, 7)),

                .pool = pool,

                .eventToFunc = .init(),
            };
        }

        pub fn push(self: *Self, alloc: Allocator, wait: Key, func: fn (Args) void, args: Args) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const handler: *Handler = if (self.nodeList.getLastOrNull()) |handlerOld| @fieldParentPtr("node", handlerOld) else try alloc.create(Handler);

            handler.* = .{
                .func = func,
                .args = args,
            };

            if (self.eventToFunc.getPtr(wait)) |node| {
                node.prepend(&handler.node);
            } else {
                var link = std.SinglyLinkedList{};

                link.prepend(&handler.node);
                try self.eventToFunc.put(alloc, wait, link);
            }
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.eventToFunc.deinit(alloc);
            self.listHandler.deinit(alloc);
        }
    };
}

const std = @import("std");

const Allocator = std.mem.Allocator;
