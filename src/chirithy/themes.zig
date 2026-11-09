//! Color themes compiled into the binary.
//!
//! The default configuration names these themes, so they have to resolve
//! even when the resources directory is missing or belongs to a different
//! build. The same files are also installed next to the bundled themes so
//! they show up in `+list-themes`.

const std = @import("std");

/// Name of the light theme of Spirit mode.
pub const spirit = "Chirithy Spirit";

/// Name of the dark theme of Spirit mode.
pub const spirit_dark = "Chirithy Spirit Dark";

/// Name of the theme of Nightmare mode.
pub const nightmare = "Chirithy Nightmare";

const Entry = struct {
    name: []const u8,
    data: []const u8,
};

const entries = [_]Entry{
    .{ .name = spirit, .data = @embedFile("themes/" ++ spirit) },
    .{ .name = spirit_dark, .data = @embedFile("themes/" ++ spirit_dark) },
    .{ .name = nightmare, .data = @embedFile("themes/" ++ nightmare) },
};

/// Returns the contents of the built-in theme with the given name, or null
/// if the name is not a built-in theme. Names match case-insensitively,
/// like theme file lookups do on case-insensitive filesystems.
pub fn builtin(name: []const u8) ?[]const u8 {
    for (entries) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.data;
    }
    return null;
}

test "builtin resolves every Chirithy theme" {
    const testing = std.testing;
    try testing.expect(builtin(spirit) != null);
    try testing.expect(builtin(spirit_dark) != null);
    try testing.expect(builtin(nightmare) != null);
    try testing.expect(builtin("chirithy spirit") != null);
    try testing.expect(builtin("Chirithy") == null);
    try testing.expect(builtin("") == null);
}

test "builtin themes define a full palette" {
    const testing = std.testing;
    for (entries) |entry| {
        var palette_lines: usize = 0;
        var it = std.mem.tokenizeScalar(u8, entry.data, '\n');
        while (it.next()) |line| {
            if (std.mem.startsWith(u8, line, "palette = ")) palette_lines += 1;
        }
        try testing.expectEqual(@as(usize, 16), palette_lines);
        try testing.expect(std.mem.indexOf(u8, entry.data, "\nbackground = ") != null);
        try testing.expect(std.mem.indexOf(u8, entry.data, "\nforeground = ") != null);
    }
}

/// Test helper: the colors of a theme as WCAG relative luminances.
const Luminances = struct {
    palette: [16]f64,
    background: f64,
    foreground: f64,

    /// The `faint-opacity` of the theme, or Ghostty's default.
    faint_opacity: f64 = 0.5,

    fn parse(data: []const u8) !Luminances {
        var result: Luminances = .{ .palette = undefined, .background = undefined, .foreground = undefined };
        var seen: u32 = 0;
        var it = std.mem.tokenizeScalar(u8, data, '\n');
        while (it.next()) |line| {
            if (std.mem.startsWith(u8, line, "palette = ")) {
                const rest = line["palette = ".len..];
                const eq = std.mem.indexOfScalar(u8, rest, '=') orelse return error.InvalidTheme;
                const index = try std.fmt.parseInt(u8, rest[0..eq], 10);
                if (index >= 16) return error.InvalidTheme;
                result.palette[index] = try luminance(rest[eq + 1 ..]);
                seen |= @as(u32, 1) << @intCast(index);
            } else if (std.mem.startsWith(u8, line, "background = ")) {
                result.background = try luminance(line["background = ".len..]);
                seen |= 1 << 16;
            } else if (std.mem.startsWith(u8, line, "foreground = ")) {
                result.foreground = try luminance(line["foreground = ".len..]);
                seen |= 1 << 17;
            } else if (std.mem.startsWith(u8, line, "faint-opacity = ")) {
                result.faint_opacity = try std.fmt.parseFloat(f64, line["faint-opacity = ".len..]);
            }
        }
        if (seen != (1 << 18) - 1) return error.InvalidTheme;
        return result;
    }

    fn luminance(hex: []const u8) !f64 {
        if (hex.len != 7 or hex[0] != '#') return error.InvalidTheme;
        var channels: [3]f64 = undefined;
        for (&channels, 0..) |*channel, i| {
            const byte = try std.fmt.parseInt(u8, hex[1 + 2 * i ..][0..2], 16);
            const c = @as(f64, @floatFromInt(byte)) / 255.0;
            channel.* = if (c <= 0.04045) c / 12.92 else std.math.pow(f64, (c + 0.055) / 1.055, 2.4);
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
    }

    fn ratio(a: f64, b: f64) f64 {
        return (@max(a, b) + 0.05) / (@min(a, b) + 0.05);
    }
};

test "Spirit Dark keeps its greys apart" {
    // Programs draw secondary text, borders and message backgrounds in the
    // greys, so on a black background each step has to stay visible.
    const testing = std.testing;
    const t = try Luminances.parse(builtin(spirit_dark).?);
    const ratio = Luminances.ratio;

    // Background < black < bright black < white < foreground.
    try testing.expect(t.background < t.palette[0]);
    try testing.expect(t.palette[0] < t.palette[8]);
    try testing.expect(t.palette[8] < t.palette[7]);
    try testing.expect(t.palette[7] < t.foreground);

    // Black is used for panels, so it must stand off the background.
    try testing.expect(ratio(t.palette[0], t.background) >= 1.3);

    // Bright black is used both for dim text and as a background under
    // ordinary text.
    try testing.expect(ratio(t.palette[8], t.background) >= 4.5);
    try testing.expect(ratio(t.foreground, t.palette[8]) >= 4.5);
    try testing.expect(ratio(t.palette[7], t.palette[8]) >= 2);

    // Normal colors work as text and as backgrounds, bright colors as text.
    for (1..7) |i| {
        try testing.expect(ratio(t.palette[i], t.background) >= 4.5);
        try testing.expect(ratio(t.foreground, t.palette[i]) >= 3);
        try testing.expect(ratio(t.palette[i + 8], t.background) >= 7);
    }

    // Faint text is the foreground blended toward the background in linear
    // light. It has to stay readable and still stand apart from ordinary
    // text; at the default opacity it does not on black.
    const faint = t.faint_opacity * t.foreground + (1 - t.faint_opacity) * t.background;
    try testing.expect(ratio(faint, t.background) >= 4.5);
    try testing.expect(ratio(t.foreground, faint) >= 3);
}
