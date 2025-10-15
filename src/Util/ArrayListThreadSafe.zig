pub fn ChunkBase(debug: bool, T: type, ChunkType: type, chunkSize: ChunkType) type {
    return struct {
        const Self = @This();
        // End exclusive
        const Range = struct { start: ChunkType, end: ChunkType };

        pub const Chunk = struct {
            base: *Self,
            ranges: ArrayList(Range) = .{},
            len: ChunkType = 0,

            pub fn init(alloc: Allocator, base: *Self) Allocator.Error!@This() {
                var self: @This() = .{ .base = base };

                try self.ranges.append(alloc, try self.base.getChunk(alloc));
                self.len = self.ranges.getLast().start;

                return self;
            }

            pub fn deinit(self: *@This(), alloc: Allocator) void {
                self.ranges.deinit(alloc);
            }

            pub fn getNextIndex(self: *@This(), alloc: Allocator) Allocator.Error!ChunkType {
                if (self.len == self.ranges.getLast().end) {
                    try self.ranges.append(alloc, try self.base.getChunk(alloc));
                    self.len = self.ranges.getLast().start;
                }

                return self.len;
            }

            pub fn append(self: *@This(), alloc: Allocator, item: T) Allocator.Error!void {
                if (self.len == self.ranges.getLast().end) {
                    try self.ranges.append(alloc, try self.base.getChunk(alloc));
                    self.len = self.ranges.getLast().start;
                }
                self.base.protec.lockShared();
                defer self.base.protec.unlockShared();
                self.base.items.items[self.len] = item;
                self.len += 1;
            }

            pub fn isInsideRange(self: *const @This(), index: ChunkType) bool {
                var left: usize = 0;
                const ranges = self.ranges.items;
                var right: usize = self.ranges.items.len;

                while (left < right) {
                    const mid = left + (right - left) / 2;
                    const range = ranges[mid];

                    if (index < range.start) {
                        right = mid;
                    } else if (index >= range.end) {
                        left = mid + 1;
                    } else {
                        return true;
                    }
                }

                return false;
            }

            pub fn get(self: *const @This(), index: ChunkType) T {
                if (debug)
                    assert(self.isInsideRange(index));

                self.base.protec.lockShared();
                defer self.base.protec.unlockShared();

                return self.base.items.items[index];
            }

            pub fn getOutChunk(self: *const @This(), index: ChunkType) T {
                if (debug)
                    assert(!self.isInsideRange(index));

                self.base.protec.lockShared();
                defer self.base.protec.unlockShared();

                return self.base.items.items[index];
            }

            pub fn getUncheck(self: *const @This(), index: ChunkType) T {
                self.base.protec.lockShared();
                defer self.base.protec.unlockShared();

                return self.base.items.items[index];
            }

            pub fn unlockShared(self: *@This()) void {
                self.base.unlockShared();
            }

            pub fn getPtr(self: *const @This(), index: ChunkType) *T {
                if (debug)
                    assert(self.isInsideRange(index));
                self.base.protec.lockShared();
                return &self.base.items.items[index];
            }

            pub fn getPtrOutChunk(self: *const @This(), index: ChunkType) *T {
                if (debug)
                    assert(!self.isInsideRange(index));
                self.base.protec.lockShared();
                return &self.base.items.items[index];
            }
        };

        items: ArrayList(T) = .{},
        protec: Thread.RwLock = .{},

        pub fn init() Self {
            return .{};
        }

        pub fn deinit(self: *@This(), alloc: Allocator) void {
            self.items.deinit(alloc);
        }

        pub fn getChunk(self: *Self, alloc: Allocator) Allocator.Error!Range {
            self.protec.lock();
            defer self.protec.unlock();

            const start = self.items.items.len;
            try self.items.appendNTimes(alloc, T{}, chunkSize);

            return .{
                .start = @intCast(start),
                .end = @intCast(start + chunkSize),
            };
        }

        pub fn unlockShared(self: *Self) void {
            self.protec.unlockShared();
        }
    };
}

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const assert = std.debug.assert;
