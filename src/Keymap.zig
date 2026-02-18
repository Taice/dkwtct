const Keymap = @This();

const std = @import("std");
const root = @import("dkwtct");

const v = @import("vars.zig");

const Layout = @import("Layout.zig");
const rl = @import("raylib");
const rlf = @import("raylib_functions.zig");
const Allocator = std.mem.Allocator;

const Key = struct {
    width: f32,
    label: []const u8,
};

const Element = union(enum) {
    key: Key,
    newline: void,

    pub const ElementParseError = error{
        NoSep,
        InvalidChar,
    };
    pub fn parse(str: []const u8, gpa: std.mem.Allocator) !Element {
        // validation check
        for (str) |char| {
            switch (char) {
                'a'...'z',
                'A'...'Z',
                '0'...'9',
                ':',
                '.',
                => {},
                else => return ElementParseError.InvalidChar,
            }
        }

        const sep_i = std.mem.indexOfScalar(u8, str, ':') orelse return ElementParseError.NoSep;
        if (sep_i + 1 >= str.len) {
            return ElementParseError.NoSep;
        }

        const lhs = str[0..sep_i];
        const rhs = str[(sep_i + 1)..];

        const rhs_parsed = std.fmt.parseFloat(f32, rhs) catch return ElementParseError.InvalidChar;

        return Element{
            .key = Key{
                .width = rhs_parsed,
                .label = try gpa.dupe(u8, lhs),
            },
        };
    }
};

data: std.ArrayList(Element) = .empty,

normalized_dimensions: rl.Vector2 = .{ .x = 0, .y = 0 },

pub fn clone(ts: *Keymap) Keymap {
    return .{
        .layout = ts.layout.clone(),
    };
}

pub fn deinit(ts: *Keymap, gpa: Allocator) void {
    for (ts.data.items) |e| {
        switch (e) {
            .key => |k| {
                gpa.free(k.label);
            },
            else => {},
        }
    }
    ts.data.deinit(gpa);
}

pub fn parse(str: []const u8, gpa: Allocator) !Keymap {
    var keymap = Keymap{};
    errdefer keymap.deinit(gpa);

    const trimmed = root.trim(str);
    var lines_iter = std.mem.splitScalar(u8, trimmed, '\n');

    while (lines_iter.next()) |line| {
        var line_width: f32 = 0;
        const trimmed_line = root.trim(line);

        var elements_iter = std.mem.splitScalar(u8, trimmed_line, ' ');
        while (elements_iter.next()) |element_str| {
            if (element_str.len == 0) {
                continue;
            }
            const element = try Element.parse(element_str, gpa);
            try keymap.data.append(gpa, element);

            switch (element) {
                .key => |x| {
                    line_width += @floatCast(x.width);
                },
                else => {},
            }
        }

        if (line_width > keymap.normalized_dimensions.x) {
            keymap.normalized_dimensions.x = line_width;
        }
        keymap.normalized_dimensions.y += 1;
        try keymap.data.append(gpa, Element{ .newline = {} });
    }

    return keymap;
}

pub fn format(ts: Keymap, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (ts.data.items) |item| {
        switch (item) {
            .key => |x| {
                const approx_spaces: usize = @intFromFloat(std.math.round(x.width));
                try writer.print("|", .{});
                for (0..approx_spaces) |i| {
                    if (i < x.label.len) {
                        try writer.print("{c}", .{x.label[i]});
                    } else {
                        try writer.print(" ", .{});
                    }
                }
            },
            .newline => {
                try writer.print("|\n", .{});
            },
        }
    }
}

pub fn renderToFill(ts: *Keymap, layout: *Layout, dims: rl.Rectangle, focused: bool, gpa: std.mem.Allocator) !void {
    const gap_size = 0;

    const n_gaps_h = 12;
    const n_gaps_v = 4;

    var coords = rl.Vector2.init(dims.x, dims.y);

    const u = rl.Vector2.init(dims.width - n_gaps_h * gap_size, dims.height - n_gaps_v * gap_size).divide(ts.normalized_dimensions);
    if (rl.isWindowResized()) {
        const new_size: i32 = @intFromFloat(u.y);
        if (v.char_font.baseSize != new_size) {
            try rlf.resizeFont(&v.char_font, new_size, gpa);
        }
    }

    for (ts.data.items, 0..) |element, i| {
        switch (element) {
            .key => |key| {
                var button_dims = rl.Rectangle.init(coords.x, coords.y, u.x * key.width, u.y);
                if (!std.mem.eql(u8, key.label, "BLNK")) {
                    if (i + 1 >= ts.data.items.len or ts.data.items[i + 1] == .newline) { // if newline
                        // expand to edge
                        button_dims.width += 50000;
                        button_dims = button_dims.getCollision(dims);
                    }
                    var k: ?*Layout.Key = null;
                    if (layout.keys.getEntry(key.label)) |*entry| {
                        k = entry.value_ptr;
                    }
                    var colors: ?rlf.Colors = null;
                    if (v.selected_button) |btn| {
                        if (std.mem.eql(u8, btn, key.label)) {
                            colors = rlf.Colors.Selected;
                        }
                    }
                    if (rlf.renderKey(k, button_dims, colors, v.selected_layer, focused)) |btn| {
                        if (btn == .left) {
                            v.selected_button = key.label;
                        }
                    }
                }
                coords.x += u.x * key.width + gap_size;
            },
            .newline => {
                coords.y += u.y + gap_size;
                coords.x = dims.x;
            },
        }
    }
}

pub fn renderForcedAspectRatio(ts: *Keymap, layout: *Layout, dims: rl.Rectangle, focused: bool, gpa: std.mem.Allocator) !void {
    const dims_v2 = rl.Vector2.init(dims.width, dims.height);
    const dims_topleft = rl.Vector2.init(dims.x, dims.y);
    const size_vec = dims_v2.divide(ts.normalized_dimensions);
    const min = @min(size_vec.x, size_vec.y);

    const base_coords = dims_v2.subtract(ts.normalized_dimensions.scale(min)).scale(0.5).add(dims_topleft);
    const size = ts.normalized_dimensions.scale(min);

    try ts.renderToFill(layout, .init(base_coords.x, base_coords.y, size.x, size.y), focused, gpa);
}
