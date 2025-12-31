const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \n\t");
}

pub fn exists(T: type, slice: []T, item: T) bool {
    return std.mem.findScalar(T, slice, item) != null;
}

pub fn getBetween(str: []const u8, comptime chars: []const u8) ?[]const u8 {
    if (chars.len != 2) {
        @compileError("Chars is supposed to be 2 characters");
    }
    if (std.mem.findScalar(u8, str, chars[0])) |a| {
        if (std.mem.findScalarPos(u8, str, a + 1, chars[1])) |b| {
            return str[a + 1 .. b];
        }
    }
    return null;
}

pub fn fatten(cstr: [:0]const u8) []const u8 {
    return cstr[0..cstr.len];
}
