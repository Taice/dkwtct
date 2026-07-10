const Appdata = @This();

const std = @import("std");
const dvui = @import("dvui");
const dkct = @import("root.zig");

const config_file = dkct.config_file;
const v = dkct.vars;

const ansi_keymap = v.ansi_str;

const RebindStack = dkct.RebindStack;
const Keymap = RebindStack.Keymap;
const Layout = RebindStack.XKBLayout;
const LayoutFile = RebindStack.LayoutFile;
const AppBackend = RebindStack.AppBackend;
const XKBLayout = RebindStack.XKBLayout;

const Theme = dkct.enums.Theme;
const Savestate = dkct.Savestate;

const dialogs = dkct.dialogs;

const Allocator = std.mem.Allocator;
const Io = std.Io;

gpa: Allocator,

rebind_stack: RebindStack,
tab: RebindStack.Tab,
layer: XKBLayout.LayerEnum,

import_dialog: bool = false,
export_dialog: bool = false,

savestate: Savestate,

pub fn init(io: Io, gpa: Allocator, default_scheme: Theme) !Appdata {
    var savestate = Savestate.load(io, gpa, config_file.savestate_path) catch Savestate{ .theme = default_scheme };
    const keymap = try getKeymap(io, gpa, &savestate.keymap_path);
    var dkwtct_layout = dkct.RebindStack.DkwtctLayout.open(io, gpa, config_file.current_layout_file) catch |e| b: {
        std.log.warn("Dkwtct layout parsing error {any}.\n", .{e});
        break :b dkct.RebindStack.DkwtctLayout.empty;
    };
    dkwtct_layout.file_path = null;

    return .{
        .gpa = gpa,
        .savestate = savestate,
        .rebind_stack = .{
            .dkwtct_layout = dkwtct_layout,
            .keymap = keymap,
        },
        .tab = .layout,
        .layer = .normal,
    };
}

pub fn deinit(ts: *Appdata) void {
    ts.rebind_stack.deinit(ts.gpa);
    ts.savestate.deinit(ts.gpa);
}

pub fn getKeymap(io: Io, gpa: Allocator, keymap_path: *?[]const u8) !Keymap {
    if (keymap_path.*) |ks| b: {
        if (std.mem.eql(u8, ks, "ansi")) {
            gpa.free(ks);
            keymap_path.* = try gpa.dupe(u8, "ansi");
            return .parse(gpa, v.ansi_str);
        }
        if (std.mem.eql(u8, ks, "iso")) {
            gpa.free(ks);
            keymap_path.* = try gpa.dupe(u8, "iso");
            return .parse(gpa, v.iso_str);
        }

        const file_contents = dkct.util.readFilePathFull(io, gpa, ks) catch break :b;
        defer gpa.free(file_contents);
        return Keymap.parse(gpa, file_contents) catch |e| {
            std.log.warn("Keymap path contains invalid keymap {any}\n", .{e});
            gpa.free(ks);
            break :b;
        };
    }
    keymap_path.* = null;
    return try .parse(gpa, v.iso_str);
}
