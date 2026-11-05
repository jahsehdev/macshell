# MacShell

A complete MacShell desktop for **Arch Linux + Hyprland** in one repository:
menu bar, Dock, desktop, widgets, Spotlight, Control Center, Launchpad, MacLock,
**Photo Booth**, GTK/Qt themes, icons, cursors, and native window-control plugins.

The installer builds the application and plugins from the source included here.
Launchpad and MacLock each run in their own Quickshell process. All components
are installed and managed by a single installer.

## Installation from Git

**Install the dependencies before installing the MacShell configuration.**
The supported automatic package setup targets Arch Linux and its derivatives.
Run the commands below as your regular desktop user; only package installation
uses `sudo`.

### 1. Check requirements and download the repository

- Hyprland with Lua configuration support (0.55+) and matching plugin headers.
- Qt 6.9+ and a Quickshell build with Wayland, Hyprland, PAM, PipeWire, MPRIS,
  UPower, system-tray, and notification support.
- A C/C++ toolchain supporting C++26 (`-std=c++2c`), CMake, Ninja, and pkg-config.
- A working Wayland session, session D-Bus, and access to `sudo` for packages.

```bash
sudo pacman -S --needed git python
git clone https://github.com/jahsehdev/macshell.git
cd macshell
```

### 2. Install dependencies first

Install the package list maintained by [scripts/dependencies.sh](scripts/dependencies.sh).
This step installs packages and prepares the wallpaper backend; it does not
copy the MacShell configuration into your home directory.

```bash
bash scripts/dependencies.sh
```

The config also uses the following runtime packages. Install them explicitly
so audio playback/capture, the media visualizer, power controls, MacLock
authentication, timer sounds, and immediate Trash updates are available:

```bash
sudo pacman -S --needed \
  pipewire-audio libpulse upower power-profiles-daemon \
  hyprlock libcanberra inotify-tools
```

`hyprlock` supplies `/etc/pam.d/hyprlock`, which MacLock uses through Quickshell's
PAM module. MacLock itself runs in Quickshell. `inotify-tools` enables immediate
Trash updates; without it, the Dock falls back to polling.

The package groups used by the installer and config are:

| Component | Arch Linux packages |
| --- | --- |
| Download, build, and Python helpers | `git base-devel cmake ninja pkgconf python python-pillow` |
| Compositor and shell | `hyprland quickshell` |
| Qt/QML, media, shaders, and Wayland | `qt6-base qt6-declarative qt6-multimedia qt6-shadertools qt6-wayland qt6-svg qt6-5compat` |
| GTK and native integrations | `gtk3 gtk4 libadwaita json-glib librsvg fontconfig` |
| File manager and bundled application launchers | `nautilus gvfs gnome-calculator gnome-console gnome-text-editor` |
| Qt appearance | `qt6ct kvantum` |
| Network and Bluetooth | `networkmanager bluez bluez-utils` |
| Audio, microphone, and output visualizer | `pipewire pipewire-pulse pipewire-audio wireplumber libpulse` |
| Desktop portals and XDG helpers | `xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-user-dirs xdg-utils` |
| Clipboard history | `wl-clipboard cliphist` |
| Screenshots and screen recording | `grim slurp swappy wf-recorder ffmpeg` |
| Brightness and media keys | `brightnessctl playerctl` |
| Battery reporting and power profiles | `upower power-profiles-daemon` |
| MacLock authentication | `hyprlock` |
| Fonts and emoji | `inter-font noto-fonts noto-fonts-emoji` |
| Notifications, sounds, and filesystem watching | `libnotify libcanberra inotify-tools` |
| JSON and HTTP helpers | `jq curl` |

The dependency helper installs its declared package list and attempts to install
`awww` for the wallpaper picker. It checks pacman first, then uses `yay`, `paru`,
or a user-owned AUR build when needed. The additional runtime command above
covers config features that are not all included in that package list.

Photo Booth requires Qt GUI and Multimedia private development headers matching
the installed Qt libraries. The Nautilus folder menu also needs the
`libnautilus-extension-4` development files, supplied by Arch's Nautilus package.
On other distributions, install the equivalent development packages separately;
see the [installation guide](docs/INSTALL.md).

### 3. Verify dependencies, then install the configuration

```bash
./install.sh --doctor
./install.sh --no-deps
```

`--doctor` checks the main executables, development modules, and Pillow; it does
not check every optional feature or whether system services are running. Fix any
reported `MISSING` items before running the configuration installer.

The installer builds Photo Booth, the Hyprland plugins, the Nautilus bridges,
and the Qt/GTK styles before copying the payload. It backs up replaced files
and installs the components in your home directory. A complete Hyprland
configuration is included. Log out and back into **Hyprland** after installation.

For a fresh Arch installation using NetworkManager and BlueZ, start their
services so the network and Bluetooth controls can work:

```bash
sudo systemctl enable --now NetworkManager bluetooth
```

Audio controls require a running PipeWire/WirePlumber user session. Battery and
power controls use UPower and power-profiles-daemon. Keep the service setup
appropriate for your existing system.

### Installer options

Running `./install.sh` without `--no-deps` runs the dependency helper before
building and copying files. After completing step 2, use `--no-deps` as shown
above to proceed directly to configuration installation.

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

### Optional feature dependencies

Install these only for the corresponding features. They are separate from the
core package setup above, and local AI/speech models are downloaded or imported
separately.

| Feature | Additional dependency |
| --- | --- |
| Local Luma AI inference | A compatible `llama-server` runtime and supported GGUF model; configured through Settings → Luma AI |
| Local OCR / Visual Intelligence | `tesseract tesseract-data-eng tesseract-data-ind` |
| Offline speech transcription | whisper.cpp's `whisper-cli`, a compatible local GGML model, and `pw-record` from `pipewire-audio` |
| Offline read-aloud | `espeak-ng` |
| Android device connection and mirroring | `android-tools scrcpy`; enable USB debugging and authorize the computer on the device |
| Extra GNOME applications | `gnome-calendar gnome-clocks gnome-contacts gnome-maps loupe gnome-weather`; provided by `macshell-gnome-apps-setup` |
| DroidCam camera input | DroidCam, matching kernel headers, DKMS, V4L2 loopback, and Android tools; see [DroidCam setup](share/macshell/droidcam/README.md) |
| SDDM login theme | `sddm`; activate separately with `install-macshell-sddm` |
| Tabby terminal integration | Tabby and its separate setup dependencies; see [Tabby integration](share/macshell/tabby/README.md) |

The default terminal launcher uses GNOME Console (`kgx`, supplied by
`gnome-console`). Applications mentioned in window rules or existing Dock pins
are installed separately when you want to use them.

Use `--skip-build` only for staging or inspecting configuration files. A normal
installation needs the compiled applications and native plugins.

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
