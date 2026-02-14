const std = @import("std");
const root = @import("dkwtct");

const v = @import("vars.zig");

const Layout = @import("Layout.zig");
const Allocator = std.mem.Allocator;

const LayoutFile = @This();

layouts: std.ArrayList(Layout) = .empty,
names: std.ArrayList([]const u8) = .empty,
file_path: []const u8,

var buf: [12288]u8 = undefined;

pub fn init(layout: Layout, name: []const u8, gpa: Allocator) !LayoutFile {
    const path = try getPath(name, gpa);
    defer gpa.free(path);
    var layouts = std.ArrayList(Layout).empty;
    try layouts.append(gpa, layout);
    std.debug.print("path: {s}\n", .{path});
    return .{
        .layouts = layouts,
        .file_path = try gpa.dupe(u8, path),
    };
}

pub fn deinit(ts: *LayoutFile, gpa: Allocator) void {
    for (ts.layouts.items) |*lay| {
        lay.deinit(gpa);
    }
    ts.layouts.deinit(gpa);
    for (ts.names.items) |name| {
        gpa.free(name);
    }
    ts.names.deinit(gpa);
    gpa.free(ts.file_path);
}

pub fn writeToFile(ts: *const LayoutFile, file: std.fs.File, gpa: std.mem.Allocator) !void {
    var str = try ts.exportStr(gpa);
    defer str.deinit(gpa);
    return file.writeAll(str.items);
}

pub fn writeToFilePath(ts: *const LayoutFile, file_path: []const u8, gpa: std.mem.Allocator) !void {
    makeDirAll(file_path);
    const file = try std.fs.createFileAbsolute(file_path, .{});
    defer file.close();

    return ts.writeToFile(file, gpa);
}

pub fn makeDirAll(dir: []const u8) void {
    var idx: usize = 1;
    while (true) {
        const slash = std.mem.indexOfScalarPos(u8, dir, idx, '/') orelse break;
        idx = slash + 1;
        std.fs.makeDirAbsolute(dir[0..slash]) catch {};
    }
}

pub fn write(ts: *const LayoutFile, gpa: std.mem.Allocator) !void {
    return ts.writeToFilePath(ts.file_path, gpa);
}

pub fn loadFromFile(file: std.fs.File, name: []const u8, gpa: Allocator) !LayoutFile {
    var reader = file.reader(&buf);
    const file_data = try reader.interface.allocRemaining(gpa, .limited(1048576));
    defer gpa.free(file_data);

    const owned = try gpa.dupe(u8, name);

    const layouts, const names = try findLayoutsInString(file_data, gpa);
    return LayoutFile{
        .layouts = layouts,
        .names = names,
        .file_path = owned,
    };
}

pub fn loadFromName(layout: []const u8, gpa: Allocator) !LayoutFile {
    const file_path = try getPath(layout, gpa);
    defer gpa.free(file_path);

    return loadFromFilePath(file_path, gpa);
}

pub fn loadFromFilePath(file_path: []const u8, gpa: Allocator) !LayoutFile {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    return loadFromFile(file, file_path, gpa);
}

pub fn exportStr(ts: *const LayoutFile, gpa: Allocator) !std.ArrayList(u8) {
    var str = std.ArrayList(u8).empty;
    for (ts.layouts.items) |layout| {
        const layout_string = try layout.exportStr();
        try str.appendSlice(gpa, layout_string);
        try str.append(gpa, '\n');
    }
    return str;
}

pub fn findLayoutsInString(string: []const u8, gpa: Allocator) !struct { std.ArrayList(Layout), std.ArrayList([]const u8) } {
    var layouts = std.ArrayList(Layout).empty;
    var names = std.ArrayList([]const u8).empty;
    var i: usize = 0;
    while (i < string.len - 12) : (i += 1) {
        if (std.mem.eql(u8, string[i .. i + 12], "\nxkb_symbols")) {
            const name = root.getBetween(string[i + 12 ..], "\"\"") orelse continue;
            const newline = std.mem.indexOfScalarPos(u8, string, i + 12, '\n') orelse continue;

            // can use newline because this function doesn't check the first character and jsut assume that the bracket is somewhere in this line
            const closed_bracket = getMatchingPair(string, newline, "{}") orelse continue;

            var layout = Layout.parse(string[newline..closed_bracket], gpa, name) catch continue;
            errdefer layout.deinit(gpa);
            const owned = try gpa.dupe(u8, name);
            layout.name = owned;
            try names.append(gpa, owned);
            try layouts.append(gpa, layout);
            i = closed_bracket;
        }
    }
    return .{ layouts, names };
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

pub fn getPath(file: []const u8, gpa: std.mem.Allocator) ![]u8 {
    const file_path = try std.fs.path.join(
        gpa,
        &[_][]const u8{ v.save_directory.items, file },
    );
    return file_path;
}
