pub fn ArrayListThreadSafe(comptime T: type) type {
    return struct {
        const Self = @This();

        items: ArrayList(T) = .{},
        mutex: Thread.Mutex = .{},

        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.items.deinit(alloc);
        }

        pub fn append(self: *Self, alloc: Allocator, item: T) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(alloc, item);
        }
        pub fn appendBounded(self: *Self, item: T) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.appendBounded(item);
        }

        pub fn appendUnlock(self: *Self, alloc: Allocator, item: T) Allocator.Error!void {
            try self.items.append(alloc, item);
        }

        pub fn appendIndex(self: *Self, alloc: Allocator, item: T) Allocator.Error!usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            const index = self.items.items.len;
            try self.items.append(alloc, item);

            return index;
        }

        pub fn get(self: *Self, index: usize) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items[index];
        }

        pub fn getPtr(self: *Self, index: usize) *T {
            self.mutex.lock();
            return &self.items.items[index];
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.items.clearRetainingCapacity();
        }

        pub fn clearAndFree(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.items.clearAndFree();
        }

        pub fn slice(self: *Self) []T {
            self.mutex.lock();
            return self.items.items;
        }

        pub fn lock(self: *Self) void {
            self.mutex.lock();
        }

        pub fn unlock(self: *Self) void {
            self.mutex.unlock();
        }

        pub fn resize(self: *Self, alloc: Allocator, newLength: usize) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.items.resize(alloc, newLength);
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.items.pop();
        }
    };
}

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
