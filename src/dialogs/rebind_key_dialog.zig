const dvui = @import("dvui");
const std = @import("std");
const dkct = @import("dkwtct");

const helpers = @import("helpers.zig");

const Appdata = dkct.Appdata;

pub const RebindDialogCtx = struct {
    appdata: *Appdata,
    selected_button: []const u8,
};

pub fn rebindKeyDialog(ctx: RebindDialogCtx) void {
    dvui.dialog(@src(), .{ .ctx = ctx }, .{
        .title = "Select a Keycode",
        .message = "",
        .displayFn = keyListDisplayFn,
        .callafterFn = keyListCallafter,
    });
}

pub fn keyListDisplayFn(id: dvui.Id) anyerror!void {
    _ = try helpers.dataGetError(null, id, "ctx", RebindDialogCtx) orelse return;
    const modal = try helpers.dataGetError(null, id, "_modal", bool) orelse return;

    const title = try helpers.dataGetError(null, id, "_title", []u8) orelse return;

    const ok_label = try helpers.dataGetError(null, id, "_ok_label", []u8) orelse return;

    const center_on = dvui.dataGet(null, id, "center_on", dvui.Rect.Natural) orelse dvui.currentWindow().subwindows.current_rect;

    const cancel_label = dvui.dataGetSlice(null, id, "_cancel_label", []u8);

    const callafter = dvui.dataGet(null, id, "_callafter", dvui.DialogCallAfterFn);

    const maxSize = dvui.dataGet(null, id, "_max_size", dvui.Options.MaxSize);

    var win = dvui.floatingWindow(@src(), .{ .modal = modal, .center_on = center_on, .window_avoid = .nudge }, .{ .role = .dialog, .id_extra = id.asUsize(), .max_size_content = maxSize });
    defer win.deinit();

    var header_openflag = true;
    win.dragAreaSet(dvui.windowHeader(title, "", &header_openflag));
    if (!header_openflag) {
        dvui.dialogRemove(id);
        if (callafter) |ca| {
            ca(id, .cancel) catch |err| {
                std.log.debug("Dialog callafter for {x} returned {any}", .{ id, err });
            };
        }
        return;
    }

    {
        // Add the buttons at the bottom first, so that they are guaranteed to be shown
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = 1.0, .gravity_y = 1.0, .margin = .all(4) });
        defer hbox.deinit();

        if (cancel_label) |cl| {
            var cancel_data: dvui.WidgetData = undefined;
            const gravx: f32, const tindex: u16 = switch (dvui.currentWindow().button_order) {
                .cancel_ok => .{ 0.0, 1 },
                .ok_cancel => .{ 1.0, 3 },
            };
            if (dvui.button(@src(), cl, .{}, .{ .tab_index = tindex, .data_out = &cancel_data, .gravity_x = gravx })) {
                dvui.dialogRemove(id);
                if (callafter) |ca| {
                    ca(id, .cancel) catch |err| {
                        std.log.debug("Dialog callafter for {x} returned {any}", .{ id, err });
                    };
                }
                return;
            }
        }

        var ok_data: dvui.WidgetData = undefined;
        if (dvui.button(@src(), ok_label, .{}, .{ .tab_index = 2, .data_out = &ok_data })) {
            dvui.dialogRemove(id);
            if (callafter) |ca| {
                ca(id, .ok) catch |err| {
                    std.log.debug("Dialog callafter for {x} returned {any}", .{ id, err });
                };
            }
            return;
        }
    }

    var te: dvui.TextEntryWidget = undefined;
    te.init(@src(), .{ .text = .{ .internal = .{ .limit = 20 } } }, .{});
    defer te.deinit();

    if (dvui.firstFrame(te.widget().data().id)) {
        dvui.focusWidget(te.widget().data().id, null, null);
    }

    {
        var sug = dvui.suggestion(&te, .{ .open_on_text_change = true });
        defer sug.deinit();

        if (te.text_changed) blk: {
            const arena = dvui.currentWindow().lifo();
            var filtered = std.ArrayList([]const u8).initCapacity(arena, dkct.keycode.keycodes.len) catch {
                dvui.dataRemove(null, te.data().id, "suggestions");
                break :blk;
            };
            defer filtered.deinit(arena);
            const filter_text = te.textGet();

            var buf: [20]u8 = undefined;
            const upper = std.ascii.upperString(&buf, filter_text);

            for (dkct.keycode.keycodes) |entry| {
                if (std.mem.startsWith(u8, entry, upper)) {
                    filtered.appendAssumeCapacity(entry);
                }
            }
            dvui.dataSetSlice(null, te.data().id, "suggestions", filtered.items);
        }
        const filtered = dvui.dataGetSlice(null, te.data().id, "suggestions", [][]const u8) orelse &dkct.keycode.keycodes;
        if (sug.dropped()) {
            for (filtered) |entry| {
                if (sug.addChoiceLabel(entry)) {
                    te.textSet(entry, true);
                }
            }
        }
    }
    dvui.dataSetSlice(null, id, "entry", te.textGet());

    te.draw();
}

pub fn keyListCallafter(id: dvui.Id, response: dvui.enums.DialogResponse) anyerror!void {
    if (response == .ok) {
        const ctx = dvui.dataGet(null, id, "ctx", RebindDialogCtx) orelse {
            std.log.err("dialogDisplay lost data for dialog ctx {x}\n", .{id});
            dvui.dialogRemove(id);
            return;
        };
        const entry = dvui.dataGetSlice(null, id, "entry", []const u8) orelse {
            std.log.err("dialogDisplay lost data for dialog entry {x}\n", .{id});
            dvui.dialogRemove(id);
            return;
        };
        var upper_buf: [20]u8 = undefined;
        const upper = std.ascii.upperString(&upper_buf, entry);

        if (dkct.keycode.getStaticKeycode(ctx.selected_button)) |keycode| {
            if (dkct.keycode.getStaticKeycode(upper)) |rebind| {
                if (std.mem.eql(u8, keycode, rebind)) {
                    _ = ctx.appdata.rebind_stack.dkwtct_layout.rebinds.map.remove(keycode);
                } else {
                    try ctx.appdata.rebind_stack.dkwtct_layout.addRebind(ctx.appdata.gpa, keycode, rebind, ctx.appdata.savestate.swap_rebinds);
                }
            }
        }
    }
}
