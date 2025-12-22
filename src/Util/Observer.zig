pub fn Observer(Key: type, Args: type) type {
    return struct {
        const Self = @This();
        const Handler = struct {
            node: std.SinglyLinkedList.Node = .{},
            func: *const fn (Args) void,
            args: Args,
        };

        bytes: [std.math.pow(usize, 2, 7)]*std.SinglyLinkedList.Node = undefined,
        nodeList: std.ArrayList(*std.SinglyLinkedList.Node) = undefined,

        pool: *std.Thread.Pool = undefined,
        mutex: std.Thread.Mutex = .{},

        eventToFunc: if (Key == []const u8) std.StringHashMapUnmanaged(std.SinglyLinkedList) else std.AutoHashMapUnmanaged(
            Key,
            std.SinglyLinkedList,
        ) = .{},

        // PERF: Later check if listHandler is worth it
        pub fn init(self: *Self, pool: *std.Thread.Pool) void {
            self.nodeList = .initBuffer(&self.bytes);
            self.pool = pool;
        }

        pub fn push(self: *Self, alloc: Allocator, wait: Key, func: *const fn (Args) void, args: Args) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.pushUnlock(alloc, wait, func, args);
        }

        pub fn pushUnlock(self: *Self, alloc: Allocator, wait: Key, func: *const fn (Args) void, args: Args) Allocator.Error!void {
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

        fn exevuteHandler(func: *const fn (Args) void, args: Args) void {
            func(args);
        }

        pub fn alert(self: *Self, alloc: Allocator, waited: Key) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var link = self.eventToFunc.fetchRemove(waited) orelse return;

            while (link.value.popFirst()) |node| {
                const handler: *Handler = @fieldParentPtr("node", node);

                try self.pool.spawn(exevuteHandler, .{ handler.func, handler.args });

                self.nodeList.appendBounded(node) catch {
                    alloc.destroy(handler);
                };
            }
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.eventToFunc.deinit(alloc);
        }
    };
}

const std = @import("std");

const Allocator = std.mem.Allocator;
