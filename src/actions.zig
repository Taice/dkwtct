const std = @import("std");
const dvui = @import("dvui");
const dkct = @import("dkwtct");

const config_file = dkct.config_file;
const actions = dkct.actions;
const dialogs = dkct.dialogs;
const util = dkct.util;
const v = dkct.vars;

const Allocator = std.mem.Allocator;
const Io = std.Io;

const AppBackend = dkct.AppBackend;

const RebindStack = dkct.RebindStack;
const Keymap = RebindStack.Keymap;
const XKBLayout = RebindStack.XKBLayout;

const Theme = dkct.enums.Theme;
const Appdata = dkct.Appdata;

pub fn saveAs(io: Io, gpa: Allocator, ctx: *Appdata) !void {
    if (try dvui.dialogNativeFileSave(gpa, .{ .path = config_file.layouts_dir })) |fp| {
        defer gpa.free(fp);

        const owned_path = try gpa.dupe(u8, fp[0..fp.len]);
        try ctx.rebind_stack.dkwtct_layout.saveNewPath(io, gpa, owned_path);
    }
}

pub fn open(io: Io, gpa: Allocator, ctx: *Appdata) !void {
    if (try dvui.dialogNativeFileOpen(gpa, .{ .path = config_file.layouts_dir })) |fp| {
        defer gpa.free(fp);

        const file_contents = util.readFilePathFull(io, gpa, fp[0..fp.len]) catch return;
        defer gpa.free(file_contents);

        const new_dkwtct_layout = dkct.RebindStack.DkwtctLayout.parse(gpa, file_contents) catch |e| {
            try dkct.dialogs.errorDialog(@src(), "{any}\n{s}", .{ e, v.extra_error_info orelse "" });
            return;
        };
        ctx.rebind_stack.dkwtct_layout.deinit(gpa);

        ctx.rebind_stack.dkwtct_layout = new_dkwtct_layout;
    }
}
