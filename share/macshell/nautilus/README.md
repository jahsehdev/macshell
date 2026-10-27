# Nautilus with the installed MacTahoe theme

Nautilus 51.1 and GVfs are installed. Theme source: https://github.com/vinceliuice/MacTahoe-gtk-theme

Nautilus follows MacShell's Light, Dark, and resolved Auto appearance. The published MacTahoe-Light and MacTahoe-Dark assets are unchanged; the shared compatibility stylesheet preserves the existing header sizing, breadcrumb framing, and other layout adjustments in both palettes.

The previous generated GTK4 corner/card frames are not loaded. compat.css maps MacTahoe's named colors to current libadwaita color variables. It also retains the existing 40 px header controls and circular folder-menu button. Four geometry differences between the published Light/Dark styles are normalized to the previous Dark values, so switching appearance does not resize the existing UI.

The native-corner synchronizer preserves the theme import without adding its own GTK4 corner overrides. Other toolkit and compositor settings remain managed by their existing configuration.

The Nautilus-only native bridge watches MacShell's settings directory, including atomic file replacements. It applies the resolved appearance to libadwaita and reloads the selected theme plus the same compat.css in existing windows. Unrelated settings changes do not reload CSS. Invalid/incomplete settings preserve the last valid appearance. If MacShell settings are absent, the bridge follows org.gnome.desktop.interface color-scheme. It does not write global appearance preferences or change other applications.

After installing or rebuilding the bridge, restart Nautilus once:

    ~/.local/bin/macshell-nautilus --reload

Subsequent Light/Dark/Auto changes apply without restarting Nautilus. To refresh the on-disk GTK4 startup configuration manually:

    python3 ~/.local/share/macshell/nautilus/configure.py theme

Rebuild the native bridge with:

    sh ~/.local/share/macshell/nautilus/native/build.sh

The build uses GTK4, libadwaita, and JSON-GLib and replaces the shared library atomically. No windows or file operations are terminated by theme synchronization.

Validation: combined Light/Dark GTK4 CSS parses with zero parser errors or deprecation warnings; all compatibility colors exist in both installed themes; 8 native-corner regression checks pass, including repeated regeneration and restore. Direct Wayland desktop rendering was unavailable to the execution sandbox, so the post-change UI has not been visually verified.

Backups: ~/.local/state/macshell/backups/nautilus-native-theme-20261023-233739 and the manifest-backed nautilus-* directories. These include the prior theme imports, GTK settings, synchronizer, tests and setup configuration script.

## Popup and native minimize repair

The compatibility stylesheet explicitly clears old border-image/background-image frames from popover wrappers, contents and arrows. The rounded menu panel uses MacTahoe's popover foreground/background colors and a 12 px radius.

GTK disables its native window.minimize action if the compositor does not advertise that capability; MacTahoe's disabled sidebar-button rule then clears the yellow button image. Setting button-layout alone cannot solve that. The Nautilus-only native GTK bridge in native/window-controls.c binds the actual existing minimize button to a local GAction that invokes the established ~/.config/hypr/minimize.sh minimize helper. Close and maximize retain their original GTK actions. The bridge reconnects after window-state changes that recreate title buttons. It loads fresh CSS above legacy providers on startup.

The launcher ~/.local/bin/macshell-nautilus is used by the desktop entry, Super+E/file-manager helper, and both DBus activation services. It loads the bridge only into Nautilus and removes its own LD_PRELOAD entry before child programs can inherit it. It preserves any unrelated preload entries. No system binary or system GTK library is patched.

A running Nautilus process needs a full restart to load this library. From a desktop terminal:

    ~/.local/bin/macshell-nautilus --reload

This uses Nautilus's normal quit request and waits briefly for its DBus name to be released. It does not force-kill a busy process. If Nautilus remains alive for file operations, the helper exits with an explanatory message.

Validation: the library compiles against installed GTK4 with -Wall -Wextra -Werror; a native GApplication loader smoke test verifies interposition and child environment cleanup; Light/Dark CSS parses with zero parser errors/deprecation warnings; desktop-file, shell, Python and native-corner regression checks pass. The sandbox blocks all UNIX display/DBus connections, including isolated display-server sockets, so real button clicks and post-restart popup rendering have not been tested in the live desktop.

Backups: ~/.local/state/macshell/backups/nautilus-popup-controls-20261023-234843 and the subsequent manifest-backed nautilus-* directory.

## Breadcrumb outer-frame repair

Inspected the resource stylesheet embedded in the installed Nautilus 51.1 executable. Its .nautilus-pathbar class supplies a 9 px parent background, while MacTahoe styles the legacy #NautilusPathBar name as a pill. The compatibility stylesheet clears the exterior fill/border/shadow, gives the scrollable breadcrumb area one capsule, and removes the linked menu button's rectangular frame while keeping a rounded hover state. Both the current CSS class and the legacy ID selectors are handled so MacTahoe's higher-specificity ID rules cannot restore the extra frame. The separate search entry, menu actions and title buttons are unaffected. Combined Light/Dark styles parse without errors.
