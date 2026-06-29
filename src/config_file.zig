pub fn getKeymapFile(io: Io, environ: std.process.Environ, gpa: Allocator, default_text: []const u8) !?[]const u8 {
    const path = try getPath(gpa, environ, "keymap.dkwtct");
    defer gpa.free(path);

    const file = Io.Dir.openFileAbsolute(io, path, .{ .mode = .read_only }) catch |e| {
        switch (e) {
            Io.File.OpenError.FileNotFound => {
                makeDirAll(io, path);
                const file = try Io.Dir.createFileAbsolute(io, path, .{});
                var write_buf: [100]u8 = undefined;
                var writer = file.writer(io, &write_buf);
                try writer.interface.writeAll(default_text);
                return null;
            },
            else => return e,
        }
    };
    return try readFileAll(io, gpa, file);
}

pub fn getPath(gpa: Allocator, environ: std.process.Environ, file: []const u8) ![]const u8 {
    const home = try environ.getAlloc(gpa, "HOME");
    defer gpa.free(home);

    const file_path = try std.fs.path.join(
        gpa,
        &[_][]const u8{ home, ".config", "dkwtct", file },
    );
    return file_path;
}

pub fn readFileAll(io: Io, gpa: Allocator, file: Io.File) ![]u8 {
    var list = std.ArrayList(u8).empty;
    defer list.deinit(gpa);

    var buf: [1024]u8 = undefined;
    var reader = file.reader(io, &buf);

    while (true) {
        const n_read = try reader.interface.readSliceShort(&buf);
        if (n_read == 0) break;
        try list.appendSlice(gpa, buf[0..n_read]);
    }

    return list.toOwnedSlice(gpa);
}

pub fn defaultPath(gpa: Allocator, environ: std.process.Environ) ![]u8 {
    const home = try environ.getAlloc(gpa, "HOME");
    defer gpa.free(home);

    return std.fs.path.join(gpa, &[_][]const u8{ home, ".config", "xkb", "symbols", "" });
}

pub fn getPreferredSaveDirectory(io: Io, gpa: Allocator, environ: std.process.Environ) ![]u8 {
    const file_path = try getPath(gpa, environ, "save_dir");
    defer gpa.free(file_path);

    const file = Io.Dir.openFileAbsolute(io, file_path, .{ .mode = .read_only }) catch |e| {
        switch (e) {
            Io.File.OpenError.FileNotFound => {
                const file = try Io.Dir.createFileAbsolute(io, file_path, .{});
                const default_dir = try defaultPath(gpa, environ);
                try file.writeStreamingAll(io, default_dir);
                return default_dir;
            },
            else => return e,
        }
    };
    defer file.close(io);

    return try readFileAll(io, gpa, file);
}

pub fn saveSaveDirectory(io: Io, gpa: Allocator, environ: std.process.Environ, save_dir: []const u8) !void {
    const file_path = try getPath(gpa, environ, "save_dir");
    std.debug.print("fp: {s}\n", .{file_path});
    defer gpa.free(file_path);

    const file = try Io.Dir.cwd().createFile(io, file_path, .{
        .truncate = true,
    });
    defer file.close(io);

    try file.writeStreamingAll(io, save_dir);
}

//
const std = @import("std");

const LayoutFile = @import("LayoutFile.zig");
const makeDirAll = @import("LayoutFile.zig").makeDirAll;

const Allocator = std.mem.Allocator;
const Io = std.Io;
