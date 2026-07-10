const RebindsFile = @This();

const std = @import("std");
const dkct = @import("dkwtct");

const util = dkct.util;
const v = dkct.vars;

const Rebinds = dkct.RebindStack.Rebinds;

const Allocator = std.mem.Allocator;

names: std.ArrayList([]const u8),
rebinds: std.ArrayList(Rebinds),

const empty = RebindsFile{ .rebinds = .empty, .names = .empty };

pub fn deinit(ts: *RebindsFile, gpa: Allocator) void {
    for (ts.names.items) |i| {
        gpa.free(i);
    }
    ts.names.deinit(gpa);

    for (ts.rebinds.items) |*r| {
        r.deinit(gpa);
    }
    ts.rebinds.deinit(gpa);
}

pub const ParseError = error{
    InvalidIdentifier,
    NoTables,
};
pub fn readFromString(gpa: Allocator, input: []const u8) !RebindsFile {
    var rf = RebindsFile.empty;
    errdefer rf.deinit(gpa);

    var tokens = std.mem.tokenizeAny(u8, input, " \n\t");

    var last_token: []const u8 = "";

    while (tokens.next()) |t| {
        if (std.mem.eql(u8, t, "=") or std.mem.eql(u8, t, "return") and bl: {
            last_token = "return";
            break :bl true;
        }) {
            if (tokens.peek()) |nt| {
                if (std.mem.eql(u8, nt, "{")) b: {
                    const between_braces, const closing_brace_idx = util.getBetween(input[tokens.index..], "{}") orelse break :b;
                    var rebinds = dkct.RebindStack.Rebinds.parseLua(gpa, between_braces) catch break :b;
                    errdefer rebinds.deinit(gpa);
                    tokens.index += closing_brace_idx + 1;

                    if (isIdentifier(last_token)) {
                        const owned_name = try gpa.dupe(u8, last_token);
                        try rf.names.append(gpa, owned_name);
                        try rf.rebinds.append(gpa, rebinds);
                    } else {
                        try v.setErrorInfo("{s}", .{last_token});
                        return ParseError.InvalidIdentifier;
                    }
                }
            }
            continue;
        }

        last_token = t;
    }

    if (rf.names.items.len == 0) {
        return ParseError.NoTables;
    }
    return rf;
}

pub fn isIdentifier(token: []const u8) bool {
    if (token.len == 0) return false;
    for (token) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '_' => {},
            else => return false,
        }
    }
    return true;
}
