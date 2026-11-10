# Integrated application window controls

The global [window policy](../window-policy/README.md) now supplies fallback
traffic lights for clients without a native integration and applies the default
75% work-area size to new main windows. The native integrations below remain the
preferred controls; their ready tag prevents a second titlebar.

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

Spotify needs one small launcher process while it runs. It exposes only five
window operations over a user-local loopback port, authenticated with a random
256-bit token and restricted to Spotify's own web origin. It accepts no GET
actions, arbitrary commands, file requests, credentials, or playback requests.
It stops when its Spotify process exits. Reopening an already running local
Spotify reuses that process and its existing bridge. A Spotify instance already
running from the original installation must be closed normally before the local
copy can become active.

The local `spotify.desktop` entry starts `macshell-spotify`, which preserves
`~/.config/spotify-flags.conf` and forwards Spotify URI arguments to the overlay.
The native menu inset patch supports the verified 1.3.4.258 and 1.3.8.620
executables. Other builds retain the original application until their menu
layout has been inspected; both the executable hash and instruction bytes must
match before a local copy is patched.

Spotify's connection port and token persist in the private integrated-apps
directory, so cached HTML can reconnect after a relaunch. The injected JS and
CSS URLs include a content revision, and the readiness handshake retries when
the window has not mapped yet. Failed button actions expose a reconnect hint
in the button tooltip rather than disappearing silently.

On XWayland, `spotify-drag.so` starts a real Hyprland drag from blank navigation
space. The launcher loads it only when its build commit matches the compositor.
It verifies Spotify's active PID and the held left button, then calls the native
drag controller with an exclusive device grab. Movement, release outside the
app, and the existing fullscreen lock use the compositor's normal behavior.
An ignored X11 move message is no longer treated as a successful drag. Search,
navigation, account controls and traffic lights keep their input. Build the
plugin with `build.sh` using matching Hyprland headers.
`build.sh --spotify-only` rebuilds just the drag integration. On launch, a stale
or missing drag build is rebuilt automatically only when the installed headers
match the running compositor commit; a mismatched build is never loaded.

Spotify minimize calls MacShell's `minimize addr` endpoint with the verified
window address. It does not rely on Quickshell's focused-toplevel lookup, which
can omit an XWayland window. The bridge confirms the window reached
`special:minimized` before returning success. Close and maximize keep their
existing dispatch paths.
The minimize bridge allows up to 12 seconds for a shell reload, screenshot and
animation. An IPC timeout first checks the verified window's workspace, then
retries the same address if needed. The web request allows 18 seconds so it
does not expire while the backend is still recovering. This addresses the
2026-11-10 failure where a seven-second QML reload exceeded the old three-second
IPC timeout.

The 2026-11-03 Spotify regression tests cover connection reuse, cache revision,
reconnection, button targeting, toolbar gestures and interactive-area exclusion.
Live CEF transport and compositor movement still require a desktop-session
check after fully quitting and reopening Spotify.

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

Zoom restore keeps Hyprland's hexadecimal stable window IDs as text across
configuration reloads, preserving the saved normal rectangle. Client restore
requests take precedence over a compositor maximize state that has not cleared
yet. Exiting F11 back to maximized resumes the preceding Zoom and clears the
fullscreen transition marker so the next green-button click restores normally.
Because Hyprland emits no fullscreen event for client-only mode changes, an
80 ms observer checks modes on recorded Zoom windows. It queues reconciliation
only when the mode changes, leaving stable window geometry and dragging alone.
The controller remembers the actual result of its own placement as well as
the requested bounds, so decoration offsets do not accidentally release Zoom
on the next focus/rule update. Genuine moves and resizes still retain geometry.
Run `~/.local/bin/macshell-zoom-reload` to verify reload activation. The last 48
transitions are kept in `$XDG_RUNTIME_DIR/macshell-zoom-trace.log`, without titles
or app content.
The reload helper also loads fullscreen-lock 1.6, which corrects native Wayland
maximize toggles against independent Zoom's client state. Without this native
request hook, a second green click can reassert client=1 without any mode change
for Lua to observe. The existing manual resize and cursor locks remain active.
An older damaged record that saved the expanded rectangle as its normal size
restores to a centered 75% work-area rectangle; valid saved sizes remain exact.
Regression coverage: `tests/test_zoom_restore.lua` at the repository root, run
with an isolated `/tmp/macshell-zoom-*` runtime and the module path as argument.

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
