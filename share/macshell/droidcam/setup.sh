#!/usr/bin/env bash
set -Eeuo pipefail

check_only=false
for argument in "$@"; do
    case "$argument" in
        --check) check_only=true ;;
        *) printf 'Argumen tidak dikenal: %s\n' "$argument" >&2; exit 2 ;;
    esac
done

finish() {
    local result=$?
    if (( result != 0 )); then
        printf '\nSetup belum selesai (kode %s). Pesan kesalahan ada di atas.\n' "$result" >&2
    fi
    if [[ -t 0 ]]; then
        read -r -p 'Tekan Enter untuk menutup… ' _ || true
    fi
}
trap finish EXIT

printf 'DroidCam Classic → Photo Booth (Arch Linux)\n\n'
if "$check_only"; then
    printf 'Kernel aktif: %s\n' "$(uname -r)"
    for package in droidcam linux-headers dkms v4l2loopback-dkms v4l-utils android-tools; do
        pacman -Q "$package" 2>/dev/null || printf '%s: belum terpasang\n' "$package"
    done
    if command -v v4l2-ctl >/dev/null; then
        v4l2-ctl --list-devices || true
    fi
    if command -v adb >/dev/null; then
        printf '\nPerangkat Android USB:\n'
        adb devices
    fi
    exit 0
fi

if (( EUID == 0 )); then
    printf 'Jalankan sebagai pengguna biasa. Script meminta sudo hanya untuk paket dan driver.\n' >&2
    exit 1
fi
command -v yay >/dev/null || { printf 'yay belum tersedia.\n' >&2; exit 1; }
command -v pacman >/dev/null || { printf 'Installer ini khusus Arch Linux.\n' >&2; exit 1; }

printf 'Memasang driver kamera virtual, header kernel, dan dukungan USB Android.\n'
printf 'Paket DroidCam Classic berasal dari AUR dan akan menampilkan proses peninjauan yay.\n\n'
sudo -v
sudo pacman -S --needed linux-headers dkms v4l2loopback-dkms v4l-utils android-tools base-devel git

# Never refresh repository databases separately: Arch partial upgrades are unsupported.
# Headers must belong to the running kernel before building/loading the webcam module.
if [[ ! -d "/usr/lib/modules/$(uname -r)/build" ]]; then
    printf '\nHeader untuk kernel aktif tidak tersedia.\n' >&2
    printf 'Jika paket kernel baru sudah terpasang, reboot lalu jalankan installer lagi.\n' >&2
    printf 'Jika paket kernel dan header berbeda versi, perbarui sistem bersama-sama dengan sudo pacman -Syu.\n' >&2
    exit 1
fi

yay -S --needed droidcam
command -v droidcam >/dev/null

# Preserve an existing configuration; these are initial video-only Wi-Fi defaults.
if [[ ! -e "$HOME/.config/droidcam" ]]; then
    mkdir -p "$HOME/.config"
    cat > "$HOME/.config/droidcam" <<'CONFIG'
v4
ip=
port=4747
audio=0
video=1
size=640x480
confirm_close=1
vertical_flip=0
horizontal_flip=0
type=0
CONFIG
fi

# Select an unused persistent video number without replacing a physical webcam.
video_number=10
while [[ -e "/dev/video$video_number" ]]; do
    if [[ $(cat "/sys/class/video4linux/video$video_number/name" 2>/dev/null || true) == DroidCam ]]; then
        break
    fi
    (( video_number += 1 ))
    if (( video_number > 63 )); then
        printf 'Tidak menemukan nomor kamera virtual yang kosong.\n' >&2
        exit 1
    fi
done

sudo install -d -m755 /etc/modprobe.d /etc/modules-load.d
printf 'options v4l2loopback devices=1 video_nr=%s card_label=DroidCam exclusive_caps=1\n' "$video_number" |
    sudo tee /etc/modprobe.d/90-photobooth-droidcam.conf >/dev/null
printf 'v4l2loopback\n' | sudo tee /etc/modules-load.d/photobooth-droidcam.conf >/dev/null
if ! modinfo v4l2loopback >/dev/null 2>&1; then
    sudo dkms autoinstall -k "$(uname -r)"
fi
sudo modprobe v4l2loopback

camera_found=false
for name_file in /sys/class/video4linux/video*/name; do
    if [[ -f "$name_file" ]] && [[ $(cat "$name_file") == DroidCam ]]; then
        camera_found=true
        printf '\nKamera virtual siap: %s\n' "$(dirname "$name_file")"
    fi
done
if ! "$camera_found"; then
    printf '\nKonfigurasi tersimpan, tetapi kamera bernama DroidCam belum aktif.\n' >&2
    printf 'Jika v4l2loopback sedang dipakai aplikasi lain, reboot lalu periksa lagi.\n' >&2
    exit 1
fi

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
printf '\nDroidCam dan driver sudah terpasang. Uji gambar masih membutuhkan HP.\n'
printf '1. Di POCO C65, pasang DroidCam Classic (Dev47Apps).\n'
printf '2. Hubungkan HP dan komputer ke jaringan lokal yang sama.\n'
printf '3. Buka DroidCam di HP; masukkan WiFi IP dan port yang tampil ke klien DroidCam di komputer.\n'
printf '4. Aktifkan Video, matikan Audio, lalu Start.\n'
printf '5. Buka Photo Booth → Settings → Camera → DroidCam.\n'
printf '\nUntuk USB, aktifkan USB debugging di HP dan izinkan komputer saat diminta.\n'
printf 'Panduan: %s/.local/share/macshell/droidcam/README.md\n' "$HOME"
