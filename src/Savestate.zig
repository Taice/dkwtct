const Savestate = @This();

const std = @import("std");
const dkct = @import("dkwtct");

const util = dkct.util;

const DLayout = dkct.RebindStack.DkwtctLayout;

const Allocator = std.mem.Allocator;

pub const ImportData = struct {
    xkb: DLayout.XKBImportData = .{},
    rebinds: DLayout.RebindsImportData = .{},

    xkb_checkmark: bool = false,
    rebinds_checkmark: bool = false,

    pub fn deinit(ts: *ImportData, gpa: Allocator) void {
        ts.xkb.deinit(gpa);
        ts.rebinds.deinit(gpa);
    }

    pub fn clone(ts: *const ImportData, gpa: Allocator) !ImportData {
        var new = ts.*;
        new.xkb = try ts.xkb.clone(gpa);
        new.rebinds = try ts.rebinds.clone(gpa);
        return new;
    }
};

pub const ExportData = struct {
    xkb: DLayout.XKBExportData = .{},
    rebinds: DLayout.RebindsExportData = .{},

    xkb_checkmark: bool = false,
    rebinds_checkmark: bool = false,

    pub fn deinit(ts: *ExportData, gpa: Allocator) void {
        ts.xkb.deinit(gpa);
        ts.rebinds.deinit(gpa);
    }

    pub fn clone(ts: *const ExportData, gpa: Allocator) !ExportData {
        var new = ts.*;
        new.xkb = try ts.xkb.clone(gpa);
        new.rebinds = try ts.rebinds.clone(gpa);
        return new;
    }
};

keymap_path: ?[]const u8 = null,
theme: dkct.enums.Theme = .adwaita_dark,
bleed_chars: bool = false,
swap_rebinds: bool = true,

import_data: ImportData = .{},
export_data: ExportData = .{},

pub fn deinit(ts: *Savestate, gpa: Allocator) void {
    util.optionFree(gpa, ts.keymap_path);
    ts.import_data.deinit(gpa);
    ts.export_data.deinit(gpa);
}

pub fn clone(ts: *const Savestate, gpa: Allocator) !Savestate {
    var new = ts.*;
    if (new.keymap_path) |str| {
        new.keymap_path = try gpa.dupe(u8, str);
    }
    new.import_data = try ts.import_data.clone(gpa);
    new.export_data = try ts.export_data.clone(gpa);
    return new;
}

pub fn setKeymapStr(ts: *Savestate, gpa: Allocator, new: ?[]const u8) void {
    util.optionFree(gpa, ts.keymap_path);
    ts.keymap_path = new;
}

pub fn parse(gpa: Allocator, str: []const u8) !Savestate {
    const parsed = try std.json.parseFromSlice(Savestate, gpa, str, .{ .allocate = .alloc_if_needed });
    const ret = try parsed.value.clone(gpa);
    parsed.deinit();

    return ret;
}

pub fn load(io: std.Io, gpa: Allocator, file_path: []const u8) !Savestate {
    const str = try dkct.util.readFilePathFull(io, gpa, file_path);
    defer gpa.free(str);

    return try Savestate.parse(gpa, str);
}

pub fn saveToPath(ts: *const Savestate, io: std.Io, gpa: Allocator, file_path: []const u8) !void {
    var writer = std.Io.Writer.Allocating.init(gpa);
    defer writer.deinit();
    try std.json.Stringify.value(ts.*, .{}, &writer.writer);

    const str = try writer.toOwnedSlice();
    defer gpa.free(str);

    const file = try std.Io.Dir.createFileAbsolute(io, file_path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, str);
}
