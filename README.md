# MacShell

A complete MacShell desktop for **Arch Linux + Hyprland** in one repository:
menu bar, Dock, desktop, widgets, Spotlight, Control Center, Launchpad, MacLock,
**Photo Booth**, GTK/Qt themes, icons, cursors, and native window-control plugins.

The installer builds the application and plugins from the source included here.
Launchpad and MacLock each run in their own Quickshell process. All components
are installed and managed by a single installer.

## Installation from Git

```bash
git clone https://github.com/jahsehdev/macshell.git
cd macshell
./install.sh
```

Run the installer as your regular user. It uses `sudo` to install system
packages, backs up configuration files it replaces, and installs all components
in your home directory. Log out and back into **Hyprland** when installation
finishes. A complete Hyprland configuration is included; your previous
configuration is backed up.

```bash
./install.sh --dry-run          # preview the installation without making changes
./install.sh --doctor           # check dependencies
./install.sh --no-deps          # use dependencies you have already installed
./install.sh --test             # build and run application tests
./install.sh --yes              # run the package manager noninteractively
```

Existing preferences, including Dock pins, themes, Launchpad layouts, camera
settings, and application preferences, are preserved. To use the bundled defaults:

```bash
./install.sh --reset-settings
```

## Manual installation

Install the dependencies listed in the [installation guide](docs/INSTALL.md), then run:

```bash
./install.sh --no-deps
```

By default, the installer builds Photo Booth, four Hyprland plugins, the
Nautilus GTK bridge, and the Qt/GTK styles automatically. Use `--skip-build`
only for staging or inspecting the configuration files.

## Usage

| Action | Shortcut / command |
| --- | --- |
| Launchpad | Super+A |
| Spotlight | Super+Space |
| Terminal (GNOME Console) | Super+Q / `macshell-terminal` |
| File manager | Super+E |
| Lock screen | Super+L |
| Screenshot | Print / Super+Shift+S |
| Settings | Apple menu or Dock |
| Photo Booth | Launchpad → Photo Booth / `tahoe-photobooth` |

Application details: [Photo Booth](apps/tahoe-photobooth/README.md).

## Updates and recovery

```bash
git pull --ff-only
./install.sh
# or: macshell-update

./uninstall.sh
# or: macshell-uninstall
```

The installation manifest and backups are stored in
`~/.local/state/macshell/installer/`. Uninstalling restores previous files
and preserves files you have modified. Personal media and session layouts
are not included in this repository.

## SDDM login screen

The SDDM theme is installed in your home directory. Activate it separately
with the following command, which uses `sudo` for system changes:

```bash
install-macshell-sddm
```

The theme takes effect at the next login. The display manager is not restarted
automatically.

## Repository structure

```text
apps/               Photo Booth source and tests
config/quickshell/  MacShell, Common, Launchpad, MacLock
config/hypr/        Hyprland configuration and window rules
bin/                Launchers, integrations, update and uninstall helpers
share/macshell/     Native plugin source and application integrations
themes/ and icons/  Desktop themes, icons, and cursors
extras/sddm/        Login theme
scripts/            Installer, dependencies, and SDDM setup
tests/              Installer tests
```

Automatic installation targets Arch Linux and its derivatives, Hyprland with
Lua configuration support (0.55+), Qt 6.9+, and a C++26 compiler for the Hyprland
plugins. Rebuild the plugins after a Hyprland ABI upgrade.

San Francisco fonts are not bundled. The system uses fallback fonts when
those families are unavailable. The included default wallpaper is an SVG
that you can replace in Settings. An optional `macshell-install-sf-fonts`
helper is available for users who want to install those fonts separately.

This distribution includes customizations of
[0-ss/MacShell](https://github.com/0-ss/MacShell),
[MacTahoe GTK](https://github.com/vinceliuice/MacTahoe-gtk-theme), and
[MacTahoe icons](https://github.com/vinceliuice/MacTahoe-icon-theme).
See [THIRD_PARTY.md](THIRD_PARTY.md) for component licenses.
This is an independent Linux project and is not affiliated with Apple.
