//! Everything that makes this build Chirithy rather than stock Ghostty.
//!
//! Chirithy-specific behavior lives under this namespace so that the edits
//! to upstream files stay small call sites, which keeps rebasing onto new
//! upstream releases cheap.

pub const elevation = @import("chirithy/elevation.zig");
pub const mode = @import("chirithy/mode.zig");
pub const shaders = @import("chirithy/shaders.zig");
pub const themes = @import("chirithy/themes.zig");

pub const Mode = mode.Mode;

/// The corner a companion sits in. This is the `chirithy-mascot-position`
/// configuration value.
pub const MascotPosition = enum {
    @"bottom-right",
    @"bottom-left",
    @"top-right",
    @"top-left",
};

/// Something that happened on a surface that the apprt may want to show.
///
/// These are delivered through an optional `chirithyEvent` method on the
/// apprt surface instead of an apprt action, so a runtime that has no use
/// for them needs no changes at all.
pub const Event = union(enum) {
    /// The surface entered the given mode.
    mode: Mode,

    /// The shell started running a command. Needs shell integration.
    command_started,

    /// The command finished, with its exit code if the shell reported one.
    /// Needs shell integration.
    command_finished: ?u8,
};

test {
    _ = elevation;
    _ = mode;
    _ = shaders;
    _ = themes;
}
