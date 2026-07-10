const Keymap = @This();

const std = @import("std");
const dvui = @import("dvui");
const dkct = @import("dkwtct");

const util = dkct.util;
const v = dkct.vars;

const Layout = dkct.XKBLayout;

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Key = struct {
    width: f32,
    keycode: []const u8,
};

const Element = union(enum) {
    key: Key,
    newline: void,

    pub const ElementParseError = error{
        NoSep,
        InvalidChar,
        InvalidIdentifier,
    };

    pub fn parse(str: []const u8) !Element {
        // validation check
        for (str) |char| {
            switch (char) {
                'a'...'z',
                'A'...'Z',
                '0'...'9',
                ':',
                '.',
                => {},
                else => |c| {
                    try v.setErrorInfo("invalid char: {c}", .{c});
                    return ElementParseError.InvalidChar;
                },
            }
        }

        const sep_i = std.mem.indexOfScalar(u8, str, ':') orelse return ElementParseError.NoSep;
        if (sep_i + 1 >= str.len) {
            return ElementParseError.NoSep;
        }

        const lhs = str[0..sep_i];
        const rhs = str[(sep_i + 1)..];

        const rhs_parsed = std.fmt.parseFloat(f32, rhs) catch return ElementParseError.InvalidChar;

        var buf: [20]u8 = undefined;
        const upper = std.ascii.upperString(&buf, lhs);

        if (std.mem.eql(u8, upper, "BLNK")) {
            return Element{
                .key = Key{
                    .width = rhs_parsed,
                    .keycode = "BLNK",
                },
            };
        }
        if (std.mem.eql(u8, upper, "DSBL")) {
            return Element{
                .key = Key{
                    .width = rhs_parsed,
                    .keycode = "DSBL",
                },
            };
        }

        if (dkct.keycode.getStaticKeycode(upper)) |kc| {
            return Element{
                .key = Key{
                    .width = rhs_parsed,
                    .keycode = kc,
                },
            };
        } else {
            try v.setErrorInfo("{s}", .{lhs});
            return ElementParseError.InvalidIdentifier;
        }
    }
};

data: std.ArrayList(Element) = .empty,

pub fn deinit(ts: *Keymap, gpa: Allocator) void {
    ts.data.deinit(gpa);
}

pub fn parse(gpa: Allocator, str: []const u8) !Keymap {
    var keymap = Keymap{};
    errdefer keymap.deinit(gpa);

    const trimmed = util.trim(str);
    var lines_iter = std.mem.splitScalar(u8, trimmed, '\n');

    while (lines_iter.next()) |line| {
        var line_width: f32 = 0;
        const trimmed_line = util.trim(line);

        var elements_iter = std.mem.splitScalar(u8, trimmed_line, ' ');
        while (elements_iter.next()) |element_str| {
            if (element_str.len == 0) {
                continue;
            }
            const element = try Element.parse(element_str);
            try keymap.data.append(gpa, element);

            switch (element) {
                .key => |x| {
                    line_width += @floatCast(x.width);
                },
                else => {},
            }
        }

        try keymap.data.append(gpa, Element{ .newline = {} });
    }

    return keymap;
}

pub fn format(ts: Keymap, writer: *Io.Writer) Io.Writer.Error!void {
    for (ts.data.items) |item| {
        switch (item) {
            .key => |x| {
                const approx_spaces: usize = @intFromFloat(std.math.round(x.width));
                try writer.print("|", .{});
                for (0..approx_spaces) |i| {
                    if (i < x.keycode.len) {
                        try writer.print("{c}", .{x.keycode[i]});
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

pub fn getNormalizedDims(ts: *const Keymap) dvui.Size {
    var height: f32 = 0;

    var max_width: f32 = 0;
    var width: f32 = 0;
    for (ts.data.items) |element| {
        switch (element) {
            .key => |k| {
                width += k.width;
            },
            .newline => {
                max_width = @max(max_width, width);
                width = 0;
                height += 1;
            },
        }
    }
    return .{ .w = max_width, .h = height };
}
