# MacShell SDDM

Adaptasi lokal dari `~/.config/quickshell/MacLock/LockScreen.qml`, bukan proses Quickshell. Jam memakai komponen MorphText dan shader asli MacLock. Wallpaper, avatar, format jam, dan gaya jam disalin dari konfigurasi saat tema dibuat. Autentikasi dan pemilihan sesi memakai API SDDM.

Tema mengikuti wallpaper, avatar, format jam, preset, ukuran, warna, dan material jam
dari MacLock. Sinkronkan ulang tanpa akses root:

```sh
bash ~/.local/bin/install-macshell-sddm --prepare
```

Pemasang menjalankan sinkronisasi ini sebelum `sudo`, lalu membundel font SF Pro
yang terpasang pada sesi pengguna ke dalam aset tema. Greeter tidak bergantung
pada akses ke direktori home. Jika SF belum tersedia, Qt memakai font fallback.

Preview tanpa logout:

```sh
sddm-greeter-qt6 --test-mode --theme ~/.local/share/sddm/themes/macshell
```

Pasang dan aktifkan (meminta password sudo di terminal):

```sh
bash ~/.local/bin/install-macshell-sddm
```

Pemasang menyalin tema beserta aset ke `/usr/share/sddm/themes/macshell`, membuat `/etc/sddm.conf.d/zz-macshell.conf`, dan menyimpan backup serta perintah pemulihan. Tidak me-restart SDDM. Tema akan digunakan saat kembali ke layar login atau boot berikutnya.

Tema memerlukan SDDM Qt 6, QtQuick Controls Basic, dan QtQuick Effects yang sudah tersedia pada sistem ini. SF Pro dipakai jika tersedia; Qt memakai font pengganti jika font tersebut tidak terpasang. Media, notifikasi, dan layanan dalam sesi desktop tidak dimuat pada layar login.

Screenshot UI QML yang dirender dengan shader OpenGL, tanpa membuka atau
me-restart layar login, tersedia di `~/Projects/ui-previews/sddm-macshell/`.
`Preview.qml` memakai model SDDM tiruan untuk menguji pengisian password,
penolakan login, dan reset. `render` membaca `theme.conf` asli; password dan
tombol daya pada preview tidak mengakses autentikasi atau layanan sistem.

Dokumentasi API: https://github.com/sddm/sddm/blob/develop/docs/THEMING.md
