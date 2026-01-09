const Backend = @This();

const std = @import("std");

const Allocator = std.mem.Allocator;

const Keymap = @import("Keymap.zig");
const Layout = @import("Layout.zig");
const LayoutFile = @import("LayoutFile.zig");
const Textbox = @import("Textbox.zig");

selected_button: ?[]const u8 = null,
selected_shift_layer: bool = false,

paused: bool = false,
current_file: ?@import("LayoutFile.zig") = null,

layout: *Layout,

pub fn init(gpa: Allocator) !Backend {
    const backend = Backend{
        .layout = try gpa.create(Layout),
    };
    backend.layout.* = .init(gpa, null);
    return backend;
}

pub fn deinit(ts: *Backend, gpa: Allocator) void {
    if (ts.current_file) |*f| {
        f.deinit(gpa);
    } else {
        ts.layout.deinit(gpa);
        gpa.destroy(ts.layout);
    }
}

pub fn saveLayoutNameVariant(ts: *Backend, name: []const u8, variant: []const u8, gpa: Allocator) !void {
    var file = LayoutFile.loadFromName(name, gpa) catch |e| {
        switch (e) {
            std.fs.File.OpenError.FileNotFound => {
                var file = try LayoutFile.init(ts.layout.*, name, gpa);
                try file.names.append(gpa, variant);
                try file.write(gpa);

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
            try file.write(gpa);
            return;
        }
    }
    try file.layouts.append(gpa, layout);
    ts.current_file = file;
    ts.layout = &file.layouts.items[file.layouts.items.len - 1];
    try file.write(gpa);
}

const ImportLayoutError = error{
    NoLayout,
};

pub fn importLayoutNameVariant(ts: *Backend, layout_name: []const u8, variant: []const u8, gpa: Allocator) !void {
    var file = try LayoutFile.loadFromName(layout_name, gpa);
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

pub fn clearShiftLayer(ts: *Backend, key: []const u8) void {
    if (ts.layout.keys.getPtr(key)) |ptr| {
        ptr.shift_layer = null;
    }
}

pub fn clearNormalLayer(ts: *Backend, key: []const u8) void {
    if (ts.layout.keys.getPtr(key)) |ptr| {
        if (ptr.shift_layer != null) {
            ptr.normal = 0;
        } else {
            _ = ts.layout.keys.remove(key);
        }
    }
}

const PasteCharacterError = error{
    InvalidLength,
    InvalidUnicode,
};

pub fn pasteCharacter(ts: *Backend, key: []const u8, text: []const u8, shift_layer: bool) !u21 {
    if (try std.unicode.utf8ByteSequenceLength(text[0]) != text.len) return PasteCharacterError.InvalidLength; // ensure single utf-8 codepoint
    const gop = try ts.layout.keys.getOrPut(key);
    if (!gop.found_existing) {
        gop.value_ptr.shift_layer = null;
        gop.value_ptr.normal = 0;
    }
    const uc = std.unicode.utf8Decode(text[0..text.len]) catch return PasteCharacterError.InvalidUnicode;
    if (shift_layer) {
        gop.value_ptr.shift_layer = uc;
    } else {
        gop.value_ptr.normal = uc;
    }

    return uc;
}

pub fn resetLayout(ts: *Backend, gpa: Allocator) !void {
    if (ts.current_file) |*f| {
        f.deinit(gpa);
        ts.layout = try gpa.create(Layout);
        ts.current_file = null;
    } else {
        ts.layout.deinit(gpa);
    }
    ts.layout.* = Layout.init(gpa, null);
}

pub fn trySavingLayout(ts: *Backend, gpa: Allocator) !bool {
    const file = &(ts.current_file orelse return false);
    try file.write(gpa);
    return true;
}

pub fn putCharacterOnKey(ts: *Backend, key: []const u8, rune: u21, shift_layer: bool) !void {
    const gop = try ts.layout.keys.getOrPut(key);
    if (!gop.found_existing) {
        gop.value_ptr.shift_layer = null;
        gop.value_ptr.normal = 0;
    }
    if (shift_layer) {
        gop.value_ptr.shift_layer = rune;
    } else {
        gop.value_ptr.normal = rune;
    }
}
