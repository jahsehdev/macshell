# Tabby installation and default-terminal migration

Tabby is installed under `~/.local/share/tabby/versions/` and is configured as
the default terminal. Its local plugin places the window controls in the tab
row and loads drag regions from `drag.css` on startup. Drag empty space in the
tab row to move the window; tabs and buttons keep their normal interactions.

To reinstall or update, run from the normal desktop terminal:

```sh
python3 ~/.local/share/macshell/tabby/install.py
```

The script downloads the latest Linux package from Eugeny/Tabby's official GitHub
release, checks its size and the release's SHA-256 digest when available, and
extracts it under `~/.local/share/tabby/versions/`. It runs no package maintainer
scripts and needs no sudo. It checks the executable and library dependencies
before preparing configuration changes. A previously downloaded official `.deb`
can be supplied with `--package /path/to/tabby.deb`.

After installation, it switches Super+Q, the Dock terminal pin, MacShell terminal
menus and fallback commands, KDE/GNOME terminal preferences, and user terminal
launchers to Tabby. `macshell-terminal` translates existing `-e` commands into
Tabby's `run` syntax and preserves argument boundaries and working directories.
The current Kitty session is not closed, and Kitty's installed package is kept.

Tabby's built-in Custom CSS places the existing working buttons at the left of
its tab row, using shared MacTahoe artwork. A standard local Tabby plugin routes
minimize through MacShell's Dock and reports control readiness before Hyprbars
is removed. No extra header or custom terminal renderer is installed.

Configuration changes are backed up under
`~/.local/state/macshell/backups/tabby-default-TIMESTAMP/`. The manifest records
each modified or created file. A configuration failure restores files already
written by that operation. Existing non-JSON Tabby YAML is merged with PyYAML if
installed; otherwise the installer stops instead of replacing existing profiles.

Installer syntax, migration plans and argument routing can be verified offline.
Actual Tabby startup and plugin loading require the official package and a
desktop session; neither has been verified inside the editing sandbox.
