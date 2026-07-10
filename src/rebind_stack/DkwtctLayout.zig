const DkwtctLayout = @This();

const std = @import("std");
const dkct = @import("dkwtct");

const v = dkct.vars;
const util = dkct.util;

const Rebinds = dkct.RebindStack.Rebinds;
const XKBLayout = dkct.RebindStack.XKBLayout;

const Allocator = std.mem.Allocator;

file_path: ?[]const u8,
rebinds: Rebinds,
layout: XKBLayout,

pub const empty = DkwtctLayout{
    .file_path = null,
    .rebinds = .empty,
    .layout = .empty,
};

pub fn deinit(ts: *DkwtctLayout, gpa: Allocator) void {
    ts.layout.deinit(gpa);
    ts.rebinds.deinit(gpa);
    util.optionFree(gpa, ts.file_path);
}

pub fn clearLayout(ts: *DkwtctLayout, gpa: Allocator) void {
    ts.layout.deinit(gpa);
    ts.layout = .empty;
}

pub fn clearRebinds(ts: *DkwtctLayout, gpa: Allocator) !void {
    var new_layout = XKBLayout.empty;
    try new_layout.keys.ensureTotalCapacity(gpa, ts.layout.keys.count());
    var iter = ts.layout.keys.iterator();
    while (iter.next()) |kv| {
        const key = ts.getOriginalKey(kv.key_ptr.*);
        new_layout.keys.putAssumeCapacity(key, kv.value_ptr.*);
    }

    ts.layout.deinit(gpa);
    ts.layout = new_layout;

    ts.rebinds.deinit(gpa);
    ts.rebinds = .empty;
}

pub fn getOriginalKey(ts: *const DkwtctLayout, key: []const u8) []const u8 {
    var iter = ts.rebinds.map.iterator();
    while (iter.next()) |kv| {
        if (std.mem.eql(u8, kv.value_ptr.*, key)) {
            return kv.key_ptr.*;
        }
    }
    return key;
}

pub fn putCharOnKey(ts: *DkwtctLayout, gpa: Allocator, key: []const u8, char: []const u8, layer: XKBLayout.LayerEnum) !void {
    var k = key;
    if (ts.rebinds.map.get(key)) |rebind| {
        k = rebind;
    }

    try ts.layout.pasteCharacter(gpa, key, char, layer);
}

pub fn clearKey(ts: *DkwtctLayout, key: []const u8, layer: XKBLayout.LayerEnum) void {
    var k = key;
    if (ts.rebinds.map.get(key)) |rebind| {
        k = rebind;
    }

    ts.layout.clearKey(k, layer);
}

pub fn addRebind(ts: *DkwtctLayout, gpa: Allocator, key: []const u8, rebind: []const u8, swap_rebinds: bool) !void {
    if (swap_rebinds) {
        var iter = ts.rebinds.map.iterator();
        var previously_this_rebind: ?[]const u8 = null;
        while (iter.next()) |kv| {
            if (std.mem.eql(u8, kv.value_ptr.*, rebind)) {
                previously_this_rebind = kv.key_ptr.*;
            }
        }

        var old = key;
        if (ts.rebinds.map.get(key)) |k| {
            old = k;
        }

        try ts.rebinds.map.put(gpa, previously_this_rebind orelse rebind, old);
        try ts.rebinds.map.put(gpa, key, rebind);

        if (dkct.keycode.untypeable_keycodes.get(rebind)) |_| {
            _ = ts.layout.keys.remove(old);
        } else {
            if (ts.layout.keys.get(old)) |old_chars| {
                if (ts.layout.keys.get(rebind)) |rebind_chars| {
                    try ts.layout.keys.put(gpa, old, rebind_chars);
                } else {
                    _ = ts.layout.keys.remove(old);
                }
                try ts.layout.keys.put(gpa, rebind, old_chars);
            } else {
                if (ts.layout.keys.get(rebind)) |rebind_chars| {
                    try ts.layout.keys.put(gpa, old, rebind_chars);
                    _ = ts.layout.keys.remove(rebind);
                }
            }
        }
    } else {
        try ts.rebinds.map.put(gpa, key, rebind);
    }

    var delete: std.ArrayList([]const u8) = .empty;
    defer delete.deinit(gpa);
    var map_iter = ts.rebinds.map.iterator();
    while (map_iter.next()) |kv| {
        if (std.mem.eql(u8, kv.key_ptr.*, kv.value_ptr.*)) {
            try delete.append(gpa, kv.key_ptr.*);
        }
    }
    for (delete.items) |k| {
        _ = ts.rebinds.map.remove(k);
    }
}

