const std = @import("std");

const keycode_maps = @import("keycode/keycode_maps.zig");

pub const keycodes = keycode_maps.keycodes;
pub const dvui_to_keycode = keycode_maps.dvui_to_keycode;
pub const keycode_aliases = keycode_maps.keycode_aliases;
pub const keycode_to_xkb = keycode_maps.keycode_to_xkb;
pub const xkb_to_keycode = keycode_maps.xkb_to_keycode;
pub const untypeable_keycodes = keycode_maps.untypeable_keycodes;

const static_keycode_aliases = std.StaticStringMap([]const u8).initComptime(.{
    .{ "LMB", "M1" },
    .{ "MOUSE1", "M1" },
    .{ "LEFTMOUSE", "M1" },
    .{ "RMB", "M2" },
    .{ "MOUSE2", "M2" },
    .{ "RIGHTMOUSE", "M2" },
    .{ "MMB", "M3" },
    .{ "MIDDLEMOUSE", "M3" },
    .{ "MB4", "M4" },
    .{ "MOUSE4", "M4" },
    .{ "MB5", "M5" },
    .{ "MOUSE5", "M5" },
});

pub fn getStaticKeycode(str: []const u8) ?[]const u8 {
    if (static_keycode_aliases.get(str)) |s| return s;
    for (keycodes) |kc| {
        if (std.mem.eql(u8, str, kc)) {
            return kc;
        }
    }
    return null;
}
