# MacShell fullscreen movement lock

Version 1.6 normalizes the native Wayland green-button request for independent
Zoom. Hyprland's Wayland backend toggles against internal maximize, which stays
zero for independent Zoom; a second click therefore reasserts client maximize
instead of clearing it. The client request hook changes that request to restore
only for mapped floating Wayland Zoom windows in internal=0/client=1. X11,
foreign-toplevel requests, untagged windows, and genuine fullscreen retain their
request semantics. Lua then restores the saved normal geometry.

The hook uses `CWindow::requestClientFullscreen`, because the shorter
`onUpdateState` wrapper is inlined in the installed compositor's backend signal
listener. `native-zoom-restores` in the status file counts corrected requests.
Run `~/.local/bin/macshell-zoom-reload` to load native 1.6 and verify the Lua
controller together; `hyprctl reload` alone cannot replace a loaded plugin.

Version 1.5 keeps the normal arrow at locked window edges and corners. Cursor
selection uses the same resize-lock policy as the drag hook. Hyprland still
handles edge hit testing, restoring normal-window resize cursors, application
text/link cursors, drag-and-drop and special cursor overrides. The symbol check
validates the native border-cursor and shape-override hooks before building.

Version 1.4 removes the Never-hide Dock resize exception. Native fullscreen,
maximize and Zoom reject manual resize. Geometry-only Fill beside a Never-hide
Dock also rejects resize, including `macshell-tiled` Fill with 8px margins.
The rounding tag is checked against current geometry so a restored window with
a stale tag stays resizable. Normal windows, half/quarter tiles and ordinary
tile tear-off keep their behavior. Every interactive resize mode uses the same
hook, including edges, corners and Super + right-drag.

After building, run `~/.local/bin/macshell-resize-reload` in the desktop session.
It validates the compositor commit and reloads only fullscreen-lock. Other
integrations and open applications keep running. A config reload alone does
not replace a library already loaded in memory. Confirm `version 1.6` in
`~/.cache/macshell/fullscreen-lock.status` before testing live gestures.

Historical behavior (superseded by version 1.4):

Version 1.2 permits edge/corner resize (including forced/free aspect-ratio modes)
for floating work-area windows tagged `macshell-dock-rounded-window` by the desktop
controller. This tag requires an enabled Never-hide Dock on that monitor and actual
reserved space. Movement remains locked; fullscreen modes still take precedence
over an older geometry tag. Once resized, the existing Lua Zoom reconciliation
clears client maximize state while keeping the user's rectangle, so the next
Zoom/restore returns to the new size.

After building, run `~/.local/bin/macshell-resize-reload` in the desktop session
to unload the old hook and load version 1.2. A config reload alone does not replace
an already-loaded shared library. No application restart is needed.

Except for Never-hide work-area resize, reject interactive move and resize requests before Hyprland releases fullscreen
or commits any drag geometry. This covers client titlebars, hyprbars, Super with
mouse buttons, and border resizing through their common drag controller.

Native fullscreen/maximize and MacShell's independent Zoom are detected through
the compositor/client states. Floating Fill is detected from its full work-area
rectangle including decorations. Monitor coordinates, scale, rotation and reserved
bar/Dock space use Hyprland's logical work area. Normal restored and half-screen
windows keep dragging. Hidden, pinned and minimized windows are excluded.
Programmatic Zoom/restore and monitor changes keep their original geometry path.

Build with `sh build.sh`. The plugin refuses to hook a different Hyprland API build;
rebuild after updating Hyprland. Its load directive is in `~/.config/hypr/hyprland.lua`.
Apply an updated installation with `~/.local/bin/macshell-resize-reload`. Successful initialization writes
`~/.cache/macshell/fullscreen-lock.status`.

Version 1.1 fixes an initialization failure: `findFunctionsByName` searches
mangled symbols, so the lookup must use `dragBegin` and then filter the demangled
class/overload. The old qualified lookup matched nothing. The build now runs
`python3 -B test_symbols.py` against `/usr/bin/Hyprland` before compiling.
After the previous failed initialization, explicitly retry loading the corrected
plugin from a terminal in the desktop session:

```sh
hyprctl plugin load "$HOME/.local/share/macshell/fullscreen-lock/fullscreen-lock.so"
```

`hyprctl plugin list` should contain `macshell-fullscreen-lock` version `1.1`,
and the status file should contain `version 1.1`. The configured load directive
keeps it enabled on subsequent session starts. Live dragging must be verified
in that desktop session; symbol and policy tests alone do not verify activation.

The policy can be checked with:
`c++ -std=c++20 test_policy.cpp -o /tmp/macshell-fullscreen-policy && /tmp/macshell-fullscreen-policy`.

Compositor paths verified against installed 0.56.2 headers and upstream:
https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/layout/supplementary/DragController.cpp
https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/layout/LayoutManager.cpp
https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/plugins/PluginAPI.cpp
