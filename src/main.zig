const std = @import("std");
const root = @import("dkwtct");

const rl = @import("raylib");
const rg = @import("raygui");
const rlf = @import("raylib_functions.zig");

const v = @import("vars.zig");

const Allocator = std.mem.Allocator;

const Keymap = @import("Keymap.zig");
const Layout = @import("Layout.zig");
const LayoutFile = @import("LayoutFile.zig");
const Textbox = @import("Textbox.zig");
const Backend = @import("Backend.zig");

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(500, 500, "dkwtct");
    defer rl.closeWindow();
    rl.setTargetFPS(rl.getMonitorRefreshRate(rl.getCurrentMonitor()));
    rl.setExitKey(.null);

    v.program_start = try .now();

    v.font = try rl.loadFontFromMemory(".ttf", v.font_data, v.fs, null);
    rl.setTextureFilter(v.font.texture, .bilinear);

    const is_debug = @import("builtin").mode == .Debug;
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer if (is_debug) std.debug.print("{any}\n", .{debug_alloc.deinit()});

    const gpa = if (is_debug) debug_alloc.allocator() else std.heap.smp_allocator;

    var backend = try Backend.init(gpa);
    defer backend.deinit(gpa);

    var keymap = try Keymap.parse(v.keymap_str, gpa);
    defer keymap.deinit(gpa);

    var is_paused = false;
    var is_saving = false;

    var layout_box = Textbox.init(gpa);
    defer layout_box.deinit();

    var variant_box = Textbox.init(gpa);
    defer variant_box.deinit();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        const screen_size = rl.Rectangle.init(0, 0, @floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight()));
        try keymap.renderForcedAspectRatio(backend.layout, screen_size, !is_paused);

        if (is_paused) {
            const pause = rlf.centerRec(screen_size, .init(screen_size.width, 75));
            rl.drawRectangleRec(pause, rl.Color.dark_gray);
            const inner = rlf.innerRec(pause, 5);

            const top = rl.Rectangle.init(inner.x, inner.y, inner.width, 30);
            const bottom = rl.Rectangle.init(inner.x, inner.y + 35, inner.width, 30);

            if (rl.isKeyPressed(.tab)) {
                layout_box.selected = !layout_box.selected;
                variant_box.selected = !layout_box.selected;
            }

            if (rl.isKeyPressed(.escape) and !layout_box.selected and !variant_box.selected) {
                is_paused = false;
                is_saving = false;
            }

            _ = try layout_box.render(top);
            if (try variant_box.render(bottom) and layout_box.text.items.len != 0 and variant_box.text.items.len != 0) {
                const layout = root.trim(layout_box.text.items);
                const variant = root.trim(variant_box.text.items);

                if (is_saving) {
                    backend.saveLayoutNameVariant(layout, variant, gpa) catch |e| {
                        std.debug.print("Error while saving layout: {any}\n", .{e});
                    };
                } else b: {
                    backend.importLayoutNameVariant(layout, variant, gpa) catch |e| {
                        std.debug.print("Error while importing layout: {any}\n", .{e});
                        break :b;
                    };
                    try rlf.addLayoutToFont(backend.layout, &v.font, gpa);
                }
                is_paused = false;
                is_saving = false;
            }
        } else {
            const keybind = rlf.isKeybindPressed;
            if (keybind("escape")) {
                if (v.selected_button) |btn| {
                    backend.layout.clearKey(btn, v.selected_layer);
                    v.selected_button = null;
                } else {
                    is_paused = true;
                }
            }
            if (keybind("tab")) {
                if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                    v.selected_layer.cycleBack();
                } else {
                    v.selected_layer.cycle();
                }
            }
            if (keybind("ctrl+c")) {
                const str = try backend.layout.exportStr();
                rl.setClipboardText(@ptrCast(str));
            }
            if (keybind("ctrl+v")) c: {
                const cstr = rl.getClipboardText();
                if (cstr[0] == 0 or cstr.len == 0) break :c;
                const cb = root.fatten(cstr);
                if (v.selected_button) |button| b: {
                    v.selected_button = null;
                    const uc = backend.layout.pasteCharacter(button, cb[0..cb.len], v.selected_layer) catch |e| {
                        std.debug.print("Error while pasting characters: {any}\n", .{e});
                        break :b;
                    };

                    if (!rlf.fontHasCodepoint(&v.font, uc)) {
                        try rlf.addCodepointToFont(&v.font, uc, std.heap.c_allocator);
                        std.debug.print("{u}\n", .{uc});
                    }
                } else b: {
                    const ly = Layout.parse(cb, gpa, null) catch |e| {
                        std.debug.print("cb: {s}\ne: {any}\n", .{ cb, e });
                        break :b;
                    };
                    backend.layout.deinit(gpa);
                    backend.layout.* = ly;
                    try rlf.addLayoutToFont(&ly, &v.font, std.heap.c_allocator);
                }
            }
            if (keybind("ctrl+n")) {
                try backend.resetLayout(gpa);
            }
            if (keybind("ctrl+s")) {
                if (rl.isKeyDown(.left_shift)) {
                    is_paused = true;
                    is_saving = true;
                } else {
                    if (!try backend.trySavingLayout(gpa)) {
                        is_paused = true;
                        is_saving = true;
                    }
                }
            }
        }
        const text = switch (v.selected_layer) {
            .alt => "alt layer",
            .alt_shift => "alt-shift layer",
            .normal => "normal layer",
            .shift => "shift layer",
        };

        rl.drawText(text, 0, 0, 20, rlf.fromInt(0x88888888));
        const c = rl.getCharPressed();
        if (c != 0) {
            if (v.selected_button) |button| {
                v.selected_button = null;
                try backend.layout.putCharacterOnKey(button, @intCast(c), v.selected_layer);
            }
        }
    }
}
