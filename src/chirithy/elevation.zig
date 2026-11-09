//! Classifies the foreground process of a terminal.
//!
//! The terminal only sees a byte stream, so the one reliable way to tell
//! that a root shell or a remote session is active is to look at the
//! process that currently owns the foreground of the pty.

const std = @import("std");
const builtin = @import("builtin");
const global = @import("../global.zig");
const Elevation = @import("mode.zig").Elevation;

const log = std.log.scoped(.chirithy_elevation);

/// Programs whose keystrokes end up on another machine.
const remote_shells = [_][]const u8{
    "ssh",
    "mosh-client",
    "autossh",
    "sshpass",
    "telnet",
};

/// Classify the process with the given ID. Anything that cannot be
/// determined (the process is gone, procfs is unavailable, the platform is
/// unsupported) is `.none`, since a missing warning is better than a wrong
/// one that never clears.
pub fn detect(pid: u64) Elevation {
    if (comptime builtin.target.os.tag != .linux) return .none;

    // The fields we need are on the first ten lines, which fit comfortably.
    var buf: [1024]u8 = undefined;
    const status = readStatus(&buf, pid) orelse return .none;
    return classify(status);
}

/// Read the head of `/proc/<pid>/status`.
fn readStatus(buf: []u8, pid: u64) ?[]const u8 {
    var path_buf: [64]u8 = undefined;
    const path = std.mem.print(&path_buf, "/proc/{d}/status", .{pid}) catch |err| {
        log.warn("status path does not fit pid={d} err={}", .{ pid, err });
        return null;
    };

    const file = std.Io.Dir.openFileAbsolute(global.io(), path, .{}) catch |err| {
        switch (err) {
            // The process exited between the foreground lookup and now.
            // That happens all the time and is not worth a warning.
            error.FileNotFound => log.debug("foreground process is gone pid={d}", .{pid}),
            else => log.warn("cannot open {s} err={}", .{ path, err }),
        }
        return null;
    };
    defer file.close(global.io());

    var read_buf: [64]u8 = undefined;
    var file_reader = file.reader(global.io(), &read_buf);
    const len = file_reader.interface.readSliceShort(buf) catch |err| {
        log.warn("cannot read {s} err={}", .{ path, err });
        return null;
    };
    return buf[0..len];
}

/// Classify a process from the contents of its procfs status file.
fn classify(status: []const u8) Elevation {
    var name: ?[]const u8 = null;
    var euid: ?u32 = null;

    var lines = std.mem.tokenizeScalar(u8, status, '\n');
    while (lines.next()) |line| {
        if (field(line, "Name:")) |v| {
            name = v;
        } else if (field(line, "Uid:")) |v| {
            // Real, effective, saved and filesystem UID in that order.
            var ids = std.mem.tokenizeAny(u8, v, " \t");
            _ = ids.next();
            const raw = ids.next() orelse continue;
            euid = std.fmt.parseInt(u32, raw, 10) catch |err| {
                log.warn("unparsable effective uid value={s} err={}", .{ raw, err });
                continue;
            };
        }

        if (name != null and euid != null) break;
    }

    // Root wins over remote: `sudo ssh` is still a root process here.
    if (euid) |v| if (v == 0) return .root;

    if (name) |v| for (remote_shells) |candidate| {
        if (std.mem.eql(u8, v, candidate)) return .ssh;
    };

    return .none;
}

/// Returns the trimmed value of `line` if it starts with `key`.
fn field(line: []const u8, key: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, key)) return null;
    return std.mem.trim(u8, line[key.len..], " \t\r");
}

test "classify an ordinary shell" {
    const testing = std.testing;
    try testing.expectEqual(Elevation.none, classify(
        "Name:\tfish\n" ++
            "Umask:\t0022\n" ++
            "State:\tS (sleeping)\n" ++
            "Tgid:\t4242\n" ++
            "Pid:\t4242\n" ++
            "PPid:\t4000\n" ++
            "TracerPid:\t0\n" ++
            "Uid:\t1000\t1000\t1000\t1000\n" ++
            "Gid:\t1000\t1000\t1000\t1000\n",
    ));
}

test "classify by effective uid, not real uid" {
    const testing = std.testing;

    // A setuid binary started by a regular user, e.g. sudo at its prompt.
    try testing.expectEqual(Elevation.root, classify(
        "Name:\tsudo\nUid:\t1000\t0\t0\t0\n",
    ));

    // A root-owned process that dropped privileges is not elevated.
    try testing.expectEqual(Elevation.none, classify(
        "Name:\tping\nUid:\t0\t1000\t1000\t1000\n",
    ));
}

test "classify remote shells" {
    const testing = std.testing;
    try testing.expectEqual(Elevation.ssh, classify(
        "Name:\tssh\nUid:\t1000\t1000\t1000\t1000\n",
    ));
    try testing.expectEqual(Elevation.ssh, classify(
        "Name:\tmosh-client\nUid:\t1000\t1000\t1000\t1000\n",
    ));

    // Names only match exactly.
    try testing.expectEqual(Elevation.none, classify(
        "Name:\tssh-agent\nUid:\t1000\t1000\t1000\t1000\n",
    ));
    try testing.expectEqual(Elevation.none, classify(
        "Name:\tsshd\nUid:\t1000\t1000\t1000\t1000\n",
    ));
}

test "classify prefers root over remote" {
    const testing = std.testing;
    try testing.expectEqual(Elevation.root, classify(
        "Name:\tssh\nUid:\t0\t0\t0\t0\n",
    ));
}

test "classify tolerates malformed input" {
    const testing = std.testing;
    try testing.expectEqual(Elevation.none, classify(""));
    try testing.expectEqual(Elevation.none, classify("garbage"));
    try testing.expectEqual(Elevation.none, classify("Name:\nUid:\n"));
    try testing.expectEqual(Elevation.none, classify("Uid:\t1000\n"));
    try testing.expectEqual(Elevation.none, classify("Uid:\t1000\tabc\n"));

    // A truncated read that still has the fields we need is fine.
    try testing.expectEqual(Elevation.ssh, classify("Name:\tssh\nUma"));
}

test "detect the test runner itself" {
    if (comptime builtin.target.os.tag != .linux) return error.SkipZigTest;

    const testing = std.testing;
    const pid: u64 = @intCast(std.os.linux.getpid());
    const expected: Elevation = if (std.os.linux.geteuid() == 0) .root else .none;
    try testing.expectEqual(expected, detect(pid));

    // A PID beyond the kernel's maximum cannot exist.
    try testing.expectEqual(Elevation.none, detect(std.math.maxInt(u32)));
}
