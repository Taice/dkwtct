const dvui = @import("dvui");
const std = @import("std");
const dkct = @import("dkwtct");

const Appdata = dkct.Appdata;
const helpers = @import("helpers.zig");

const util = dkct.util;

const Allocator = std.mem.Allocator;

pub var layout_file: ?dkct.RebindStack.LayoutFile = null;
pub var rebinds_file: ?dkct.RebindStack.RebindsFile = null;

var lf_changed = false;
var rf_changed = false;

pub fn importDialog(io: std.Io, gpa: std.mem.Allocator, ctx: *Appdata, menu_bool: *bool) !void {
    const savestate = &ctx.savestate;
    const import_data = &savestate.import_data;

    const fw = dvui.floatingWindow(@src(), .{ .resize = .none }, .{});
    defer fw.deinit();

    fw.autoSize();

    if (dvui.firstFrame(fw.data().id)) {
        bl: {
            util.optionDeinit(gpa, &layout_file);
            if (import_data.xkb.file_path) |fp| b: {
                const file_content = dkct.util.readFilePathFull(io, gpa, fp) catch break :b;
                defer gpa.free(file_content);

                const lf = dkct.RebindStack.LayoutFile.loadFromString(gpa, file_content, ctx.savestate.bleed_chars) catch break :b;
                layout_file = lf;
                break :bl;
            } else {
                break :bl;
            }
            import_data.xkb.file_path = null;
        }

        bl: {
            util.optionDeinit(gpa, &rebinds_file);
            if (import_data.rebinds.file_path) |fp| b: {
                const file_content = dkct.util.readFilePathFull(io, gpa, fp) catch break :b;
                defer gpa.free(file_content);

                const rf = dkct.RebindStack.RebindsFile.readFromString(gpa, file_content) catch break :b;
                rebinds_file = rf;
                break :bl;
            } else {
                break :bl;
            }
            import_data.rebinds.file_path = null;
        }
    }
    var header_openflag = true;
    fw.dragAreaSet(dvui.windowHeader("Import", "", &header_openflag));
    if (!header_openflag) {
        util.optionDeinit(gpa, &layout_file);
        util.optionDeinit(gpa, &rebinds_file);
        menu_bool.* = false;
        return;
    }

    {
        // Add the buttons at the bottom first, so that they are guaranteed to be shown
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = 1.0, .gravity_y = 1.0, .margin = .all(4) });
        defer hbox.deinit();

        if (dvui.button(@src(), "Import", .{}, .{})) b: {
            if (import_data.xkb_checkmark) {
                if (!try validateImportXKB(import_data)) {
                    break :b;
                }
            }
            if (import_data.rebinds_checkmark) {
                if (!try validateImportRebinds(import_data)) {
                    break :b;
                }
            }
            try import(gpa, ctx);

            util.optionDeinit(gpa, &layout_file);
            menu_bool.* = false;
            return;
        }
    }

    {
        const xkb_stuff = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer xkb_stuff.deinit();

        _ = dvui.checkbox(@src(), &import_data.xkb_checkmark, "import xkb layout", .{});
        const disabler = util.disablerBox(@src(), .{ .dir = .horizontal }, .{}, !import_data.xkb_checkmark);
        defer disabler.deinit();
        if (dvui.button(
            @src(),
            util.cropPathNullable(import_data.xkb.file_path) orelse "open file",
            .{ .grayed = !import_data.xkb_checkmark },
            .{},
        )) {
            if (try dvui.dialogNativeFileOpen(gpa, .{
                .path = dkct.config_file.xkb_dir,
            })) |file_path| b: {
                defer gpa.free(file_path);

                const file_contents = dkct.util.readFilePathFull(io, gpa, file_path) catch |e| {
                    try dkct.dialogs.errorDialog(@src(), "Erorr reading xkb file: {any}", .{e});
                    break :b;
                };
                defer gpa.free(file_contents);

                const new_layout_file = dkct.RebindStack.LayoutFile.loadFromString(gpa, file_contents, savestate.bleed_chars) catch |e| {
                    try dkct.dialogs.errorDialog(@src(), "Erorr parsing xkb file: {any}", .{e});
                    break :b;
                };

                const owned_path = try gpa.dupe(u8, file_path[0..file_path.len]);

                util.optionDeinit(gpa, &layout_file);
                lf_changed = true;
                layout_file = new_layout_file;

                dkct.util.optionFree(gpa, import_data.xkb.file_path);
                import_data.xkb.file_path = owned_path;

                dkct.util.optionFree(gpa, import_data.xkb.variant);
                import_data.xkb.variant = null;
            }
        }

        if (layout_file) |lf| {
            dvui.labelNoFmt(@src(), "layout name:", .{}, .{});
            var te: dvui.TextEntryWidget = undefined;
            te.init(@src(), .{ .text = .{ .internal = .{ .limit = 20 } } }, .{});
            defer te.deinit();

            if (dvui.firstFrame(te.data().id)) {
                te.textSet(import_data.xkb.variant orelse "", false);
            }
            if (lf_changed) {
                te.textSet("", true);
                dvui.focusWidget(te.data().id, null, null);
            }

            util.suggestionBox(&te, lf.names.items);

            te.draw();

            dkct.util.optionFree(gpa, import_data.xkb.variant);
            const txt = te.textGet();
            if (txt.len == 0) {
                import_data.xkb.variant = null;
            } else {
                import_data.xkb.variant = try gpa.dupe(u8, txt);
            }
            lf_changed = false;
        }
    }
    {
        const rebind_stuff = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer rebind_stuff.deinit();

        _ = dvui.checkbox(@src(), &import_data.rebinds_checkmark, "import rebinds", .{});
        const disabler = util.disablerBox(@src(), .{ .dir = .horizontal }, .{}, !import_data.rebinds_checkmark);
        defer disabler.deinit();
        if (dvui.button(
            @src(),
            util.cropPathNullable(import_data.rebinds.file_path) orelse "open file",
            .{ .grayed = !import_data.rebinds_checkmark },
            .{},
        )) {
            if (try dvui.dialogNativeFileOpen(gpa, .{
                .path = dkct.config_file.waywall_dir,
            })) |file_path| b: {
                defer gpa.free(file_path);

                const file_contents = dkct.util.readFilePathFull(io, gpa, file_path) catch |e| {
                    try dkct.dialogs.errorDialog(@src(), "Erorr reading rebinds file: {any}", .{e});
                    break :b;
                };
                defer gpa.free(file_contents);

                const new_rebinds = dkct.RebindStack.RebindsFile.readFromString(gpa, file_contents) catch |e| {
                    try dkct.dialogs.errorDialog(@src(), "Erorr reading rebinds file: {any}", .{e});
                    break :b;
                };
                const owned_path = try gpa.dupe(u8, file_path[0..file_path.len]);

                util.optionDeinit(gpa, &rebinds_file);
                rebinds_file = new_rebinds;

                util.optionFree(gpa, import_data.rebinds.file_path);
                import_data.rebinds.file_path = owned_path;
            }
        }

        if (rebinds_file) |rf| {
            dvui.labelNoFmt(@src(), "table name:", .{}, .{});
            var te: dvui.TextEntryWidget = undefined;
            te.init(@src(), .{ .text = .{ .internal = .{ .limit = 20 } } }, .{});
            defer te.deinit();

            if (dvui.firstFrame(te.data().id)) {
                te.textSet(import_data.rebinds.table orelse "", false);
            }
            if (rf_changed) {
                te.textSet("", true);
                dvui.focusWidget(te.data().id, null, null);
            }

            util.suggestionBox(&te, rf.names.items);

            te.draw();

            dkct.util.optionFree(gpa, import_data.rebinds.table);
            const txt = te.textGet();
            if (txt.len == 0) {
                import_data.rebinds.table = null;
            } else {
                import_data.rebinds.table = try gpa.dupe(u8, txt);
            }
            rf_changed = false;
        }
    }
}

