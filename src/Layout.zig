const Layout = @This();

const std = @import("std");
const root = @import("dkwtct");
const rl = @import("raylib");
const rlf = @import("raylib_functions.zig");
const unicode = @import("unicode.zig");

const OwningStringHashmap = @import("owning_string_hashmap.zig").OwningStringHashmap;

const stringmap = @import("keysym_string_map.zig").keysym_string_map;

const Allocator = std.mem.Allocator;

pub var export_buf: [12288]u8 = undefined;
pub var keys_buf: [4096]u8 = undefined;

pub const Key = struct {
    normal: u21 = 0,
    shift: ?u21 = null,
    alt: u21 = 0,
    alt_shift: ?u21 = null,
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

    if (unicode.parseHexUnicode(string)) |u| {
        return u;
    } else |_| {}

    if (stringmap.get(string)) |u| {
        return u;
    }

    return null;
}

pub fn parse(str: []const u8, gpa: Allocator, name: ?[]const u8) !Layout {
    var ts = Layout.init(gpa, name);
    errdefer ts.deinit(gpa);
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

        try ts.to_be_freed.append(gpa, owned_key);

        // the brace thing is just to kinda validate syntax cause like idk it'd be kinda weirdo otherwise i think
        const inside_brackets = root.getBetween(root.getBetween(trimmed, "{}") orelse continue, "[]") orelse continue;

        const InvKey = LayoutParseError.InvalidKey;

        var k = Layout.Key{};
        var iter = std.mem.splitScalar(u8, inside_brackets, ',');
        const normal = iter.next();
        if (normal) |x| {
            const s = root.trim(x);
            const cp = stringToCodepoint(s) orelse continue;
            k.normal = cp;
        } else {
            return InvKey;
        }
        const shift = iter.next();
        if (shift) |x| {
            const s = root.trim(x);
            const cp = stringToCodepoint(s) orelse continue;
            k.shift = cp;
        }
        const alt = iter.next();
        if (alt) |x| {
            const s = root.trim(x);
            const cp = stringToCodepoint(s) orelse continue;
            k.alt = cp;
        }
        const alt_shift = iter.next();
        if (alt_shift) |x| {
            const s = root.trim(x);
            const cp = stringToCodepoint(s) orelse continue;
            k.alt_shift = cp;
        }

        if (k.normal == k.shift) {
            k.shift = null;
        }
        if (k.alt == k.alt_shift) {
            k.alt_shift = null;
        }

        changed = true;
        try ts.keys.put(owned_key, k);
    }
    if (!changed) return LayoutParseError.NoKeys;
    return ts;
}

pub fn format(ts: Layout, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    var iter = ts.keys.iterator();
    while (iter.next()) |entry| {
        try writer.print(
            "    key <{s}> {{ [ {s}, {s}, {s}, {s} ] }};\n",
            .{
                entry.key_ptr.*,
                &unicode.codepointToUnicode(entry.value_ptr.normal),
                &unicode.codepointToUnicode(entry.value_ptr.shift orelse entry.value_ptr.normal),
                &unicode.codepointToUnicode(entry.value_ptr.alt),
                &unicode.codepointToUnicode(entry.value_ptr.alt_shift orelse entry.value_ptr.alt),
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
        \\    key <RALT> {{[  ISO_Level3_Shift  ], type[group1]="ONE_LEVEL" }};
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

pub const LayerEnum = enum(u8) {
    normal = 0,
    shift = 1,
    alt = 2,
    alt_shift = 3,

    pub fn cycle(ts: *LayerEnum) void {
        const numeral: u8 = @intFromEnum(ts.*);
        ts.* = if (numeral >= 3) .normal else @enumFromInt(numeral + 1);
    }

    pub fn cycleBack(ts: *LayerEnum) void {
        const numeral: u8 = @intFromEnum(ts.*);
        ts.* = if (numeral <= 0) .alt_shift else @enumFromInt(numeral - 1);
    }
};

const PasteCharacterError = error{
    InvalidLength,
    InvalidUnicode,
};

pub fn pasteCharacter(ts: *Layout, key: []const u8, text: []const u8, layer: LayerEnum) !u21 {
    if (try std.unicode.utf8ByteSequenceLength(text[0]) != text.len) return PasteCharacterError.InvalidLength; // ensure single utf-8 codepoint
    const uc = std.unicode.utf8Decode(text[0..text.len]) catch return PasteCharacterError.InvalidUnicode;
    try ts.putCharacterOnKey(key, uc, layer);
    return uc;
}

pub fn putCharacterOnKey(ts: *Layout, key: []const u8, cp: u21, layer: LayerEnum) !void {
    const gop = try ts.keys.getOrPut(key);
    var ptr = gop.value_ptr;
    if (!gop.found_existing) {
        ptr.* = .{};
    }
    switch (layer) {
        .shift => ptr.shift = cp,
        .normal => ptr.normal = cp,
        .alt => ptr.alt = cp,
        .alt_shift => ptr.alt_shift = cp,
    }
}

pub fn clearKey(ts: *Layout, key: []const u8, layer: LayerEnum) void {
    if (ts.keys.getPtr(key)) |ptr| {
        switch (layer) {
            .shift => ptr.shift = null,
            .alt_shift => ptr.alt_shift = null,
            .normal => ptr.normal = 0,
            .alt => ptr.alt = 0,
        }
        if (ptr.alt == 0 and ptr.normal == 0 and ptr.shift == null and ptr.alt_shift == null) { // if the key is blank
            _ = ts.keys.remove(key);
        }
    }
}
