pub fn BucketArray(comptime T: type, comptime BucketType: type, comptime nodes_per_bucket: BucketType) type {
    return struct {
        const Self = @This();
        const Bucket = [nodes_per_bucket]T;

        buckets: ArrayList(*Bucket) = .{},
        next_index: Atomic(BucketType) = .init(0),
        protec: Thread.Mutex = .{},

        pub fn deinit(self: *Self, alloc: Allocator) void {
            for (self.buckets.items) |bucket| {
                alloc.destroy(bucket);
            }
            self.buckets.deinit(alloc);
        }

        pub fn append(self: *Self, alloc: Allocator, item: T) Allocator.Error!void {
            const index = self.next_index.fetchAdd(1, .monotonic);
            const bucket_id = index / nodes_per_bucket;
            const offset = index % nodes_per_bucket;

            if (bucket_id >= self.buckets.items.len) {
                self.protec.lock();
                defer self.protec.unlock();

                if (bucket_id >= self.buckets.items.len) {
                    const bucket = try alloc.create(Bucket);
                    try self.buckets.append(alloc, bucket);
                }
            }

            self.buckets.items[bucket_id][offset] = item;
        }

        pub fn appendIndex(self: *Self, alloc: Allocator, item: T) Allocator.Error!BucketType {
            const index = self.next_index.fetchAdd(1, .monotonic);
            const bucket_id = index / nodes_per_bucket;
            const offset = index % nodes_per_bucket;

            if (bucket_id >= self.buckets.items.len) {
                self.protec.lock();
                defer self.protec.unlock();

                if (bucket_id >= self.buckets.items.len) {
                    const bucket = try alloc.create(Bucket);
                    try self.buckets.append(alloc, bucket);
                }
            }

            self.buckets.items[bucket_id][offset] = item;
            return index;
        }

        pub fn get(self: *const Self, index: BucketType) T {
            const bucket_id = index / nodes_per_bucket;
            const offset = index % nodes_per_bucket;

            return self.buckets.items[bucket_id][offset];
        }

        pub fn getPtr(self: *const Self, index: BucketType) *T {
            const bucket_id = index / nodes_per_bucket;
            const offset = index % nodes_per_bucket;

            return &self.buckets.items[bucket_id][offset];
        }
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Thread = std.Thread;
const Atomic = std.atomic.Value;
const assert = std.debug.assert;
