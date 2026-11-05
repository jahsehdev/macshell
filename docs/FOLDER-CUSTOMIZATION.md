# Customize Folder

Right-click one local folder on the MacShell desktop or in Files (Nautilus)
and choose **Customize Folder…**. The color circles in the context menu apply
a color directly. The popover provides a live folder preview, seven colors,
custom hexadecimal colors, 71 symbols in four categories, and a searchable
emoji picker with categories and recent selections. A symbol and an emoji are
alternative emblems; either can be combined with a folder color.

**Clear** restores the folder's previous custom icon, or the system folder icon
when no previous icon was set. Escape dismisses an open picker before closing
the customization panel. The interface follows MacShell's light/dark palette.
The popover has no close button; use Escape or click outside it on the desktop.
Desktop context-menu actions have aligned outline icons, including the tag
symbol for Customize Folder, a pencil for Rename, and a bin for Move to Trash.

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
pictograms. Emoji use the installed Noto Color Emoji font, and their drawing
differs from Apple's emoji font.

## Installation

The normal `./install.sh` installer includes the interface, launcher, artwork
backend, and native Nautilus integration. Required packages include Nautilus,
GVfs, librsvg (`rsvg-convert`), Fontconfig, Pillow, and Noto Color Emoji.

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
