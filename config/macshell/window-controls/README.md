# Default MacTahoe window controls

The light and dark PNGs are unchanged copies of Nautilus's MacTahoe theme in
`~/.local/share/macshell/nautilus/themes/MacTahoe-{Light,Dark}/gtk-4.0/windows-assets/`.

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
