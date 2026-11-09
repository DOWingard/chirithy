//! Color themes compiled into the binary.
//!
//! The default configuration names these themes, so they have to resolve
//! even when the resources directory is missing or belongs to a different
//! build. The same files are also installed next to the bundled themes so
//! they show up in `+list-themes`.

const std = @import("std");

/// Name of the light theme, used while in Spirit mode.
pub const spirit = "Chirithy Spirit";

/// Name of the dark theme, used while in Nightmare mode.
pub const nightmare = "Chirithy Nightmare";

const Entry = struct {
    name: []const u8,
    data: []const u8,
};

const entries = [_]Entry{
    .{ .name = spirit, .data = @embedFile("themes/" ++ spirit) },
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

test "builtin resolves both modes" {
    const testing = std.testing;
    try testing.expect(builtin(spirit) != null);
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
