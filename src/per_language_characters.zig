const std = @import("std");

const file = @embedFile("assets/per_language_characters");

const Lang = struct {
    lang: []const u8,
    chars: []const u8,
};

const lang_chars = parseFileForLangs();

pub fn parseFileForLangs() []Lang {
    var lines = std.mem.splitScalar(u8, file, '\n');
    var i = 0;
    while (lines.next()) |_| {
        i += 1;
    }
    var langs: [i]Lang = .{};
    while (lines.next()) |line| {
        var split = std.mem.splitScalar(u8, line, ':');

        const lhs = std.mem.trim(u8, split.next().?, " \n\t");
        const rhs = std.mem.trim(u8, split.next().?, " \n\t");

        langs[i] = .{ .lang = lhs, .chars = rhs };
    }
}
