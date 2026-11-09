<h1>
<p align="center">
  <img src="images/chirithy/icons/256.png" alt="Chirithy" width="128">
  <br>Chirithy
</h1>
<p align="center">
  The Ghostty terminal emulator, themed after the Spirit Dream Eater.
</p>

## About

Chirithy is a build of [Ghostty](https://github.com/ghostty-org/ghostty)
for Linux (GTK). It keeps Ghostty's terminal core, renderer and features
unchanged and adds a theme with behavior:

- **Two modes.** A terminal is in Spirit mode (light) or Nightmare mode
  (dark). Spirit is home. A terminal turns to Nightmare while a root
  process or a remote shell holds its foreground, so the palette is a
  warning about where your keystrokes are going.
- **A companion.** Spirit or Nightmare Chirithy sits in a corner of every
  terminal and reacts to the shell: it perks up while a command runs, jumps
  when one succeeds and shakes when one fails.
- **The Lux trail.** An optional cursor effect: a streak of light and a
  burst of sparkles when the cursor jumps.
- **The Final World.** An optional background: an endless sky over still
  water, by day in Spirit mode and by night in Nightmare mode.
- **Chirithy chrome.** Its own icon, and tabby stripes on the header and tab
  bars.

The executable is `chirithy`. Everything Ghostty documents at
<https://ghostty.org/docs> still applies; only the differences are listed
here.

## Modes

| Mode      | Theme                | Companion          | When                                             |
| --------- | -------------------- | ------------------ | ------------------------------------------------ |
| Spirit    | `Chirithy Spirit`    | Spirit Chirithy    | By default                                       |
| Nightmare | `Chirithy Nightmare` | Nightmare Chirithy | The foreground process is root or a remote shell |

The default theme is `light:Chirithy Spirit,dark:Chirithy Nightmare`. Spirit
mode uses the light half of that pair and Nightmare mode the dark half. If
you set `theme` to a single theme, the mode still decides which companion is
shown but no longer changes colors.

The mode is tracked per terminal, so one split can be in Nightmare mode
while the one next to it stays in Spirit mode.

Root and remote detection work as follows:

- Linux only. The process that owns the foreground of the terminal is read
  from procfs: an effective user ID of 0 counts as root, and a process named
  `ssh`, `mosh-client`, `autossh`, `sshpass` or `telnet` counts as remote.
- Only the terminal's own foreground process is visible. A root shell inside
  tmux, or `sudo` on the far end of an SSH session, cannot be seen.
- The foreground is sampled five times per second while the terminal is
  focused. A condition must hold for about half a second before the mode
  changes, so a quick `sudo` command does not flash the whole palette.
  Leaving Nightmare mode is immediate.

Programs that enable color scheme reports (mode 2031) are told about mode
changes, so an editor can follow the terminal into the other palette.

## Configuration

Configuration lives in `$XDG_CONFIG_HOME/chirithy/config.ghostty`, usually
`~/.config/chirithy/config.ghostty`. The file format and every Ghostty
option are unchanged. `~/.config/ghostty` is not read.

| Option                        | Default        | Meaning                                                                    |
| ----------------------------- | -------------- | -------------------------------------------------------------------------- |
| `chirithy-mode`               | `auto`         | `auto`, `spirit` or `nightmare`. The last two pin the mode.                |
| `chirithy-nightmare-triggers` | `root,ssh`     | What turns `auto` to Nightmare: `root`, `ssh`, `dark`. Prefix `no-` to disable one. |
| `chirithy-mascot`             | `true`         | Show the companion.                                                        |
| `chirithy-mascot-size`        | `96`           | Height of the companion in pixels, from 32 to 512.                         |
| `chirithy-mascot-position`    | `bottom-right` | `bottom-right`, `bottom-left`, `top-right` or `top-left`.                  |
| `chirithy-cursor-trail`       | `false`        | Enable the Lux trail.                                                      |
| `chirithy-final-world`        | `false`        | Use the Final World as the background.                                     |

Some common setups:

```ini
# Follow the desktop color scheme as well: Nightmare on a dark desktop.
chirithy-nightmare-triggers = dark

# Always dark, companion in the top right corner, with the cursor effect.
chirithy-mode = nightmare
chirithy-mascot-position = top-right
chirithy-cursor-trail = true
```

The `dark` trigger is off by default on purpose. With it on, a dark desktop
keeps every terminal in Nightmare mode, and the root and remote warnings can
no longer be seen.

## The companion

The companion reacts to shell integration marks (OSC 133), which Ghostty's
shell integration emits automatically for bash, zsh, fish, elvish and
nushell. Without shell integration it still shows the mode but does not
react to commands.

| State              | What you see                             |
| ------------------ | ---------------------------------------- |
| Terminal unfocused | Faded and grey: it is asleep             |
| Command running    | Fully opaque and slightly raised         |
| Command succeeded  | A jump                                   |
| Command failed     | A shake                                  |
| Terminal too small | Hidden, so it never crowds a small split |

It is an overlay on top of the terminal rather than part of the renderer.
It only causes redraws during its one second reactions, never while idle,
and never in an unfocused terminal. It takes no pointer or keyboard input,
so text underneath it stays selectable and clickable.

## The Lux trail

`chirithy-cursor-trail = true` adds a bundled custom shader. It reacts to
cursor jumps of more than a cell or two (a new prompt, a jump in an editor)
and ignores typing and scrolling output. It is tinted with the cursor color.

It is off by default because any animated custom shader makes the focused
terminal render every frame instead of only when something changes. It also
needs `custom-shader-animation` left at its default.

## The Final World

`chirithy-final-world = true` sets `background-image` to a bundled image for
the current mode and `background-image-fit` to `cover`. The image follows
the mode, including when `theme` is a single theme. It does nothing if you
set `background-image` yourself; `background-image-opacity` still applies.

Both images are soft gradients blended toward the theme background, so text
stays readable on top of them.

## What is unchanged

These stay exactly as in Ghostty so that programs and remote hosts that know
about Ghostty keep working:

- `TERM` is `xterm-ghostty`, with the same terminfo entry.
- `TERM_PROGRAM` is `ghostty`, and the `GHOSTTY_*` environment variables
  keep their names.
- Resources are installed under `share/ghostty`.

## Building and installing

Requirements beyond those of Ghostty itself:

- Zig 0.17
- `blueprint-compiler` 0.20 or newer
- GTK 4.18 and libadwaita 1.7 or newer

```sh
zig build \
  -Doptimize=ReleaseFast \
  -Dinstalled-exe-path="$HOME/.local/bin/chirithy" \
  --prefix "$HOME/.local"
```

`-Dinstalled-exe-path` writes the absolute path of the executable into the
desktop entry and the D-Bus and systemd units. It is needed for any prefix
other than `/usr` or `/usr/local`.

Run the tests for the Chirithy-specific code with:

```sh
zig build test \
  -Dtest-filter=tracker -Dtest-filter=classify -Dtest-filter=polic \
  -Dtest-filter=builtin -Dtest-filter="bundled shaders" \
  -Dtest-filter="Final World"
```

## Scope

Only the Linux GTK application is rebranded and themed. The macOS app, the
Flatpak, Snap and Nix packaging and `libghostty` are carried along from
upstream unmodified and still use the Ghostty names.

Chirithy-specific Zig code lives in `src/chirithy/` and
`src/apprt/gtk/class/chirithy_mascot.zig`. The changes to upstream files are
kept to small call sites so that rebasing onto a new Ghostty release stays
cheap.

## Credits and license

Chirithy is built on Ghostty by Mitchell Hashimoto and the Ghostty
contributors, and is distributed under the same MIT license. See `LICENSE`.

Chirithy is a character from the Kingdom Hearts series. The character and
the artwork under `images/chirithy/` belong to Square Enix and Disney. This
is an unofficial fan project for personal use, with no affiliation to or
endorsement by either company; the MIT license does not cover that artwork.
