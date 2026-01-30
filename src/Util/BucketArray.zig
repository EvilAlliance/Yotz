pub fn BucketArray(comptime T: type, comptime BucketType: type, comptime nodesPerBucket: BucketType) type {
    return struct {
        const Self = @This();
        const Bucket = [nodesPerBucket]T;

        buckets: ArrayList(*Bucket) = .{},
        nextIndex: Atomic(BucketType) = .init(0),
        bucketCount: Atomic(BucketType) = .init(0),
        protec: Thread.Mutex = .{},

        pub fn deinit(self: *Self, alloc: Allocator) void {
            for (self.buckets.items) |bucket| {
                alloc.destroy(bucket);
            }
            self.buckets.deinit(alloc);
        }

        pub fn append(self: *Self, alloc: Allocator, item: T) Allocator.Error!void {
            const index = self.nextIndex.fetchAdd(1, .monotonic);
            const bucketId = index / nodesPerBucket;
            const offset = index % nodesPerBucket;

            if (bucketId < self.bucketCount.load(.acquire)) {
                self.buckets.items[bucketId][offset] = item;
                return;
            }

            self.protec.lock();
            defer self.protec.unlock();

            while (bucketId >= self.buckets.items.len) {
                const bucket = try alloc.create(Bucket);
                try self.buckets.append(alloc, bucket);
                self.bucketCount.store(@intCast(self.buckets.items.len), .release);
            }

            self.buckets.items[bucketId][offset] = item;
        }

        pub fn reserve(self: *Self, alloc: Allocator) Allocator.Error!*T {
            const index = self.nextIndex.fetchAdd(1, .monotonic);
            const bucketId = index / nodesPerBucket;
            const offset = index % nodesPerBucket;

            if (bucketId < self.bucketCount.load(.acquire)) {
                return &self.buckets.items[bucketId][offset];
            }

            self.protec.lock();
            defer self.protec.unlock();

            while (bucketId >= self.buckets.items.len) {
                const bucket = try alloc.create(Bucket);
                try self.buckets.append(alloc, bucket);
                self.bucketCount.store(@intCast(self.buckets.items.len), .release);
            }

            return &self.buckets.items[bucketId][offset];
        }

        pub fn appendIndex(self: *Self, alloc: Allocator, item: T) Allocator.Error!BucketType {
            const index = self.nextIndex.fetchAdd(1, .monotonic);
            const bucketId = index / nodesPerBucket;
            const offset = index % nodesPerBucket;

            if (bucketId < self.bucketCount.load(.acquire)) {
                self.buckets.items[bucketId][offset] = item;
                return index;
            }

            self.protec.lock();
            defer self.protec.unlock();

            while (bucketId >= self.buckets.items.len) {
                const bucket = try alloc.create(Bucket);
                try self.buckets.append(alloc, bucket);
                self.bucketCount.store(@intCast(self.buckets.items.len), .release);
            }

            self.buckets.items[bucketId][offset] = item;
            return index;
        }

        pub fn get(self: *const Self, index: BucketType) T {
            const bucketId = index / nodesPerBucket;
            const offset = index % nodesPerBucket;

            return self.buckets.items[bucketId][offset];
        }

        pub fn getPtr(self: *const Self, index: BucketType) *T {
            const bucketId = index / nodesPerBucket;
            const offset = index % nodesPerBucket;

            return &self.buckets.items[bucketId][offset];
        }

        pub fn getConstPtr(self: *const Self, index: BucketType) *const T {
            const bucketId = index / nodesPerBucket;
            const offset = index % nodesPerBucket;

            return &self.buckets.items[bucketId][offset];
        }

        pub fn indexOf(self: *const Self, ptr: *const T) BucketType {
            const addr = @intFromPtr(ptr);

            for (self.buckets.items, 0..) |bucket, bucketId| {
                const bucketAddr = @intFromPtr(bucket);
                const bucketSize = @sizeOf(Bucket);

                if (addr >= bucketAddr and addr < bucketAddr + bucketSize) {
                    const offset = (addr - bucketAddr) / @sizeOf(T);
                    return @intCast(bucketId * nodesPerBucket + offset);
                }
            }

            @panic("Pointer not from this Array");
        }
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Thread = std.Thread;
const Atomic = std.atomic.Value;
const assert = std.debug.assert;
