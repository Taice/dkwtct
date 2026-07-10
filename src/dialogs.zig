const std = @import("std");
const dkct = @import("dkwtct");

const util = dkct.util;

pub const import_dialog = @import("dialogs/import_dialog.zig");
pub const export_dialog = @import("dialogs/export_dialog.zig");

pub const rebindKeyDialog = @import("dialogs/rebind_key_dialog.zig").rebindKeyDialog;
pub const errorDialog = @import("dialogs/error_dialog.zig").errorDialog;
pub const importDialog = import_dialog.importDialog;
pub const exportDialog = export_dialog.exportDialog;

const Allocator = std.mem.Allocator;

pub fn initDialogData(gpa: Allocator) !void {
    _ = gpa;
}

pub fn deinitDialogData(gpa: Allocator) void {
    util.optionDeinit(gpa, &import_dialog.layout_file);
    util.optionDeinit(gpa, &import_dialog.rebinds_file);
    util.optionDeinit(gpa, &export_dialog.layout_file);
}
