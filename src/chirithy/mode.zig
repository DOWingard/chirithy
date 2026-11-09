//! Spirit and Nightmare mode.
//!
//! A surface is always in exactly one of the two modes. The mode decides
//! which side of a light/dark theme pair the surface renders with and which
//! companion it shows. Spirit is home. A surface turns to Nightmare while
//! something privileged or remote holds its foreground, which makes the
//! palette a warning about where the next keystrokes are going. Following
//! the desktop color scheme instead is opt-in, because doing both at once
//! would hide that warning from everyone on a dark desktop.

const std = @import("std");
const conditional = @import("../config/conditional.zig");

pub const Mode = enum {
    spirit,
    nightmare,

    /// The conditional theme state a surface in this mode uses.
    pub fn theme(self: Mode) conditional.State.Theme {
        return switch (self) {
            .spirit => .light,
            .nightmare => .dark,
        };
    }
};

/// How the mode of a surface is chosen. This is the `chirithy-mode`
/// configuration value.
pub const Policy = enum {
    /// Decide from the conditions enabled in `Triggers`.
    auto,

    /// Always Spirit.
    spirit,

    /// Always Nightmare.
    nightmare,
};

/// The conditions that put a surface into Nightmare mode under the `auto`
/// policy. This is the `chirithy-nightmare-triggers` configuration value.
pub const Triggers = packed struct {
    /// The desktop prefers a dark color scheme. Off by default: with it
    /// on, a dark desktop is always in Nightmare mode and the other two
    /// conditions can no longer be seen.
    dark: bool = false,

    /// The foreground process of the terminal runs as root.
    root: bool = true,

    /// The foreground process of the terminal is a remote shell client.
    ssh: bool = true,
};

/// What holds the foreground of a terminal, as far as the mode cares.
pub const Elevation = enum {
    /// An ordinary local process.
    none,

    /// A remote shell client: keystrokes leave this machine.
    ssh,

    /// A process with an effective user ID of 0.
    root,
};

/// Everything the mode of a surface depends on.
pub const Inputs = struct {
    policy: Policy = .auto,
    triggers: Triggers = .{},

    /// The color scheme the desktop asks for.
    system: conditional.State.Theme = .light,

    elevation: Elevation = .none,

    pub fn resolve(self: Inputs) Mode {
        return switch (self.policy) {
            .spirit => .spirit,
            .nightmare => .nightmare,
            .auto => if ((self.triggers.dark and self.system == .dark) or
                (self.triggers.root and self.elevation == .root) or
                (self.triggers.ssh and self.elevation == .ssh))
                .nightmare
            else
                .spirit,
        };
    }
};

/// Debounces raw foreground observations into a stable elevation.
///
/// The foreground is sampled on a timer. Entering an elevated state needs
/// several consecutive samples, so a short `sudo` command does not flash the
/// whole palette. Leaving it is immediate: once nothing privileged is in
/// the foreground there is no reason to keep warning.
pub const Tracker = struct {
    /// Consecutive samples required before an elevated state is reported.
    pub const enter_samples = 3;

    /// The elevation last returned from `observe`.
    reported: Elevation = .none,

    /// An elevated state that has been seen but not yet reported.
    candidate: Elevation = .none,
    streak: u8 = 0,

    /// Feed one sample. Returns the new elevation when the stable value
    /// changes, and null when it stays the same.
    pub fn observe(self: *Tracker, seen: Elevation) ?Elevation {
        if (seen == self.reported) {
            self.candidate = .none;
            self.streak = 0;
            return null;
        }

        if (seen != .none) {
            if (seen != self.candidate) {
                self.candidate = seen;
                self.streak = 0;
            }
            self.streak += 1;
            if (self.streak < enter_samples) return null;
        }

        self.candidate = .none;
        self.streak = 0;
        self.reported = seen;
        return seen;
    }

    /// Forget the last reported value after it could not be delivered, so
    /// the next sample reports it again. `previous` is the value that was
    /// reported before the failed one.
    pub fn retract(self: *Tracker, previous: Elevation) void {
        self.reported = previous;
        self.candidate = .none;
        self.streak = 0;
    }
};

