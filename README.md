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
copy the MacShell configuration into your home directory. Complete the feature
dependencies in step 3 as well before running `./install.sh --no-deps`.

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
| Interface fonts | **SF Pro Text / SF Pro Display**; install with `macshell-install-sf-fonts` after configuration |
| Monospace font | **SF Mono**; installed by the same font helper |
| Emoji | **Apple Color Emoji** (`AppleColorEmoji-Linux.ttf`); see [font and emoji setup](#fonts-and-emoji) |
| Notifications, sounds, and filesystem watching | `libnotify libcanberra inotify-tools` |
| JSON and HTTP helpers | `jq curl` |

The dependency helper installs its declared package list and attempts to install
`awww` for the wallpaper picker. It checks pacman first, then uses `yay`, `paru`,
or a user-owned AUR build when needed. The additional runtime command above
covers config features that are not all included in that package list.
The helper also installs fallback fonts. Install SF Pro, SF Mono, and Apple
Color Emoji separately as described in [Fonts and emoji](#fonts-and-emoji).

Photo Booth requires Qt GUI and Multimedia private development headers matching
the installed Qt libraries. The Nautilus folder menu also needs the
`libnautilus-extension-4` development files, supplied by Arch's Nautilus package.
On other distributions, install the equivalent development packages separately;
see the [installation guide](docs/INSTALL.md).

### 3. Install dependencies for the features you will use

**Finish this step before installing the configuration.** Optional means the
feature can be skipped; its dependencies are required when you enable it.
The base dependency helper does not install every package or local model below.

#### Live / video wallpaper

Install **[`mpvpaper`](https://github.com/GhostNaN/mpvpaper)** (the executable is
named `mpvpaper`), plus `mpv` and `ffmpeg`, before using video wallpapers.
`awww` handles static wallpapers; it does not replace the video backend.

```bash
sudo pacman -S --needed mpv ffmpeg

# Use the repository package if your distribution provides it.
# Otherwise install the AUR package with an existing AUR helper.
if pacman -Si mpvpaper >/dev/null 2>&1; then
  sudo pacman -S --needed mpvpaper
elif command -v yay >/dev/null 2>&1; then
  yay -S --needed mpvpaper
elif command -v paru >/dev/null 2>&1; then
  paru -S --needed mpvpaper
else
  echo "Install mpvpaper using the upstream build instructions linked above."
fi

command -v mpvpaper
command -v mpv
command -v ffmpeg
```

If building from source, follow the upstream instructions for its Wayland/wlroots,
libmpv, Meson, and Ninja requirements. Run the build as your regular user.
Video files are supplied separately.

**Current integration limitation:** the wallpaper picker calls
`~/.config/hypr-macshell/scripts/macshell-setwall.sh` for videos and animated
previews. That helper is not included in this repository. Installing `mpvpaper`
alone does not complete the picker's video support on a fresh installation;
the compatible helper must also be supplied. Static wallpaper selection uses
`awww` and is independent of this missing video helper.

#### Other feature dependencies

| Feature | Install before configuration / additional setup |
| --- | --- |
| Static wallpaper picker and transitions | `awww` and `awww-daemon`; prepared by `scripts/dependencies.sh` |
| Screenshot, annotation, clipboard capture | `grim slurp swappy wl-clipboard`; included in the base helper |
| Screen / selected-area recording | `wf-recorder ffmpeg`, plus the PipeWire packages above for audio; included in the base helper except `pipewire-audio` |
| Photo Booth camera, microphone, and export | Qt Multimedia and FFmpeg from the base helper, a working camera, and PipeWire audio; phone cameras additionally need DroidCam below |
| Media controls and Dynamic Notch music | `playerctl` and a player exposing MPRIS; audio visualization needs `pw-cat` (`pipewire-audio`) or `parec` (`libpulse`) |
| Network and Bluetooth controls | `networkmanager bluez bluez-utils`, with the corresponding services running |
| Brightness, battery, and power profiles | `brightnessctl upower power-profiles-daemon`; hardware must expose the relevant controls |
| Clipboard history | `wl-clipboard cliphist`; included in the base helper |
| MacLock authentication | `hyprlock` supplies the PAM configuration; Quickshell needs PAM support |
| Timer sounds and immediate Trash updates | `libcanberra inotify-tools` |
| Local Luma AI inference | A compatible `llama-server` runtime and supported GGUF model; see [Luma AI setup](docs/LUMA.md). Models can be imported or installed through Settings → Luma AI after configuration |
| Local OCR / Visual Intelligence | `tesseract tesseract-data-eng tesseract-data-ind` and `grim` |
| Offline speech transcription | whisper.cpp's `whisper-cli`, a compatible local GGML model, and `pw-record` from `pipewire-audio`; configure the local speech model after installation |
| Offline read-aloud | `espeak-ng` |
| Android device connection and mirroring | `android-tools scrcpy`; enable USB debugging and authorize the computer on the device |
| Extra GNOME applications | `gnome-calendar gnome-clocks gnome-contacts gnome-maps loupe gnome-weather`; `macshell-gnome-apps-setup` can configure their integration after installation |
| DroidCam camera input | DroidCam, matching kernel headers, DKMS, V4L2 loopback, and Android tools; follow [DroidCam setup](share/macshell/droidcam/README.md) |
| SDDM login theme | `sddm`; activate separately with `install-macshell-sddm` after installation |
| Tabby terminal integration | Tabby and its separate setup dependencies; see [Tabby integration](share/macshell/tabby/README.md) |

For OCR, read-aloud, and Android mirroring, install the packages for the features
you want before continuing (omit the other groups):

```bash
# OCR / Visual Intelligence
sudo pacman -S --needed tesseract tesseract-data-eng tesseract-data-ind
# Offline read-aloud
sudo pacman -S --needed espeak-ng
# Android device connection and mirroring
sudo pacman -S --needed android-tools scrcpy
```

AI and speech model files are not bundled or downloaded by the config installer.
Prepare the required runtimes first, then select/import their models through the
installed application. Device pairing and theme activation happen after the
configuration is installed.

### 4. Verify dependencies, then install the configuration

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
building and copying files. After completing steps 2 and 3, use `--no-deps`
as shown above to proceed directly to configuration installation.

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
| Luma AI Search or Ask menu | Super+Shift+Space |
| Luma AI menu-bar quick panel | Round Luma icon in the menu bar |
| Luma AI application | `macshell-luma` / Launchpad → Luma AI |
| Terminal (GNOME Console) | Super+Q / `macshell-terminal` |
| File manager | Super+E |
| Lock screen | Super+L |
| Find cursor | Shake the mouse or move a finger rapidly back and forth on the trackpad |
| Screenshot | Print / Super+Shift+S |
| Record screen or area | Control Center → Record → Entire Screen / Selected Area |
| Settings | Apple menu or Dock |
| Interface font | Settings → Appearance → Typography → Font |
| Customize a folder | Right-click one local folder on the desktop or in Files → Customize Folder… |
| Resize a desktop widget | Right-click the widget → Small / Medium / Large / Extra Large |
| Photo Booth | Launchpad → Photo Booth / `tahoe-photobooth` |

Application details: [Photo Booth](apps/tahoe-photobooth/README.md).

**Shake to find** temporarily enlarges the current cursor up to 4× and smoothly
restores it after shaking stops. See [cursor configuration and rebuild instructions](share/macshell/shake-to-find/README.md).

**Customize Folder** changes an individual folder's color and adds a symbol or
emoji, with a live preview. Use the context-menu color circles for a quick color
change, or open **Customize Folder…** for symbols and the searchable emoji picker.
Emoji use an installed, usable **Apple Color Emoji** font when available and
fall back to **Noto Color Emoji**. **Clear** restores the previous folder icon;
press **Esc** or click outside the desktop popover to dismiss it. See
[folder customization](docs/FOLDER-CUSTOMIZATION.md) for font setup, supported
folders, and the targeted feature updater.

Desktop widgets offer **Extra Large** from their context menu when supported;
the Clock widget supports Small, Medium, and Large.

**Settings → Appearance → Typography → Font** provides a searchable dropdown with
all installed SF font families, including **SF Pro Text**, **SF Pro Display**,
**SF Pro Rounded**, and **SF Mono**, plus **System** for interface labels and menus.
Type in **Search fonts** to filter the list; the current font has a check mark.
SF Pro Text is the default for the Luma panels, recording overlay, and folder
customizer. Install the San Francisco font files with
`~/.local/bin/macshell-install-sf-fonts` after installing the config, then restart
MacShell and applications to refresh their fonts. Missing font families use an
installed fallback; emoji keep their separate color font.

**Dynamic Notch** sits at the top center, above the menu-bar contents. Hover or
click to reveal music controls, timers, recording, charging and volume/brightness
feedback. **Settings → Dynamic Notch** switches between Attached and
Floating, sets fullscreen visibility, size and displays. See
[Dynamic Notch](docs/DYNAMIC-NOTCH.md) for behavior and validation details.

For an area recording, choose **Selected Area**, drag the part of the screen to
record, and release to start. **Esc** or a right click cancels selection.
The selected area stays outlined in red with a recording timer until you stop.
Stop from the recording control or the privacy indicator; videos are saved as MP4 in
`~/Videos/`. **File → Record Selected Area…** opens the same picker.

**Luma AI** is an optional, local assistant. Open **Settings → Luma AI** to install
the Light model or choose a larger model. The installer does not download models
or start an AI server. After setup, chat and writing assistance work offline;
models load on demand and leave memory after 90 seconds idle. Access it from
Spotlight with **Ask Luma AI**, or type `luma: your question`.
**Super+Shift+Space** opens a separate **Search or Ask** menu in the center of
the focused display, with frosted liquid glass and answers below the input.
The menu-bar icon has its own compact quick panel. **Open app**
continues the same conversation in the full application. Hide the shortcut in
**Settings → Menu Bar → Luma AI** if desired.
See [Luma AI](docs/LUMA.md) for installation, privacy, and supported desktop actions.

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

## Fonts and emoji

MacShell uses **SF Pro Text** and **SF Pro Display** for interface text.
San Francisco font files are installed separately. After
installing the config, run:

```sh
~/.local/bin/macshell-install-sf-fonts
```

The helper downloads SF Pro from
[sahibjotsaggu/San-Francisco-Pro-Fonts](https://github.com/sahibjotsaggu/San-Francisco-Pro-Fonts)
and SF Mono for fixed-width text, then updates the font cache and session
preferences. Restart MacShell and applications to refresh their loaded fonts.
Without the font files, the system substitutes an installed fallback such as
Noto. The included default wallpaper is an SVG that you can replace in Settings.

For folder emoji, install **Apple Color Emoji** separately using the Linux build
`AppleColorEmoji-Linux.ttf` in `~/.local/share/fonts/`, run `fc-cache -f`, then
reload MacShell. The SF font helper does not install emoji fonts. The folder
picker and artwork renderer prefer the usable Apple font; **Noto Color Emoji**
is only the fallback when it is unavailable. See
[folder emoji font setup](docs/FOLDER-CUSTOMIZATION.md) for the font source and
installation details.

This distribution includes customizations of
[0-ss/MacShell](https://github.com/0-ss/MacShell),
[MacTahoe GTK](https://github.com/vinceliuice/MacTahoe-gtk-theme), and
[MacTahoe icons](https://github.com/vinceliuice/MacTahoe-icon-theme).
See [THIRD_PARTY.md](THIRD_PARTY.md) for component licenses.
This is an independent Linux project and is not affiliated with Apple.
