const std = @import("std");
const root = @import("dkwtct");

const dvui = @import("dvui");

const RaylibBackend = @import("rl");
const rl = RaylibBackend.raylib;

const rlf = @import("raylib_functions.zig");

const v = @import("vars.zig");

const Allocator = std.mem.Allocator;

const Keymap = @import("Keymap.zig");
const Layout = @import("Layout.zig");
const LayoutFile = @import("LayoutFile.zig");
const Textbox = @import("Textbox.zig");
const Backend = @import("Backend.zig");

const vsync = true;

pub var scale_val: f32 = 1.0;
pub var theme: dvui.enums.ColorScheme = .light;

pub fn main() !void {
    const is_debug = @import("builtin").mode == .Debug;
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer if (is_debug) {
        _ = debug_alloc.deinit();
    };
    const gpa = if (is_debug) debug_alloc.allocator() else std.heap.smp_allocator;

    RaylibBackend.enableRaylibLogging();
    var gui_backend = try RaylibBackend.initWindow(.{
        .gpa = gpa,
        .size = .zero,
        .vsync = vsync,
        .title = "Haello",
    });
    defer gui_backend.deinit();
    gui_backend.log_events = true;

    var win = try dvui.Window.init(@src(), gpa, gui_backend.backend(), .{
        .color_scheme = theme,
    });
    defer win.deinit();

    v.program_start = try .now();

    rl.setTextureFilter(v.font.texture, .bilinear);
    v.font = try rl.loadFontFromMemory(".ttf", v.font_data, v.fs, null);

    var app_backend = try Backend.init(gpa);
    defer app_backend.deinit(gpa);

    var keymap = try Keymap.parse(v.keymap_str, gpa);
    defer keymap.deinit(gpa);

    // var is_paused = false;
    // var is_saving = false;

    var layout_box = Textbox.init(gpa);
    defer layout_box.deinit();

    var variant_box = Textbox.init(gpa);
    defer variant_box.deinit();

    {
        try win.begin(0);
        try dvui.addFont("mplus", v.font_data, null);
        _ = try win.end(.{});
    }

    main_loop: while (true) {
        rl.beginDrawing();

        const nstime = win.beginWait(true);

        try win.begin(nstime);
        try gui_backend.addAllEvents(&win);

        gui_backend.clear();

        const keep_running = dvuiFrame();
        if (!keep_running) break :main_loop;

        const end_micros = try win.end(.{});

        gui_backend.setCursor(win.cursorRequested());

        const wait_event_micros = win.waitTime(end_micros);
        gui_backend.EndDrawingWaitEventTimeout(wait_event_micros);
    }
}

fn dvuiFrame() bool {
    const font = dvui.Font.find(.{ .family = "mplus" });
    var scaler = dvui.scale(@src(), .{ .scale = &scale_val }, .{});
    defer scaler.deinit();

    {
        const rows = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .ratio, .background = true });
        _ = dvui.button(@src(), "button", .{}, .{
            .font = font,
        });

        defer rows.deinit();
    }
    // event handling
    for (dvui.events()) |*e| {
        // assume we only have a single window
        if (e.evt == .window and e.evt.window.action == .close) return false;
        if (e.evt == .app and e.evt.app.action == .quit) return false;
        if (e.evt == .key) {
            const key = e.evt.key;
            if (key.mod.control()) {
                if (key.code == .minus) {
                    scale_val = scale(font.size, scale_val, -1);
                } else if (key.code == .equal) {
                    scale_val = scale(font.size, scale_val, 1);
                }
            }
        }
    }
    return true;
}

fn scale(font_size: f32, s: f32, add: f32) f32 {
    return @round(font_size * s + add) / font_size;
}
