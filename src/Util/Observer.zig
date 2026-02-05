pub fn Multiple(Key: type, Args: type, ContextOpt: ?type) type {
    const Context = if (ContextOpt) |T| T else struct {
        pub fn init(arg: *Args) void {
            _ = arg;
        }
        pub fn deinit(arg: Args, runned: bool) void {
            _ = arg;
            _ = runned;
        }
    };

    if (@sizeOf(Context) != 0)
        @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call promoteContext instead.");

    return struct {
        const Self = @This();
        pub const Handler = struct {
            node: std.SinglyLinkedList.Node = .{},
            func: *const fn (Args) void,
            args: Args,
        };

        node: std.SinglyLinkedList = .{},

        pool: *std.Thread.Pool = undefined,
        mutex: std.Thread.Mutex = .{},
        ctx: Context = undefined,

        eventToFunc: if (Key == []const u8) std.StringHashMapUnmanaged(std.SinglyLinkedList) else std.AutoHashMapUnmanaged(
            Key,
            std.SinglyLinkedList,
        ) = .{},

        // PERF: Later check if listHandler is worth it
        pub fn init(self: *Self, pool: *std.Thread.Pool) void {
            self.pool = pool;
        }

        pub fn push(self: *Self, alloc: Allocator, wait: Key, func: *const fn (Args) void, args: Args) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.pushUnlock(alloc, wait, func, args);
        }

        pub fn pushUnlock(self: *Self, alloc: Allocator, wait: Key, func: *const fn (Args) void, args: Args) Allocator.Error!void {
            const handler: *Handler = if (self.node.popFirst()) |handlerOld| @fieldParentPtr("node", handlerOld) else try alloc.create(Handler);

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

        fn executeHandler(self: *Self, func: *const fn (Args) void, args: Args) void {
            func(args);
            self.ctx.deinit(args, true);
        }

        pub fn alert(self: *Self, waited: Key) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var link = self.eventToFunc.fetchRemove(waited) orelse return;

            while (link.value.popFirst()) |node| {
                const handler: *Handler = @fieldParentPtr("node", node);

                self.ctx.init(&handler.args);
                try self.pool.spawn(executeHandler, .{ self, handler.func, handler.args });

                self.node.prepend(node);
            }
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            var it = self.eventToFunc.valueIterator();
            while (it.next()) |entry| {
                while (entry.popFirst()) |node| {
                    const handler: *Handler = @fieldParentPtr("node", node);
                    self.ctx.deinit(handler.args, false);
                    alloc.destroy(handler);
                }
            }

            while (self.node.popFirst()) |n| {
                const handler: *Handler = @fieldParentPtr("node", n);
                alloc.destroy(handler);
            }

            self.eventToFunc.deinit(alloc);
        }
    };
}

pub fn Simple(Args: type, ContextOpt: ?type) type {
    const Context = if (ContextOpt) |T| T else struct {
        pub fn init(self: @This(), arg: Args) void {
            _ = self;
            _ = arg;
        }
        pub fn deinit(self: @This(), arg: Args, runned: bool) void {
            _ = self;
            _ = arg;
            _ = runned;
        }
    };

    if (@sizeOf(Context) != 0)
        @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call promoteContext instead.");
    return struct {
        const Self = @This();

        const Handler = struct {
            func: *const fn (Args) void,
            args: Args,
        };

        list: std.ArrayList(Handler) = .{},
        pool: *std.Thread.Pool = undefined,
        mutex: std.Thread.Mutex = .{},
        ctx: Context = undefined,

        pub fn initCapacity(self: *Self, alloc: Allocator, pool: *std.Thread.Pool, capacity: usize) Allocator.Error!void {
            self.list = try .initCapacity(alloc, capacity);
            self.pool = pool;
        }

        fn executeHandler(self: *Self, func: *const fn (Args) void, args: Args) void {
            func(args);
            self.ctx.deinit(args, true);
        }

        pub fn push(self: *Self, alloc: Allocator, func: *const fn (Args) void, args: Args) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.pushUnlock(alloc, func, args);
        }

        pub fn pushUnlock(self: *Self, alloc: Allocator, func: *const fn (Args) void, args: Args) Allocator.Error!void {
            const handler: Handler = .{
                .func = func,
                .args = args,
            };

            try self.list.append(alloc, handler);
        }

        pub fn alert(self: *Self) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.list.pop()) |handler| {
                self.ctx.init(&handler.args);
                try self.pool.spawn(executeHandler, .{ self, handler.func, handler.args });
            }
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            while (self.list.pop()) |handler| {
                self.ctx.deinit(handler.args, false);
            }

            self.list.deinit(alloc);
        }
    };
}

const std = @import("std");

const Allocator = std.mem.Allocator;
