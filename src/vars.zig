const std = @import("std");
const rl = @import("raylib");

pub const keymap_str = @embedFile("layout.dkwtct");
pub const font_data = @embedFile("MPLUSRounded1c-Regular.ttf");

pub var selected_button: ?[]const u8 = null;
pub var selected_shift_layer: bool = false;
pub var font: rl.Font = undefined;

pub const fs = 256;

pub var paused: bool = false;
pub var current_file: ?@import("LayoutFile.zig") = null;
pub var current_file_idx: usize = 0;

pub var program_start: std.time.Instant = undefined;
