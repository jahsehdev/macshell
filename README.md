# MacShell

Satu repo untuk desktop MacShell di **Arch Linux + Hyprland**: menu bar, Dock,
desktop, widgets, Spotlight, Control Center, Launchpad, MacLock, **Photo Booth**,
**Tahoe Terminal**, tema GTK/Qt/icon/cursor, dan plugin kontrol jendela native.

Installer membangun aplikasi serta plugin dari source yang ada di repo ini.
Launchpad dan MacLock tetap memakai proses Quickshell masing-masing; seluruh
komponen dipasang dan dikelola oleh satu installer.

## Instalasi melalui Git

```bash
git clone https://github.com/jahsehdev/macshell.git
cd macshell
./install.sh
```

Jalankan sebagai pengguna biasa. Installer memakai `sudo` untuk paket sistem,
mencadangkan file konfigurasi yang diganti, lalu memasang seluruh komponen ke
home pengguna. Keluar dan masuk kembali ke sesi **Hyprland** setelah selesai.
Konfigurasi Hyprland lengkap disertakan; konfigurasi lama dicadangkan.

```bash
./install.sh --dry-run          # lihat rencana tanpa perubahan
./install.sh --doctor           # periksa dependensi
./install.sh --no-deps          # dependensi sudah dipasang manual
./install.sh --test             # build dan jalankan tes aplikasi
./install.sh --yes              # package manager noninteraktif
```

Pengaturan yang sudah ada seperti pin Dock, tema, layout Launchpad, kamera,
dan preferensi aplikasi dipertahankan. Untuk memakai default paket:

```bash
./install.sh --reset-settings
```

## Instalasi manual

Pasang dependensi sesuai [panduan instalasi](docs/INSTALL.md), kemudian:

```bash
./install.sh --no-deps
```

Tanpa `--skip-build`, Photo Booth, Tahoe Terminal, empat plugin Hyprland,
bridge GTK Nautilus, serta style Qt/GTK dibangun otomatis. `--skip-build`
hanya disediakan untuk staging atau pemeriksaan payload konfigurasi.

## Pemakaian

| Aksi | Shortcut/perintah |
| --- | --- |
| Launchpad | Super+A |
| Spotlight | Super+Space |
| Terminal | Super+Q |
| File manager | Super+E |
| Lock screen | Super+L |
| Screenshot | Print / Super+Shift+S |
| Settings | Menu Apple atau Dock |
| Photo Booth | Launchpad → Photo Booth / `tahoe-photobooth` |
| Tahoe Terminal | Launchpad → Tahoe Terminal / `tahoe-terminal` |

Detail aplikasi: [Photo Booth](apps/tahoe-photobooth/README.md) dan
[Tahoe Terminal](apps/tahoe-terminal/README.md).

## Update dan pemulihan

```bash
git pull --ff-only
./install.sh
# atau: macshell-update

./uninstall.sh
# atau: macshell-uninstall
```

Manifest dan cadangan berada di
`~/.local/state/macshell/installer/`. Uninstall mengembalikan file lama;
file yang sudah diubah pengguna dipertahankan. File media dan layout sesi
pengguna tidak menjadi bagian dari repo.

## Login screen SDDM

Tema SDDM ikut dipasang ke home pengguna. Aktivasi sistem dilakukan terpisah
karena memerlukan akses root:

```bash
install-macshell-sddm
```

Tidak ada restart display manager otomatis. Tema berlaku saat login berikutnya.

## Struktur

```text
apps/               Photo Booth dan Tahoe Terminal beserta source/test/vendor
config/quickshell/  MacShell, Common, Launchpad, MacLock
config/hypr/        Konfigurasi Hyprland dan aturan jendela
bin/                Launcher, integrasi, update dan uninstall
share/macshell/     Source plugin native dan integrasi aplikasi
themes/ dan icons/  Tema desktop lengkap
extras/sddm/        Tema login
scripts/            Installer, dependensi, SDDM
tests/              Tes installer
```

Dukungan otomatis ditargetkan pada Arch Linux dan turunannya, Hyprland dengan
konfigurasi Lua (0.55+), Qt 6.9+ dan compiler C++26 untuk plugin Hyprland.
Plugin harus dibangun ulang sesudah upgrade ABI Hyprland.

San Francisco fonts tidak dibundel; sistem memakai font fallback jika keluarga
font tersebut belum terpasang. Wallpaper default berupa SVG milik paket dan
bisa diganti dari Settings. Helper opsional `macshell-install-sf-fonts` juga
tersedia untuk pengguna yang ingin menyiapkan font tersebut sendiri.

Paket ini memuat kustomisasi dari [0-ss/MacShell](https://github.com/0-ss/MacShell),
tema [MacTahoe GTK](https://github.com/vinceliuice/MacTahoe-gtk-theme), dan
[MacTahoe icons](https://github.com/vinceliuice/MacTahoe-icon-theme).
Lihat [THIRD_PARTY.md](THIRD_PARTY.md) untuk lisensi masing-masing komponen.
Ini adalah proyek Linux independen, tidak berafiliasi dengan Apple.
