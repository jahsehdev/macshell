# GNOME native minimize

GTK disables its native minimize action when the compositor omits minimize from
the Wayland `xdg_toplevel.wm_capabilities` event. Hyprland does not provide the
MacShell special-workspace minimize behavior by itself.

This bridge advertises minimize to GNOME Console (`org.gnome.Console` / `kgx`)
and GNOME Calculator (`org.gnome.Calculator` / `gnome-calculator`)
and GNOME Text Editor (`org.gnome.TextEditor` / `gnome-text-editor`)
plus Calendar, Clocks, Contacts, Maps, Loupe (Image Viewer), and Weather
and listens for its native `set_minimized` request. It forwards that request to
`qs -c MacShell ipc call minimize addr <requesting-window-address>`, reusing the
existing Genie/Scale animation, Dock preview and restore path. It targets the
requesting window even if focus changes while the command starts.

It attaches to existing supported windows when loaded and new supported windows
when they map. Closing a window removes its listener. Unloading removes all
listeners and withdraws the additional capability. Other applications retain
their existing controls. No client files, terminal processes or jobs are changed.

Build with `sh build.sh` after updating Hyprland; loading checks the complete
Hyprland API build hash. `~/.config/hypr/hyprland.lua` loads the built plugin.
`~/.cache/macshell/native-minimize.status` records attachment/forward counts.

Verified in the real desktop compositor with a temporary GTK 4 application using
Console's application ID and a native `GtkHeaderBar` / `GtkWindowControls`:

- GDK reports the minimize capability and the native yellow button is enabled.
- Emitting the button's click sends the native request and parks that exact
  window in `special:minimized` through MacShell.
- Restoring through the Dock IPC returns it to workspace 1.
- The temporary window closes normally and the previous application regains focus.
- Hyprland reports no configuration errors.

The test source and results are saved in
`~/dock-config-backup/remove-dock-style-console-minimize-20261025/`.

The Calculator extension uses the same capability and request forwarding path.
After rebuilding, run `~/.local/bin/macshell-minimize-reload` from the desktop
terminal to reload this plugin and attach to already open Calculator windows.
The Calculator change has been compiled locally; live desktop validation must
be performed after reloading because the Codex sandbox cannot access the
compositor socket.

Version 1.2 adds GNOME Text Editor to the same capability and request forwarding
path. Run `~/.local/bin/macshell-minimize-reload` from a desktop terminal to apply
the rebuilt plugin to existing windows without closing documents. This extension
has been compiled locally; its live button and Dock behavior still need to be
checked after reloading on the desktop.

Version 1.3 adds the six GNOME apps above. The installer at
`~/.local/bin/macshell-gnome-apps-setup` installs their native Arch packages,
checks the existing GTK 4 MacTahoe theme, and reloads this bridge. Use
`--check` to validate the local theme and bridge without installing packages.
Compilation is checked locally; validation of the real windows and minimize
buttons requires the desktop session after installing and reloading.
