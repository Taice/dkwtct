const std = @import("std");
const dvui = @import("dvui");
const dkct = @import("dkwtct");

const config_file = dkct.config_file;
const actions = dkct.actions;
const dialogs = dkct.dialogs;
const util = dkct.util;
const v = dkct.vars;

const Allocator = std.mem.Allocator;
const Io = std.Io;

const AppBackend = dkct.AppBackend;

const RebindStack = dkct.RebindStack;
const Keymap = RebindStack.Keymap;
const XKBLayout = RebindStack.XKBLayout;

const Theme = dkct.enums.Theme;
const Appdata = dkct.Appdata;

const SDLBackend = @import("sdl3").SDLBackend;

pub fn main(init: std.process.Init) !void {
    var timer = std.Io.Timestamp.now(init.io, .real);

    dkct.RebindStack.label_to_icon = try .init(
        init.gpa,
        &.{" "},
        &.{try dvui.svgToTvg(init.gpa, @embedFile("assets/spacebar.svg"))},
    );
    defer {
        for (dkct.RebindStack.label_to_icon.values()) |x| {
            init.gpa.free(x);
        }
        dkct.RebindStack.label_to_icon.deinit(init.gpa);
    }

    v.error_info_gpa = init.gpa;
    defer util.optionFree(init.gpa, v.extra_error_info);

    try config_file.initRelevantThings(init.io, init.gpa, init.minimal.environ);
    defer config_file.deinitRelevantThings();

    try dialogs.initDialogData(init.gpa);
    defer dialogs.deinitDialogData(init.gpa);

    SDLBackend.enableSDLLogging();
    std.log.info("SDL version: {f}", .{SDLBackend.getSDLVersion()});

    // init SDL backend (creates and owns OS window)
    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = true,
        .title = "DVUI SDL Standalone Example",
    });
    defer backend.deinit();

    _ = SDLBackend.c.SDL_EnableScreenSaver();

    var window_open = true;

    const preferred_scheme = backend.preferredColorScheme() orelse .dark;
    const default_theme: Theme = if (preferred_scheme == .light) .adwaita_light else .adwaita_dark;
    // init dvui Window (maps onto a single OS window)
    var ctx: Appdata = undefined;
    defer ctx.deinit();

    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{
        // you can set the default theme here in the init options
        .open_flag = &window_open,
    });
    defer win.deinit();

    var interrupted = false;
    var first_frame = true;

    main_loop: while (window_open) {
        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        if (first_frame) {
            ctx = try Appdata.init(init.io, init.gpa, default_theme);
            first_frame = false;
            try dvui.addFont("GoNotoKurrent", v.char_font_data, null);
            win.themeSet(ctx.savestate.theme.getTheme());
        }
        // send all SDL events to dvui for processing
        try backend.addAllEvents(&win);

        const events = dvui.events();
        for (events) |event| {
            @setEvalBranchQuota(10000);
            switch (event.evt) {
                .key => |k| b: {
                    if (k.action != .down) break :b;

                    switch (util.hashKey(k)) {
                        util.keyHash("ctrl+s") => {
                            if (ctx.rebind_stack.dkwtct_layout.file_path) |fp| {
                                try ctx.rebind_stack.dkwtct_layout.saveToPath(init.io, init.gpa, fp);
                            } else {
                                try actions.saveAs(init.io, init.gpa, &ctx);
                            }
                        },
                        util.keyHash("ctrl+shift+s") => try actions.saveAs(init.io, init.gpa, &ctx),

                        util.keyHash("ctrl+o") => try actions.open(init.io, init.gpa, &ctx),

                        util.keyHash("ctrl+e") => ctx.export_dialog = true,
                        util.keyHash("ctrl+i") => ctx.import_dialog = true,

                        util.keyHash("ctrl+1") => ctx.layer = .normal,
                        util.keyHash("ctrl+2") => ctx.layer = .shift,
                        util.keyHash("ctrl+3") => ctx.layer = .alt,
                        util.keyHash("ctrl+4") => ctx.layer = .alt_shift,

                        util.keyHash("ctrl+b") => ctx.savestate.bleed_chars = !ctx.savestate.bleed_chars,

                        util.keyHash("ctrl+n") => {
                            ctx.rebind_stack.dkwtct_layout.deinit(init.gpa);
                            ctx.rebind_stack.dkwtct_layout = .empty;
                        },

                        util.keyHash("ctrl+space") => {
                            if (ctx.tab == .layout) {
                                ctx.tab = .rebinds;
                            } else {
                                ctx.tab = .layout;
                            }
                        },
                        else => {},
                    }
                },
                .mouse => {},
                .text => {},
                else => {},
            }
        }

        const keep_running = try guiFrame(init.io, &ctx);
        if (!keep_running) break :main_loop;

        // marks end of dvui frame, don't call dvui functions after this
        // by default, manage backend (cursor handling, rendering) as well.
        const end_micros = try win.end(.{});

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);

        if (timer.untilNow(init.io, .real).toSeconds() >= 5) {
            timer = .now(init.io, .real);
            try saveData(init.io, init.gpa, &ctx);
        }
    }

    try saveData(init.io, init.gpa, &ctx);
}

