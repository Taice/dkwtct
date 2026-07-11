const RebindStack = @This();

const std = @import("std");
const dvui = @import("dvui");
const dkct = @import("dkwtct");

pub const Keymap = @import("rebind_stack/Keymap.zig");
pub const Rebinds = @import("rebind_stack/Rebinds.zig");
pub const XKBLayout = @import("rebind_stack/XKBLayout.zig");
pub const DkwtctLayout = @import("rebind_stack/DkwtctLayout.zig");
pub const RebindsFile = @import("rebind_stack/RebindsFile.zig");
pub const LayoutFile = @import("rebind_stack/LayoutFile.zig");

const Allocator = std.mem.Allocator;

keymap: Keymap,
dkwtct_layout: DkwtctLayout,

pub fn init(keymap: Keymap) RebindStack {
    return .{
        .keymap = keymap,
        .dkwtct_layout = .init(),
    };
}

pub fn deinit(ts: *RebindStack, gpa: Allocator) void {
    ts.keymap.deinit(gpa);
    ts.dkwtct_layout.deinit(gpa);
}

pub const Tab = enum {
    layout,
    rebinds,
};

const ButtonOpts = struct {
    keycode: []const u8,
    label: []const u8,
    grayed: bool = false,
    disabled: bool = false,
};

const char_aliases = std.StaticStringMap([]const u8).initComptime(.{});

var out_buf: [5]u8 = undefined;
pub fn getButtonOpts(ts: *const RebindStack, keycode: []const u8, tab: Tab, layer: XKBLayout.LayerEnum, bleed_chars: bool) !ButtonOpts {
    if (std.mem.eql(u8, keycode, "DSBL")) {
        return .{
            .keycode = "",
            .label = "",
            .disabled = true,
            .grayed = false,
        };
    }
    var opts = ButtonOpts{
        .keycode = keycode,
        .label = "",
    };
    b: switch (tab) {
        .layout => {
            var key = keycode;
            if (ts.dkwtct_layout.rebinds.map.get(keycode)) |k| {
                key = k;
            }

            if (dkct.keycode.untypeable_keycodes.get(key) != null) {
                opts.grayed = true;
                opts.disabled = true;
                if (dkct.keycode.keycode_aliases.get(key)) |alias| {
                    opts.label = alias;
                    break :b;
                }
                opts.label = key;
                break :b;
            }

            if (ts.dkwtct_layout.layout.keys.get(key)) |k| {
                if (k.getLayer(layer)) |cp| {
                    const num_bytes = try std.unicode.utf8Encode(cp, &out_buf);
                    opts.label = out_buf[0..num_bytes];
                    if (char_aliases.get(opts.label)) |alias| {
                        opts.label = alias;
                    }
                    break :b;
                } else if (bleed_chars) {
                    const normal = layer.cycleBack();
                    const cp = k.getLayer(normal) orelse unreachable;
                    opts.grayed = true;
                    if (cp != 0) {
                        const num_bytes = try std.unicode.utf8Encode(cp, &out_buf);
                        opts.label = out_buf[0..num_bytes];
                        if (char_aliases.get(opts.label)) |alias| {
                            opts.label = alias;
                        }
                        break :b;
                    }
                }
            }
            opts.label = "";
        },
        .rebinds => {
            opts.label = keycode;
            if (ts.dkwtct_layout.rebinds.map.get(keycode)) |k| {
                opts.label = k;
            }

            if (dkct.keycode.keycode_aliases.get(opts.label)) |alias| {
                opts.label = alias;
                break :b;
            }
        },
    }
    return opts;
}

const button_padding: f32 = 5;
const button_border: f32 = 2;
const button_margin: f32 = 2;
const button_m_height: f32 = 2.5;

