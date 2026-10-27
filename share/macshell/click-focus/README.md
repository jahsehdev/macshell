# MacShell click focus

Hyprland's normal click handler compares the window under the pointer with its
cached active window. It can leave keyboard focus on a previous layer or surface
when the cached window is already the clicked app. Dragging forces a new focus
transition, explaining why moving that app temporarily fixes typing.

This plugin repairs that mismatch on a mouse press before the app receives it.
It only acts when the pointer's window is already active and is still under the
cursor. Focus belonging to the same app (including its popups), layer surfaces,
exclusive shell UI, seat grabs, pointer constraints and the lock screen retain
their normal behavior. It does not focus windows on hover or poll for focus.
Hyprbars may consume a titlebar click; the same repair applies to that click.

Run `sh build.sh` after updating Hyprland. Loading checks the complete API build
hash. `~/.config/hypr/hyprland.lua` loads `click-focus.so` on startup, and a
successful initialization writes `~/.cache/macshell/click-focus.status`.

The Dock uses one activation owner (restore, then focus), and closing Alt+Tab or
the wallpaper picker releases its input region immediately while it fades out.
