const LayoutFile = @This();

const std = @import("std");
const dkct = @import("dkwtct");

const util = dkct.util;
const v = dkct.vars;

const Layout = dkct.RebindStack.XKBLayout;

const Allocator = std.mem.Allocator;
const Io = std.Io;

layouts: std.ArrayList(Layout) = .empty,
names: std.ArrayList([]const u8) = .empty,

var buf: [12288]u8 = undefined;

pub const empty = LayoutFile{};

pub fn deinit(ts: *LayoutFile, gpa: Allocator) void {
    for (ts.layouts.items) |*lay| {
        lay.deinit(gpa);
    }
    ts.layouts.deinit(gpa);
    for (ts.names.items) |name| {
        gpa.free(name);
    }
    ts.names.deinit(gpa);
}

pub fn writeToFilePath(ts: *const LayoutFile, io: Io, gpa: Allocator, file_path: []const u8, bleed_chars: bool) !void {
    makeDirAll(io, file_path);
    const file = try Io.Dir.createFileAbsolute(io, file_path, .{});
    defer file.close(io);

    const str = try ts.exportStr(gpa, bleed_chars);
    defer gpa.free(str);

    try file.writeStreamingAll(io, str);
}

pub fn makeDirAll(io: Io, dir: []const u8) void {
    var idx: usize = 1;
    while (true) {
        const slash = std.mem.indexOfScalarPos(u8, dir, idx, '/') orelse break;
        idx = slash + 1;
        Io.Dir.createDirAbsolute(io, dir[0..slash], .default_dir) catch {};
    }
}

pub fn write(ts: *const LayoutFile, io: Io, gpa: Allocator) !void {
    return ts.writeToFilePath(io, gpa, ts.file_path);
}

pub fn loadFromFile(io: Io, gpa: Allocator, file: Io.File, name: []const u8) !LayoutFile {
    var reader = file.reader(io, &buf);
    const file_data = try reader.interface.allocRemaining(gpa, .limited(1048576));
    defer gpa.free(file_data);

    const owned = try gpa.dupe(u8, name);

    const layouts, const names = try loadFromString(file_data, gpa);
    return LayoutFile{
        .layouts = layouts,
        .names = names,
        .file_path = owned,
    };
}

pub fn loadFromName(io: Io, gpa: Allocator, layout: []const u8) !LayoutFile {
    const file_path = try getPath(layout, gpa);
    defer gpa.free(file_path);

    return loadFromFilePath(io, gpa, file_path);
}

pub fn loadFromFilePath(io: Io, gpa: Allocator, file_path: []const u8) !LayoutFile {
    const file = try Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);
    return loadFromFile(io, gpa, file, file_path);
}

pub fn exportStr(ts: *const LayoutFile, gpa: Allocator, bleed_chars: bool) ![]const u8 {
    var writer = std.Io.Writer.Allocating.init(gpa);
    defer writer.deinit();
    for (ts.layouts.items, 0..) |layout, i| {
        const layout_string = try layout.exportStr(gpa, ts.names.items[i], bleed_chars);
        defer gpa.free(layout_string);
        try writer.writer.print("{s}\n", .{layout_string});
    }
    return writer.toOwnedSlice();
}

pub const LayoutFileParseError = error{NoLayouts};
pub fn loadFromString(gpa: Allocator, string: []const u8, bleed_chars: bool) !LayoutFile {
    var lf = LayoutFile.empty;
    errdefer lf.deinit(gpa);

    var i: usize = 0;
    while (i < string.len - 12) : (i += 1) {
        if (std.mem.eql(u8, string[i .. i + 12], "\nxkb_symbols")) {
            const name, _ = util.getBetween(string[i + 12 ..], "\"\"") orelse continue;
            const newline = std.mem.indexOfScalarPos(u8, string, i + 12, '\n') orelse continue;

            // can use newline because this function doesn't check the first character and jsut assume that the bracket is somewhere in this line
            const closed_bracket = getMatchingPair(string, newline, "{}") orelse continue;

            const layout = try Layout.parse(gpa, string[newline..closed_bracket], bleed_chars);

            const owned = try gpa.dupe(u8, name);
            try lf.names.append(gpa, owned);
            try lf.layouts.append(gpa, layout);
            i = closed_bracket;
        }
    }
    if (lf.layouts.items.len == 0) return LayoutFileParseError.NoLayouts;
    return lf;
}

pub fn getMatchingPair(string: []const u8, index: usize, comptime chars: []const u8) ?usize {
    if (chars.len != 2) {
        @compileError("Chars is supposed to be of len 2.");
    }
    var cntr: usize = 0;
    for (string[index + 1 ..], index + 1..) |c, i| {
        if (c == chars[0]) {
            cntr += 1;
        } else if (c == chars[1]) {
            if (cntr == 0) {
                return i;
            }
            cntr -= 1;
        }
    }
    return null;
}

pub fn getPath(file: []const u8, gpa: Allocator) ![]u8 {
    const file_path = try std.fs.path.join(
        gpa,
        &[_][]const u8{ v.save_directory.items, file },
    );
    return file_path;
}