test "mode maps onto the theme pair" {
    const testing = std.testing;
    try testing.expectEqual(conditional.State.Theme.light, Mode.spirit.theme());
    try testing.expectEqual(conditional.State.Theme.dark, Mode.nightmare.theme());
}

test "fixed policies ignore every condition" {
    const testing = std.testing;
    try testing.expectEqual(Mode.spirit, (Inputs{
        .policy = .spirit,
        .system = .dark,
        .elevation = .root,
    }).resolve());
    try testing.expectEqual(Mode.nightmare, (Inputs{
        .policy = .nightmare,
        .system = .light,
        .elevation = .none,
    }).resolve());
}

test "auto policy follows enabled triggers" {
    const testing = std.testing;

    // Nothing going on.
    try testing.expectEqual(Mode.spirit, (Inputs{}).resolve());

    // Each trigger on its own.
    const all: Triggers = .{ .dark = true, .root = true, .ssh = true };
    try testing.expectEqual(Mode.nightmare, (Inputs{
        .triggers = all,
        .system = .dark,
    }).resolve());
    try testing.expectEqual(Mode.nightmare, (Inputs{
        .triggers = all,
        .elevation = .root,
    }).resolve());
    try testing.expectEqual(Mode.nightmare, (Inputs{
        .triggers = all,
        .elevation = .ssh,
    }).resolve());

    // A disabled trigger does nothing, the others still work.
    const no_dark: Triggers = .{ .dark = false, .root = true, .ssh = true };
    try testing.expectEqual(Mode.spirit, (Inputs{
        .triggers = no_dark,
        .system = .dark,
    }).resolve());
    try testing.expectEqual(Mode.nightmare, (Inputs{
        .triggers = no_dark,
        .system = .dark,
        .elevation = .root,
    }).resolve());

    const only_dark: Triggers = .{ .dark = true, .root = false, .ssh = false };
    try testing.expectEqual(Mode.spirit, (Inputs{
        .triggers = only_dark,
        .elevation = .root,
    }).resolve());
    try testing.expectEqual(Mode.spirit, (Inputs{
        .triggers = only_dark,
        .elevation = .ssh,
    }).resolve());
}

test "a dark desktop stays in Spirit by default" {
    const testing = std.testing;
    try testing.expectEqual(Mode.spirit, (Inputs{ .system = .dark }).resolve());
    try testing.expectEqual(Mode.nightmare, (Inputs{
        .system = .dark,
        .elevation = .root,
    }).resolve());
    try testing.expectEqual(Mode.nightmare, (Inputs{ .elevation = .ssh }).resolve());
}

test "tracker needs consecutive samples to enter" {
    const testing = std.testing;
    var t: Tracker = .{};

    try testing.expectEqual(@as(?Elevation, null), t.observe(.none));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(@as(?Elevation, .root), t.observe(.root));

    // Stable from here on.
    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(Elevation.root, t.reported);
}

test "tracker ignores a short burst" {
    const testing = std.testing;
    var t: Tracker = .{};

    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.none));

    // The streak starts over.
    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(@as(?Elevation, .root), t.observe(.root));
}

test "tracker leaves immediately" {
    const testing = std.testing;
    var t: Tracker = .{ .reported = .root };
    try testing.expectEqual(@as(?Elevation, .none), t.observe(.none));
    try testing.expectEqual(Elevation.none, t.reported);
}

test "tracker restarts the streak when the candidate changes" {
    const testing = std.testing;
    var t: Tracker = .{};

    try testing.expectEqual(@as(?Elevation, null), t.observe(.ssh));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.ssh));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.root));
    try testing.expectEqual(@as(?Elevation, .root), t.observe(.root));

    // Moving between two elevated states is debounced as well.
    try testing.expectEqual(@as(?Elevation, null), t.observe(.ssh));
    try testing.expectEqual(@as(?Elevation, null), t.observe(.ssh));
    try testing.expectEqual(@as(?Elevation, .ssh), t.observe(.ssh));
}

test "tracker reports again after a retraction" {
    const testing = std.testing;
    var t: Tracker = .{ .reported = .root };

    try testing.expectEqual(@as(?Elevation, .none), t.observe(.none));
    t.retract(.root);
    try testing.expectEqual(Elevation.root, t.reported);
    try testing.expectEqual(@as(?Elevation, .none), t.observe(.none));
}
