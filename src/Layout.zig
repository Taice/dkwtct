const Layout = @This();

const std = @import("std");
const root = @import("dkwtct");
const rl = @import("raylib");
const rlf = @import("raylib_functions.zig");
const uc = @import("unicode.zig");

const OwningStringHashmap = @import("owning_string_hashmap.zig").OwningStringHashmap;

const stringmap = @import("keysym_string_map.zig").keysym_string_map;

const Allocator = std.mem.Allocator;

pub var export_buf: [12288]u8 = undefined;
pub var keys_buf: [4096]u8 = undefined;

pub const Key = struct {
    normal: u21,
    shift_layer: ?u21 = null,
};

name: ?[]const u8,
keys: std.StringHashMap(Key),
to_be_freed: std.ArrayList([]const u8) = .empty,

pub fn init(gpa: Allocator, name: ?[]const u8) Layout {
    return Layout{ .keys = .init(gpa), .name = name };
}

pub fn clone(ts: *const Layout, gpa: Allocator) !Layout {
    var keys_clone = try ts.keys.clone();
    var to_be_freed = std.ArrayList([]const u8).empty;
    var iter = keys_clone.iterator();
    while (iter.next()) |entry| {
        entry.key_ptr.* = try gpa.dupe(u8, entry.key_ptr.*);
        try to_be_freed.append(gpa, entry.key_ptr.*);
    }
    return .{
        .keys = keys_clone,
        .to_be_freed = to_be_freed,
        .name = ts.name,
    };
}
pub fn deinit(ts: *Layout, gpa: Allocator) void {
    ts.keys.deinit();
    for (ts.to_be_freed.items) |t| {
        gpa.free(t);
    }
    ts.to_be_freed.deinit(gpa);
}

pub const LayoutParseError = error{
    InvalidKey,
    NoKeys,
};

fn stringToCodepoint(string: []const u8) ?u21 {
    if (string.len == 1) {
        return string[0];
    }

    if (uc.parseHexUnicode(string)) |u| {
        return u;
    } else |_| {}

    if (stringmap.get(string)) |u| {
        return u;
    }

    return null;
}

pub fn parse(str: []const u8, gpa: Allocator, name: ?[]const u8) !Layout {
    var ts = Layout.init(gpa, name);
    var split_iter = std.mem.splitScalar(u8, str, '\n');

    var changed = false;
    while (split_iter.next()) |line| {
        const trimmed = root.trim(line);
        if (trimmed.len < 4) continue;
        if (!std.mem.eql(u8, "key", trimmed[0..3])) {
            continue;
        }

        const key = root.getBetween(trimmed, "<>") orelse continue;
        const owned_key = try gpa.dupe(u8, key);
        errdefer gpa.free(owned_key);

        try ts.to_be_freed.append(gpa, owned_key);

        // the brace thing is just to kinda validate syntax cause like idk it'd be kinda weirdo otherwise i think
        const inside_brackets = root.getBetween(root.getBetween(trimmed, "{}") orelse continue, "[]") orelse continue;

        errdefer std.debug.print("invalid_key: {s}\n\n", .{line});

        const InvKey = LayoutParseError.InvalidKey;
        if (std.mem.indexOfScalar(u8, inside_brackets, ',')) |comma_idx| {
            const lhs = root.trim(inside_brackets[0..comma_idx]);
            const rhs = root.trim(inside_brackets[comma_idx + 1 ..]);

            const lhs_cp = stringToCodepoint(lhs) orelse return InvKey;

            var rhs_cp: ?u21 = stringToCodepoint(rhs) orelse return InvKey;

            if (rhs_cp == lhs_cp) {
                rhs_cp = null;
            }
            try ts.keys.put(owned_key, .{ .normal = lhs_cp, .shift_layer = rhs_cp });
            changed = true;
        } else {
            const unicode = root.trim(inside_brackets);
            const cp = stringToCodepoint(unicode) orelse return InvKey;
            try ts.keys.put(owned_key, .{ .normal = cp });
            changed = true;
        }
    }
    if (!changed) return LayoutParseError.NoKeys;
    return ts;
}

pub fn format(ts: Layout, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var iter = ts.keys.iterator();
    while (iter.next()) |entry| {
        try writer.print(
            "    key <{s}> {{ [ {s}, {s} ] }};\n",
            .{
                entry.key_ptr.*,
                &uc.codepointToUnicode(entry.value_ptr.normal),
                &uc.codepointToUnicode(entry.value_ptr.shift_layer orelse entry.value_ptr.normal),
            },
        );
    }
}

const ExportStrError = error{
    NoName,
};
pub fn exportStr(ts: *const Layout) ![]const u8 {
    const name = ts.name orelse "layout";
    const keys = try std.fmt.bufPrint(&keys_buf, "{f}", .{ts});
    // std.debug.print("keys: {s}\n\n\n\n", .{keys});
    const str = try std.fmt.bufPrint(
        &export_buf,
        \\partial alphanumeric_keys
        \\xkb_symbols "{s}" {{
        \\    name[Group1] = "{s} search crafting.";
        \\
        \\{s}}};
        \\
    ,
        .{
            name,
            name,
            keys,
        },
    );

    const trimmed = root.trim(str);
    export_buf[trimmed.len] = 0;
    return trimmed;
}

const Range = struct {
    from: usize,
    to: usize,
};
