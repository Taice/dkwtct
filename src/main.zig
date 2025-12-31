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

pub fn main() !void {
    rl.setConfigFlags(.{ .window_resizable = true });
    rl.initWindow(500, 500, "dkwtct");
    defer rl.closeWindow();
    rl.setTargetFPS(rl.getMonitorRefreshRate(rl.getCurrentMonitor()));
    rl.setTextureFilter(v.font.texture, .bilinear);
    rl.setExitKey(.null);

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();
    const gpa = std.heap.page_allocator;

    v.font = try rl.loadFontFromMemory(".ttf", v.font_data, v.fs, null);
    v.program_start = try .now();

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
        try keymap.renderForcedAspectRatio(screen_size, !is_paused);

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
            if (try variant_box.render(bottom) and layout_box.text.items.len != 0 and variant_box.text.items.len != 0) b: {
                const layout = root.trim(layout_box.text.items);
                const variant = try gpa.dupe(u8, root.trim(variant_box.text.items));

                keymap.layout.name = variant;

                if (is_saving) c: {
                    // save layout
                    var file = LayoutFile.loadFromName(layout, io, gpa) catch |e| {
                        switch (e) {
                            std.fs.File.OpenError.FileNotFound => {
                                var file = try LayoutFile.init(keymap.layout, layout, gpa);
                                try file.names.append(gpa, variant);
                                try file.write(gpa);

                                v.current_file_idx = 0;
                                v.current_file = file;
                            },
                            else => return e,
                        }
                        break :c;
                    };
                    try file.names.append(gpa, variant);
                    for (file.layouts.items, 0..) |*l, i| {
                        if (std.mem.eql(u8, l.name.?, variant)) {
                            if (v.current_file) |*f| {
                                f.deinit(gpa);
                            }
                            v.current_file = file;
                            v.current_file_idx = i;
                            l.deinit();
                            l.* = keymap.layout;
                            try file.write(gpa);
                            break :c;
                        }
                    }
                    try file.layouts.append(gpa, keymap.layout);
                    try file.write(gpa);
                } else {
                    // import layout
                    var file = LayoutFile.loadFromName(layout, io, gpa) catch break :b;
                    var found = false;
                    for (file.layouts.items, 0..) |l, i| {
                        if (std.mem.eql(u8, l.name.?, variant_box.text.items)) {
                            found = true;

                            if (v.current_file) |*f| {
                                f.deinit(gpa);
                            }
                            v.current_file = file;
                            v.current_file_idx = i;

                            keymap.layout = l;
                            try rlf.addLayoutToFont(&keymap.layout, &v.font, gpa);
                            break;
                        }
                    }
                    if (!found) {
                        file.deinit(gpa);
                    }
                }
                is_paused = false;
                is_saving = false;
            }
        } else {
            const keybind = rlf.isKeybindPressed;
            if (keybind("escape")) {
                if (v.selected_button) |btn| {
                    if (v.selected_shift_layer) {
                        if (keymap.layout.keys.getPtr(btn)) |k| {
                            k.shift_layer = null;
                        }
                    } else {
                        _ = keymap.layout.keys.remove(btn);
                    }
                    v.selected_button = null;
                } else {
                    is_paused = true;
                }
            }
            if (keybind("ctrl+c")) {
                const str = try keymap.layout.exportStr();
                rl.setClipboardText(@ptrCast(str));
            }
            if (keybind("ctrl+v")) {
                if (v.selected_button) |button| b: {
                    const cb = rl.getClipboardText();
                    if (std.unicode.utf8ByteSequenceLength(cb[0]) catch break :b != cb.len) break :b; // ensure single utf-8 codepoint
                    const get_or_put = try keymap.layout.keys.getOrPut(button);
                    if (!get_or_put.found_existing) {
                        get_or_put.value_ptr.shift_layer = null;
                        get_or_put.value_ptr.normal = 0;
                    }
                    if (v.selected_shift_layer) {
                        const sl = std.unicode.utf8Decode(cb[0..cb.len]) catch break :b;
                        get_or_put.value_ptr.shift_layer = sl;
                        if (!rlf.fontHasCodepoint(&v.font, sl)) {
                            try rlf.addCodepointToFont(&v.font, sl, std.heap.c_allocator);
                            std.debug.print("{u}\n", .{sl});
                        }
                    } else {
                        get_or_put.value_ptr.normal = std.unicode.utf8Decode(cb[0..cb.len]) catch break :b;
                        if (!rlf.fontHasCodepoint(&v.font, get_or_put.value_ptr.normal)) {
                            try rlf.addCodepointToFont(&v.font, get_or_put.value_ptr.normal, std.heap.c_allocator);
                            std.debug.print("{u}\n", .{get_or_put.value_ptr.normal});
                        }
                    }
                    v.selected_button = null;
                    v.selected_shift_layer = false;
                } else b: {
                    const cstr = rl.getClipboardText();
                    if (cstr.len == 0) break :b;
                    const cb = root.fatten(cstr);
                    const ly = Layout.parse(cb, gpa, null) catch |e| {
                        std.debug.print("cb: {s}\ne: {any}\n", .{ cb, e });
                        break :b;
                    };
                    keymap.layout.deinit();
                    keymap.layout = ly;
                    try rlf.addLayoutToFont(&keymap.layout, &v.font, std.heap.c_allocator);
                }
            }
            if (keybind("ctrl+n")) {
                if (v.current_file) |*f| {
                    f.deinit(gpa);
                }
                v.current_file = null;
                keymap.layout.deinit();
                keymap.layout.name = null;
                keymap.layout.keys = .init(gpa);
            }
            if (keybind("ctrl+s")) {
                if (rl.isKeyDown(.left_shift)) {
                    is_paused = true;
                    is_saving = true;
                } else {
                    if (v.current_file) |f| {
                        f.layouts.items[v.current_file_idx] = keymap.layout;
                        try f.write(gpa);
                    } else {
                        is_paused = true;
                        is_saving = true;
                    }
                }
            }
            const c = rl.getCharPressed();
            if (c != 0) {
                if (v.selected_button) |button| {
                    const get_or_put = try keymap.layout.keys.getOrPut(button);
                    if (!get_or_put.found_existing) {
                        get_or_put.value_ptr.shift_layer = null;
                        get_or_put.value_ptr.normal = 0;
                    }
                    if (v.selected_shift_layer) {
                        get_or_put.value_ptr.shift_layer = @intCast(c);
                    } else {
                        get_or_put.value_ptr.normal = @intCast(c);
                    }
                    v.selected_button = null;
                    v.selected_shift_layer = false;
                }
            }
        }
    }
}
