# Instalasi lengkap dan manual

## Arch Linux

`./install.sh` memasang paket yang belum ada memakai pacman. Perintah tidak
menjalankan upgrade sistem penuh dan tidak mengganti driver grafis. Wallpaper
backend `awww` diperiksa di repositori pacman, lalu AUR bila diperlukan.

Untuk memasang dependensi sendiri:

```bash
bash scripts/dependencies.sh
./install.sh --no-deps
```

Daftar paket lengkap terdapat di `scripts/dependencies.sh`. Paket build utama:
`base-devel cmake ninja pkgconf python python-pillow qt6-base qt6-declarative
qt6-multimedia qt6-shadertools qt6-wayland qt6-svg qt6-5compat gtk3 gtk4 libadwaita
webkit2gtk-4.1 json-glib hyprland quickshell`.

Photo Booth memakai Qt private development headers yang harus cocok dengan
versi Qt Multimedia/Gui. Plugin native menggunakan header dan simbol compositor
Hyprland yang terpasang. Installer berhenti sebelum menyalin payload jika build
salah satu komponen gagal.

## Distribusi lain

Pasang padanan dependensi tersebut melalui package manager distribusi. Qt harus
6.9 atau lebih baru; Hyprland harus mendukung konfigurasi Lua serta header
plugin yang sama dengan binary-nya. Jalankan `./install.sh --doctor`, kemudian
`./install.sh --no-deps`. Instalasi lintas distro belum diuji secara penuh.

## Yang dipasang

- Konfigurasi: `$XDG_CONFIG_HOME` atau `~/.config`.
- Native plugins dan tema: `$XDG_DATA_HOME` atau `~/.local/share`.
- Aplikasi dan resource aplikasi: prefix `~/.local`.
- Cadangan/manifest: `$XDG_STATE_HOME/macshell/installer` atau
  `~/.local/state/macshell/installer`.

Tambahkan `~/.local/bin` ke PATH bila distribusi belum melakukannya.
Konfigurasi Hyprland bundle memanggil launcher dengan path absolut yang dirender
sesuai pengguna tujuan. Tidak ada path home pembuat repo di payload publik.

Bluetooth dan jaringan menggunakan service sistem yang sudah terpasang.
Jika belum aktif, sesuaikan pengelolaan service komputer, misalnya pada instalasi
Arch baru: `sudo systemctl enable --now NetworkManager bluetooth`.
Installer tidak mematikan layanan jaringan yang sudah berjalan.

## Staging tanpa mengubah desktop aktif

```bash
./install.sh --dry-run
./install.sh --home /tmp/macshell-demo --no-deps --skip-build
./uninstall.sh --home /tmp/macshell-demo
```

`--home` ditujukan untuk pengujian. Instalasi biasa memakai home dan variabel
XDG milik pengguna yang sedang masuk. Jalankan installer tanpa sudo.

## SDDM

`install-macshell-sddm` mengaktifkan tema dengan sudo, mencadangkan tema dan
file konfigurasi lama, dan menampilkan lokasi cadangannya. Langkah ini opsional;
MacLock dalam sesi dan seluruh aplikasi tetap dipasang oleh installer utama.

## Pengujian

```bash
python3 -m unittest discover -s tests -v
./install.sh --no-deps --test
```

Mode `--test` membangun dua aplikasi dan menjalankan tes PTY, ekspor media,
encoder video, dan interaksi UI headless sebelum instalasi. Kamera fisik,
mikrofon, SDDM, dan perilaku compositor tetap membutuhkan pengujian di desktop
sesungguhnya. Tidak ada klaim batas RAM 500 MB dari sekadar bundling ini.
