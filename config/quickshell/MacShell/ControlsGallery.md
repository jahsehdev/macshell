# Tahoe Controls Gallery

Open **Control Center → Edit Controls**, or **System Settings → Control Center → Edit Controls…**.
IPC entry point: `qs -c MacShell ipc call controlcenter edit`.

The gallery follows MacShell's light/dark appearance. Search or select a category, then click/right-click a control to add it to Control Center or the menu bar. A blue check marks controls already in Control Center. Drag controls onto either destination to add them directly.

While editing:

- Drag panel controls to reorder; drag them away to remove, or use the minus badge.
- Click a panel control for its placement and size menu. Display, Sound and Now Playing support medium/large; the six added action controls support small/medium/large. Other existing controls keep their supported size.
- Drag pinned icons along the menu bar to reorder, or drag down to remove. Right-click a pinned icon to open its placement menu, including Move Left/Move Right.
- Scroll the panel if its controls exceed the screen height. Reset restores the panel controls and their sizes; Done closes the gallery.

The 12 existing controls retain their backends. Six additions use existing MacShell features:

| Control | Action |
| --- | --- |
| Alarm | Open the Clock app's Alarms tab |
| Stopwatch | Open the Clock app's Stopwatch tab |
| Timer | Open the Clock app's Timers tab |
| Show Desktop | Toggle desktop visibility through DesktopController |
| Capture Screen | Open the existing screenshot region selector |
| Lock Screen | Run the existing MacShell lock action |

Pinned Wi-Fi and Bluetooth icons open their device/network panels; Sound opens the volume panel. Display and Now Playing open Control Center. Other pinned controls invoke their corresponding actions.

Order, sizes and pins persist in `~/.config/macbar/settings.json` using `ccControls`, `ccSizes`, and `barControlPins`. Existing native Wi-Fi, Bluetooth and volume icons are integrated without duplicating their pinned equivalents.

Implementation: `ControlsGallery.qml`, `ControlIcon.qml`, `ControlCatalog.js`, with integration in `UpstreamBar/MacBar.qml` and `MacDock.qml`.

Validation: `python3 ~/.config/quickshell/MacShell/tests/test_controls_gallery.py` exercises the real QML UI and production layout/persistence functions using Qt Quick Test. Theme renders are saved to `/tmp/macshell-controls-light.png` and `/tmp/macshell-controls-dark.png`.

The Tahoe redesign uses an inset sidebar, capsule search, and a consistent blue
Done button. Every catalog control uses the same neutral gray surface with
white symbols and labels, including controls already added. Added controls
retain their check badges. The action menu includes
symbols and rounded selection rows. Hover and press feedback works in both
appearances; keyboard focus remains visible. Categories, preview cards, menu
actions, and Done can be reached by keyboard. Done also accepts Return/Enter.

The selected sidebar category uses the user's solid accent with white text,
matching System Settings. Its color follows the shared accent live in both
appearances and in the compact icon rail.

While dragging directly from Control Center, the original tile, label, and
remove badge follow the pointer; the small shared drag preview is hidden.
Drags from the gallery or menu bar still use that preview. Release or
cancellation clears the source tile reference. `python3 tests/test_control_center_drag.py`
exercises the production tile delegate for wide and circular controls, click
actions, cancellation, dropping outside the grid, and dragging to the menu bar.

All Controls starts with a What’s New card containing a small illustrative
desktop and Control Center preview, rendered by `ControlsPreview.qml`. It has
no device connections or settings side effects. The card scrolls with the
catalog and is hidden when searching or choosing another category.

Below 470 pixels, the sidebar becomes an icon rail with category tooltips,
search moves above the catalog, and wide controls stack without overlapping.
The UI tests also cover this 330-pixel layout, clearing search, keyboard
activation, and the existing drag, pin, size, and persistence behavior.

Additional previews are saved as `/tmp/macshell-controls-connectivity-light.png`,
`/tmp/macshell-controls-connectivity-dark.png`,
`/tmp/macshell-controls-menu-dark.png`, and
`/tmp/macshell-controls-compact-light.png`. These use an isolated controller and
Qt's offscreen software renderer. The desktop shell watches the installed QML
files and reloads them automatically.
