const std = @import("std");

const LayoutFile = @import("LayoutFile.zig");
const makeDirAll = @import("LayoutFile.zig").makeDirAll;

pub fn getKeymapFile(gpa: std.mem.Allocator, default_text: []const u8) !?[]const u8 {
    const path = try getPath("keymap.dkwtct", gpa);
    defer gpa.free(path);

    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_only }) catch |e| {
        switch (e) {
            std.fs.File.OpenError.FileNotFound => {
                makeDirAll(path);
                const file = try std.fs.createFileAbsolute(path, .{});
                var write_buf: [100]u8 = undefined;
                var writer = file.writer(&write_buf);
                try writer.interface.writeAll(default_text);
                return null;
            },
            else => return e,
        }
    };
    return try readFileAll(file, gpa);
}

pub fn getPath(file: []const u8, gpa: std.mem.Allocator) ![]const u8 {
    const home = try std.process.getEnvVarOwned(gpa, "HOME");
    defer gpa.free(home);

    const file_path = try std.fs.path.join(
        gpa,
        &[_][]const u8{ home, ".config", "dkwtct", file },
    );
    return file_path;
}

pub fn readFileAll(file: std.fs.File, gpa: std.mem.Allocator) ![]u8 {
    var list = std.ArrayList(u8).empty;
    defer list.deinit(gpa);

    var buf: [1024]u8 = undefined;
    var reader = file.reader(&buf);

    while (true) {
        const n_read = try reader.interface.readSliceShort(&buf);
        if (n_read == 0) break;
        try list.appendSlice(gpa, buf[0..n_read]);
    }

    return list.toOwnedSlice(gpa);
}

pub fn defaultPath(gpa: std.mem.Allocator) ![]u8 {
    const home = try std.process.getEnvVarOwned(gpa, "HOME");
    defer gpa.free(home);

    return std.fs.path.join(gpa, &[_][]const u8{ home, ".config", "xkb", "symbols", "" });
}

pub fn getPreferredSaveDirectory(gpa: std.mem.Allocator) ![]u8 {
    const file_path = try getPath("save_dir", gpa);
    defer gpa.free(file_path);

    const file = std.fs.openFileAbsolute(file_path, .{ .mode = .read_only }) catch |e| {
        switch (e) {
            std.fs.File.OpenError.FileNotFound => {
                const file = try std.fs.createFileAbsolute(file_path, .{});
                const default_dir = try defaultPath(gpa);
                try file.writeAll(default_dir);
                return default_dir;
            },
            else => return e,
        }
    };
    defer file.close();

    return try readFileAll(file, gpa);
}

pub fn saveSaveDirectory(gpa: std.mem.Allocator, save_dir: []const u8) !void {
    const file_path = try getPath("save_dir", gpa);
    std.debug.print("fp: {s}\n", .{file_path});
    defer gpa.free(file_path);

    const file = try std.fs.cwd().createFile(file_path, .{
        .truncate = true,
    });
    defer file.close();

    try file.writeAll(save_dir);
}
