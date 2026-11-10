# Default window policy

`window-policy.so` supplies the two global MacShell window defaults:

- New normal app windows occupy 75% of the monitor's available logical work
  area, including any fallback titlebar. Menu-bar and Dock reservations, display
  scale, rotated displays, negative monitor origins, client size limits and the
  existing five-position cascade are accounted for.
- Apps without a native MacShell control integration receive a 34 px reserved
  title row with the existing red, yellow and green assets. This includes
  undecorated clients such as OpenCode and Tayang Studio and unknown app IDs.

Red requests a normal client close, yellow uses MacShell's address-specific Dock
minimize endpoint, and green toggles native maximize/restore through the existing
independent Zoom controller. Dragging empty title-row space uses Hyprland's real
drag controller and therefore retains the fullscreen-lock and top-boundary rules.
The renderer follows the [Hyprland 0.57 decoration API](https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/render/decorations/CHyprBorderDecoration.cpp).

Native integrations acknowledge readiness with `macshell-native-controls`.
Known MacShell-native applications retain their existing controls. The explicit
`macshell-force-controls` tag overrides this exemption for a client that needs
the fallback. A window losing its native-ready tag receives the fallback again.
The fallback uses the GTK MacTahoe light/dark preference at configuration reload.

Initial sizing runs once, 150 ms after map, for floating main windows. Transient
dialogs, modal windows, fixed-size clients, pinned overlays and Launchpad keep
their intended geometry. Actual fullscreen is preserved. Later moves, resizes,
focus changes, configuration reloads and Zoom operations do not reset size.
App minimum sizes can require a window larger than the 75% default.

Build with matching Hyprland headers:

```sh
sh ~/.local/share/macshell/window-policy/build.sh
~/.local/bin/macshell-window-integration-reload --policy-only
```

Reloading attaches missing controls to already open windows without moving them.
To explicitly apply the default size to existing normal app windows as well:

```sh
~/.local/bin/macshell-window-integration-reload --policy-only --normalize
```

The reload helper validates the compositor commit before unloading a plugin or
changing geometry. Installations build this plugin with the other native parts.
Version 1.1 uses `hl.plugin.macshell_window_policy.normalize()` through
`hyprctl eval`. Hyprland 0.57's old `addDispatcherV2` API no longer registers
dispatchers, so the previous `macshell:normalize` command was unavailable.

Version 1.2 fixes normal app detection. Hyprland 0.57 returns true from
`CWindow::desktopComponent()` for every app window; treating it as a background
surface flag skipped both initial sizing and fallback controls for all apps.
The policy now excludes only actual Launchpad surfaces, pinned overlays,
override-redirect surfaces and clients that prevent focus. Existing dialog,
size-limit and fullscreen checks still apply to initial sizing.

## Verification

Version 1.3 recognizes the current `Setting` window title, alongside `Settings`
and `System Settings`, so the preferences window keeps only its own traffic
lights and does not receive a second header.

```sh
c++ -std=c++23 -Wall -Wextra -Werror test_policy.cpp -o /tmp/macshell-window-policy-test
/tmp/macshell-window-policy-test
```

The policy test covers normal app detection, work-area coordinates, monitor origins, frame extents,
cascade boundaries, client constraints, native-ready/force tags and hit targets.
Repository reload tests cover plugin selection, version validation and explicit
normalization. Build and config verification also run against Hyprland 0.57.1.
The editing environment has no `/dev/dri` and cannot reach the user's live IPC
socket, so live rendering, mouse actions and OpenCode/Tayang appearance still
require a desktop-session check.
