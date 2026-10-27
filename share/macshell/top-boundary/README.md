# MacShell top boundary

The transparent `macbarbg` surface reserves the top bar's height. This plugin
constrains the active floating window's drag geometry before Hyprland commits
it, so holding a window against the boundary does not create a correction
animation. There is no timer or window-move dispatcher.

The boundary uses the monitor's reserved work area and the window's actual
decoration extents. Horizontal dragging remains free. Resizing from the top
preserves the bottom edge, subject to the application's minimum height.
Programmatic placement, Zoom and fullscreen keep their existing geometry path.

`build.sh` compiles against the installed Hyprland headers. The plugin checks
the complete Hyprland API build hash and refuses to hook a different version.
Rebuild it after updating Hyprland. The original Lua timer implementation is
backed up under `~/dock-config-backup/fix-top-boundary-blink-*` and is no longer
loaded by the configuration.

The load directive is at the end of `~/.config/hypr/hyprland.lua`. Apply it with
`hyprctl reload`. A successful native initialization writes
`~/.cache/macshell/top-boundary.status`.
