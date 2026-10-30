# Product Requirement Document (PRD)

## IbnuTify - System Modernization, Bug Fixes, & Feature Enhancements

**Versi Dokumen:** 2.1.0

**Tanggal:** 30 Oktober 2026

**Status:** In-Draft / Technical Review

**Pengembang Utama:** Ibnu Sina Sudrajat

**Platform Target:** Android (Flutter Cross-Platform Engine)

## 1. Ringkasan Eksekutif (Executive Summary)

IbnuTify adalah aplikasi pemutar musik *offline-first* dengan integrasi *Machine Learning* lokal, pelacak kebugaran, serta fitur pengunduh media pintar. Dokumen PRD ini bertujuan untuk memberikan spesifikasi teknis mendalam guna mengatasi masalah kestabilan latar belakang (*background service*), sinkronisasi UI/UX pengunduhan, pelacakan olahraga, hingga penambahan profil pengguna dan retensi *caching* lirik.

## 2. Gambaran Umum Sistem & Arsitektur (System Architecture)

Sistem IbnuTify dibangun atas arsitektur **Clean Architecture + MVVM** menggunakan *state management* `flutter_riverpod`.

```
[ UI Layer (Screens / Widgets) ]
               │
               ▼
[ ViewModel Layer (Riverpod Notifiers) ]
               │
      ┌────────┴────────────────────────┬────────────────────────┐
      ▼                                 ▼                        ▼
[ Audio Engine ]              [ Local Storage ]          [ Background Services ]
(just_audio / audio_service)   (SQLite / Prefs)           (Chaquopy / Foreground)

```

## 3. Spesifikasi Fitur & Perbaikan Detail (Detailed Requirements)

### EPIC 1: Pengunduh Media & Integrasi UI (Media Downloader & UI Engine)

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) | 
| ----- | ----- | ----- | ----- | ----- | 
| **REQ-1.1** | Atomic Download Engine | Unduhan sering gagal/gantung di kompresi Python, tetapi berkas sudah terbentuk sebagian sehingga memicu *conflict* saat diulang. | Implementasikan *atomic file writing* pada skrip Python (`yt-dlp`). Berkas diunduh sebagai `.tmp`. Hanya di-rename menjadi `.mp3` jika proses pengunduhan, ekstraksi, dan penyematan metadata berhasil 100%. | Berkas `.mp3` hanya muncul di direktori lokal jika proses unduhan selesai tanpa error. Tidak ada berkas corrupt yang tersisa jika terjadi pembatalan/kegagalan. | 
| **REQ-1.2** | Real-Time UI Progress & Album Art | UI pengunduhan hanya menampilkan animasi *loading* bundar tanpa persentase, estimasi waktu, atau gambar *cover*. Teks masih menggunakan "ETA". | 1\. Hubungkan `MethodChannel` Python ke `StreamController` di Dart.  2\. Kirim status persentase, URL/path *thumbnail*, dan sisa detik secara *real-time*.  3\. Lokalisasi teks UI dari `"ETA"` menjadi `"Sisa Waktu"`. | UI menampilkan *progress bar* presisi (%), estimasi "Sisa Waktu", dan gambar *cover album* lagu yang sedang diproses. | 
| **REQ-1.3** | State Obrolan & Tombol Pembatalan | Tautan yang dikirim pengguna langsung lenyap dari bubble chat dan langsung berpindah ke mode download tanpa kontrol pembatalan. | 1\. Pastikan `addMessage(userMessage)` dipanggil sebelum eksekusi unduhan.  2\. Ubah indikator *loading* bundar di sudut obrolan menjadi **Tombol Jeda/Batal (Pause/Cancel)** yang mengirimkan *Cancellation Token* ke skrip Python. | Teks input tautan pengguna tetap tampil dalam obrolan chat. Pengguna dapat menghentikan proses unduhan kapan saja via tombol Batal. | 
| **REQ-1.4** | Fallback Album Art Embedding | Beberapa hasil unduhan tidak memiliki *cover art* (kosong/hitam). | Jika penyematan `--embed-thumbnail` di Python gagal, panggil `AlbumArtService` di Flutter untuk mencari gambar via API/CDN, lalu simpan berkas `.jpg` ke direktori `Download/Ibnutify/`. | Setiap lagu yang berhasil diunduh memiliki *artwork* album yang valid di SQLite dan direktori lokal. | 

### EPIC 2: Modul Lirik & Interaksi Sync (Local Lyrics Engine)

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) | 
| ----- | ----- | ----- | ----- | ----- | 
| **REQ-2.1** | Local Lyrics Caching | Lirik selalu diunduh ulang dari internet setiap kali lagu diputar (pemborosan kuota). | Sebelum memanggil `LyricsApiService`, lakukan kueri SQLite: |  | 
| $$ \text{SELECT lyrics FROM songs WHERE uri = ?} $$ |  |  |  |  | 
| Jika lirik ditemukan, gunakan lirik lokal. Jika tidak, unduh dari API lalu simpan ke database/berkas `.lrc`. | Lirik hanya diunduh **satu kali** saat koneksi pertama, dan selanjutnya dibaca 100% secara *offline*. |  |  |  | 
| **REQ-2.2** | Sync Jump & Scroll Lock Release | Pengguna tidak bisa mengetuk baris lirik aktif/lain saat posisi scroll manual berada jauh dari baris yang sedang berputar. | Reset flag `userIsScrolling = false` ketika pengguna mengetuk baris lirik mana pun atau menekan tombol "Sync". Panggil `itemScrollController.scrollTo()` menuju indeks waktu baris tersebut dan jalankan `audioHandler.seek(timestamp)`. | Mengetuk baris lirik apa pun langsung memindahkan posisi pemutaran lagu ke detik lirik tersebut dan mengembalikan *auto-scroll*. | 

