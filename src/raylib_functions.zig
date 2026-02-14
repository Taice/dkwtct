const rl = @import("raylib");
const std = @import("std");

const root = @import("dkwtct");
const v = @import("vars.zig");
const uc = @import("unicode.zig");

const Layout = @import("Layout.zig");
const Backend = @import("Backend.zig");
const Allocator = std.mem.Allocator;

pub fn innerRec(rec: rl.Rectangle, thick: f32) rl.Rectangle {
    return .init(rec.x + thick, rec.y + thick, rec.width - 2 * thick, rec.height - 2 * thick);
}

pub const Colors = struct {
    border_color: rl.Color,
    background_color: rl.Color,
    text_color: rl.Color,
    shift_layer_color: rl.Color,
    pub const Normal = Colors{
        .border_color = fromInt(0x000000FF),
        .background_color = fromInt(0xCCCCCCFF),
        .text_color = fromInt(0x000000FF),
        .shift_layer_color = fromInt(0x777777FF),
    };
    pub const Hovered = Colors{
        .border_color = fromInt(0x0000000FF),
        .background_color = fromInt(0xBBBBBBFF),
        .text_color = fromInt(0x000000FF),
        .shift_layer_color = fromInt(0x777777FF),
    };
    pub const Pressed = Colors{
        .border_color = fromInt(0x8888AAFF),
        .background_color = fromInt(0xAAAAFFFF),
        .text_color = fromInt(0x000000FF),
        .shift_layer_color = fromInt(0x777777FF),
    };
    pub const Selected = Colors{
        .border_color = fromInt(0x000000FF),
        .background_color = fromInt(0xAAAAAAFF),
        .text_color = fromInt(0x000000FF),
        .shift_layer_color = fromInt(0x777777FF),
    };
};

pub fn fromInt(int: u32) rl.Color {
    const r: u8 = @intCast((int & 0xFF000000) >> 24);
    const g: u8 = @intCast((int & 0x00FF0000) >> 16);
    const b: u8 = @intCast((int & 0x0000FF00) >> 8);
    const a: u8 = @intCast(int & 0x000000FF);

    return rl.Color{ .r = r, .g = g, .b = b, .a = a };
}

pub fn renderButton(key: ?*Layout.Key, dims: rl.Rectangle, optional_colors: ?Colors, layer: Layout.LayerEnum, focused: bool) ?rl.MouseButton {
    const is_hovering = rl.checkCollisionPointRec(rl.getMousePosition(), dims) and focused;
    const is_held = rl.isMouseButtonDown(.left) or rl.isMouseButtonDown(.right);

    const inner = innerRec(dims, 2);

    var colors = optional_colors orelse Colors.Normal;

    if (is_hovering) {
        if (is_held) {
            colors = Colors.Pressed;
        } else if (optional_colors == null) {
            colors = Colors.Hovered;
        }
    }

    rl.drawRectangleLinesEx(dims, 2, colors.border_color);
    rl.drawRectangleRec(inner, colors.background_color);
    if (key) |k| {
        var c = switch (layer) {
            .normal => k.normal,
            .shift => k.shift orelse k.normal,
            .alt => k.alt,
            .alt_shift => k.alt_shift orelse k.alt,
        };
        if (c != 0) {
            if (c == ' ') {
                c = '_';
            }
            if ((layer == .shift and k.shift == null) or (layer == .alt_shift and k.alt_shift == null)) {
                drawCodepointCentered(c, inner, fromInt(0x00000077));
            } else {
                drawCodepointCentered(c, inner, colors.text_color);
            }
        }
    }

    if (is_hovering) {
        for (std.enums.values(rl.MouseButton)) |mbutton| {
            if (rl.isMouseButtonPressed(mbutton)) return mbutton;
        }
    }
    return null;
}

pub fn fontHasCodepoint(f: *rl.Font, codepoint: u21) bool {
    return findCpInGlyphs(f.glyphs[0..@intCast(f.glyphCount)], codepoint);
}

pub fn addCodepointToFont(
    f: *rl.Font,
    new_cp: u21,
    gpa: Allocator,
) !void {
    const old_count: usize = @intCast(f.glyphCount);

    var cps = gpa.alloc(i32, old_count + 1) catch unreachable;
    defer gpa.free(cps);

    // copy existing codepoints
    for (cps[0..old_count], 0..) |*cp, i| {
        cp.* = f.glyphs[i].value;
    }

    cps[old_count] = new_cp;

    rl.unloadFont(f.*);
    f.* = try rl.loadFontFromMemory(
        ".ttf",
        v.font_data,
        v.fs,
        cps,
    );
}

