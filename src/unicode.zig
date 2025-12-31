pub fn hexNibble(n: u16) u8 {
    return if (n < 10)
        @intCast('0' + n)
    else
        @intCast('A' + (n - 10));
}

pub const HexParseError = error{
    InvalidFirstChar,
    InvalidChar,
    Overflow,
};

pub fn parseHexUnicode(unicode: []const u8) !u21 {
    if (unicode.len < 2) return HexParseError.InvalidChar;
    if (unicode[0] != 'U' and unicode[0] != 'u')
        return HexParseError.InvalidFirstChar;

    var acc: u21 = 0;

    for (unicode[1..]) |c| {
        const n: u21 = parseHexDigit(c) orelse
            return HexParseError.InvalidChar;

        // acc = acc * 16 + n with overflow check
        if (acc > (0x10FFFF - n) / 16)
            return HexParseError.Overflow;

        acc = acc * 16 + n;
    }

    if (acc > 0x10FFFF)
        return HexParseError.Overflow;

    return acc;
}

pub fn parseHexDigit(digit: u8) ?u8 {
    return switch (digit) {
        '0'...'9' => digit - '0',
        'a'...'f' => digit - 'a' + 10,
        'A'...'F' => digit - 'A' + 10,
        else => null,
    };
}

pub fn codepointToUnicode(codepoint: u21) [5]u8 {
    const x: u16 = @intCast(codepoint & 0xFFFF);

    return .{
        'U',
        hexNibble((x >> 12) & 0xF),
        hexNibble((x >> 8) & 0xF),
        hexNibble((x >> 4) & 0xF),
        hexNibble(x & 0xF),
    };
}
