//! Everything that makes this build Chirithy rather than stock Ghostty.
//!
//! Chirithy-specific behavior lives under this namespace so that the edits
//! to upstream files stay small call sites, which keeps rebasing onto new
//! upstream releases cheap.

pub const themes = @import("chirithy/themes.zig");

test {
    _ = themes;
}
