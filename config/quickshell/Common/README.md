# Glass defaults and continuous UI corners

## Theme colors and text selection

Appearance → Theme has **Color** (Multicolor or eight fixed accents) and
**Text highlight color** (Automatic, eight colors, or Other… for a custom color).
Multicolor lets each shell app use its preferred accent: Settings, Dock,
Control Center and Launchpad use blue; Clock uses orange. A fixed color
overrides these accents. Functional colors such as warning red remain semantic.

Automatic text highlighting follows the current app accent. A fixed or custom
highlight remains independent when the control accent changes. Light mode uses
a pale selection background; Dark uses a deeper background. Selected text uses
the black or white foreground with the stronger contrast. The Theme card has a
selectable text preview.

`ThemeColors.qml` watches `~/.config/macshell/colors.json` (under
`XDG_CONFIG_HOME` when set). The settings schema is `{mode: "multicolor" | "single",
accent: "#rrggbb", highlight: "automatic" | colorId | "custom",
customHighlight: "#rrggbb"}`. Existing Dock accents are preserved when this file
does not exist; resetting Appearance restores Multicolor / Automatic. Old Dock
and Menu Bar `accent` values remain compatibility snapshots, while the shared
preference owns the live color. Invalid or partial file writes retain the last
valid theme. Only deliberate selections write the preference.

The selection palette applies to editable text in System Settings, Spotlight,
Clipboard and other Menu Bar dialogs, Clock, widget search, desktop renaming,
and Launchpad search/folder renaming. This preference controls MacShell and
Launchpad; external applications retain their toolkit's theme settings.

