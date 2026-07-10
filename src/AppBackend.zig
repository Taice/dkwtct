const AppBackend = @This();

const std = @import("std");
const dkct = @import("dkwtct");

const Keymap = dkct.Keymap;
const Layout = dkct.XKBLayout;
const LayoutFile = dkct.LayoutFile;
const Textbox = dkct.Textbox;

const Allocator = std.mem.Allocator;
const Io = std.Io;

selected_button: ?[]const u8 = null,
selected_shift_layer: bool = false,

paused: bool = false,
current_file: ?dkct.LayoutFile = null,

layout: *Layout,

pub fn init(gpa: Allocator) !AppBackend {
    const backend = AppBackend{
        .layout = try gpa.create(Layout),
    };
    backend.layout.* = .init(null);
    return backend;
}

pub fn deinit(ts: *AppBackend, gpa: Allocator) void {
    if (ts.current_file) |*f| {
        f.deinit(gpa);
    } else {
        ts.layout.deinit(gpa);
        gpa.destroy(ts.layout);
    }
}

pub fn saveLayoutNameVariant(ts: *AppBackend, io: Io, gpa: Allocator, name: []const u8, variant: []const u8) !void {
    var file = LayoutFile.loadFromName(io, gpa, name) catch |e| {
        switch (e) {
            std.Io.File.OpenError.FileNotFound => {
                var file = try LayoutFile.init(ts.layout.*, name, gpa);
                try file.names.append(gpa, try gpa.dupe(u8, variant));
                try file.write(io, gpa);

                if (ts.current_file) |*f| {
                    f.deinit(gpa);
                } else {
                    gpa.destroy(ts.layout);
                }
                ts.current_file = file;
                ts.layout = &file.layouts.items[0];
            },
            else => |err| {
                return err;
            },
        }
        return;
    };
    errdefer file.deinit(gpa);
    const variant_owned = try gpa.dupe(u8, variant);
    try file.names.append(gpa, variant_owned);
    var layout = ts.layout.*;
    if (ts.current_file) |*f| {
        layout = try ts.layout.clone(gpa);
        f.deinit(gpa);
    } else {
        gpa.destroy(ts.layout);
    }
    layout.name = variant_owned;
    for (file.layouts.items) |*l| {
        if (std.mem.eql(u8, l.name.?, variant)) {
            ts.current_file = file;
            l.deinit(gpa);
            l.* = layout;
            ts.layout = l;
            try file.write(io, gpa);
            return;
        }
    }
    try file.layouts.append(gpa, layout);
    ts.current_file = file;
    ts.layout = &file.layouts.items[file.layouts.items.len - 1];
    try file.write(io, gpa);
}

const ImportLayoutError = error{
    NoLayout,
};

pub fn importLayoutNameVariant(ts: *AppBackend, io: Io, gpa: Allocator, layout_name: []const u8, variant: []const u8) !void {
    var file = try LayoutFile.loadFromName(io, gpa, layout_name);
    errdefer file.deinit(gpa);
    var found = false;
    for (file.layouts.items) |*l| {
        if (std.mem.eql(u8, l.name.?, variant)) {
            found = true;

            if (ts.current_file) |*f| {
                f.deinit(gpa);
            } else {
                ts.layout.deinit(gpa);
                gpa.destroy(ts.layout);
            }
            ts.current_file = file;

            ts.layout = l;
            ts.layout.name = try gpa.dupe(u8, variant);
            try ts.layout.to_be_freed.append(gpa, ts.layout.name.?);
            return;
        }
    }
    return ImportLayoutError.NoLayout;
}

pub fn resetLayout(ts: *AppBackend, gpa: Allocator) !void {
    if (ts.current_file) |*f| {
        f.deinit(gpa);
        ts.layout = try gpa.create(Layout);
        ts.current_file = null;
    } else {
        ts.layout.deinit(gpa);
    }
    ts.layout.* = Layout.init(gpa, null);
}

pub fn trySavingLayout(ts: *AppBackend, io: Io, gpa: Allocator) !bool {
    const file = ts.current_file orelse return false;
    try file.write(io, gpa);
    return true;
}
