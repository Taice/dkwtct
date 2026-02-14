const std = @import("std");
const rl = @import("raylib");

const Layout = @import("Layout.zig");

pub const keymap_str = @embedFile("layout.dkwtct");
pub const mplus_data = @embedFile("MPLUSRounded1c-Regular.ttf");
pub const notosans_data = @embedFile("MPLUSRounded1c-Regular.ttf");

pub var char_font: rl.Font = undefined;
pub var text_font: rl.Font = undefined;

pub var selected_layer = Layout.LayerEnum.normal;

pub var selected_button: ?[]const u8 = null;
pub var program_start: std.time.Instant = undefined;

pub var save_directory: *std.ArrayList(u8) = undefined;

pub const fs = 256;