### EPIC 3: Pelacak Olahraga (Workout Tracking & Sensor Fusion)

Formula kalkulasi jarak menggunakan persamaan **Haversine**:

$$
d = 2r \arcsin \left( \sqrt{\sin^2\left(\frac{\Delta \phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta \lambda}{2}\right)} \right)
$$

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) | 
| ----- | ----- | ----- | ----- | ----- | 
| **REQ-3.1** | GPS Tracking & Haversine Fix | Jarak tertahan di `0.00 KM` dan titik GPS tertahan di `1 titik GPS` meskipun lokasi aktif. | Turunkan `distanceFilter` GPS menjadi 2 meter. Pastikan kalkulasi Haversine di-eksekusi secara berurutan setiap kali jumlah titik GPS $\ge 2$. | Jarak (KM), Pace, dan rute peta bergerak secara dinamis sesuai pergerakan pengguna saat olahraga. | 
| **REQ-3.2** | Background Location & Wakelock | Pelacakan mati/terhenti saat layar HP terkunci (Doze Mode). | Tambahkan izin `ACCESS_BACKGROUND_LOCATION` serta pasang `WakelockPlus` pada `WorkoutTaskHandler` yang berjalan di *Android Foreground Service*. | Pelacakan olahraga tetap berjalan akurat 100% meskipun HP dimasukkan ke dalam saku dengan layar mati selama berjam-jam. | 
| **REQ-3.3** | Sensor Pedometer & Activity Recognition | Langkah (Step), SPM, dan Kalori bernilai `0`. | Minta izin runtime `android.permission.ACTIVITY_RECOGNITION`. Hubungkan sensor *Accelerometer* internal untuk mendeteksi puncak gelombang langkah. | Metrik Langkah, SPM, dan perkiraan Kalori terhitung secara *real-time*. | 

### EPIC 4: Notifikasi Pemutaran Media (Media Notification)

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) | 
| ----- | ----- | ----- | ----- | ----- | 
| **REQ-4.1** | Notification Album Art | Cover album di panel notifikasi OS sering kosong/hilang. | Format nilai `artUri` pada `MediaItem` menggunakan skema URI yang valid (`Uri.file(path).toString()`). Lakukan *downscaling* resolusi gambar maksimal $512 \times 512$ pixel agar tidak ditolak oleh Android OS Notification Manager. | Panel notifikasi OS selalu menampilkan gambar *cover art* lagu yang sedang diputar. | 
| **REQ-4.2** | Notification Seek Bar Sync | *Progress bar* notifikasi berhenti bergerak saat aplikasi berada di *recent apps*. | Pancarkan (*broadcast*) `PlaybackStateCompat` dari `audio_service` secara rutin dengan menyertakan variabel `position`, `playbackSpeed`, dan `bufferedPosition`. | *Progress bar* pada bar notifikasi OS terus berjalan mulus meskipun aplikasi berada di latar belakang. | 

### EPIC 5: Manajemen Profil User, Riwayat, & Developer Branding

#### 5.1 Layar Profil Pengguna (User Profile Screen)

* **Aksi Navigasi:** Mengklik ikon profil pada bagian kiri atas header `HomeScreen` (`_M3TopBar`) akan membuka `UserProfileScreen`.

* **Form Data Lokal:** Menyediakan bidang isian yang tersimpan di `SharedPreferences`/SQLite:

  * Nama Pengguna (String)

  * Umur (Integer)

  * Genre Musik Favorit (String)

* **Developer Watermark (Bagian Bawah Screen):**

  * **Foto Profil Pengembang:** Diambil dari URL `https://ibnusinasudrajat.netlify.app/assets/img/ibnu.png`.

  * **Teks Hak Cipta:** *"Aplikasi dibuat oleh Ibnu Sina Sudrajat"*.

  * **Interaksi Klik:** Mengklik area watermark akan membuka URL `https://ibnusinasudrajat.netlify.app/` pada browser eksternal perangkat (*External Application Browser* via `url_launcher`).

```
┌───────────────────────────────────────────┐
│              PROFIL PENGGUNA              │
├───────────────────────────────────────────┤
│ Nama : [ Ibnu Sina                      ] │
│ Umur : [ 22                             ] │
│                                           │
│ [ SIMPAN DATA ]                           │
│                                           │
│ ───────────────────────────────────────── │
│ ┌───────────────────────────────────────┐ │
│ │ (Foto) Aplikasi dibuat oleh          │ │
│ │        Ibnu Sina Sudrajat             │ │
│ └───────────────────────────────────────┘ │
└───────────────────────────────────────────┘

```

#### 5.2 Tombol Riwayat Pemutaran (History Routing Fix)

* **Aksi Navigasi:** Menghubungkan *callback* `onPressed` pada ikon jam/riwayat di bagian header kanan atas `HomeScreen` menuju `RecentlyPlayedScreen` / `ListeningHistoryScreen`.

## 4. Matriks Validasi & Pengujian Debugging (QA Matrix)

```
[Sesi Debugging Final]
├── 1. Test Download Engine   --> Simulasi link playlist 30 lagu & single track.
├── 2. Test GPS Workout       --> Run outdoor tracking dengan layar terkunci.
├── 3. Test Lyrics Caching    --> Diputar offline (Airplane Mode) setelah di-cache.
└── 4. Test External Launcher --> Klik Watermark Dev pada Profile Screen.

```

*Dokumen PRD ini disetujui untuk diimplementasikan secara langsung oleh AI Coding Agent pada codebase IbnuTify.*
