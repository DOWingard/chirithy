const std = @import("std");
const adw = @import("adw");
const gdk = @import("gdk");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const chirithy = @import("../../../chirithy.zig");
const configpkg = @import("../../../config.zig");
const gresource = @import("../build/gresource.zig");
const Common = @import("../class.zig").Common;

const log = std.log.scoped(.gtk_chirithy_mascot);

const art = gresource.mascot;

/// The companion that sits in a corner of a surface.
///
/// It shows Spirit Chirithy or Nightmare Chirithy depending on the mode of
/// the surface, and reacts to what the shell is doing. It is purely an
/// overlay widget: it never touches the terminal renderer, and it only
/// causes redraws while one of its short reactions plays.
///
/// General usage:
///
///   1. Add it to an overlay over the terminal.
///   2. Keep it up to date with `setConfig`, `setMode`, `setAwake` and
///      `setRoom`.
///   3. Report shell activity with `setBusy` and `react`.
pub const ChirithyMascot = extern struct {
    const Self = @This();
    parent_instance: Parent,
    pub const Parent = adw.Bin;
    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "ChirithyMascot",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    /// Something the companion visibly responds to.
    pub const Reaction = enum {
        /// A jump: a command succeeded, or the companion says hello.
        cheer,

        /// A shake of the head: a command failed.
        worry,
    };

    /// The smallest and largest height the companion can be configured to.
    const min_height = 32;
    const max_height = 512;

    /// The companion is hidden unless the surface is at least this many
    /// times its width and height, so it never dominates a small split.
    const room_factor_width = 5;
    const room_factor_height = 3;

    /// How long the CSS reactions run. These have to cover the durations
    /// of the matching animations in the stylesheet.
    const hop_ms = 850;
    const shake_ms = 550;

    const Private = struct {
        /// Template children.
        clamp: *adw.Clamp,
        picture: *gtk.Picture,

        /// GObject zeroes private data, so everything below starts out as
        /// zero and is given its real initial value in `init`.
        mode: chirithy.Mode,

        /// Whether the config asks for the companion at all.
        enabled: bool,

        /// Whether the surface is large enough to show it.
        has_room: bool,

        /// Whether the surface has focus.
        awake: bool,

        /// Whether the hello jump has been played.
        greeted: bool,

        /// Height in pixels the companion is displayed at.
        height: c_int,

        /// The Spirit animation frame currently shown.
        frame: usize,

        /// Timer driving the Spirit frame animation.
        frame_timer: ?c_uint,

        /// Timer that ends a CSS reaction.
        reaction_timer: ?c_uint,

        pub var offset: c_int = 0;
    };

    /// The decoded images. They are identical for every surface, so they
    /// are loaded once, on first use, and kept for the life of the process.
    /// Only ever touched from the main thread.
    const Textures = struct {
        spirit: [art.spirit_frames]*gdk.Texture,
        nightmare: *gdk.Texture,

        var shared: ?Textures = null;

        fn get() *const Textures {
            if (shared) |*v| return v;

            const start = glib.getMonotonicTime();
            var result: Textures = undefined;
            inline for (0..art.spirit_frames) |i| {
                result.spirit[i] = gdk.Texture.newFromResource(
                    comptime art.spiritFrame(i),
                );
            }
            result.nightmare = gdk.Texture.newFromResource(art.nightmare);
            shared = result;

            log.info("loaded mascot textures count={d} elapsed_us={d}", .{
                art.spirit_frames + 1,
                glib.getMonotonicTime() - start,
            });
            return &shared.?;
        }
    };

    fn init(self: *Self, _: *Class) callconv(.c) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));

        const priv = self.private();
        priv.mode = .spirit;
        priv.enabled = true;
        priv.has_room = true;
        priv.awake = false;
        priv.greeted = false;
        priv.height = 0;
        priv.frame = 0;
        priv.frame_timer = null;
        priv.reaction_timer = null;

        // Unfocused until the surface says otherwise.
        self.as(gtk.Widget).addCssClass("asleep");

        self.setHeight(96);
        self.showFrame();
    }

    //---------------------------------------------------------------
    // Public API

    /// Apply the companion-related configuration.
    pub fn setConfig(self: *Self, config: *const configpkg.Config) void {
        const priv = self.private();
        priv.enabled = config.@"chirithy-mascot";

        const requested = config.@"chirithy-mascot-size";
        const height = std.math.clamp(requested, min_height, max_height);
        if (height != requested) log.warn(
            "chirithy-mascot-size out of range, clamping requested={d} used={d}",
            .{ requested, height },
        );
        self.setHeight(height);

        const widget = self.as(gtk.Widget);
        const halign: gtk.Align, const valign: gtk.Align =
            switch (config.@"chirithy-mascot-position") {
                .@"bottom-right" => .{ .end, .end },
                .@"bottom-left" => .{ .start, .end },
                .@"top-right" => .{ .end, .start },
                .@"top-left" => .{ .start, .start },
            };
        widget.setHalign(halign);
        widget.setValign(valign);

        self.syncVisible();
    }

    /// Show the companion that belongs to the given mode.
    pub fn setMode(self: *Self, mode: chirithy.Mode) void {
        const priv = self.private();
        if (priv.mode == mode) return;
        log.debug("mascot mode changed mode={t}", .{mode});
        priv.mode = mode;

        // Whatever was playing belonged to the other companion.
        self.stopReactions();
        self.showFrame();
    }

    /// Wake the companion up or let it doze off. It should be awake
    /// exactly while its surface has focus.
    pub fn setAwake(self: *Self, awake: bool) void {
        const priv = self.private();
        if (priv.awake == awake) return;
        priv.awake = awake;

        const widget = self.as(gtk.Widget);
        if (awake) {
            widget.removeCssClass("asleep");
            self.greet();
        } else {
            // A sleeping companion stays still so that unfocused surfaces
            // never cause redraws.
            self.stopReactions();
            self.showFrame();
            widget.addCssClass("asleep");
        }
    }

    /// Mark whether the shell is busy running a command.
    pub fn setBusy(self: *Self, busy: bool) void {
        const widget = self.as(gtk.Widget);
        if (busy) {
            widget.addCssClass("busy");
        } else {
            widget.removeCssClass("busy");
        }
    }

    /// Tell the companion how large its surface is, in the same units as
    /// its own size, so it can step aside when there is no room for it.
    pub fn setRoom(self: *Self, width: c_int, height: c_int) void {
        const priv = self.private();
        const own_width = widthFor(priv.height);
        const has_room = width >= own_width * room_factor_width and
            height >= priv.height * room_factor_height;
        if (priv.has_room == has_room) return;

        log.debug("mascot room changed has_room={} surface={d}x{d}", .{
            has_room,
            width,
            height,
        });
        priv.has_room = has_room;
        self.syncVisible();
    }

    /// Play a reaction. This does nothing while the companion is hidden or
    /// asleep, since nobody would see it.
    pub fn react(self: *Self, reaction: Reaction) void {
        const priv = self.private();
        if (!priv.awake) return;
        if (self.as(gtk.Widget).getMapped() == 0) return;

        self.stopReactions();
        switch (reaction) {
            .cheer => switch (priv.mode) {
                // The Spirit companion has real animation frames.
                .spirit => {
                    priv.frame = 0;
                    priv.frame_timer = glib.timeoutAdd(
                        art.spirit_frame_ms,
                        onFrameTimer,
                        self,
                    );
                },

                // The Nightmare companion is a still image, so its jump
                // is a CSS animation of the whole widget.
                .nightmare => self.startCssReaction("hop", hop_ms),
            },

            .worry => self.startCssReaction("worried", shake_ms),
        }
    }

    //---------------------------------------------------------------
    // Internals

    /// Say hello with a jump, once, the first time the companion is both
    /// on screen and awake.
    fn greet(self: *Self) void {
        const priv = self.private();
        if (priv.greeted) return;
        if (!priv.awake) return;
        if (self.as(gtk.Widget).getMapped() == 0) return;
        priv.greeted = true;
        self.react(.cheer);
    }

    /// The width that goes with a height, from the aspect of the images.
    fn widthFor(height: c_int) c_int {
        const h: f64 = @floatFromInt(height);
        return @max(1, @as(c_int, @intFromFloat(@round(h * art.aspect))));
    }

    fn setHeight(self: *Self, height: c_int) void {
        const priv = self.private();
        if (priv.height == height) return;
        priv.height = height;

        // The clamp scales the picture down to this width and the size
        // request scales it up to it, so the two together pin the width.
        // The picture derives its height from its width.
        const width = widthFor(height);
        priv.clamp.setMaximumSize(width);
        priv.clamp.setTighteningThreshold(width);
        priv.picture.as(gtk.Widget).setSizeRequest(width, -1);
    }

    fn syncVisible(self: *Self) void {
        const priv = self.private();
        const visible = priv.enabled and priv.has_room;
        if (!visible) self.stopReactions();
        self.as(gtk.Widget).setVisible(@intFromBool(visible));
    }

    /// Put the image for the current mode and frame on screen.
    fn showFrame(self: *Self) void {
        const priv = self.private();
        const textures = Textures.get();
        const texture = switch (priv.mode) {
            .spirit => textures.spirit[priv.frame],
            .nightmare => textures.nightmare,
        };
        priv.picture.setPaintable(texture.as(gdk.Paintable));
    }

    fn startCssReaction(self: *Self, class: [:0]const u8, duration_ms: c_uint) void {
        const priv = self.private();
        self.as(gtk.Widget).addCssClass(class);
        priv.reaction_timer = glib.timeoutAdd(
            duration_ms,
            onReactionTimer,
            self,
        );
    }

    /// Cancel any reaction and return to the resting pose.
    fn stopReactions(self: *Self) void {
        const priv = self.private();
        if (priv.frame_timer) |v| {
            if (glib.Source.remove(v) == 0) {
                log.warn("unable to remove mascot frame timer", .{});
            }
            priv.frame_timer = null;
        }
        if (priv.reaction_timer) |v| {
            if (glib.Source.remove(v) == 0) {
                log.warn("unable to remove mascot reaction timer", .{});
            }
            priv.reaction_timer = null;
        }

        const widget = self.as(gtk.Widget);
        widget.removeCssClass("hop");
        widget.removeCssClass("worried");
        priv.frame = 0;
    }

    fn onFrameTimer(ud: ?*anyopaque) callconv(.c) c_int {
        const self: *Self = @ptrCast(@alignCast(ud orelse return 0));
        const priv = self.private();

        priv.frame += 1;
        if (priv.frame >= art.spirit_frames) {
            // Back to the resting pose. Returning 0 removes the source.
            priv.frame = 0;
            priv.frame_timer = null;
            self.showFrame();
            return 0;
        }

        self.showFrame();
        return 1;
    }

    fn onReactionTimer(ud: ?*anyopaque) callconv(.c) c_int {
        const self: *Self = @ptrCast(@alignCast(ud orelse return 0));
        const priv = self.private();
        priv.reaction_timer = null;

        const widget = self.as(gtk.Widget);
        widget.removeCssClass("hop");
        widget.removeCssClass("worried");
        return 0;
    }

    //---------------------------------------------------------------
    // Template callbacks

    fn mapped(_: *gtk.Widget, self: *Self) callconv(.c) void {
        self.greet();
    }

    //---------------------------------------------------------------
    // Virtual methods

    fn dispose(self: *Self) callconv(.c) void {
        self.stopReactions();

        gtk.Widget.disposeTemplate(
            self.as(gtk.Widget),
            getGObjectType(),
        );

        gobject.Object.virtual_methods.dispose.call(
            Class.parent,
            self.as(Parent),
        );
    }

    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    const private = C.private;

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;
        pub const Instance = Self;

        fn init(class: *Class) callconv(.c) void {
            gtk.Widget.Class.setTemplateFromResource(
                class.as(gtk.Widget.Class),
                comptime gresource.blueprint(.{
                    .major = 1,
                    .minor = 0,
                    .name = "chirithy-mascot",
                }),
            );

            // Bindings
            class.bindTemplateChildPrivate("clamp", .{});
            class.bindTemplateChildPrivate("picture", .{});

            // Template callbacks
            class.bindTemplateCallback("mapped", &mapped);

            // Virtual methods
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }

        pub const as = C.Class.as;
        pub const bindTemplateChildPrivate = C.Class.bindTemplateChildPrivate;
        pub const bindTemplateCallback = C.Class.bindTemplateCallback;
    };
};
