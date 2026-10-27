# Tahoe Terminal

A desktop terminal made for this Arch Linux / Hyprland / MacShell setup.
The window controls, compact tab strip, theme inspector, keyboard routing and PTY
integration are custom. Terminal emulation uses xterm.js, rather than an
incomplete ANSI parser. This is an independent GTK3/WebKitGTK application;
Quickshell continues to provide the desktop, menu bar and Dock.

## Run

```sh
tahoe-terminal
tahoe-terminal --working-directory ~/Projects
tahoe-terminal -e /usr/bin/bash --noprofile --norc
```

It also appears as **Tahoe Terminal** in Launchpad and your application menu.
Each tab starts a real login shell with a controlling PTY and job control.
New tabs inherit the current tab's directory. The original terminal remains
available and this app does not replace your default terminal automatically.
The yellow window button uses this desktop's MacShell minimize/restore service
on Hyprland and the ordinary window-manager minimize request elsewhere.

## Customize

The default appearance matches a simple classic macOS terminal: a 23 px gray
title bar, traffic lights, centered shell name, black terminal, block cursor
and small corners. The tab strip appears only when multiple tabs are open;
the toolbar and status bar are hidden initially.

Press **Ctrl+,** or choose **Customize…** from the terminal's right-click menu. Changes save
automatically to `~/.config/tahoe-terminal/settings.json`:

- Light / Dark / Auto; Auto follows `~/.config/macbar/settings.json` live.
- Classic, Tahoe, Ocean, Forest, Rose and Amber color profiles.
- Font family, size, line height, cursor shape and cursor blinking.
- Window opacity and corner radius, terminal padding, scrollback and status bar.
- Shell executable for new tabs.

SF Pro Text is used for the interface and SF Mono for the terminal when those
fonts are installed. The interface falls back to Inter/system fonts and the
terminal to Noto Sans Mono. Opacity uses a transparent native Wayland window;
the compositor supplies the blur. It does not capture other windows.

**Edit custom.css** opens `~/.config/tahoe-terminal/custom.css`. Saving that
file updates the UI immediately. You can override any selector in `web/app.css`.
For example:

```css
:root { --accent: #6894cc; }
.titlebar { height: 58px; min-height: 58px; }
.tab { border-radius: 12px; }
.statusbar { display: none; }
```

User CSS is applied after the app's stylesheet. Changing the terminal's cell
font, size or line spacing should use the inspector so xterm can recalculate
the grid. Shell changes apply to new tabs, not existing sessions.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| New tab / close tab | Ctrl+Shift+T / Ctrl+Shift+W |
| New window | Ctrl+Shift+N |
| Previous / next tab | Ctrl+PageUp / Ctrl+PageDown |
| Copy / paste | Ctrl+Shift+C / Ctrl+Shift+V |
| Find | Ctrl+Shift+F |
| Next / previous search result | Enter / Shift+Enter in search |
| Clear terminal | Ctrl+Shift+K |
| Increase / decrease font | Ctrl++ / Ctrl+- |
| Reset font size | Ctrl+0 |
| Settings | Ctrl+, |
| Fullscreen | F11 |
| Open URL | Ctrl+click |

Ctrl+C, Ctrl+D, Ctrl+Z, normal readline shortcuts and application mouse input
go to the shell. Selecting tabs returns keyboard focus to the terminal. A tab
whose shell has exited can be restarted by pressing Enter. A confirmation is
shown when closing a tab with a separate foreground process.

## Build on Arch Linux

Requires GTK3, WebKitGTK 4.1, json-glib, GLib and a C++20 toolchain. On Arch:

```sh
sudo pacman -S --needed base-devel cmake ninja pkgconf gtk3 webkit2gtk-4.1 json-glib
./install.sh
```

`install.sh` builds, runs the PTY integration tests, and installs in `~/.local`.
Pass another prefix as the first argument if needed. The small xterm browser
assets are vendored in `web/vendor`, so building does not need npm or a network
connection. Their original MIT licenses and exact versions are included.

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel 2
ctest --test-dir build --output-on-failure
build/tahoe-terminal --check
```

The original xterm assets were copied from the installed Antigravity packages
under `/opt/antigravity-ide/resources/app/node_modules/@xterm/`. They are copied
files, not runtime links to that installation. Upstream: https://xtermjs.org/.
The fit helper uses renderer measurements from this pinned xterm version;
review that helper when upgrading the vendored terminal library.

## Source map

| Path | Purpose |
| --- | --- |
| `src/pty.cpp` | PTY, shell spawning, UTF-8 byte transport, resize, output backpressure, process cleanup |
| `src/main.cpp` | Native window, local WebKit bridge, settings, clipboard, file watching |
| `web/index.html` | UI structure and accessible controls |
| `web/app.css` | Editable Tahoe appearance |
| `web/app.js` | Tabs, terminal views, shortcuts, search, settings and focus |
| `tests/` | Real PTY integration, resize, streaming, Ctrl+C |

There is no HTTP server, remote asset loading or Electron runtime. Terminal
bytes are never inserted into HTML; only xterm parses them. Output acknowledgments
bound the renderer queue and feed backpressure to the PTY. No clipboard-writing
terminal addon is enabled. Links open only on user action and only for HTTP(S).
Your shell history remains managed by your shell; this app does not record
terminal output or restore running processes after an application restart.

This first version has tabs and separate windows. Split panes, SSH profile
management, GPU renderer tuning and session restoration are not implemented.
GUI behavior must be checked in a desktop session; automated tests exercise real PTYs.
