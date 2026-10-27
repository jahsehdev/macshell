#!/usr/bin/env bash
set -euo pipefail
mode=${1:-install}
packages=(git base-devel cmake ninja pkgconf python python-pillow qt6-base qt6-declarative
    qt6-multimedia qt6-shadertools qt6-wayland qt6-svg qt6-5compat gtk3 gtk4 libadwaita
    webkit2gtk-4.1 json-glib hyprland quickshell nautilus gnome-calculator gnome-console
    gnome-text-editor qt6ct kvantum networkmanager bluez bluez-utils pipewire pipewire-pulse
    wireplumber xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-user-dirs xdg-utils
    wl-clipboard cliphist grim slurp swappy wf-recorder ffmpeg brightnessctl playerctl
    inter-font noto-fonts noto-fonts-emoji libnotify jq curl)
if [[ $mode == --check ]]; then
    missing=0
    for executable in qs Hyprland cmake ninja pkg-config python3 jq ffmpeg nautilus; do
        if command -v "$executable" >/dev/null; then
            printf 'OK      %s\n' "$executable"
        else
            printf 'MISSING %s\n' "$executable"; missing=1
        fi
    done
    for module in hyprland gtk+-3.0 gtk4 libadwaita-1 webkit2gtk-4.1 json-glib-1.0 Qt6Core Qt6Multimedia Qt6ShaderTools; do
        if pkg-config --exists "$module"; then
            printf 'OK      %s %s\n' "$module" "$(pkg-config --modversion "$module")"
        else
            printf 'MISSING %s\n' "$module"; missing=1
        fi
    done
    python3 -c 'from PIL import Image' || missing=1
    exit "$missing"
fi
if ! command -v pacman >/dev/null; then
    echo 'Instalasi dependensi otomatis mendukung Arch Linux dan turunannya.' >&2
    echo 'Pasang dependensi pada docs/INSTALL.md, lalu jalankan ./install.sh --no-deps.' >&2
    exit 1
fi
missing=()
for package in "${packages[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 || missing+=("$package")
done
if ((${#missing[@]})); then
    options=(--needed)
    [[ $mode == --yes ]] && options+=(--noconfirm)
    sudo pacman -S "${options[@]}" "${missing[@]}"
fi
# Optional wallpaper backends are auto-detected by MacShell. awww enables the
# full wallpaper picker. Build the AUR package as the current user if necessary.
if ! command -v awww >/dev/null; then
    if pacman -Si awww >/dev/null 2>&1; then
        options=(--needed); [[ $mode == --yes ]] && options+=(--noconfirm)
        sudo pacman -S "${options[@]}" awww
    elif command -v yay >/dev/null; then
        options=(--needed); [[ $mode == --yes ]] && options+=(--noconfirm)
        yay -S "${options[@]}" awww
    elif command -v paru >/dev/null; then
        options=(--needed); [[ $mode == --yes ]] && options+=(--noconfirm)
        paru -S "${options[@]}" awww
    else
        awww_build=$(mktemp -d /tmp/macshell-awww.XXXXXX)
        trap 'rm -rf -- "$awww_build"' EXIT
        git clone --depth 1 https://aur.archlinux.org/awww.git "$awww_build/source"
        options=(--syncdeps --install --needed); [[ $mode == --yes ]] && options+=(--noconfirm)
        (cd "$awww_build/source" && makepkg "${options[@]}")
    fi
fi
bash "$(dirname -- "$0")/dependencies.sh" --check