pub fn draw(
    ts: *const RebindStack,
    src: std.builtin.SourceLocation,
    tab: Tab,
    layer: XKBLayout.LayerEnum,
    bleed_chars: bool,
) !?RelevantButtonEvents {
    const whole = dvui.parentGet().data().contentRect();

    const box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    const keyboard_normal = ts.keymap.getNormalizedDims();

    const w = keyboard_normal.w + 4;
    const keyboard_portion_scale = keyboard_normal.w / w;
    const keyboard_portion = dvui.Size{ .w = whole.w * keyboard_portion_scale, .h = whole.h };

    const keyboard_box = dvui.box(@src(), .{}, .{
        .min_size_content = keyboard_portion,
        .max_size_content = .size(keyboard_portion),
    });
    var scale: f32 = 0;
    const button_events = try ts.drawKeyboard(@src(), tab, layer, &scale, bleed_chars);
    keyboard_box.deinit();

    var font = dvui.Font.find(.{ .family = "GoNotoKurrent" });
    const base_button = font.sizeM(0, 2.5).h;

    _ = dvui.spacer(@src(), .{
        .min_size_content = .width(base_button * scale),
    });

    const keyboard_size = keyboard_normal.scale(scale * base_button, dvui.Size);
    const mouse_size = dvui.Size{ .w = 3 * scale * base_button, .h = 4 * scale * base_button };
    const height_difference = keyboard_size.h - mouse_size.h;

    const vbox = dvui.box(@src(), .{ .dir = .vertical }, .{});
    defer vbox.deinit();
    _ = dvui.spacer(@src(), .{
        .min_size_content = .height(height_difference),
    });
    const mouse_box = dvui.box(@src(), .{}, .{
        .min_size_content = mouse_size,
        .max_size_content = .size(mouse_size),
    });
    defer mouse_box.deinit();
    return try ts.drawMouse(@src(), tab, layer, scale, bleed_chars) orelse button_events;
}

pub fn drawMouse(
    ts: *const RebindStack,
    src: std.builtin.SourceLocation,
    tab: Tab,
    layer: XKBLayout.LayerEnum,
    _scale: ?f32,
    bleed_chars: bool,
) !?RelevantButtonEvents {
    var button_events: ?RelevantButtonEvents = null;
    var font = dvui.Font.find(.{ .family = "GoNotoKurrent" });

    const normalized_dims = dvui.Size{ .w = 3, .h = 4 };
    const available_size = dvui.parentGet().data().contentRect();

    var default_button_size = font.sizeM(0, 2.5);
    default_button_size.w = default_button_size.h;

    const whole_base_button_size = dvui.Size.all(@min(available_size.w / normalized_dims.w, available_size.h / normalized_dims.h));
    const scale = _scale orelse whole_base_button_size.w / default_button_size.w;

    var base_button_size = default_button_size.scale(scale, dvui.Size);

    base_button_size = base_button_size.padNeg(.all((button_padding + button_margin + button_border) * scale));
    font.size *= scale;
    font.size = @floor(font.size);

    const rows = dvui.box(src, .{ .dir = .vertical }, .{});
    defer rows.deinit();

    var top_row = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .min_size_content = base_button_size.pad(.all((button_padding + button_margin + button_border) * scale)),
    });

    blank(@src(), getButtonSize(base_button_size, 0.5, 1, scale), scale, null);

    var opts = try ts.getButtonOpts("M1", tab, layer, bleed_chars);
    button_events = try keymapButton(@src(), opts, getButtonSize(base_button_size, 1, 1, scale), font, scale, null) orelse button_events;

    opts = try ts.getButtonOpts("M3", tab, layer, bleed_chars);
    button_events = try keymapButton(@src(), opts, getButtonSize(base_button_size, 0.5, 1, scale), font, scale, null) orelse button_events;

    opts = try ts.getButtonOpts("M2", tab, layer, bleed_chars);
    button_events = try keymapButton(@src(), opts, getButtonSize(base_button_size, 1, 1, scale), font, scale, null) orelse button_events;
    top_row.deinit();

    const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});

    const left_side = dvui.box(@src(), .{}, .{});

    opts = try ts.getButtonOpts("M5", tab, layer, bleed_chars);
    button_events = try keymapButton(@src(), opts, getButtonSize(base_button_size, 0.5, 1, scale), font, scale, null) orelse button_events;

    opts = try ts.getButtonOpts("M4", tab, layer, bleed_chars);
    button_events = try keymapButton(@src(), opts, getButtonSize(base_button_size, 0.5, 1, scale), font, scale, null) orelse button_events;

    left_side.deinit();

    _ = try keymapButton(@src(), .{ .keycode = "", .label = "", .disabled = true }, getButtonSize(base_button_size, 2.5, 3, scale), font, scale, null);

    hbox.deinit();

    return button_events;
}

