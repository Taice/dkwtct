const std = @import("std");
const dvui = @import("dvui");
const dkct = @import("dkwtct");

const v = dkct.vars;

var err_buf: [1024]u8 = .{0} ** 1024;

pub fn errorDialog(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) !void {
    dvui.dialog(src, .{}, .{ .message = try std.fmt.bufPrint(&err_buf, fmt, args), .callafterFn = errDialogCallafter });
}

pub fn errDialogCallafter(_: dvui.Id, _: dvui.enums.DialogResponse) anyerror!void {}
