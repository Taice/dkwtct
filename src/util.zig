const std = @import("std");
const dvui = @import("dvui");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \n\t");
}

pub fn exists(T: type, slice: []T, item: T) bool {
    return std.mem.indexOfScalar(T, slice, item) != null;
}

pub fn getBetween(str: []const u8, chars: []const u8) ?struct { []const u8, usize } {
    if (chars.len != 2) {
        std.debug.panic("Chars({s}), should be 2 characters.\n", .{chars});
    }
    if (std.mem.indexOfScalar(u8, str, chars[0])) |a| {
        if (std.mem.indexOfScalarPos(u8, str, a + 1, chars[1])) |b| {
            return .{ str[a + 1 .. b], b };
        }
    }
    return null;
}

pub fn makeDirAll(io: Io, dir: []const u8) void {
    var idx: usize = 1;
    while (true) {
        const slash = std.mem.indexOfScalarPos(u8, dir, idx, '/') orelse break;
        idx = slash + 1;
        Io.Dir.createDirAbsolute(io, dir[0..slash], .default_dir) catch {};
    }
}

var buf: [1024]u8 = undefined;
pub fn readFilePathFull(io: std.Io, gpa: Allocator, file_path: []const u8) ![]u8 {
    const file = try std.Io.Dir.openFileAbsolute(io, file_path, .{});
    defer file.close(io);

    var reader = file.reader(io, &buf);

    return try reader.interface.allocRemaining(gpa, .unlimited);
}

pub fn writeFilePathFull(io: std.Io, file_path: []const u8, contents: []const u8) !void {
    makeDirAll(io, file_path);

    const file = try Io.Dir.createFileAbsolute(io, file_path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, contents);
}

pub fn optionDeinit(gpa: Allocator, optional: anytype) void {
    if (optional.*) |*t| {
        t.deinit(gpa);
    }
    optional.* = null;
}

pub fn optionFree(gpa: Allocator, optional: anytype) void {
    if (optional) |t| {
        gpa.free(t);
    }
}

pub fn dupeOptional(gpa: Allocator, optional_slice: ?[]const u8) !?[]const u8 {
    if (optional_slice) |fp| {
        return try gpa.dupe(u8, fp);
    }
    return null;
}

pub fn hashKey(key: dvui.Event.Key) u12 {
    var mod: u4 = 0;
    if (key.mod.shift()) {
        mod |= 1 << 0;
    }
    if (key.mod.control()) {
        mod |= 1 << 1;
    }
    if (key.mod.alt()) {
        mod |= 1 << 2;
    }
    if (key.mod.command()) {
        mod |= 1 << 3;
    }

    const k = @intFromEnum(key.code);

    var hash: u12 = @as(u12, mod) << 8;
    hash |= k;

    return hash;
}

pub fn keyHash(comptime fmt: []const u8) u24 {
    var tokens = std.mem.tokenizeAny(u8, fmt, "-+, \n\t\r");
    var mod: u4 = 0;

    var key: ?dvui.enums.Key = null;
    while (tokens.next()) |token| {
        if (std.mem.eql(u8, token, "shift")) {
            mod |= 1 << 0;
        } else if (std.mem.eql(u8, token, "ctrl")) {
            mod |= 1 << 1;
        } else if (std.mem.eql(u8, token, "alt")) {
            mod |= 1 << 2;
        } else if (std.mem.eql(u8, token, "win")) {
            mod |= 1 << 3;
        } else if (token.len == 1 and std.ascii.isDigit(token[0])) {
            const number = token[0] - '0';
            const k: dvui.enums.Key = @enumFromInt(@intFromEnum(dvui.enums.Key.zero) + number);

            key = k;
        } else if (std.meta.stringToEnum(dvui.enums.Key, token)) |k| {
            if (key != null) {
                @compileError("Fuck you rocsktsar games fuck your game fuck your  name.\n");
            }
            key = k;
        } else {
            @compileError("Fuck you rocsktsar games fuck your game fuck your  name. " ++ std.fmt.comptimePrint("{s}\n", .{token}));
        }
    }
    if (key == null) {
        @compileError("Fuck you rocsktsar games fuck your game fuck your  name.\n");
    }

    const key_real_this_time = @intFromEnum(key.?);
    return (@as(u12, mod) << 8) | key_real_this_time;
}

pub fn disablerBox(
    src: std.builtin.SourceLocation,
    box_init: dvui.BoxWidget.InitOptions,
    opts: dvui.Options,
    disable: bool,
) *dvui.BoxWidget {
    const box = dvui.box(src, box_init, opts);
    if (disable) {
        for (dvui.events()) |*e| {
            if (dvui.eventMatch(e, .{
                .id = box.data().id,
                .r = box.data().borderRectScale().r,
            })) {
                e.handle(@src(), box.data());
            }
        }
    }

    return box;
}

pub fn cropPathNullable(path: ?[]const u8) ?[]const u8 {
    if (path == null) return null;
    const p = path.?;
    if (std.mem.findScalarLast(u8, p[0 .. p.len - 1], '/')) |last| {
        return p[last + 1 ..];
    }
    return p;
}

pub fn suggestionBox(
    te: *dvui.TextEntryWidget,
    items: [][]const u8,
) void {
    var b1: [128]u8 = undefined;
    var b2: [128]u8 = undefined;

    const sug = dvui.suggestion(te, .{});
    defer sug.deinit();

    const filter = te.textGet();
    const lower_filter = std.ascii.lowerString(&b1, filter);
    if (sug.dropped()) {
        for (items) |i| {
            const lower_i = std.ascii.lowerString(&b2, i);
            if (std.mem.startsWith(u8, lower_i, lower_filter)) {
                if (sug.addChoiceLabel(i)) {
                    te.textSet(i, true);
                }
            }
        }
    }
}

pub fn findSlice(T: type, slice: []const []const T, pattern: []const T) ?usize {
    for (slice, 0..) |t, i| {
        if (std.mem.eql(T, t, pattern)) {
            return i;
        }
    }
    return null;
}