Behavior follows Apple's [Appearance settings](https://support.apple.com/en-jo/guide/mac-help/mchlp1225/mac)
and [app accent color guidance](https://developer.apple.com/design/human-interface-guidelines/color).
Run the behavior/contrast checks with
`node ~/.config/quickshell/Common/tests/test_theme_colors.cjs`.

## Icon and widget appearance

`AppIcon.qml` keeps the longest visible artwork edge at 87.5% of its icon cell,
matching the original MacTahoe Launchpad icon. Dock, Launchpad, Spotlight and switcher icons
share this default, including icons from inherited themes. `icon_geometry.py`
measures opaque artwork, excludes soft shadows and caches measurements by file
timestamp and size. It uses Pillow and `rsvg-convert`; source artwork stays intact.

Appearance → the card below Theme controls **Default / Dark / Clear / Tinted**
for Dock, Launchpad and folder miniatures, Spotlight app icons, the app switcher,
notification app icons, desktop app/file icons and all desktop widgets.
The photo widget and desktop image thumbnails retain their original pixels.

Default uses original application colors and opaque widgets. Dark has
Always / Auto; Auto resolves to Default while system appearance is light.
Clear has Light / Dark / Auto, translucent silver icons and the existing
refractive widget glass with the Dock's inset edge treatment. Tinted uses dark
opaque widgets with one shared color for their text/graphics and application
icons. Icons provided as flat Linux images are transformed by one shared
shader; this approximates Apple's layered icon variants without replacing
application files. Default bypasses the shader entirely.

Folder color is independent of the control accent; Automatic uses blue.
In Tinted the row becomes **Icon, widget, & folder color**, and Automatic
follows Theme's resolved accent. The separately saved folder preference
returns when leaving Tinted. The custom color picker is available in both rows.
Old per-widget style values are ignored by the renderer, and widget additions
use the global appearance. Existing positions, sizes, content and photo sources
are retained. The old Dock-only Icon Tint controls link to Appearance instead.

`IconStyle.qml` watches `~/.config/macshell/icon-style.json` with schema
`{style, darkAppearance, clearAppearance, folderColor, tintColor}`. The three
appearance fields store IDs shown in the UI (lowercase); color fields accept
`automatic` or `#rrggbb`. The settings persist and synchronize across shell
processes. The Dock owns native folder synchronization; Launchpad reads it.

`sync_icon_style.py` generates a cached folder-only theme under
`~/.local/share/icons/MacShellFolders-*`, inheriting the user's original icon
theme for all application icons. It preserves white paper, folder emblems,
explicitly colored folder variants and all original theme files. GTK3/GTK4,
qt6ct and KDE settings use the same theme, so Nautilus/Dolphin folder colors
match the desktop. Toolkit settings are updated without changing window theme,
fonts or unrelated settings. Already open native file managers may need
reopening if they retain an icon cache. Native themes and generated folder
paths are recorded in `~/.config/macshell/folders/native-state.json`.

Build `icon-style-v1.frag.qsb` using `qsb --qt6` from `icon-style.frag`.
Verify behavior with `node Common/tests/test_icon_style.cjs` and native theme
generation with `python3 Common/tests/test_sync_icon_style.py` (from the
quickshell directory). Tests use isolated directories; they do not recolor
the user's folders.

## Liquid Glass material

Appearance → Liquid Glass offers **Clear** (the existing light blur) and
**Tinted** (maximum backdrop blur, equivalent to the old 80 px Blur slider).
Tinted does not darken the material or add a colour overlay. Both retain
live-backdrop refraction and the existing edge highlights. The
choice applies immediately to MacShell's liquid Dock, tooltips/menus,
Spotlight/Clipboard, Control Center/popovers, liquid desktop widgets,
Launchpad's glass surfaces and MacLock's password, notification and media slabs.
Normal Blur and non-liquid widget styles are unchanged, as are icon tint,
native app themes and each component's layout.

The single preference is saved in `~/.config/macshell/liquidglass.json`;
missing/unknown modes use Clear, preserving existing installations. The Blur
slider is removed; old `glassBlur` values are retained only as Clear's baseline
for backwards compatibility. Glass tint and refraction defaults are 0 and 0.5.
The Glass & Corners card and its preview are removed from System Settings;
these defaults also apply after resetting settings. The Dock uses a 32 px
corner radius and 57% continuous corner smoothing.
The material can also be selected
with `qs -c MacShell ipc call glass material clear` (or `tinted`), and read with
`qs -c MacShell ipc call glass materialMode`.

`GlassMaterial.qml` owns the optical profile and watches the legacy Dock tuning
(`glassOpacity`, `glassLiquid`, `glassBlur`, `glassRim`, `glassGrain`). Those
values now apply across all glass surfaces instead of using separate bar,
Launchpad and lockscreen defaults. Partial settings writes retain the last
valid profile. `GlassMaterial.js` supplies the intensity interpolation.
`LiquidGlassSurface.qml` binds that profile to the rectangular shader uniforms;
components supply their backdrop coordinates, contour and theme. The masked
notch and slider adapters receive the same profile through vector uniforms.
Clear / Tinted only changes the backdrop blur passes, never foreground text/icons.
The material source is **`Common/LiquidGlass.frag`**. It restores MacShell's
previous deep lens, backdrop sampling, white veil, rim lighting and grain.
Dock, bar, menus, widgets, Launchpad and lock-screen slabs all call the same
`shadeGlass()` implementation and use its fine inset highlight. There are no
per-component lens, tint or rim recipes. The notch and slider adapters also call it;
their masks and coordinate mapping remain specific to their geometry.

There are no component-owned Liquid Glass fragment sources. Geometry and
uniform-layout adapters are selected at build time from this one file:

| Adapter | Purpose |
| --- | --- |
| default / Dock | Rounded panel, folder, material preview and inset Dock border |
| bar / lock | Existing bar and lock-screen uniform layouts |
| frosted menu | Compatibility layout; uses the shared lens, tint and rim instead of a separate fixed plate |
| menu / tooltip / portal | Rounded bodies with their existing tails |
| notch / slider | Canvas-mask and local-track coordinate adapters |
| Spotlight / Luma | Existing animated unions and connecting necks |
| text / coat / voice | Glyph, toggle-coat and voice overlays over the shared material |

All `.qsb` adapters live beside the source in `Common/`. They are generated
artifacts for different masks and input layouts, not independently maintained
materials. The standalone SDDM package carries only generated lock/text
binaries; it does not contain another material source.

Each Quickshell configuration accesses these files through its own `Common`
symlink. For example, MacShell uses `Common/LiquidGlass.frag` and UpstreamBar
uses `../Common/LiquidGlass.frag`. Do not resolve outside the configuration
root: Quickshell replaces escaping URLs with `qrc:/qs-blackhole`, even when
the same path exists on the physical filesystem. The shared-glass tests run
the production URLs through Quickshell's VFS and compile the resolved source.

Rebuild every adapter after editing the source:

```sh
python scripts/build-glass-shaders.py
```

This requires Qt 6 `qsb` from `qt6-shadertools`. Dock, bar, Spotlight/Luma and
widget runtime builds also read this same source. Shared-v1 cache names avoid
reusing the replaced material. Settings previews read the bundled Dock adapter.
Appearance preferences and existing pre-blur passes retain their saved values.

Menu-bar dropdowns (Apple/application menus, tray, sound, keyboard,
notifications, Wi-Fi, Bluetooth and calendar) explicitly select the frosted
menu profile. Control Center keeps the shared Liquid Glass material. Frosted
menu blur and tint do not follow the Liquid Glass intensity preference.

Desktop/file/widget context menus and the side Dock and Stage Manager menus
use `FrostedMenuSurface.qml` with the same 42 px pre-blur, bundled frosted-menu
shader, theme tint and MenuBorder hairlines. These surfaces sample a dedicated
wallpaper/backdrop item so the menu cannot capture itself. Reduced transparency,
software rendering and unavailable backdrops retain an opaque themed fallback.

## Corner geometry

Panels, menus, widgets, Launchpad and the lock screen default to a fixed Lamé
softer curve (`n = 2.7`, smoothing 35%). Round buttons, toggles and slider handles explicitly keep their
native circular shape. Panels normalize their radius to 20–32 px; small items adapt to their available
space, while circular controls keep their original radius. The Dock alone reads
`cornerSquircle` from `~/.config/macdock/settings.json`, defaulting to 0.57.
Dock radius and smoothing have no controls in System Settings.

`ContinuousRectangle.qml` creates its curve renderer only for continuous
surfaces with a radius of at least 3 px. Round controls, separators and tiny
radii use native rectangles. Shared normalized samples are cached, and panel
outlines use 16–48 segments per corner, depending on size. Geometry depends
only on dimensions, radius and stroke; colour changes do not recalculate it.
Image masks use the same contour.

`sync_apps.py --once` applies fixed native panel assets and window rounding at
shell startup, preserving original native button artwork. It does not watch Dock
corner settings or regenerate assets when they change. Native apps may need reopening
to reload cached theme assets. Original theme files are retained under
`~/.local/share/macshell/corners/base`.


## Desktop & Dock

`DesktopPreferences.qml` shares validated preferences from
`~/.config/macshell/desktop-dock.json`. Defaults are Bottom, Genie, titlebar Fill,
separate minimized thumbnails, and at most three recent apps. Existing Dock size,
magnification, autohide, bounce, indicators, capture and appearance preferences
remain in `~/.config/macdock/settings.json`. Recent app IDs are saved in
`~/.config/macdock/recent-apps.json`; running and pinned apps are deduplicated.

`SideDock.qml` uses the same keyed cell model and Liquid Glass shader as the
bottom Dock. Its content supports vertical magnification, app menus, pinned app
reordering, running indicators, launch bounce, live previews and autohide.
`DockVisibility.js` drives Smart hide on all Dock edges. It recognizes tiled
windows, compositor fullscreen/maximize, client-only independent Zoom, and
floating Fill geometry against the logical monitor work area. Only mapped,
visible windows on that monitor's displayed workspaces contribute.
Regression checks: `node ~/.config/quickshell/Common/tests/test_dock_visibility.cjs`.
`MacMinimize.qml` chooses an app or minimized-thumbnail target on any Dock edge;
`window-transition.frag.qsb` contains reversible Genie and Scale mappings.
Capture requests are queued, tiled windows keep their tiled state, and stale
minimize records are reconciled with live clients.
Live window capture also keeps its source for minimized windows on every Dock
edge. Saved minimize images are a fallback until live pixels arrive; disabling
Live window capture shows app icons and releases the preview capture sources.

The titlebar helper toggles Fill within the monitor's usable work area, delegates
Zoom to the compositor's native maximize handshake, minimizes through MacShell,
or does nothing. Hyprbars, Settings/Clock, and the application-local Qt/GTK drag
bridges use this preference. Qt/GTK applications already running must be reopened
to load the updated bridge. Applications implementing their own separate titlebar
gestures can retain their application-specific double-click behavior.

Stage Manager starts off. When enabled, `desktop_controller.py` groups windows by
application and monitor/workspace. The sidebar switches stages, accepts a stage
onto another stage (or Add to Current Group), and offers individual windows in
its context menu. The Dock's window menu can add a window to the current group or
separate it. All at Once / One at a Time controls how many windows per app remain
visible. Recent stages can hide until the pointer touches their screen edge.
Cards use snapshots taken when leaving a stage, with app icons before a snapshot
is available. Photos and window contents keep their original colors.

Show Desktop only affects the chosen monitor's current workspace; opening an app
returns to it. Desktop items and widgets have independent normal/Stage visibility
preferences. The controller journals original geometry and PID before parking
windows on its own special workspaces. Disabling Stage Manager, shutting down the
worker, or recovering its journal restores managed windows. Other special
workspaces and minimized windows are left to their own owners.

IPC: `qs -c MacShell ipc call desktop stage true` (or `false`),
`qs -c MacShell ipc call desktop show`, and
`qs -c MacShell ipc call desktop titlebar`.

Validation: `python3 ~/.config/quickshell/MacShell/tests/test_desktop_controller.py`,
`node ~/.config/quickshell/Common/tests/test_desktop_preferences.cjs`, and
`sh ~/.local/share/macshell/window-controls/tests/check_drag.sh`.
Recompile transitions with `/usr/lib/qt6/bin/qsb --qt6 -o window-transition.frag.qsb window-transition.frag`
from the MacShell directory after editing their source.

Behavior references: Apple [Desktop & Dock settings](https://support.apple.com/en-euro/guide/mac-help/mchlp1119/26/mac/26)
and [Dock device management settings](https://support.apple.com/en-ae/guide/deployment/depef1fdf19/web).


## Expanded window corners

`MacShell/bin/window_corners.py` checks rectangles that actually cover the
monitor's logical work area, including native fullscreen, independent Zoom and
floating Fill. With an enabled **Never** hide Dock on that display, rectangles
inside its reserved work area receive `macshell-dock-rounded-window` and inherit
their window-style rounding: toolbar 26px, compact toolbar 20px, titlebar 16px.
26px is the global fallback; explicit application rules select 20px/16px because
Lua `window_rule.rounding` is limited to 20. Wayland has no general toolbar-style
hint, so unknown apps use the fallback. Settings uses 26px and its inset sidebar
16px; Clock uses 20px; terminals and Photo Booth use 16px. Native GTK4 frame cutouts
are delegated to the compositor so an old 24px cutout cannot override this policy.
Settings and Clock's green buttons maximize into the reserved work area.
Rectangles covering the desktop still receive `macshell-square-window`.
Client/internal fullscreen flags alone do not remove rounding:
F11 or HTML fullscreen can leave those flags on a smaller floating window.
The compositor rule at the end of `hyprland.lua` matches this geometry tag only;
it is removed after restore or resize. Settings and Clock use the same geometry
state for their outer frame, keeping inset cards and normal windows rounded.
Firefox's shared stylesheet also removes native CSD clipping in its own expanded
states; Hyprland still applies the normal outer rounding to smaller windows.

Tests: `python3 ~/.config/quickshell/MacShell/tests/test_window_corners.py`.
Rule syntax reference: [Hyprland window rules](https://wiki.hypr.land/configuring/core/rules/window-rules/).


Settings is displayed as **Settings** in the Dock, active application menu and
Alt+Tab. The switcher uses the Dock's window identity map and `settingAppIcon`
source, including the active icon theme's Settings artwork. Current and legacy Settings
window titles are recognized separately from Clock and other Quickshell apps.
Regression check: `node ~/.config/quickshell/MacShell/tests/test_switcher_settings.cjs`.


## Alt+Tab display modes

Settings → Desktop & Dock → App Switcher (Alt + Tab) → Display mode offers
**App Icons** (the default, grouped by application) or **Live Window Previews**
(one card per window, with an app icon, title, live contents and blue selection
outline). `switcherMode` is saved alongside the existing independent material
preference `switcherStyle` in `~/.config/macbar/settings.json`.

The preview grid adapts to logical screen size and scrolls when needed. Tab,
Shift+Tab and arrow keys navigate; releasing Alt or clicking activates the exact
selected window. Closed windows are reconciled without losing a surviving
selection, and minimized/Stage Manager windows restore through their owners.
Live captures exist only while the preview switcher is visible, use the shared
capture admission gate, pause during capture churn/recording, and stop when the
switcher closes. A minimize snapshot or app icon fills the card until live pixels
arrive. The Dock's live-capture preference remains independent.

Regression checks: `node ~/.config/quickshell/MacShell/tests/test_switcher_modes.cjs`
and `node ~/.config/quickshell/MacShell/tests/test_switcher_settings.cjs`.

Click focus: `~/.local/share/macshell/click-focus/click-focus.so` repairs the
specific case where Hyprland still considers the clicked app active but its
keyboard focus belongs elsewhere or is empty. It acts on presses only, including
consumed Hyprbars titlebar clicks, and leaves grabs, exclusive layers, constraints
and the lock screen alone. Rebuild with that directory's `build.sh` after updating
Hyprland; the plugin checks the complete API hash before loading.

The Dock activates a visible app directly once; minimized windows, parked stages
and Show Desktop restoration use their respective owner instead. Closing the
Alt+Tab switcher or wallpaper picker immediately empties the input region even
while its visual fade continues. Dock focus regression checks are in
`tests/test_window_focus.cjs`; seven native compositor checks (including stale
focus repair, consumed titlebar presses, release, grab and valid focus behavior)
passed. The temporary probe was unloaded and its results were saved under
`~/dock-config-backup/click-focus-20261025/`.
