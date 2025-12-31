const std = @import("std");

const Allocator = std.mem.Allocator;

const Layout = @import("Layout.zig");

pub fn OwningStringHashmap(T: type) type {
    return struct {
        const Ts = @This();
        inner: std.StringHashMap(T),

        pub fn init(gpa: Allocator) Ts {
            return .{
                .inner = .init(gpa),
            };
        }

        pub fn put(ts: *Ts, key: []const u8, v: T) !void {
            const str = try ts.inner.allocator.dupe(u8, key);
            try ts.inner.put(str, v);
        }

        pub fn deinit(ts: *Ts) void {
            var iter = ts.inner.iterator();
            while (iter.next()) |v| {
                ts.inner.allocator.free(v.key_ptr.*);
            }
        }

        pub fn remove(ts: *Ts, key: []const u8) void {
            if (ts.inner.getEntry(key)) |entry| {
                ts.inner.allocator.free(entry.key_ptr.*);
                _ = ts.inner.remove(key);
            }
        }

        const GetOrPutResult = std.StringHashMap(Layout.Key).GetOrPutResult;
        pub fn getOrPut(ts: *Ts, key: []const u8) !GetOrPutResult {
            if (ts.inner.getEntry(key)) |val| {
                return .{
                    .found_existing = true,
                    .key_ptr = val.key_ptr,
                    .value_ptr = val.value_ptr,
                };
            } else {
                const alloc = try ts.inner.allocator.dupe(u8, key);
                try ts.inner.put(alloc, .{ .normal = 0, .shift_layer = null });
                return ts.inner.getOrPut(alloc);
            }
        }
    };
}
