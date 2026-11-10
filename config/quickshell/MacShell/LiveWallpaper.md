# Wallpaper gambar dan video

Buka **System Settings → Wallpaper**. Tab **Pictures** menampilkan gambar, tab
**Live** menampilkan video. **Choose File…** dapat memilih media dari folder lain.
Klik media untuk menerapkannya. Preview video hanya berjalan ketika pengaturan
terlihat atau kartu di-hover. Video desktop memakai mpvpaper, tanpa suara dan
loop, dengan pause saat tertutup jendela fullscreen.

Wallpaper dipakai juga di MacLock dan tema login SDDM. Bila login sync belum
terpasang, **Enable Login Sync…** membuka pemasang di terminal untuk pemasangan
satu kali. Pilihan berikutnya disinkronkan otomatis.

Autostart memakai jalur Hyprland yang sudah ada:
`hyprland.start → ~/.local/bin/macshell-start → macshell-wallpaper restore`.
Tidak perlu menambahkan proses mpvpaper lain ke konfigurasi Hyprland.

Konfigurasi: `~/.config/macshell/wallpaper.json`.
Log pemutar: `~/.cache/macshell/wallpaper/player.log`.
Tes: `python3 ~/.local/share/macshell/tests/test_wallpaper.py -v`.

Gambar diproses backend gambar (awww/swww/hyprpaper/swaybg), video oleh
mpvpaper, dan lock/login screen memutar video melalui Qt Multimedia.
Pergantian yang gagal mempertahankan pilihan terakhir.
