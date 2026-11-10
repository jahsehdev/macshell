# MacShell click focus

Hyprland's normal click handler compares the window under the pointer with its
cached active window. It can leave keyboard focus on a previous layer or surface
when the cached window is already the clicked app. Dragging forces a new focus
transition, explaining why moving that app temporarily fixes typing.

This plugin repairs that mismatch on a mouse press before the app receives it.
It only acts when the pointer belongs to a mapped application window still
under the cursor. Inactive windows receive ordinary full-window click focus;
an already-active window only has its stale keyboard surface repaired. Focus belonging to the same app (including its popups), layer surfaces,
exclusive shell UI, seat grabs, pointer constraints and the lock screen retain
their normal behavior. It does not focus windows on hover or poll for focus.
Hyprbars may consume a titlebar click; the same repair applies to that click.

Run `sh build.sh` after updating Hyprland. Loading checks the complete API build
hash. `~/.config/hypr/hyprland.lua` loads `click-focus.so` on startup, and a
successful initialization writes `~/.cache/macshell/click-focus.status`.

The Dock uses one activation owner (restore, then focus), and closing Alt+Tab or
the wallpaper picker releases its input region immediately while it fades out.

Hyprland 0.57 moves the window header and exclusive keyboard layer state.
Version 1.1 supports this API and retains the older header layout. Rebuild the
installed plugin after updating Hyprland, then run
`~/.local/bin/macshell-window-integration-reload` from a desktop terminal. This
reloads click focus and native minimize without closing applications and refuses
to replace loaded integrations if the binary and running compositor commits differ.

Version 1.2 also activates an inactive clicked app. MacShell runs the reload
helper with `--ensure` at startup/reload, preserving current plugins and
replacing outdated versions after validating compositor/build commits.

Focus raises only the selected app. The Hyprland config no longer lowers every
other floating app when a fullscreen window gains focus, and no delayed
fullscreen callback raises a different app after a click. Focus repair does not
minimize clients or change their fullscreen state.