pub fn drawCodepointCentered(cp: u21, dims: rl.Rectangle, color: rl.Color) void {
    // backspace specialization
    if (cp == 1) {
        const topleft = rl.Vector2.init(dims.x, dims.y);
        const size = rl.Vector2.init(dims.width, dims.height);
        const text_dims = rl.Vector2.init(rl.measureTextEx(v.font, "BS", @round(dims.height), 0).x, size.y);
        const offset_non_rounded = size.subtract(text_dims).scale(0.5);
        const offset = rl.Vector2.init(@round(offset_non_rounded.x), @round(offset_non_rounded.y));
        rl.drawTextEx(v.font, "BS", topleft.add(offset), @round(dims.height), 0, color);
        return;
    }
    // home specialization
    if (cp == 2) {
        const topleft = rl.Vector2.init(dims.x, dims.y);
        const size = rl.Vector2.init(dims.width, dims.height);
        const text_dims = rl.Vector2.init(rl.measureTextEx(v.font, "Home", @round(dims.height), 0).x, size.y);
        if (text_dims.x > dims.width) {
            const scale = dims.width / text_dims.x;

            const offset_non_rounded = size.subtract(text_dims.scale(scale)).scale(0.5);
            const offset = rl.Vector2.init(@round(offset_non_rounded.x), @round(offset_non_rounded.y));
            rl.drawTextEx(v.font, "Home", topleft.add(offset), @round(dims.height * scale), 0, color);
        } else {
            const offset_non_rounded = size.subtract(text_dims).scale(0.5);
            const offset = rl.Vector2.init(@round(offset_non_rounded.x), @round(offset_non_rounded.y));
            std.debug.print("a", .{});
            rl.drawTextEx(v.font, "Home", topleft.add(offset), @round(dims.height), 0, color);
        }
        return;
    }
    const rec = v.font.recs[@intCast(rl.getGlyphIndex(v.font, @intCast(cp)))];
    const scale = dims.height / @as(f32, @floatFromInt(v.font.baseSize));

    const x_size = scale * rec.width;

    const x = (dims.width - x_size) / 2 + dims.x;

    rl.drawTextCodepoint(v.font, cp, .init(@round(x), @round(dims.y)), dims.height, color);
}

pub fn addCodepointsToFont(f: *rl.Font, cps: []i32, gpa: Allocator) !void {
    const glyph_count: usize = @intCast(f.glyphCount);
    const count = glyph_count + cps.len;

    var codepoints = try gpa.alloc(i32, count);
    defer gpa.free(codepoints);

    for (f.glyphs[0..glyph_count], 0..) |g, i| {
        codepoints[i] = g.value;
    }
    for (cps, 0..) |cp, i| {
        codepoints[i + glyph_count] = cp;
    }

    rl.unloadFont(f.*);
    f.* = try rl.loadFontFromMemory(".ttf", v.font_data, v.fs, codepoints);
}

pub fn findCpInGlyphs(glyphs: []rl.GlyphInfo, cp: u21) bool {
    for (glyphs) |g| {
        if (g.value == cp) return true;
    }
    return false;
}

pub fn addLayoutToFont(layout: *const Layout, f: *rl.Font, gpa: Allocator) !void {
    var cps = std.ArrayList(i32).empty;
    defer cps.deinit(gpa);
    var iter = layout.keys.valueIterator();
    while (iter.next()) |key| {
        {
            const cp = key.normal;
            if (!fontHasCodepoint(f, cp) and !root.exists(i32, cps.items, cp)) {
                try cps.append(gpa, cp);
            }
        }
        if (key.shift) |cp| {
            if (!fontHasCodepoint(f, cp) and !root.exists(i32, cps.items, cp)) {
                try cps.append(gpa, cp);
            }
        }
    }
    if (cps.items.len == 0) return;

    try addCodepointsToFont(f, cps.items, std.heap.c_allocator);
}

pub fn centerRec(bounds: rl.Rectangle, size: rl.Vector2) rl.Rectangle {
    return rl.Rectangle.init((bounds.width - size.x) / 2, (bounds.height - size.y) / 2, size.x, size.y);
}

pub fn isKeybindPressed(keybind: []const u8) bool {
    var split = std.mem.splitAny(u8, keybind, "+-");
    while (split.next()) |t| {
        if (std.mem.eql(u8, t, "ctrl") or std.mem.eql(u8, t, "control")) {
            if (!rl.isKeyDown(.left_control) and !rl.isKeyDown(.right_control)) return false;
            continue;
        }
        if (std.mem.eql(u8, t, "shift")) {
            if (!rl.isKeyDown(.left_shift) and !rl.isKeyDown(.right_shift)) return false;
            continue;
        }
        if (std.mem.eql(u8, t, "alt")) {
            if (!rl.isKeyDown(.left_alt) and !rl.isKeyDown(.right_alt)) return false;
            continue;
        }
        if (std.mem.eql(u8, t, "win") or std.mem.eql(u8, t, "super")) {
            if (!rl.isKeyDown(.left_super) and !rl.isKeyDown(.right_control)) return false;
            continue;
        }
        if (std.meta.stringToEnum(rl.KeyboardKey, t)) |k| {
            switch (k) {
                .left_control,
                .left_alt,
                .left_shift,
                .left_super,
                .right_alt,
                .right_control,
                .right_shift,
                .right_super,
                => if (!rl.isKeyDown(k)) return false,
                else => if (!rl.isKeyPressed(k)) return false,
            }
        } else {
            std.debug.print("fuck this shit bro you gave me {s} waht the fuck am i supposed to do with that bruh\n", .{t});
            std.process.exit(1);
        }
    }
    return true;
}
