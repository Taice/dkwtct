const std = @import("std");
const RaylibBackend = @import("rl");
const rl = RaylibBackend.raylib;

const v = @import("vars.zig");

const Textbox = @This();

text: std.ArrayList(u8) = .empty,
selected: bool = false,
gpa: std.mem.Allocator,

pub fn deinit(ts: *Textbox) void {
    ts.text.deinit(ts.gpa);
}

pub fn init(gpa: std.mem.Allocator) Textbox {
    return .{
        .gpa = gpa,
    };
}

pub fn render(ts: *Textbox, bounds: rl.Rectangle) !bool {
    const mpos = rl.getMousePosition();
    if (rl.isMouseButtonPressed(.left)) {
        ts.selected = rl.checkCollisionPointRec(mpos, bounds);
    }

    var color = rl.Color.ray_white;
    if (ts.selected) {
        color = rl.Color.light_gray;
        const ch = rl.getCharPressed();
        if (ch != 0) {
            if (ch < 128) {
                try ts.text.append(ts.gpa, @intCast(ch));
            }
        }

        if (rl.isKeyPressed(.backspace)) {
            if (rl.isKeyDown(.left_control)) {
                ts.text.items.len = 0;
            } else {
                _ = ts.text.pop();
            }
        }

        if (rl.isKeyPressed(.escape)) {
            ts.selected = false;
        }
    }

    rl.drawRectangleRec(bounds, color);

    try ts.text.append(ts.gpa, 0);
    rl.drawTextEx(v.font, @ptrCast(ts.text.items), .init(@round(bounds.x), @round(bounds.y)), @round(bounds.height), 2, rl.Color.black);
    const w = rl.measureTextEx(v.font, @ptrCast(ts.text.items), @round(bounds.height), 2).x;
    _ = ts.text.pop();

    if (ts.selected) {
        if (((try std.time.Instant.now()).since(v.program_start) / (std.time.ns_per_s / 2)) % 2 == 0)
            rl.drawLineEx(.init(bounds.x + w + 2, bounds.y), .init(bounds.x + 2 + w, bounds.y + bounds.height), 2, rl.Color.black);
    }

    const is_enter = rl.isKeyPressed(.enter) and ts.selected;
    if (is_enter) {
        ts.selected = false;
    }

    return is_enter;
}
