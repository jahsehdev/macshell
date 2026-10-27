# DroidCam opsional untuk Photo Booth

Integrasi ini memungkinkan kamera ponsel dipakai oleh Photo Booth.
Driver dan aplikasi DroidCam dipasang terpisah melalui helper berikut.

## Pasang di komputer (sekali)

Cari **DroidCam Setup** di Launchpad, atau jalankan:

```bash
bash ~/.local/share/macshell/droidcam/setup.sh
```

Installer menggunakan yay yang sudah tersedia untuk memasang paket AUR `droidcam`
(klien Classic). Driver standar `v4l2loopback-dkms`, header kernel, `v4l-utils`,
dan `android-tools` dipasang dari repositori Arch. Paket tambahan untuk build
adalah `base-devel` dan `git`. Ikuti peninjauan dan konfirmasi paket yang tampil.
Jika unduhan 404 akibat mirror/paket lama, lakukan pembaruan sistem Arch secara
utuh dengan `sudo pacman -Syu`, reboot jika kernel berubah, lalu jalankan lagi.

Kamera virtual diberi nama **DroidCam**, dimuat otomatis saat boot, memakai nomor
/dev/video kosong mulai dari 10. Konfigurasi driver berada di
/etc/modprobe.d/90-photobooth-droidcam.conf dan
/etc/modules-load.d/photobooth-droidcam.conf.

## Pasang di ponsel Android

Pakai **DroidCam Classic** oleh Dev47Apps, sesuai klien Classic di komputer.
Aplikasi DroidCam Webcam & OBS Camera yang baru adalah varian berbeda.

Situs resmi varian Classic: https://www.dev47apps.com/

## Uji melalui Wi-Fi (cara awal)

1. Hubungkan komputer dan HP ke jaringan lokal yang sama. Komputer boleh memakai Ethernet.
2. Buka DroidCam Classic di HP dan izinkan kamera. Catat WiFi IP dan DroidCam Port.
3. Buka aplikasi **DroidCam** di komputer (setelah installer selesai).
4. Pilih koneksi Wi-Fi, isi IP dan port dari layar HP (biasanya 4747).
5. Aktifkan Video dan matikan Audio untuk pengujian awal, lalu tekan Start.
6. Buka Photo Booth → Settings → Camera → DroidCam. Jika belum muncul,
   tekan Retry camera di layar tengah atau tutup dan buka lagi Photo Booth.
7. Uji foto dan video pendek. Gambar nyata belum dapat diuji sebelum HP dihubungkan.

Bawaan awal 640×480, video saja. Pengaturan lama DroidCam tidak ditimpa.
Jika kamera terputus saat aplikasi HP masuk latar belakang, buka pengaturan baterai
untuk DroidCam pada ponsel dan izinkan berjalan tanpa pembatasan, atau biarkan
aplikasinya terbuka selama pengujian.

## Pilihan USB

Aktifkan Developer options dan USB debugging di pengaturan HP. Nama menu bergantung
pada versi MIUI/HyperOS. Sambungkan kabel USB data dan setujui dialog Allow USB
debugging pada HP. Pilih koneksi USB/Android di klien DroidCam. `android-tools`
yang dipasang installer menyediakan adb. Untuk memeriksa koneksi:

```bash
adb devices
```

Status harus `device`, bukan `unauthorized`.

## Periksa pemasangan

```bash
bash ~/.local/share/macshell/droidcam/setup.sh --check
```

Dengan `exclusive_caps=1`, kamera virtual dapat baru muncul sebagai kamera masukan
setelah DroidCam mulai mengirim gambar. Mulai koneksi DroidCam sebelum membuka
Photo Booth. Mikrofon bisa dipilih terpisah di Settings → Microphone.

Dokumentasi resmi: https://www.dev47apps.com/droidcam/linux/
Perbedaan varian: https://droidcam.app/help/