pub fn saveData(io: std.Io, gpa: Allocator, ctx: *Appdata) !void {
    try ctx.savestate.saveToPath(io, gpa, config_file.savestate_path);
    try ctx.rebind_stack.dkwtct_layout.saveToPath(io, gpa, config_file.current_layout_file);
}

pub fn guiFrame(io: std.Io, ctx: *Appdata) !bool {
    const gpa = ctx.gpa;

    const screen = dvui.box(@src(), .{ .dir = .vertical }, .{ .background = true, .expand = .both });
    defer screen.deinit();
    {
        const toolbar = dvui.menu(@src(), .horizontal, .{});
        defer toolbar.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .corners = .square })) |r| {
            const fm = dvui.floatingMenu(@src(), .{ .from = r }, .{
                .corners = .square,
                .padding = .all(0),
            });
            defer fm.deinit();

            const mi_opts = dvui.Options{ .corners = .square, .expand = .horizontal };

            if (dvui.menuItemLabel(@src(), "Open", .{}, mi_opts)) |_| {
                if (try dvui.dialogNativeFileOpen(gpa, .{ .path = config_file.layouts_dir })) |file_path| b: {
                    defer gpa.free(file_path);

                    const owned_file_path = try gpa.dupe(u8, file_path[0..file_path.len]);
                    const new_dkwtct_layout = dkct.RebindStack.DkwtctLayout.open(io, gpa, owned_file_path) catch |e| {
                        try dialogs.errorDialog(@src(), "Error trying to import layout: {any}\n{s}", .{
                            e, v.extra_error_info orelse "",
                        });
                        break :b;
                    };
                    ctx.rebind_stack.dkwtct_layout.deinit(gpa);
                    ctx.rebind_stack.dkwtct_layout = new_dkwtct_layout;
                }
                fm.close();
            }

            if (dvui.menuItemLabel(@src(), "Save", .{}, mi_opts)) |_| {
                if (ctx.rebind_stack.dkwtct_layout.file_path) |fp| {
                    try ctx.rebind_stack.dkwtct_layout.saveToPath(io, gpa, fp);
                } else if (try dvui.dialogNativeFileSave(gpa, .{ .path = config_file.layouts_dir })) |file_path| {
                    defer gpa.free(file_path);

                    const dupe = try gpa.dupe(u8, file_path[0..file_path.len]);

                    try ctx.rebind_stack.dkwtct_layout.saveNewPath(io, gpa, dupe);
                }
                fm.close();
            }

            if (dvui.menuItemLabel(@src(), "Save As", .{}, mi_opts)) |_| {
                if (try dvui.dialogNativeFileSave(gpa, .{ .path = config_file.layouts_dir })) |file_path| {
                    defer gpa.free(file_path);

                    const dupe = try gpa.dupe(u8, file_path[0..file_path.len]);

                    try ctx.rebind_stack.dkwtct_layout.saveNewPath(io, gpa, dupe);
                }
                fm.close();
            }

            if (dvui.menuItemLabel(@src(), "Import", .{}, mi_opts)) |_| {
                ctx.import_dialog = true;
                fm.close();
            }
            if (dvui.menuItemLabel(@src(), "Export", .{}, mi_opts)) |_| {
                ctx.export_dialog = true;
                fm.close();
            }
        }
        if (dvui.menuItemLabel(@src(), "Keymap", .{ .submenu = true }, .{ .corners = .square })) |r| {
            const fm = dvui.floatingMenu(@src(), .{ .from = r }, .{
                .corners = .square,
                .padding = .all(0),
            });
            defer fm.deinit();

            const mi_opts = dvui.Options{ .corners = .square, .expand = .horizontal };

            if (dvui.menuItemLabel(@src(), "Open", .{}, mi_opts)) |_| {
                if (try dvui.dialogNativeFileOpen(gpa, .{ .path = config_file.keymaps_dir })) |file_path| b: {
                    defer gpa.free(file_path);

                    const owned_file_path = try gpa.dupe(u8, file_path[0..file_path.len]);

                    const file_contents = util.readFilePathFull(io, gpa, owned_file_path) catch |e| {
                        try dialogs.errorDialog(@src(), "Error {any}\n{s}", .{ e, v.extra_error_info orelse "" });
                        gpa.free(owned_file_path);
                        break :b;
                    };
                    defer gpa.free(file_contents);
                    ctx.rebind_stack.loadKeymap(gpa, file_contents) catch |e| {
                        try dialogs.errorDialog(@src(), "Error {any}\n{s}", .{ e, v.extra_error_info orelse "" });
                        gpa.free(owned_file_path);
                        break :b;
                    };
                    ctx.savestate.setKeymapStr(gpa, owned_file_path);
                }

                fm.close();
            }

            if (dvui.menuItemLabel(@src(), "ansi", .{}, mi_opts)) |_| b: {
                ctx.rebind_stack.loadKeymap(gpa, v.ansi_str) catch |e| {
                    try dialogs.errorDialog(@src(), "Error {any}\n{s}", .{ e, v.extra_error_info orelse "" });
                    break :b;
                };
                ctx.savestate.setKeymapStr(gpa, try gpa.dupe(u8, "ansi"));
            }
            if (dvui.menuItemLabel(@src(), "iso", .{}, mi_opts)) |_| b: {
                ctx.rebind_stack.loadKeymap(gpa, v.iso_str) catch |e| {
                    try dialogs.errorDialog(@src(), "Error {any}\n{s}", .{ e, v.extra_error_info orelse "" });
                    break :b;
                };
                ctx.savestate.setKeymapStr(gpa, try gpa.dupe(u8, "iso"));
            }
        }
    }
    {
        const topbar = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .expand = .horizontal });
        defer topbar.deinit();

        if (dvui.dropdownEnum(@src(), Theme, .{ .choice = &ctx.savestate.theme }, .{}, .{})) {
            dvui.themeSet(ctx.savestate.theme.getTheme());
        }

        _ = dvui.dropdownEnum(@src(), RebindStack.Tab, .{ .choice = &ctx.tab }, .{}, .{});
    }
    {
        const current_tab_related = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .expand = .horizontal });
        defer current_tab_related.deinit();
        switch (ctx.tab) {
            .layout => {
                if (dvui.button(@src(), "clear layout", .{}, .{})) {
                    ctx.rebind_stack.dkwtct_layout.clearLayout(gpa);
                }
                _ = dvui.dropdownEnum(@src(), XKBLayout.LayerEnum, .{ .choice = &ctx.layer }, .{}, .{});
                if (dvui.button(@src(), if (ctx.savestate.bleed_chars) "bleed chars: true" else "bleed chars: false", .{}, .{})) {
                    ctx.savestate.bleed_chars = !ctx.savestate.bleed_chars;
                }
            },
            .rebinds => {
                if (dvui.button(@src(), "clear rebinds", .{}, .{})) {
                    try ctx.rebind_stack.dkwtct_layout.clearRebinds(gpa);
                }
                if (dvui.button(@src(), if (ctx.savestate.swap_rebinds) "swap rebinds: true" else "swap rebinds: false", .{}, .{})) {
                    ctx.savestate.swap_rebinds = !ctx.savestate.swap_rebinds;
                }
            },
        }
    }

    if (try ctx.rebind_stack.draw(@src(), ctx.tab, ctx.layer, ctx.savestate.bleed_chars)) |be| {
        for (be.events.items) |evt| {
            switch (ctx.tab) {
                .layout => {
                    var keycode = be.button_keycode;
                    if (ctx.rebind_stack.dkwtct_layout.rebinds.map.get(keycode)) |rb| {
                        keycode = rb;
                    }

                    sw: switch (evt) {
                        .key => |key| {
                            switch (util.hashKey(key)) {
                                util.keyHash("escape") => {
                                    ctx.rebind_stack.dkwtct_layout.layout.clearKey(keycode, ctx.layer);
                                },
                                util.keyHash("ctrl+c") => {
                                    if (ctx.rebind_stack.dkwtct_layout.layout.keys.get(keycode)) |char| b: {
                                        var temp: [5]u8 = undefined;
                                        const bytes = try std.unicode.utf8Encode(char.getLayer(ctx.layer) orelse break :b, &temp);
                                        dvui.clipboardTextSet(temp[0..bytes]);
                                    }
                                },
                                util.keyHash("ctrl+v") => {
                                    const cb = dvui.clipboardText();
                                    _ = ctx.rebind_stack.dkwtct_layout.layout.pasteCharacter(gpa, keycode, cb, ctx.layer) catch {};
                                },
                                else => break :sw,
                            }

                            dvui.focusWidget(.zero, null, null);
                        },
                        .text => |txt| {
                            if (txt.action == .value) {
                                const str = txt.action.value.txt;
                                _ = ctx.rebind_stack.dkwtct_layout.layout.pasteCharacter(gpa, keycode, str, ctx.layer) catch |e| {
                                    try dialogs.errorDialog(@src(), "Error putting character on layout: \"{any}\"\n->\"{s}\"", .{ e, str });
                                };
                            } else {
                                break :sw;
                            }

                            dvui.focusWidget(.zero, null, null);
                        },
                        .mouse => |m| {
                            if (m.action == .press and m.button == .middle) {
                                ctx.rebind_stack.dkwtct_layout.layout.clearKey(keycode, ctx.layer);
                            } else {
                                break :sw;
                            }

                            dvui.focusWidget(.zero, null, null);
                        },
                        else => {},
                    }
                },
                .rebinds => {
                    sw: switch (evt) {
                        .key => |key| {
                            if (key.action == .down and key.code != .unknown) {
                                const new_keycode = dkct.keycode.dvui_to_keycode[@intFromEnum(key.code)];
                                try ctx.rebind_stack.dkwtct_layout.addRebind(gpa, be.button_keycode, new_keycode, ctx.savestate.swap_rebinds);
                            } else {
                                break :sw;
                            }

                            dvui.focusWidget(.zero, null, null);
                        },
                        .mouse => |mouse| {
                            if (mouse.action == .press and mouse.button == .middle) {
                                try ctx.rebind_stack.dkwtct_layout.removeRebind(gpa, be.button_keycode, ctx.savestate.swap_rebinds);
                            } else if (mouse.action == .press and mouse.button == .right) {
                                dialogs.rebindKeyDialog(.{
                                    .appdata = ctx,
                                    .selected_button = be.button_keycode,
                                });
                            } else {
                                break :sw;
                            }

                            dvui.focusWidget(.zero, null, null);
                        },
                        else => {},
                    }
                },
            }
        }
    }

    if (ctx.import_dialog) {
        try dialogs.importDialog(io, gpa, ctx, &ctx.import_dialog);
    }

    if (ctx.export_dialog) {
        try dialogs.exportDialog(io, gpa, ctx, &ctx.export_dialog);
    }

    return true;
}
