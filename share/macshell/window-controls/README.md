# Integrated application window controls

Installed on 2026-10-24. Red, yellow and green buttons live inside existing
application rows. A window receives the `macshell-native-controls` Hyprland tag
only after its application reports that its controls are ready. The tag disables
Hyprbars for that individual window. Existing unmodified windows keep their
controls until they are reopened.

| Application | Integration |
| --- | --- |
| Firefox, Nautilus, MacShell Settings and Clock | Existing native controls retained |
| Dolphin | Native Qt widgets prepended to the existing navigation toolbar |
| Kitty | Custom native tab renderer; close preserves running-job confirmation |
| Antigravity IDE | Existing working Electron controls, styled and positioned at the left of its existing title row |
| Spotify | Three buttons in its existing global navigation row |
| Qt Settings | Existing tab row, using Qt's native corner widget |
| Kvantum Manager | Inside the first existing toolbox heading |
| CMake GUI and Video4Linux Test | Existing menu row |
| Network Connections | Existing Add/Edit/Delete toolbar moved above the list, with native GTK buttons |

Dialogs, authentication prompts, and applications without a compatible existing
row retain their original decoration. Video4Linux Capture cannot be checked on
this machine because `/dev/video0` is absent; its wrapper retains Hyprbars if
native controls are unavailable.

Close and reopen affected applications through their usual application icons.
Do not terminate file transfers, editor sessions, or terminal jobs just to reload
their appearance. Hyprland watches its configuration; `hyprctl reload` can also be
used from the desktop session.

## Application copies

System files in `/opt` and `/usr` are unchanged. Antigravity and Spotify use local
overlays under `~/.local/share/macshell/integrated-apps/`. The executables are
copied; other unmodified resources are symlinked. The launcher rebuilds an overlay
when the upstream executable or relevant UI files change. An incompatible
Antigravity API falls back to the original application with its header intact.

Spotify needs one small launcher process while it runs. It exposes only four
window operations over an ephemeral loopback port, authenticated with a random
256-bit token and restricted to Spotify's own web origin. It accepts no GET
actions, arbitrary commands, file requests, credentials, or playback requests.
It stops when its Spotify process exits. Reopening an already running local
Spotify reuses that process and its existing bridge. A Spotify instance already
running from the original installation must be closed normally before the local
copy can become active.

Kitty's custom renderer uses its installed `TabManager` mouse API. Qt and GTK
plugins are selected only by the application-local launchers. Rebuild after an
incompatible toolkit update with `~/.local/share/macshell/window-controls/build.sh`.

## Verification

- Hyprland's actual `--verify-config` reports `config ok`.
- The real Dolphin binary, running offscreen with an isolated settings directory,
  passes close-event, maximize, restore, minimize-helper and duplicate-control
  checks. Its navigation actions retain their order.
- The real Qt Settings, Kvantum Manager, CMake GUI and Video4Linux Test binaries
  display all three native controls in offscreen inspection.
- Eight tests run inside Kitty's own Python environment cover button hit areas,
  close confirmation, correct window targeting, drag cancellation and normal tabs.
- Fourteen Python tests check window targeting and bridge authorization.
- JavaScript tests cover Spotify mounting, accessibility, actions, duplicate
  prevention and Antigravity's readiness/minimize hook. Antigravity's patched
  module passes Node's syntax check.
- GTK 3 and Qt modules build with `-Wall -Wextra -Werror`.
- Local desktop entries and launcher syntax are validated.

Live desktop IPC and loopback binding are unavailable inside the editing sandbox.
Spotify's real CEF transport, Antigravity's live rendering and Network Connections'
live rendering are therefore not verified. The standalone Firefox headless
preview also cannot start successfully in this sandbox. No affected running
application was force-closed.

The actual Dolphin preview is saved as `preview-dolphin.png` in this directory.
The regression checks are in `tests/`.

## Window dragging

Empty space in the existing Qt toolbar, menu row, tab row and inline control
margins initiates a native system move. Buttons, tabs and application content
keep their original input behavior. Network Connections uses GTK's native
move request on its existing toolbar. Spotify and Antigravity declare drag
regions in their existing top rows and exclude interactive controls.

Tabby's local plugin loads `drag.css` on startup, independently of saved Custom
CSS. This survives an older running instance saving its previous appearance
settings on exit. Close and reopen affected applications normally to load the
updated plugins and overlays. Run `hyprctl reload` to refresh the Zoom logic.
Moved Zoom windows retain their new geometry when focus or window rules update;
monitor/workspace changes still recalculate the maximized bounds.

Run `sh tests/check_drag.sh` for offscreen gesture routing, button/tab exclusion,
Zoom geometry regression checks and Tabby plugin checks. Actual compositor
movement still requires testing in the desktop session. Super + left-drag
remains available as the compositor's universal move gesture.

## Restore

Backup and file manifest:
`~/.local/state/macshell/backups/integrated-window-controls-20261024-221024/`.

Run that directory's `restore.py` with Python to restore the previous settings
and remove newly installed integration files. Then close and reopen the affected
applications and run `hyprctl reload` from the desktop session.
