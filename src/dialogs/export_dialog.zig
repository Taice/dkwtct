const dvui = @import("dvui");
const std = @import("std");
const dkct = @import("dkwtct");

const Appdata = dkct.Appdata;
const helpers = @import("helpers.zig");

const util = dkct.util;

const Allocator = std.mem.Allocator;

pub var layout_file: ?dkct.RebindStack.LayoutFile = null;

var lf_changed = false;

pub fn exportDialog(io: std.Io, gpa: std.mem.Allocator, ctx: *Appdata, menu_bool: *bool) !void {
    const savestate = &ctx.savestate;
    const export_data = &savestate.export_data;

    const fw = dvui.floatingWindow(@src(), .{ .resize = .none }, .{});
    defer fw.deinit();

    fw.autoSize();

    if (dvui.firstFrame(fw.data().id)) {
        bl: {
            util.optionDeinit(gpa, &layout_file);
            if (export_data.xkb.file_path) |fp| b: {
                const file_content = dkct.util.readFilePathFull(io, gpa, fp) catch break :b;
                defer gpa.free(file_content);

                const lf = dkct.RebindStack.LayoutFile.loadFromString(gpa, file_content, savestate.bleed_chars) catch break :b;
                layout_file = lf;
                break :bl;
            } else {
                break :bl;
            }
            export_data.xkb.file_path = null;
        }
    }
    var header_openflag = true;
    fw.dragAreaSet(dvui.windowHeader("Import", "", &header_openflag));
    if (!header_openflag) {
        util.optionDeinit(gpa, &layout_file);
        menu_bool.* = false;
        return;
    }

    {
        // Add the buttons at the bottom first, so that they are guaranteed to be shown
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = 1.0, .gravity_y = 1.0, .margin = .all(4) });
        defer hbox.deinit();

        if (dvui.button(@src(), "Export", .{}, .{})) b: {
            if (export_data.xkb_checkmark) {
                if (!try validateExportXKB(export_data)) {
                    break :b;
                }
            }
            if (export_data.rebinds_checkmark) {
                if (!try validateExportRebinds(export_data)) {
                    break :b;
                }
            }
            try exportCallAfter(io, gpa, ctx);

            util.optionDeinit(gpa, &layout_file);
            menu_bool.* = false;
            return;
        }
    }

    {
        const xkb_stuff = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer xkb_stuff.deinit();

        _ = dvui.checkbox(@src(), &export_data.xkb_checkmark, "export xkb layout", .{});
        const disabler = util.disablerBox(@src(), .{ .dir = .horizontal }, .{}, !export_data.xkb_checkmark);
        defer disabler.deinit();
        if (dvui.button(
            @src(),
            util.cropPathNullable(export_data.xkb.file_path) orelse "save to file",
            .{ .grayed = !export_data.xkb_checkmark },
            .{},
        )) {
            if (try dvui.dialogNativeFileSave(gpa, .{
                .path = dkct.config_file.xkb_dir,
            })) |file_path| {
                defer gpa.free(file_path);

                util.optionDeinit(gpa, &layout_file);

                const file_contents = dkct.util.readFilePathFull(io, gpa, file_path) catch null;
                if (file_contents) |fc| bl: {
                    defer gpa.free(fc);

                    const new_layout_file = dkct.RebindStack.LayoutFile.loadFromString(gpa, fc, savestate.bleed_chars) catch |e| {
                        try dkct.dialogs.errorDialog(@src(), "Erorr parsing xkb file: {any}", .{e});
                        break :bl;
                    };

                    layout_file = new_layout_file;
                }
                lf_changed = true;
                const owned_path = try gpa.dupe(u8, file_path[0..file_path.len]);

                dkct.util.optionFree(gpa, export_data.xkb.file_path);
                export_data.xkb.file_path = owned_path;

                dkct.util.optionFree(gpa, export_data.xkb.variant);
                export_data.xkb.variant = null;
            }
        }

        if (layout_file) |lf| {
            dvui.labelNoFmt(@src(), "layout name:", .{}, .{});
            var te: dvui.TextEntryWidget = undefined;
            te.init(@src(), .{ .text = .{ .internal = .{ .limit = 20 } } }, .{});
            defer te.deinit();

            if (dvui.firstFrame(te.data().id)) {
                te.textSet(export_data.xkb.variant orelse "", false);
            }
            if (lf_changed) {
                te.textSet("", true);
                dvui.focusWidget(te.data().id, null, null);
            }

            util.suggestionBox(&te, lf.names.items);

            te.draw();

            dkct.util.optionFree(gpa, export_data.xkb.variant);
            const txt = te.textGet();
            if (txt.len == 0) {
                export_data.xkb.variant = null;
            } else {
                export_data.xkb.variant = try gpa.dupe(u8, txt);
            }
        } else {
            if (export_data.xkb.file_path) |_| {
                dvui.labelNoFmt(@src(), "layout name:", .{}, .{});
                const te = dvui.textEntry(@src(), .{}, .{});

                if (dvui.firstFrame(te.data().id)) {
                    te.textSet(export_data.xkb.variant orelse "", false);
                }
                if (lf_changed) {
                    te.textSet("", true);
                    dvui.focusWidget(te.data().id, null, null);
                }

                dkct.util.optionFree(gpa, export_data.xkb.variant);
                const txt = te.textGet();
                if (txt.len == 0) {
                    export_data.xkb.variant = null;
                } else {
                    export_data.xkb.variant = try gpa.dupe(u8, txt);
                }

                te.deinit();
            }
        }
        lf_changed = false;
    }
    {
        const rebind_stuff = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer rebind_stuff.deinit();

        _ = dvui.checkbox(@src(), &export_data.rebinds_checkmark, "export rebinds", .{});
        const disabler = util.disablerBox(@src(), .{ .dir = .horizontal }, .{}, !export_data.rebinds_checkmark);
        defer disabler.deinit();
        if (dvui.button(
            @src(),
            util.cropPathNullable(export_data.rebinds.file_path) orelse "open file",
            .{ .grayed = !export_data.rebinds_checkmark },
            .{},
        )) {
            if (try dvui.dialogNativeFileSave(gpa, .{
                .path = dkct.config_file.waywall_dir,
            })) |file_path| {
                defer gpa.free(file_path);

                const owned_path = try gpa.dupe(u8, file_path[0..file_path.len]);

                util.optionFree(gpa, export_data.rebinds.file_path);
                export_data.rebinds.file_path = owned_path;
            }
        }
    }
}

