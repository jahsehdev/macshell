# Default MacShell glass window controls

The default light and dark PNGs use the glass traffic-light design: a soft
lower reflection, a brighter upper/lower rim, and subtle inner shading.
Inactive windows use neutral gray glass. Hover reveals the action glyph only;
the glass fill, border highlights and inactive gray remain unchanged.
The shared QML controls use no scale animation. Pressed and maximize/restore
artwork retain their existing filenames and interaction roles.
Artwork stays 14px across inside the original 16px/32px transparent canvases;
button spacing, hit areas and window actions are unchanged.

`scripts/generate-window-controls.py` renders the artwork from native SVG using
`rsvg-convert` (librsvg). It refreshes these shared PNGs, the repo's GTK 3/4
MacTahoe theme copies, Nautilus's bundled themes, and Photo Booth's source assets.
Pass `--install` to refresh existing user-installed shared/GTK theme copies too:

```sh
python3 scripts/generate-window-controls.py --install \
  --backup-dir "$HOME/.local/state/macshell/backups/glass-traffic-lights-$(date +%Y%m%d-%H%M%S)"
```

The backup contains every replaced original and a `manifest.json` with absolute
source/backup paths and before/after hashes. To restore, copy each manifest
entry's `backup` file to its `path`. Close and reopen applications normally to
discard cached artwork. Photo Booth prefers the installed shared artwork;
its embedded fallback is refreshed on the next build. Electron overlay
fingerprints include the shared PNGs so a relaunch regenerates embedded CSS
when the artwork changes.

- GTK 3 and GTK 4 use their existing MacTahoe themes and left-hand close/minimize/maximize layout.
- Firefox's shared customChrome.css imports firefox.css, covering both installed profiles and all native button states.
- MacShell Settings and Clock use WindowControls.qml and these shared PNGs.
- Photo Booth uses its own titlebar and the shared MacTahoe artwork.

Compositor titlebars (Hyprbars) have been removed globally. Do not add a plugin
load or compositor titlebar fallback: applications own their window controls.

Apply titlebar settings with `hyprctl reload`. Restart MacShell and Firefox to load their changed UI files.

## Integrated application controls (2026-10-24)

Dolphin, Kitty, Antigravity, Spotify, and compatible Qt/GTK utilities now load
application-local controls in their existing toolbar, tab, menu, or navigation
row. Hyprbars is no longer loaded globally; the old readiness tag is not needed
to hide an external titlebar. Close and reopen applications to load their integration.

Implementation, verification limits and rollback instructions:
`~/.local/share/macshell/window-controls/README.md`.