pub fn removeRebind(ts: *DkwtctLayout, gpa: Allocator, key: []const u8, swap_binds: bool) !void {
    try ts.addRebind(gpa, key, key, swap_binds);
}

const DkwtctLayoutParseError = error{ InvalidFormat, InvalidKeycode };

//  format:
//
//  rebinds:
//  [keycode1,rebind1]
//  [keycode2,rebind2]
//  [keycode3,rebind3]
//  ...
//
//  layout:
//  [key,normal,shift,alt,alt_shift] // unicode number representation or null
//  ...
pub fn parse(gpa: Allocator, str: []const u8) !DkwtctLayout {
    var layout = DkwtctLayout.empty;
    errdefer layout.deinit(gpa);

    var lines = std.mem.tokenizeAny(u8, str, " \n\t");

    var rebind_mode: ?bool = null;
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "rebinds:")) {
            rebind_mode = true;
            continue;
        }
        if (std.mem.eql(u8, line, "layout:")) {
            rebind_mode = false;
            continue;
        }

        if (rebind_mode orelse return DkwtctLayoutParseError.InvalidFormat) {
            // rebind mode
            const inbetween, _ = util.getBetween(line, "[]") orelse return DkwtctLayoutParseError.InvalidFormat;
            var tokenize = std.mem.tokenizeScalar(u8, inbetween, ',');
            const lhs = tokenize.next() orelse return DkwtctLayoutParseError.InvalidFormat;
            const rhs = tokenize.next() orelse return DkwtctLayoutParseError.InvalidFormat;
            if (tokenize.next() != null) return DkwtctLayoutParseError.InvalidFormat;

            if (dkct.keycode.getStaticKeycode(lhs)) |static_key| {
                if (dkct.keycode.getStaticKeycode(rhs)) |static_rebind| {
                    try layout.rebinds.map.put(gpa, static_key, static_rebind);
                } else {
                    try v.setErrorInfo("{s}", .{rhs});
                    return DkwtctLayoutParseError.InvalidKeycode;
                }
            } else {
                try v.setErrorInfo("{s}", .{rhs});
                return DkwtctLayoutParseError.InvalidKeycode;
            }
        } else {
            // layout mode
            const inbetween, _ = util.getBetween(line, "[]") orelse return DkwtctLayoutParseError.InvalidFormat;
            var tokenize = std.mem.tokenizeScalar(u8, inbetween, ',');
            const key = tokenize.next() orelse return DkwtctLayoutParseError.InvalidFormat;
            const normal = tokenize.next() orelse return DkwtctLayoutParseError.InvalidFormat;
            const shift = tokenize.next() orelse return DkwtctLayoutParseError.InvalidFormat;
            const alt = tokenize.next() orelse return DkwtctLayoutParseError.InvalidFormat;
            const alt_shift = tokenize.next() orelse return DkwtctLayoutParseError.InvalidFormat;
            if (tokenize.next() != null) return DkwtctLayoutParseError.InvalidFormat;

            if (dkct.keycode.getStaticKeycode(key)) |static_key| {
                const n = try std.fmt.parseInt(u21, normal, 10);
                const s: ?u21 = std.fmt.parseInt(u21, shift, 10) catch |e| b: {
                    if (std.mem.eql(u8, shift, "null")) break :b null;
                    try v.setErrorInfo("{s}", .{shift});
                    return e;
                };
                const a = try std.fmt.parseInt(u21, alt, 10);
                const as: ?u21 = std.fmt.parseInt(u21, alt_shift, 10) catch |e| b: {
                    if (std.mem.eql(u8, alt_shift, "null")) break :b null;
                    try v.setErrorInfo("{s}", .{alt_shift});
                    return e;
                };

                try layout.layout.keys.put(gpa, static_key, .{
                    .normal = n,
                    .shift = s,
                    .alt = a,
                    .alt_shift = as,
                });
            } else {
                try v.setErrorInfo("{s}", .{key});
                return DkwtctLayoutParseError.InvalidKeycode;
            }
        }
    }
    return layout;
}

pub fn printRebinds(ts: *const DkwtctLayout, writer: *std.Io.Writer) !void {
    var iter = ts.rebinds.map.iterator();
    while (iter.next()) |kv| {
        try writer.print("[{s},{s}]\n", .{ kv.key_ptr.*, kv.value_ptr.* });
    }
}

