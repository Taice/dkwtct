const Rebinds = @This();

const std = @import("std");
const dkct = @import("dkwtct");

const util = dkct.util;
const v = dkct.vars;

const Allocator = std.mem.Allocator;

map: std.StringHashMapUnmanaged([]const u8) = .empty,

pub const empty = Rebinds{};

pub fn clone(ts: *Rebinds, gpa: Allocator) !Rebinds {
    return .{
        .map = try ts.map.clone(gpa),
    };
}

pub fn deinit(ts: *Rebinds, gpa: Allocator) void {
    ts.map.deinit(gpa);
}

const ParseError = error{
    NotRebinds,
    NoKey,
    NoValue,
    NotKey,
    NotValue,
    TooManyTokens,
    InvalidKey,
};
pub fn parseLua(gpa: Allocator, str: []const u8) !Rebinds {
    var rebinds = Rebinds.empty;
    errdefer rebinds.deinit(gpa);

    var lines = std.mem.tokenizeScalar(u8, str, '\n');

    while (lines.next()) |t| {
        var tokens = std.mem.tokenizeAny(u8, t, " =\n\t");

        if (tokens.peek()) |n| {
            if (n.len >= 2) {
                if (std.mem.eql(u8, n[0..2], "--")) {
                    continue;
                }
            }
        }

        const key_str = tokens.next() orelse continue;
        var value_str = tokens.next() orelse return ParseError.NoValue;
        value_str.len -= 1;

        if (tokens.next() != null) {
            return ParseError.TooManyTokens;
        }

        const key = getKey(key_str) orelse return ParseError.NotKey;
        const val = getValue(value_str) orelse return ParseError.NotValue;

        var buf: [20]u8 = undefined;
        if (key.len > buf.len or val.len > buf.len) {
            return ParseError.InvalidKey;
        }

        const upper_key = std.ascii.upperString(&buf, key);
        const static_key = dkct.keycode.getStaticKeycode(upper_key) orelse return ParseError.InvalidKey;

        const upper_val = std.ascii.upperString(&buf, val);
        const static_val = dkct.keycode.getStaticKeycode(upper_val) orelse return ParseError.InvalidKey;

        try rebinds.map.put(gpa, static_key, static_val);
    }

    return rebinds;
}

pub fn getKey(str: []const u8) ?[]const u8 {
    if (str.len < 5) return null;
    if (str[0] != '[' or str[str.len - 1] != ']') return null;
    const second_char = str[1];
    if (second_char != '\'' and second_char != '"') return null;
    if (str[str.len - 2] != second_char) return null;

    return str[2 .. str.len - 2];
}

pub fn getValue(str: []const u8) ?[]const u8 {
    if (str.len < 3) return null;
    const brace = str[0];
    if (brace != '\'' and brace != '"') return null;
    if (str[str.len - 1] != brace) return null;

    return str[1 .. str.len - 1];
}

pub fn getLuaFile(ts: *const Rebinds, gpa: Allocator) ![]const u8 {
    var writer = std.Io.Writer.Allocating.init(gpa);
    defer writer.deinit();

    try writer.writer.print("return {{\n", .{});
    var iter = ts.map.iterator();
    while (iter.next()) |kv| {
        try writer.writer.print("   [\"{s}\"] = \"{s}\",\n", .{ kv.key_ptr.*, kv.value_ptr.* });
    }
    try writer.writer.print("}}", .{});

    return writer.toOwnedSlice();
}