pub fn drawKeyboard(
    ts: *const RebindStack,
    src: std.builtin.SourceLocation,
    tab: Tab,
    layer: XKBLayout.LayerEnum,
    _scale: *f32,
    bleed_chars: bool,
) !?RelevantButtonEvents {
    var button_events: ?RelevantButtonEvents = null;
    var font = dvui.Font.find(.{ .family = "GoNotoKurrent" });

    const normalized_dims = ts.keymap.getNormalizedDims();
    const available_size = dvui.parentGet().data().contentRect();

    var default_button_size = font.sizeM(0, 2.5);
    default_button_size.w = default_button_size.h;

    var base_button_size = dvui.Size.all(@min(available_size.w / normalized_dims.w, available_size.h / normalized_dims.h));
    _scale.* = base_button_size.w / default_button_size.w;
    const scale = _scale.*;

    base_button_size = base_button_size.padNeg(.all((button_padding + button_margin + button_border) * scale));

    font.size = base_button_size.padNeg(.all((button_padding + button_margin + button_border) * scale)).h;
    font.size = @floor(font.size);

    const rows = dvui.box(src, .{ .dir = .vertical }, .{});
    defer rows.deinit();

    var curr_row = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .min_size_content = base_button_size.pad(.all((button_padding + button_margin + button_border) * scale)),
    });
    defer curr_row.deinit();

    for (ts.keymap.data.items, 0..) |element, i| {
        switch (element) {
            .key => |k| {
                const size = getButtonSize(base_button_size, k.width, 1, scale);

                if (std.mem.eql(u8, "BLNK", k.keycode)) {
                    blank(@src(), size, scale, i);
                    continue;
                }

                const button_opts = try ts.getButtonOpts(k.keycode, tab, layer, bleed_chars);

                if (try keymapButton(@src(), button_opts, size, font, scale, i)) |be| b: {
                    if (button_opts.grayed) break :b;

                    button_events = be;
                }
            },
            .newline => {
                curr_row.deinit();
                curr_row = dvui.box(@src(), .{ .dir = .horizontal }, .{
                    .min_size_content = base_button_size.pad(.all((button_padding + button_margin + button_border) * scale)),
                    .id_extra = i,
                });
            },
        }
    }
    return button_events;
}

pub fn getButtonSize(base_size: dvui.Size, norm_w: f32, norm_h: f32, scale: f32) dvui.Size {
    var size = base_size;
    size.w += (size.w + 2 * scale * (button_padding + button_margin + button_border)) * (norm_w - 1);
    size.h += (size.h + 2 * scale * (button_padding + button_margin + button_border)) * (norm_h - 1);
    return size;
}

const RelevantButtonEvents = struct {
    button_keycode: []const u8,
    events: std.ArrayList(dvui.Event.EventTypes) = .empty,
};

const spacebar_tvg = b: {
    var buf: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    break :b dvui.svgToTvg(fba.allocator(), @embedFile("assets/spacebar.svg")) catch unreachable;
};

