# MacShell fullscreen movement lock

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
