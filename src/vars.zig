const std = @import("std");

const RaylibBackend = @import("rl");
const rl = RaylibBackend.raylib;

pub const keymap_str = @embedFile("layout.dkwtct");
pub const font_data = @embedFile("MPLUSRounded1c-Regular.ttf");

pub var font: rl.Font = undefined;
pub var selected_button: ?[]const u8 = null;
pub var selected_shift_layer: bool = false;
pub var program_start: std.time.Instant = undefined;

pub const fs = 256;
