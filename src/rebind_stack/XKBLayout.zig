const XKBLayout = @This();

const std = @import("std");
const dkct = @import("dkwtct");

const util = dkct.util;
const unicode = dkct.unicode;
const v = dkct.vars;

const keycode_to_xkb = dkct.keycode.keycode_to_xkb;
const xkb_to_keycode = dkct.keycode.keycode_to_xkb;

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Key = struct {
    normal: u21 = 0,
    shift: ?u21 = null,
    alt: u21 = 0,
    alt_shift: ?u21 = null,

    pub fn getLayer(ts: *const Key, layer: LayerEnum) ?u21 {
        return switch (layer) {
            .normal => ts.normal,
            .shift => ts.shift,
            .alt => ts.alt,
            .alt_shift => ts.alt_shift,
        };
    }
};

keys: std.StringHashMapUnmanaged(Key) = .empty,

pub const empty = XKBLayout{};

pub fn deinit(ts: *XKBLayout, gpa: Allocator) void {
    ts.keys.deinit(gpa);
}

pub fn clone(ts: *const XKBLayout, gpa: Allocator) !XKBLayout {
    return .{
        .keys = try ts.keys.clone(gpa),
    };
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

    if (dkct.keysym_string_map.keysym_string_map.get(string)) |u| {
        return u;
    }

    return null;
}

pub fn importFromFile(io: Io, gpa: Allocator, file: []const u8, variant: []const u8) !?XKBLayout {
    const file_contents = try util.readFilePathFull(io, gpa, file);
    defer gpa.free(file_contents);

    const layout_file = try dkct.LayoutFile.loadFromString(gpa, file_contents);
    defer layout_file.deinit(gpa);

    for (layout_file.layouts.items) |lay| {
        if (std.mem.eql(u8, lay.name.?, variant)) {
            return lay.clone(gpa);
        }
    }

    return null;
}

pub fn parse(gpa: Allocator, str: []const u8, bleed_chars: bool) !XKBLayout {
    const InvKey = LayoutParseError.InvalidKey;

    var ts = XKBLayout.empty;
    errdefer ts.deinit(gpa);
    var split_iter = std.mem.splitScalar(u8, str, '\n');

    while (split_iter.next()) |line| {
        const trimmed = util.trim(line);
        if (trimmed.len < 4) continue;
        if (!std.mem.eql(u8, "key", trimmed[0..3])) {
            continue;
        }

        const key, _ = util.getBetween(trimmed, "<>") orelse continue;
        const static_key = dkct.keycode.xkb_to_keycode.get(key) orelse return InvKey;

        // the brace thing is just to kinda validate syntax cause like idk it'd be kinda weirdo otherwise i think
        const inside_brackets, _ = util.getBetween((util.getBetween(trimmed, "{}") orelse continue).@"0", "[]") orelse continue;

        var k = Key{};
        var iter = std.mem.splitScalar(u8, inside_brackets, ',');
        const normal = iter.next();
        if (normal) |x| {
            const s = util.trim(x);
            const cp = stringToCodepoint(s) orelse continue;
            k.normal = cp;
        } else {
            return InvKey;
        }
        const shift = iter.next();
        if (shift) |x| {
            const s = util.trim(x);
            const cp = stringToCodepoint(s) orelse continue;
            k.shift = cp;
        }
        const alt = iter.next();
        if (alt) |x| {
            const s = util.trim(x);
            const cp = stringToCodepoint(s) orelse continue;
            k.alt = cp;
        }
        const alt_shift = iter.next();
        if (alt_shift) |x| {
            const s = util.trim(x);
            const cp = stringToCodepoint(s) orelse continue;
            k.alt_shift = cp;
        }

        if (bleed_chars) {
            if (k.normal == k.shift) {
                k.shift = null;
            }
            if (k.alt == k.alt_shift) {
                k.alt_shift = null;
            }
        }

        if (k.shift == 0) k.shift = null;
        if (k.alt_shift == 0) k.alt_shift = null;

        if (dkct.keycode.untypeable_keycodes.has(static_key)) {
            continue;
        }
        try ts.keys.put(gpa, static_key, k);
    }
    if (ts.keys.count() == 0) return LayoutParseError.NoKeys;
    return ts;
}

pub fn keysStr(ts: XKBLayout, gpa: Allocator, bleed: bool) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(gpa);
    defer aw.deinit();

    var iter = ts.keys.iterator();
    while (iter.next()) |entry| {
        try aw.writer.print(
            "    key <{s}> {{ [ {s}, {s}, {s}, {s} ] }};\n",
            .{
                keycode_to_xkb.get(entry.key_ptr.*) orelse {
                    try v.setErrorInfo("{s}", .{entry.key_ptr.*});
                    return ExportStrError.InvalidKey;
                },
                &unicode.codepointToHexUnicode(entry.value_ptr.normal),
                &unicode.codepointToHexUnicode(entry.value_ptr.shift orelse if (bleed) entry.value_ptr.normal else 0),
                &unicode.codepointToHexUnicode(entry.value_ptr.alt),
                &unicode.codepointToHexUnicode(entry.value_ptr.alt_shift orelse if (bleed) entry.value_ptr.alt else 0),
            },
        );
    }
    return aw.toOwnedSlice();
}

const ExportStrError = error{
    NoName,
    InvalidKey,
};

pub fn exportStr(ts: *const XKBLayout, gpa: Allocator, name: []const u8, bleed: bool) ![]const u8 {
    const keys = try ts.keysStr(gpa, bleed);
    defer gpa.free(keys);
    // std.debug.print("keys: {s}\n\n\n\n", .{keys});
    const str = try std.fmt.allocPrint(
        gpa,
        \\partial alphanumeric_keys
        \\xkb_symbols "{s}" {{
        \\    name[Group1] = "{s} search crafting.";
        \\
        \\    key <RALT> {{[  ISO_Level3_Shift  ], type[group1]="ONE_LEVEL" }};
        \\
        \\{s}}};
    ,
        .{
            name,
            name,
            keys,
        },
    );

    return str;
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

    pub fn cycle(ts: LayerEnum) LayerEnum {
        const numeral: u8 = @intFromEnum(ts);
        return if (numeral >= 3) .normal else @enumFromInt(numeral + 1);
    }

    pub fn cycleBack(ts: LayerEnum) LayerEnum {
        const numeral: u8 = @intFromEnum(ts);
        return if (numeral <= 0) .alt_shift else @enumFromInt(numeral - 1);
    }
};

const PasteCharacterError = error{
    InvalidLength,
    InvalidUnicode,
};

pub fn pasteCharacter(ts: *XKBLayout, gpa: Allocator, key: []const u8, text: []const u8, layer: LayerEnum) !u21 {
    if (text.len == 0 or try std.unicode.utf8ByteSequenceLength(text[0]) != text.len) return PasteCharacterError.InvalidLength; // ensure single utf-8 codepoint
    const uc = std.unicode.utf8Decode(text[0..text.len]) catch return PasteCharacterError.InvalidUnicode;
    try ts.putCharacterOnKey(gpa, key, uc, layer);
    return uc;
}

pub fn putCharacterOnKey(ts: *XKBLayout, gpa: Allocator, key: []const u8, cp: u21, layer: LayerEnum) !void {
    const gop = try ts.keys.getOrPut(gpa, key);
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

pub fn clearKey(ts: *XKBLayout, key: []const u8, layer: LayerEnum) void {
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
