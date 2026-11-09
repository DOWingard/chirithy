//! Background images that ship with the build.
//!
//! They are ordinary images installed into the resources directory and
//! assigned to `background-image` by the config option that enables them,
//! so the renderer treats them exactly like an image the user picked.

const std = @import("std");
const Allocator = std.mem.Allocator;
const global = @import("../global.zig");
const Mode = @import("mode.zig").Mode;

/// The subdirectory of the resources directory the images are installed to.
pub const subdir = "backgrounds";

pub const Background = enum {
    /// An endless sky over still water.
    final_world_spirit,

    /// The same view at night, with a single light on the horizon.
    final_world_nightmare,

    /// The Final World as it looks in the given mode.
    pub fn finalWorld(mode: Mode) Background {
        return switch (mode) {
            .spirit => .final_world_spirit,
            .nightmare => .final_world_nightmare,
        };
    }

    /// The name of the image file, both in the source tree next to this
    /// file and in the installed `subdir`.
    pub fn filename(self: Background) []const u8 {
        return switch (self) {
            .final_world_spirit => "final-world-spirit.jpg",
            .final_world_nightmare => "final-world-nightmare.jpg",
        };
    }
};

pub const PathError = error{
    OutOfMemory,

    /// The build is not running from an installed tree, so there is no
    /// directory to find the image in.
    ResourcesDirNotFound,
};

/// The absolute path of an installed background image.
pub fn path(alloc: Allocator, background: Background) PathError![:0]const u8 {
    const dir = global.resourcesDir().app() orelse
        return error.ResourcesDirNotFound;
    return try std.fs.path.joinZ(alloc, &.{ dir, subdir, background.filename() });
}

test "every mode has a Final World" {
    const testing = std.testing;
    try testing.expectEqual(Background.final_world_spirit, Background.finalWorld(.spirit));
    try testing.expectEqual(Background.final_world_nightmare, Background.finalWorld(.nightmare));
}

test "every background exists in the source tree" {
    // Embedding fails the build if a file name does not match a real file.
    inline for (comptime std.enums.values(Background)) |background| {
        const data = @embedFile("backgrounds/" ++ comptime background.filename());

        // JPEG files start with the SOI marker.
        try std.testing.expect(data.len > 2);
        try std.testing.expectEqual(@as(u8, 0xFF), data[0]);
        try std.testing.expectEqual(@as(u8, 0xD8), data[1]);
    }
}

test "path needs a resources directory" {
    const testing = std.testing;

    // Tests run without one.
    try testing.expectError(
        error.ResourcesDirNotFound,
        path(testing.allocator, .final_world_spirit),
    );
}
