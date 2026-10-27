# Desktop and widgets

The desktop is part of MacShell's existing process. It appears on the primary
display selected in Settings and stays below application windows.

- Right-click the wallpaper and choose **Edit Widgets…** to open the gallery.
  Add a size, drag the widget on its grid, then click **Done**. Settings →
  General → Desktop Widgets remains available.
- Widgets initially fill the left side; file icons fill the right side.
- Drop local files or folders from Nautilus onto the desktop to **copy** them.
  Original files stay in place. Name collisions create a separate copy.
- Double-click an icon to open it. Ctrl/Shift-click or draw a rectangle for
  selection. F2 renames; Delete moves selected files to Trash. Right-click
  provides the same actions, New Folder, and Open Desktop in Nautilus.
- Drag icons to reposition them. Layouts are saved and avoid widget footprints.
  If the display is full, the overflow button opens all desktop files in Nautilus.

`bin/desktop_files.py` runs as a child of `DesktopFiles.qml`. It exchanges JSON
over pipes and watches the desktop directory with inotify. Shell reloads own its
lifecycle; no extra autostart/service is needed. Drops pass URLs as data, not
shell commands. Rename never replaces an existing file. Trash uses GIO, with a
same-filesystem freedesktop Trash fallback for bind mounts GIO does not support.

Data locations:

- Desktop folder: `XDG_DESKTOP_DIR` from `user-dirs.dirs`, otherwise `~/Desktop`.
- Icon positions: `$XDG_CONFIG_HOME/macdesktop/layout.json` (default `~/.config`).
- Existing widget preferences/layout: `~/.config/macwidgets/settings.json`.

Backend regression checks:

```sh
python -m unittest discover -s ~/.config/quickshell/MacShell/bin/tests -v
```
