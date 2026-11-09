//! Custom shaders that ship with the build.
//!
//! They are ordinary custom shaders installed into the resources directory
//! and added to `custom-shader` by the config options that enable them, so
//! the renderer treats them exactly like a shader the user wrote.

const std = @import("std");
const Allocator = std.mem.Allocator;
const global = @import("../global.zig");

/// The subdirectory of the resources directory the shaders are installed to.
pub const subdir = "shaders";

pub const Shader = enum {
    /// A streak and a burst of sparkles when the cursor jumps.
    lux_trail,

    /// The name of the shader file, both in the source tree next to this
    /// file and in the installed `subdir`.
    pub fn filename(self: Shader) []const u8 {
        return switch (self) {
            .lux_trail => "lux-trail.glsl",
        };
    }

    /// The shader source as it is in the source tree.
    fn source(comptime self: Shader) []const u8 {
        return @embedFile("shaders/" ++ comptime self.filename());
    }
};

pub const PathError = error{
    OutOfMemory,

    /// The build is not running from an installed tree, so there is no
    /// directory to find the shader in.
    ResourcesDirNotFound,
};

/// The absolute path of an installed shader.
pub fn path(alloc: Allocator, shader: Shader) PathError![:0]const u8 {
    const dir = global.resourcesDir().app() orelse
        return error.ResourcesDirNotFound;
    return try std.fs.path.joinZ(alloc, &.{ dir, subdir, shader.filename() });
}

test "path needs a resources directory" {
    const testing = std.testing;

    // Tests run without one.
    try testing.expectError(
        error.ResourcesDirNotFound,
        path(testing.allocator, .lux_trail),
    );
}

test "bundled shaders compile" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const shadertoy = @import("../renderer/shadertoy.zig");

    // The same conversion the renderer runs when it loads a custom shader.
    inline for (comptime std.enums.values(Shader)) |shader| {
        var glsl_buf: std.Io.Writer.Allocating = .init(alloc);
        defer glsl_buf.deinit();
        try shadertoy.glslFromShader(&glsl_buf.writer, shader.source());
        const glsl = try glsl_buf.toOwnedSliceSentinel(0);
        defer alloc.free(glsl);

        var spv_buf: std.Io.Writer.Allocating = .init(alloc);
        defer spv_buf.deinit();
        try shadertoy.spirvFromGlsl(&spv_buf.writer, null, glsl);

        var spv: std.ArrayListAligned(u8, .of(u32)) = .empty;
        defer spv.deinit(alloc);
        try spv.appendSlice(alloc, spv_buf.written());

        const converted = try shadertoy.glslFromSpv(alloc, spv.items);
        defer alloc.free(converted);
        try testing.expect(converted.len > 0);
    }
}