pub var label_to_icon: std.array_hash_map.String([]const u8) = undefined;
fn keymapButton(
    src: std.builtin.SourceLocation,
    button_opts: ButtonOpts,
    size: dvui.Size,
    font: dvui.Font,
    scale: f32,
    id_extra: ?usize,
) !?RelevantButtonEvents {
    const gpa = dvui.currentWindow().arena();

    var button_events = RelevantButtonEvents{
        .button_keycode = button_opts.keycode,
    };

    var local_font = font;

    const text_size = font.textSize(button_opts.label);

    var bsize = size.w;
    var rotation: f32 = 0;
    if (size.h > size.w) {
        bsize = size.h;
        rotation = -std.math.pi / 2.0;
    }

    const give_or_take: f32 = 4 * scale;
    if (text_size.w > bsize - give_or_take) {
        const scale_factor = (bsize - give_or_take) / text_size.w;
        local_font.size = @floor(font.size * scale_factor);
    }

    // initialize widget and get rectangle from parent and make ourselves the new parent
    var bw: dvui.ButtonWidget = undefined;
    var opts: dvui.Options = .{
        .margin = .all(button_margin * scale),
        .border = .all(button_border * scale),
        .padding = .all(button_padding * scale),
        .min_size_content = size,
        .max_size_content = .size(size),
        .corners = .square,
        .font = local_font,

        .rotation = rotation,

        .id_extra = id_extra,
    };
    const init_opts: dvui.ButtonWidget.InitOptions = .{ .grayed = button_opts.grayed, .draw_focus = !button_opts.grayed };

    bw.init(src, init_opts, opts);

    const click_rect = bw.data().borderRectScale().r;

    const evts = dvui.events();
    const wd = bw.data();
    if (!button_opts.disabled) {
        for (evts) |*e| {
            if (!dvui.eventMatch(e, .{ .id = wd.id, .r = click_rect })) continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .focus) {
                        e.handle(@src(), wd);

                        // focus this widget for events after this one (starting with e.num)
                        dvui.focusWidget(wd.id, null, e.num);
                    } else if (me.action == .press) {
                        e.handle(@src(), wd);
                        dvui.captureMouse(wd, e.num);

                        dvui.focusWidget(wd.id, null, e.num);
                    } else if (me.action == .release) {
                        // mouse button was released, do we still have mouse capture?
                        if (dvui.captured(wd.id)) {
                            e.handle(@src(), wd);

                            // cancel our capture
                            dvui.captureMouse(null, e.num);
                            dvui.dragEnd();

                            // if the release was within our border, the click is successful
                            if (click_rect.contains(me.p)) {

                                // if the user interacts successfully with a
                                // widget, it usually means part of the GUI is
                                // changing, so the convention is to call refresh
                                // so the user doesn't have to remember
                                dvui.refresh(null, @src(), wd.id);
                            }
                        }
                    } else if (me.action == .position) {
                        // Usually you don't want to mark .position events as
                        // handled, so that multiple widgets can all do hover
                        // highlighting.

                        // a single .position mouse event is at the end of each
                        // frame, so this means the mouse ended above us
                        bw.hover = true;
                    }
                    try button_events.events.append(gpa, .{ .mouse = me });
                },
                else => {},
            }

            try button_events.events.append(gpa, e.evt);
        }
    }
    const focused = bw.focused();
    if (focused) {
        dvui.wantTextInput(bw.data().borderRectScale().r.toNatural());
    }

    bw.drawBackground();

    if (label_to_icon.get(button_opts.label)) |tvg_data| {
        dvui.icon(
            @src(),
            button_opts.label,
            tvg_data,
            .{ .stroke_width = 1 * scale },
            opts.strip().override(bw.style()).override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .padding = opts.paddingGet().scale(1.0, dvui.Rect) }),
        );
    } else {
        dvui.labelNoFmt(
            @src(),
            button_opts.label,
            .{ .align_x = 0.5, .align_y = 0.5 },
            opts.strip().override(bw.style()).override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }),
        );
    }

    bw.drawFocus();

    bw.deinit();

    if (!focused or (button_events.events.items.len == 0)) return null;

    return button_events;
}

fn blank(
    src: std.builtin.SourceLocation,
    size: dvui.Size,
    scale: f32,
    id_extra: ?usize,
) void {
    const box = dvui.box(src, .{}, .{
        .padding = .all((button_padding + button_margin + button_border) * scale),
        .min_size_content = size,
        .max_size_content = .size(size),
        .id_extra = id_extra,
    });
    box.deinit();
}

pub fn loadKeymap(ts: *RebindStack, gpa: Allocator, str: []const u8) !void {
    const new_keymap = try Keymap.parse(gpa, str);
    ts.keymap.deinit(gpa);
    ts.keymap = new_keymap;
}
