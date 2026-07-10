const std = @import("std");
const dkct = @import("dkwtct");

const Layout = dkct.Layout;

pub var extra_error_info: ?[]const u8 = null;
pub var error_info_gpa: std.mem.Allocator = undefined;

pub const ansi_str = @embedFile("assets/ansi.dkwtct");
pub const iso_str = @embedFile("assets/iso.dkwtct");

pub const char_font_data = @embedFile("assets/GoNotoKurrent-Regular.ttf");

pub fn setErrorInfo(comptime fmt: []const u8, args: anytype) !void {
    if (extra_error_info) |ei| {
        error_info_gpa.free(ei);
    }

    extra_error_info = try std.fmt.allocPrint(error_info_gpa, fmt, args);
}
