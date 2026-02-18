const std = @import("std");
const root = @import("dkwtct");

const rl = @import("raylib");
const rg = @import("raygui");
const rlf = @import("raylib_functions.zig");

const config_file = @import("config_file.zig");

const v = @import("vars.zig");

const Allocator = std.mem.Allocator;

const Keymap = @import("Keymap.zig");
const Layout = @import("Layout.zig");
const LayoutFile = @import("LayoutFile.zig");
const Textbox = @import("Textbox.zig");
const Backend = @import("Backend.zig");

pub const default_keymap_str = @embedFile("keymap.dkwtct");

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(500, 500, "dkwtct");
    defer rl.closeWindow();
    rl.setTargetFPS(rl.getMonitorRefreshRate(rl.getCurrentMonitor()));
    rl.setExitKey(.null);

    v.program_start = try .now();

    v.char_font = try rl.loadFontFromMemory(".ttf", v.char_font_data, v.fs, null);
    v.text_font = try rl.loadFontFromMemory(".ttf", v.text_font_data, 30, null);
    // rl.setTextureFilter(v.char_font.texture, .bilinear);

    const is_debug = @import("builtin").mode == .Debug;
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer if (is_debug) std.debug.print("{any}\n", .{debug_alloc.deinit()});

    const gpa = if (is_debug) debug_alloc.allocator() else std.heap.smp_allocator;

    var backend = try Backend.init(gpa);
    defer backend.deinit(gpa);

    var keymap: Keymap = undefined;
    if (config_file.getKeymapFile(gpa, default_keymap_str)) |f| {
        if (f) |file_contents| {
            keymap = Keymap.parse(file_contents, gpa) catch try Keymap.parse(default_keymap_str, gpa);
            std.debug.print("\n\n{s}\n", .{file_contents});
            gpa.free(file_contents);
        } else {
            keymap = try Keymap.parse(default_keymap_str, gpa);
        }
    } else |_| {
        keymap = try Keymap.parse(default_keymap_str, gpa);
    }
    defer keymap.deinit(gpa);

    var is_paused = false;
    var is_saving = false;

    var layout_box = Textbox.init(gpa);
    defer layout_box.deinit();

    var variant_box = Textbox.init(gpa);
    defer variant_box.deinit();

    var directory_box = Textbox.init(gpa);
    directory_box.text = std.ArrayList(u8).fromOwnedSlice(try config_file.getPreferredSaveDirectory(gpa));
    defer directory_box.deinit();

    v.save_directory = &directory_box.text;

    var layer_dropdown = false;
    // var keymap_dropdown = false;

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        v.currently_hovered = false;

        const screen_size = rl.Rectangle.init(0, 20, @floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight() - 20));
        try keymap.renderForcedAspectRatio(backend.layout, screen_size, !is_paused, gpa);

        if (is_paused) {
            const pause = rlf.centerRec(screen_size, .init(screen_size.width * 0.8, 110));
            rl.drawRectangleRec(pause, rl.Color.dark_gray);
            const inner = rlf.innerRec(pause, 5);

            const top = rl.Rectangle.init(inner.x, inner.y, inner.width, 30);
            const middle = rl.Rectangle.init(inner.x, inner.y + 35, inner.width, 30);
            const bottom = rl.Rectangle.init(inner.x, inner.y + 70, inner.width, 30);

            if (rl.isKeyPressed(.tab)) {
                if (rl.isKeyDown(.left_shift)) {
                    if (directory_box.selected) {
                        directory_box.selected = false;
                        layout_box.selected = false;
                        variant_box.selected = true;
                    } else if (layout_box.selected) {
                        directory_box.selected = true;
                        layout_box.selected = false;
                        variant_box.selected = false;
                    } else if (variant_box.selected) {
                        directory_box.selected = false;
                        layout_box.selected = true;
                        variant_box.selected = false;
                    } else {
                        directory_box.selected = true;
                    }
                } else {
                    if (directory_box.selected) {
                        directory_box.selected = false;
                        layout_box.selected = true;
                        variant_box.selected = false;
                    } else if (layout_box.selected) {
                        directory_box.selected = false;
                        layout_box.selected = false;
                        variant_box.selected = true;
                    } else if (variant_box.selected) {
                        directory_box.selected = true;
                        layout_box.selected = false;
                        variant_box.selected = false;
                    } else {
                        directory_box.selected = true;
                    }
                }
            }

            if (rl.isKeyPressed(.escape)) {
                is_paused = false;
                is_saving = false;
            }

            _ = try directory_box.render(top, "directory", if (is_saving) "SAVE" else "LOAD");
            _ = try layout_box.render(middle, "layout", "");
            if (try variant_box.render(bottom, "variant", "") and layout_box.text.items.len != 0 and variant_box.text.items.len != 0) {
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
                    try rlf.addLayoutToFont(backend.layout, &v.char_font, gpa);
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
                    directory_box.selected = false;
                    variant_box.selected = false;
                    layout_box.selected = true;
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
                if (v.selected_button) |btn| {
                    if (backend.layout.keys.get(btn)) |k| {
                        if (k.getLayer(v.selected_layer)) |uc| {
                            var out: [5]u8 = .{0} ** 5;
                            _ = try std.unicode.utf8Encode(uc, &out);
                            rl.setClipboardText(@ptrCast(&out));
                            v.selected_button = null;
                        }
                    }
                } else {
                    const str = try backend.layout.exportStr();
                    rl.setClipboardText(@ptrCast(str));
                }
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

                    if (!rlf.fontHasCodepoint(&v.char_font, uc)) {
                        try rlf.addCodepointToFont(&v.char_font, uc, std.heap.c_allocator);
                        std.debug.print("{u}\n", .{uc});
                    }
                } else b: {
                    const ly = Layout.parse(cb, gpa, null) catch |e| {
                        std.debug.print("cb: {s}\ne: {any}\n", .{ cb, e });
                        break :b;
                    };
                    backend.layout.deinit(gpa);
                    backend.layout.* = ly;
                    try rlf.addLayoutToFont(&ly, &v.char_font, std.heap.c_allocator);
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

        {
            const c = rl.getCharPressed();
            if (c != 0) {
                if (v.selected_button) |button| {
                    v.selected_button = null;
                    try backend.layout.putCharacterOnKey(button, @intCast(c), v.selected_layer);
                    if (!rlf.fontHasCodepoint(&v.char_font, @intCast(c))) {
                        try rlf.addCodepointToFont(&v.char_font, @intCast(c), gpa);
                        std.debug.print("{u}\n", .{@as(u21, @intCast(c))});
                    }
                }
            }
        }

        if (rl.isKeyPressed(.backspace)) {
            const c = 1;
            if (c != 0) {
                if (v.selected_button) |button| {
                    v.selected_button = null;
                    try backend.layout.putCharacterOnKey(button, @intCast(c), v.selected_layer);
                }
            }
        }
        if (rl.isKeyPressed(.home)) {
            const c = 2;
            if (c != 0) {
                if (v.selected_button) |button| {
                    v.selected_button = null;
                    try backend.layout.putCharacterOnKey(button, @intCast(c), v.selected_layer);
                }
            }
        }

        const layer_text = switch (v.selected_layer) {
            .alt => "alt layer",
            .alt_shift => "alt-shift layer",
            .normal => "normal layer",
            .shift => "shift layer",
        };

        const mouse_pos = rl.getMousePosition();

        const layer_button_rect = rl.Rectangle.init(0, 0, 100, 20);
        _ = rg.button(layer_button_rect, layer_text);

        const layer_button_dropdown_rect = rl.Rectangle.init(0, 20, 100, 80);
        if (rl.checkCollisionPointRec(mouse_pos, layer_button_rect)) {
            layer_dropdown = true;
        } else {
            if (!rl.checkCollisionPointRec(mouse_pos, layer_button_dropdown_rect)) {
                layer_dropdown = false;
            }
        }

        if (layer_dropdown) {
            for (&[_]f32{ 20, 40, 60, 80 }, 0..) |y, i| {
                const layer: Layout.LayerEnum = @enumFromInt(i);
                const text = switch (layer) {
                    .alt => "alt layer",
                    .alt_shift => "alt-shift layer",
                    .normal => "normal layer",
                    .shift => "shift layer",
                };
                const button_rect = rl.Rectangle.init(0, y, 100, 20);
                if (rg.button(button_rect, text)) {
                    v.selected_layer = layer;
                    layer_dropdown = false;
                    break;
                }
                if (layer == v.selected_layer) {
                    rl.drawRectangleRec(button_rect, rlf.fromInt(0x00000033));
                }
            }
        }

        // const keymap_button_rect = rl.Rectangle.init(100, 0, 100, 20);
        // _ = rg.button(keymap_button_rect, "keymap");
        //
        // const keymap_button_dropdown_rect = rl.Rectangle.init(100, 20, 100, 40);
        // if (rl.checkCollisionPointRec(mouse_pos, keymap_button_rect)) {
        //     keymap_dropdown = true;
        // } else {
        //     if (!rl.checkCollisionPointRec(mouse_pos, keymap_button_dropdown_rect)) {
        //         keymap_dropdown = false;
        //     }
        // }

        // if (keymap_dropdown) {
        //     if (rg.button(rl.Rectangle.init(100, 20, 100, 20), ""))
        //         rl.drawRectangleRec(layer_button_dropdown_rect, rlf.fromInt(0x00000033));
        // }

        if (!v.currently_hovered and rl.isMouseButtonPressed(.left)) {
            v.selected_button = null;
        }
    }

    try config_file.saveSaveDirectory(gpa, directory_box.text.items);
}
