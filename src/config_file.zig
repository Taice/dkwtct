const std = @import("std");
const dkct = @import("dkwtct");

const util = dkct.util;

const LayoutFile = dkct.LayoutFile;

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub var arena: std.heap.ArenaAllocator = undefined;

pub var config_dir: []const u8 = "";
pub var dkwtct_config_dir: []const u8 = "";
pub var layouts_dir: []const u8 = "";
pub var keymaps_dir: []const u8 = "";
pub var savestate_path: []const u8 = "";
pub var xkb_dir: []const u8 = "";
pub var waywall_dir: []const u8 = "";
pub var current_layout_file: []const u8 = "";

pub fn initRelevantThings(io: Io, backing_alloc: Allocator, environ: std.process.Environ) !void {
    arena = .init(backing_alloc);
    const gpa = arena.allocator();

    config_dir = try getConfigDir(gpa, environ);
    dkwtct_config_dir = try getDkwtctConfigPath(gpa);
    layouts_dir = try getPath(gpa, "layouts/");
    keymaps_dir = try getPath(gpa, "keymaps/");
    savestate_path = try getPath(gpa, "savestate");
    xkb_dir = try std.fs.path.join(gpa, &.{ config_dir, "xkb/symbols/" });
    waywall_dir = try std.fs.path.join(gpa, &.{ config_dir, "waywall/" });
    current_layout_file = try std.fs.path.join(gpa, &.{ dkwtct_config_dir, "cached_layout" });

    util.makeDirAll(io, layouts_dir);
    util.makeDirAll(io, keymaps_dir);
}

pub fn deinitRelevantThings() void {
    arena.deinit();
}

pub fn getConfigDir(gpa: Allocator, environ: std.process.Environ) ![]const u8 {
    const xdg_config_home = environ.getAlloc(gpa, "XDG_CONFIG_HOME") catch |e| {
        switch (e) {
            error.EnvironmentVariableMissing => {
                const home = try environ.getAlloc(gpa, "HOME");
                defer gpa.free(home);
                const path = try std.fs.path.join(gpa, &.{ home, ".config" });
                return path;
            },
            else => return e,
        }
    };
    return xdg_config_home;
}

pub fn getDkwtctConfigPath(gpa: Allocator) ![]const u8 {
    const dkwtct_dir = try std.fs.path.join(gpa, &.{ config_dir, "dkwtct" });
    return dkwtct_dir;
}

pub fn getPath(gpa: Allocator, file: []const u8) ![]const u8 {
    const file_path = try std.fs.path.join(
        gpa,
        &[_][]const u8{ dkwtct_config_dir, file },
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
                defer file.close(io);

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