pub fn import(gpa: Allocator, ctx: *Appdata) !void {
    if (ctx.savestate.import_data.xkb_checkmark) {
        const lf = layout_file orelse unreachable;
        const variant = ctx.savestate.import_data.xkb.variant orelse unreachable;
        _ = ctx.savestate.import_data.xkb.file_path orelse unreachable;

        if (util.findSlice(u8, lf.names.items, variant)) |i| {
            ctx.rebind_stack.dkwtct_layout.layout.deinit(gpa);
            ctx.rebind_stack.dkwtct_layout.layout = try lf.layouts.items[i].clone(gpa);
        } else {
            try dkct.dialogs.errorDialog(@src(), "XKB: No layout named: {s} found in layout file.", .{variant});
        }
    }
    if (ctx.savestate.import_data.rebinds_checkmark) {
        const rf = rebinds_file orelse unreachable;
        const table = ctx.savestate.import_data.rebinds.table orelse unreachable;
        _ = ctx.savestate.import_data.xkb.file_path orelse unreachable;

        if (util.findSlice(u8, rf.names.items, table)) |i| {
            ctx.rebind_stack.dkwtct_layout.rebinds.deinit(gpa);
            ctx.rebind_stack.dkwtct_layout.rebinds = try rf.rebinds.items[i].clone(gpa);
        } else {
            try dkct.dialogs.errorDialog(@src(), "Rebinds: No table named: {s} found in lua file.", .{table});
        }
    }
}

pub fn validateImportXKB(import_data: *dkct.Savestate.ImportData) !bool {
    if (import_data.xkb.file_path == null or layout_file == null) {
        try dkct.dialogs.errorDialog(@src(), "XKB: Can't load xkb layout without a file.", .{});
    } else if (import_data.xkb.variant == null) {
        try dkct.dialogs.errorDialog(@src(), "XKB: Can't load xkb layout without a variant.", .{});
    } else if (util.findSlice(u8, layout_file.?.names.items, import_data.xkb.variant.?) == null) {
        try dkct.dialogs.errorDialog(@src(), "XKB: File doesn't contain that variant.", .{});
    } else {
        return true;
    }
    return false;
}

pub fn validateImportRebinds(import_data: *dkct.Savestate.ImportData) !bool {
    if (import_data.rebinds.file_path == null or rebinds_file == null) {
        try dkct.dialogs.errorDialog(@src(), "Rebinds: Can't load rebinds without a file.", .{});
    } else if (import_data.rebinds.table == null) {
        try dkct.dialogs.errorDialog(@src(), "Rebinds: Can't load rebinds without a table.", .{});
    } else if (util.findSlice(u8, rebinds_file.?.names.items, import_data.rebinds.table.?) == null) {
        try dkct.dialogs.errorDialog(@src(), "Rebinds: No such table found.", .{});
    } else {
        return true;
    }
    return false;
}