pub fn printLayout(ts: *const DkwtctLayout, writer: *std.Io.Writer) !void {
    var iter = ts.layout.keys.iterator();

    while (iter.next()) |kv| {
        try writer.print("[{s},{d},", .{ kv.key_ptr.*, kv.value_ptr.normal });
        if (kv.value_ptr.shift) |sh| {
            try writer.print("{d},", .{sh});
        } else {
            try writer.print("null,", .{});
        }
        try writer.print("{d},", .{kv.value_ptr.alt});
        if (kv.value_ptr.alt_shift) |as| {
            try writer.print("{d}]\n", .{as});
        } else {
            try writer.print("null]\n", .{});
        }
    }
}

pub fn exportStr(ts: *const DkwtctLayout, gpa: Allocator) ![]u8 {
    var writer = std.Io.Writer.Allocating.init(gpa);
    defer writer.deinit();

    try writer.writer.print("rebinds:\n", .{});
    try ts.printRebinds(&writer.writer);
    try writer.writer.print("layout:\n", .{});
    try ts.printLayout(&writer.writer);

    return writer.toOwnedSlice();
}

pub fn saveToPath(ts: *const DkwtctLayout, io: std.Io, gpa: Allocator, path: []const u8) !void {
    const str = try ts.exportStr(gpa);
    defer gpa.free(str);

    const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, str);
}

pub fn saveNewPath(ts: *DkwtctLayout, io: std.Io, gpa: Allocator, path: []const u8) !void {
    util.optionFree(gpa, ts.file_path);
    ts.file_path = path;

    try ts.saveToPath(io, gpa, path);
}

pub fn open(io: std.Io, gpa: Allocator, owned_file_path: []const u8) !DkwtctLayout {
    const file = try std.Io.Dir.openFileAbsolute(io, owned_file_path, .{});
    defer file.close(io);

    var file_buf: [1024]u8 = undefined;

    var reader = file.readerStreaming(io, &file_buf);

    const file_contents = try reader.interface.allocRemaining(gpa, .unlimited);
    defer gpa.free(file_contents);

    var ret = try DkwtctLayout.parse(gpa, file_contents);
    ret.file_path = owned_file_path;
    return ret;
}

pub const XKBImportData = struct {
    file_path: ?[]const u8 = null,
    variant: ?[]const u8 = null,

    pub fn clone(ts: *const XKBImportData, gpa: Allocator) !XKBImportData {
        return .{
            .file_path = try util.dupeOptional(gpa, ts.file_path),
            .variant = try util.dupeOptional(gpa, ts.variant),
        };
    }
    pub fn deinit(ts: *const XKBImportData, gpa: Allocator) void {
        util.optionFree(gpa, ts.variant);
        util.optionFree(gpa, ts.file_path);
    }
};

pub const XKBExportData = XKBImportData;

pub const RebindsImportData = struct {
    file_path: ?[]const u8 = null,
    table: ?[]const u8 = null,

    pub fn clone(ts: *const RebindsImportData, gpa: Allocator) !RebindsImportData {
        return .{
            .file_path = try util.dupeOptional(gpa, ts.file_path),
            .table = try util.dupeOptional(gpa, ts.table),
        };
    }

    pub fn deinit(ts: *const RebindsImportData, gpa: Allocator) void {
        util.optionFree(gpa, ts.file_path);
        util.optionFree(gpa, ts.table);
    }
};

pub const RebindsExportData = struct {
    file_path: ?[]const u8 = null,

    pub fn clone(ts: *const RebindsExportData, gpa: Allocator) !RebindsExportData {
        return .{
            .file_path = try util.dupeOptional(gpa, ts.file_path),
        };
    }

    pub fn deinit(ts: *const RebindsExportData, gpa: Allocator) void {
        util.optionFree(gpa, ts.file_path);
    }
};

pub fn import(io: std.Io, gpa: Allocator, xkb_opts: XKBImportData, rebinds: RebindsImportData) !?DkwtctLayout {
    const have_xkb_opts = !(xkb_opts.file_path == null and xkb_opts.variant == null);
    if (!have_xkb_opts and rebinds.file_path == null) return null;

    var layout: XKBLayout = .init(null);

    if (have_xkb_opts) {
        const fp = xkb_opts.file_path.?;
        const layout_name = xkb_opts.variant.?;

        const file_contents = try util.readFilePathFull(io, gpa, fp);
        defer gpa.free(file_contents);

        const layout_file = try dkct.LayoutFile.loadFromString(gpa, file_contents);
        defer layout_file.deinit(gpa);

        var replace: ?usize = null;
        for (layout_file.layouts.items, 0..) |l, i| {
            if (std.mem.eql(u8, layout_name, l.name.?)) {
                replace = i;
            }
        }

        if (replace) |i| {
            layout = try layout_file.layouts.items[i].clone(gpa);
        }
    }
}
