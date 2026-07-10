const std = @import("std");
const dvui = @import("dvui");

const errDialog = @import("error_dialog.zig").errorDialog;

pub fn dataGetError(win: ?*dvui.Window, id: dvui.Id, name: []const u8, T: type) !?T {
    const ft = @typeInfo(T);

    const data = if (ft == .pointer and (ft.pointer.size == .slice or (ft.pointer.size == .one and @typeInfo(ft.pointer.child) == .array)))
        dvui.dataGetSlice(win, id, name, T)
    else
        dvui.dataGet(win, id, name, T);

    if (data == null) {
        dvui.dialogRemove(id);
        try errDialog(@src(), "Dialog({x}) lost \"{s}\" data", .{ id, name });
    }
    return data;
}