pub fn exportCallAfter(io: std.Io, gpa: Allocator, ctx: *Appdata) !void {
    const export_data = &ctx.savestate.export_data;
    if (export_data.xkb_checkmark) {
        const file_path = export_data.xkb.file_path.?;
        const variant = export_data.xkb.variant.?;

        if (layout_file) |*lf| {
            if (util.findSlice(u8, lf.names.items, variant)) |i| {
                lf.layouts.items[i].deinit(gpa);
                lf.layouts.items[i] = try ctx.rebind_stack.dkwtct_layout.layout.clone(gpa);
            } else {
                try lf.names.append(gpa, try gpa.dupe(u8, variant));
                try lf.layouts.append(gpa, try ctx.rebind_stack.dkwtct_layout.layout.clone(gpa));
            }

            try lf.writeToFilePath(io, gpa, file_path, ctx.savestate.bleed_chars);
        } else {
            layout_file = dkct.RebindStack.LayoutFile.empty;
            try layout_file.?.layouts.append(gpa, try ctx.rebind_stack.dkwtct_layout.layout.clone(gpa));
            try layout_file.?.names.append(gpa, try gpa.dupe(u8, variant));

            try layout_file.?.writeToFilePath(io, gpa, file_path, ctx.savestate.bleed_chars);
        }
    }

    if (export_data.rebinds_checkmark) {
        const file_path = export_data.rebinds.file_path orelse unreachable;
        const file_contents = try ctx.rebind_stack.dkwtct_layout.rebinds.getLuaFile(gpa);
        defer gpa.free(file_contents);

        try util.writeFilePathFull(io, file_path, file_contents);
    }
}

pub fn validateExportXKB(export_data: *dkct.Savestate.ExportData) !bool {
    if (export_data.xkb.file_path == null) {
        try dkct.dialogs.errorDialog(@src(), "Please select a layout file.", .{});
    } else if (export_data.xkb.variant == null) {
        try dkct.dialogs.errorDialog(@src(), "Please type in a variant", .{});
    } else {
        return true;
    }
    return false;
}

pub fn validateExportRebinds(export_data: *dkct.Savestate.ExportData) !bool {
    if (export_data.rebinds.file_path == null) {
        try dkct.dialogs.errorDialog(@src(), "Please select a rebinds file.", .{});
    } else {
        return true;
    }
    return false;
}
