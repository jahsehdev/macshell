# Customize Folder

Right-click one local folder on the MacShell desktop or in Files (Nautilus)
and choose **Customize Folder…**. The color circles in the context menu apply
a color directly. The popover provides a live folder preview, seven colors,
custom hexadecimal colors, 71 symbols in four categories, and a searchable
emoji picker with categories and recent selections. A symbol and an emoji are
alternative emblems; either can be combined with a folder color.

The additional controls provide a portable adaptation of
[Folderify](https://github.com/lgarron/folderify)'s mask-based workflow:

- **Engraved** switches symbols and imported masks between a flat mark and an
  inset fill with opposing highlights and shadows. Emoji retain their colors.
- **Import PNG…** accepts a visible symbol on a transparent background. Empty
  margins are trimmed; the symbol is centered without changing its proportions.
  Imports are limited to 16 MiB and 4096 × 4096 pixels. An immutable copy is kept
  under `$XDG_DATA_HOME/macshell/folder-masks`, so moving or deleting the source
  PNG does not break the folder icon. Selecting a symbol or emoji replaces it.
- **Export…** creates a new `MacShell-*.iconset` directory in the chosen folder,
  containing the ten standard 1×/2× PNG representations from 16px to 1024px.
  Existing exports are never overwritten. Exporting does not modify the folder.

Import and export use Zenity's GTK/GNOME file chooser, following the same desktop
theme, icons and font as Files. They do not use Qt Quick's fallback file dialog.
Import filters PNG files; export selects a directory. Cancel leaves the folder
unchanged. The `zenity` package is included in the dependency installer.

This is a Linux implementation using Pillow, librsvg and the existing MacTahoe
folder material. It does not bundle or run Folderify's Rust binary, redistribute
Apple folder templates, or require `iconutil`/Cocoa. The PNG iconset format can
be consumed separately; `.icns` conversion and Finder icon assignment remain
macOS operations. Colors, custom symbols and emoji continue to work in the
MacShell preview, desktop and Nautilus through the same PNG/GIO integration.

The worker also exposes the workflow from a terminal:

```sh
python3 ~/.config/quickshell/folder-customizer/bin/folder_customizer.py \
  --folder /path/to/folder --mask /path/to/mask.png --style engraved
python3 ~/.config/quickshell/folder-customizer/bin/folder_customizer.py \
  --folder /path/to/folder --export-iconset /path/to/exports
```

**Clear** restores the folder's previous custom icon, or the system folder icon
when no previous icon was set. Escape dismisses an open picker before closing
the customization panel. The interface follows MacShell's light/dark palette.
The popover has no close button; use Escape or click outside it on the desktop.
Desktop context-menu actions have aligned outline icons, including the tag
symbol for Customize Folder, a pencil for Rename, and a bin for Move to Trash.
Button tooltips copy the Dock label's frosted capsule, continuous pointer,
light/dark colors, and typography. They stay inside the window and flip below
their button near the top edge.

The panel layout follows the supplied macOS Tahoe references: preview and name
above the color circles, scrollable symbol categories below a separator, and
Clear/Emoji buttons in the footer. The emoji picker overlaps the symbol panel.
The pointer and panel use one continuous outline with the Dock tooltip's curve.
On the desktop the popover anchors to the selected folder image, with an 8px
gap from its pointer. It flips sides near the left edge and keeps the pointer
aligned vertically when the panel is clamped inside the screen.
The panel is 620px tall and reserves 100px at the bottom of the desktop for the
Dock. Shorter screens reduce the panel height further; the symbol list scrolls
while Clear and Emoji stay in the footer above the Dock.
Folder artwork uses the bundled [MacTahoe SVG](../icons/MacTahoe/places/scalable/folder.svg),
under its [existing license](../icons/MacTahoe/COPYING), with original symbol
pictograms. Emoji prefer an installed, usable **Apple Color Emoji** font, with
**Noto Color Emoji** as the fallback. The picker loads the same font file used
by the artwork renderer. Font changes give emoji artwork a new cache URI.

The optional [samuelngs/apple-emoji-ttf Linux build](https://github.com/samuelngs/apple-emoji-ttf)
can be installed in `~/.local/share/fonts/`, followed by `fc-cache -f` and a
MacShell reload. Use `AppleColorEmoji-Linux.ttf`; its 96px bitmap strike differs
from Noto's 109px strike. The converted font is not bundled with this config;
the upstream MIT license covers its code, not Apple's emoji artwork.

## Installation

The normal `./install.sh` installer includes the interface, launcher, artwork
backend, and native Nautilus integration. Required packages include Nautilus,
GVfs, librsvg (`rsvg-convert`), Fontconfig, Pillow, and Zenity for native file
selection. For emoji, install
**Apple Color Emoji** using the Linux build described above; **Noto Color Emoji**
is supported as a fallback.

To update this feature in an existing installation without reinstalling the
other shell components:

```sh
python3 scripts/install-folder-customizer.py --dry-run
python3 scripts/install-folder-customizer.py
```

The targeted updater backs up replaced files under
`~/.local/state/macshell/backups/folder-customizer-*` and restores them if an
update fails. It does not install packages or restart desktop applications.
The installed launch command is:

```sh
~/.local/bin/macshell-folder-customize /path/to/folder
```

Reload MacShell if its QML file watcher has not picked up the updated desktop.
An already running Nautilus process must be restarted once to load the new
native module; finish file operations first, then run
`~/.local/bin/macshell-nautilus --reload`. All following icon changes update
through the existing desktop inotify/GIO mechanisms.

## Persistence and integration

Settings are stored as the `user.macshell.folder-customization` extended
attribute on the directory. Same-filesystem renames and moves preserve it.
Content-addressed 256px PNGs are retained in
`$XDG_DATA_HOME/macshell/folder-icons`; Nautilus receives their URI through
`metadata::custom-icon`. This uses GVfs metadata in the logged-in desktop
session. The previous custom icon is recorded only on the first edit and
restored by Clear. Failed metadata updates roll back the extended attribute.
The shell's global folder color remains the default for folders without an
individual customization.

Exports preserve the selected color's lightness, retain the theme's original
folder material, and supersample fine symbol details. Renderer changes use a
new cache URI. Existing desktop folders migrate their GIO icon URI when the
desktop worker starts; other folders migrate when the editor opens. The saved
previous icon remains available to Clear. Missing cached exports are rebuilt
from the folder's saved settings. The old renderer's owned PNGs are also
refreshed atomically so existing GIO file-icon references remain usable while
the URI migration is pending.

Supported targets are writable local directories on filesystems supporting
user extended attributes. Files, symbolic links, remote locations, and multiple
selections do not expose the action. Other filesystems or sync/archive tools
may discard extended attributes or GVfs metadata; preservation across those
tools is not promised. MacShell does not add an Apple Finder Tags database.

Nautilus's public menu-provider API supplies the action. A launcher-scoped
bridge adds this one module to the normal extension loader, retains existing
extensions, and adds the inline GTK color row. The loader bridge uses public
GLib/GTK entry points and requires no modification of system binaries or
global GTK settings. Its own preload entry is removed before Nautilus can
launch child applications. A future Nautilus/GTK change to extension discovery
or menu structure may require adapting the bridge; the launcher remains a
separate way to open the editor.

## Validation

```sh
python3 -m unittest discover -s config/quickshell/folder-customizer/tests -p 'test_*.py'
python3 -m unittest discover -s config/quickshell/MacShell/bin/tests -p 'test_desktop_files.py'
config/quickshell/folder-customizer/tests/run-ui-tests.sh
sh share/macshell/folder-customizer/native/test.sh
```

The tests cover real PNG/emoji rendering, on-directory state, rename/move,
Clear and original-icon restoration, metadata/xattr failure rollback, input
validation, desktop actions, picker interactions, and the public Nautilus menu
provider interface. The UI runner captures light/dark, emoji, and context-menu
previews. It runs without a compositor; the environment may report an IPC
socket error because the sandbox denies UNIX sockets. This does not prevent
the offscreen UI tests from running.

Live Wayland menu placement, the inline GTK color row, and cross-application
GVfs updates require the real desktop session. They cannot be fully validated
in the current sandbox, which denies its display and session-bus sockets.
