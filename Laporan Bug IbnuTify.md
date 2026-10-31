# Product Requirement Document (PRD)

## IbnuTify - System Modernization, Bug Fixes, & Feature Enhancements

**Versi Dokumen:** 3.0.0 (Comprehensive Revision)  
**Tanggal:** 31 Oktober 2026  
**Status:** In-Draft / Technical Specification  
**Pengembang Utama:** Ibnu Sina Sudrajat  
**Platform Target:** Android (Flutter Cross-Platform Engine)

---

## 1. Ringkasan Eksekutif (Executive Summary)

IbnuTify adalah aplikasi pemutar musik *offline-first* berbasis Flutter yang dilengkapi dengan fitur pengunduh media pintar, analisis Machine Learning lokal, pelacak kebugaran, dan manajemen lirik. 

Dokumen PRD versi 3.0.0 ini menyusun spesifikasi teknis mendalam untuk menyelesaikan seluruh isu krusial yang ditemukan pada pengujian versi lapangan:
1. **Kegagalan Pelacakan Olahraga (Workout Tracking Standstill):** Penanganan stream error recovery GPS/Sensor dan pemulihan Isolate background.
2. **Notifikasi Media Android (MIUI Xiaomi Specific Bug):** Penanganan logo hitam monokrom, gambar album *null URI*, dan freeze progress bar.
3. **Visual Lirik & Interaksi Sync:** Penyusutan font preview, penghapusan spasi raksasa/footer "Akhir lirik", serta pemulihan logika tombol *Sync*.
4. **Manajemen Profil Pengguna:** Pemisahan View Mode vs Edit Mode (hilangnya tombol simpan permanen).
5. **Kontrol Sistem Pemutaran & Bluetooth:** Sleep Timer di Release Mode, auto-pause saat TWS terputus, dan pemulihan state pemutaran tanpa auto-play.

---

## 2. Gambaran Umum Sistem & Arsitektur (System Architecture)

Sistem IbnuTify dibangun atas arsitektur **Clean Architecture + MVVM** menggunakan *state management* `flutter_riverpod`.

```
[ UI Layer (Screens / Widgets / MediaNotification) ]
                         │
                         ▼
     [ ViewModel Layer (Riverpod Notifiers) ]
                         │
      ┌──────────────────┼────────────────────────┬────────────────────────┐
      ▼                  ▼                        ▼                        ▼
[ Audio Engine ]   [ Local Storage ]   [ Background Services ]   [ Native Android Bridge ]
(just_audio /      (SQLite / Cache /   (Chaquopy / Foreground    (MethodChannel / Kotlin /
 audio_service)     SharedPreferences)   Task Isolate)            MIUI Notifications)
```

---

## 3. Spesifikasi Fitur & Perbaikan Detail (Detailed Requirements)

### EPIC 1: Pengunduh Media & Integrasi UI (Media Downloader Engine)

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-1.1** | Atomic Download Engine | Unduhan sering gagal/gantung di pertengahan kompresi Python, tetapi berkas mentah sudah terbentuk sehingga memicu *conflict* saat diulang. | Implementasikan *atomic file writing* pada skrip Python (`yt-dlp`). Berkas diunduh sebagai `.tmp`. Hanya di-rename menjadi `.mp3` jika proses pengunduhan, kompresi, dan metadata selesai 100%. | Berkas `.mp3` hanya tersimpan di direktori lokal jika unduhan sukses 100%. Tidak ada berkas *corrupt* tersisa saat error. |
| **REQ-1.2** | Real-Time Progress & Cover UI | UI pengunduhan hanya menampilkan indikator berputar tanpa persentase, estimasi sisa waktu, atau cover album (`image_7de57e.png`). Teks masih "ETA". | 1. Pancarkan data persentase (%), URL cover art, dan detik sisa via `MethodChannel` stream.<br>2. Ganti teks "ETA" menjadi **"Sisa Waktu"**.<br>3. Tampilkan gambar cover art secara real-time di UI obrolan unduhan. | UI menampilkan *progress bar* presisi (%), estimasi "Sisa Waktu", dan gambar *cover album* lagu yang sedang diproses. |
| **REQ-1.3** | State Obrolan & Tombol Pembatalan | Pesan input tautan pengguna langsung lenyap dari bubble obrolan dan tidak bisa dibatalkan. | 1. Panggil `addMessage(userMessage)` sebelum memicu unduhan.<br>2. Ubah indikator berputar menjadi **Tombol Batal/Pause (X)** yang memicu *Cancellation Token* ke skrip Python. | Teks tautan pengguna tetap tampil dalam bubble chat. Pengguna dapat menghentikan unduhan kapan saja via tombol Batal. |
| **REQ-1.4** | Fallback Cover Embedding | Beberapa lagu hasil unduhan memiliki cover art kosong. | Jika penyematan `--embed-thumbnail` di Python gagal, panggil `AlbumArtService` di Flutter untuk mengambil gambar via CDN dan simpan sebagai berkas `.jpg` di direktori `Download/Ibnutify/`. | Setiap lagu yang diunduh memiliki *artwork* album yang valid di SQLite dan direktori lokal. |

---

### EPIC 2: Pelacak Olahraga (Workout Tracking & Sensor Fusion)

Formula kalkulasi jarak menggunakan persamaan **Haversine**:

$$
d = 2r \arcsin \left( \sqrt{\sin^2\left(\frac{\Delta \phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta \lambda}{2}\right)} \right)
$$

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-2.1** | GPS Tracking & Haversine Stream Fix | Tracking terhenti setelah 2 detik (`image_7de8a4.jpg`, `image_7de881.png`). Waktu berjalan, namun KM, Pace, SPM, Kalori tertahan di `0`. | 1. Turunkan `distanceFilter` GPS menjadi 2 meter.<br>2. Bungkus stream `Geolocator` dan `Pedometer` dengan error recovery handler (`onError` retry logic) agar lonjakan koordinat invalid tidak mematikan stream.<br>3. Eksekusi rumus Haversine berurutan saat jumlah titik GPS $\ge 2$. | Jarak (KM), Pace, SPM, Kalori, dan rute peta bergerak secara kontinyu seiring pergerakan pengguna. |
| **REQ-2.2** | Foreground Isolate Heartbeat | Service mati/freeze saat HP dalam saku atau layar mati (Doze Mode). | 1. Tambahkan izin `ACCESS_BACKGROUND_LOCATION`.<br>2. Pasang `WakelockPlus` pada `WorkoutTaskHandler`.<br>3. Buat mekanisasi *Heartbeat Timer* (1 detik) di dalam Isolate untuk terus memancarkan payload data ke Main UI Isolate. | Pelacakan olahraga tetap berjalan akurat 100% meskipun perangkat dikunci/diberhentikan di saku selama berjam-jam. |
| **REQ-2.3** | Activity Recognition & Pedometer | Langkah (Step), SPM, dan Kalori bernilai `0`. | Minta izin runtime `android.permission.ACTIVITY_RECOGNITION`. Hubungkan sensor accelerometer internal untuk mendeteksi puncak gelombang langkah (*step peak detection*). | Metrik Langkah, SPM, dan perkiraan Kalori terhitung secara *real-time*. |

---

### EPIC 3: Notifikasi Media Pemutaran (Android & MIUI Specifics)

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-3.1** | MIUI Small Notification Icon | Logo ikon aplikasi di baris notifikasi berupa kotak hitam murni (`image_7de923.png`). | Buat resource Android native `ic_stat_music.png` (PNG vector monokrom putih dengan transparansi Alpha) untuk `notificationChannel`. MIUI mewajibkan format ini untuk small icon. | Baris status notifikasi OS menampilkan logo ikon aplikasi yang jernih dan putih transparan (tidak hitam). |
| **REQ-3.2** | Notification Artwork & Blank State | Notifikasi kadang muncul sebagai bar putih kosong ("Not playing") atau tanpa cover art (`image_7dec23.png`, `image_7de923.png`). | Pada `IbnuTifyAudioHandler`, jika lagu tidak memiliki URI artwork eksternal (byte buffer ID3), ekspor byte gambar tersebut secara temporer sebagai berkas `file:///...` dan pasang URI lokal tersebut ke `MediaItem.artUri`. | Panel notifikasi OS selalu menampilkan cover art album dan informasi judul/artis lagu yang sedang diputar. |
| **REQ-3.3** | Background Seek Bar Progress | Progress bar notifikasi berhenti bergerak saat aplikasi berada di *recent apps* / background. | Pancarkan (*broadcast*) `PlaybackStateCompat` dari `audio_service` secara berkala dengan menyertakan variabel `position`, `playbackSpeed`, dan `updateTime`. | *Progress bar* pada bar notifikasi OS terus berjalan mulus meskipun aplikasi berada di latar belakang. |

---

### EPIC 4: Layar Lirik, Visual Formatting, & Interaksi Sync

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-4.1** | PlayerScreen Lyric Preview Styling | Font lirik aktif pada card preview di `PlayerScreen` terlalu besar sehingga menutupi/memotong baris lirik sekitarnya (`image_7de522.jpg`). | Kecilkan `fontSize` lirik aktif pada preview card, tambahkan properti `maxLines: 2` dan `overflow: TextOverflow.ellipsis` agar layout konsisten dan rapi. | Baris lirik preview tampil rapi tanpa menutupi atau memotong baris lirik di atas/bawahnya. |
| **REQ-4.2** | LyricsScreen Layout Clean-up | Terdapat ruang kosong raksasa di bagian bawah `LyricsScreen` dan terdapat pemisah teks "Akhir lirik" (`image_7de8e4.png`, `image_7de57e.png`). | 1. Hapus total widget `Divider` + `Text("Akhir lirik")`.<br>2. Kurangi padding/SizedBox bagian bawah `ListView.builder` dari 300px menjadi `height: 40`. | Tampilan lirik bersih hingga baris terakhir tanpa spasi kosong berlebihan dan tanpa teks "Akhir lirik". |
| **REQ-4.3** | Sync Button Jump Logic | Tombol chip `Sync` (`image_7de55b.png`) tidak dapat mengembalikan/menggulirkan layar ke baris lirik yang sedang aktif saat diklik. | Ketika tombol `Sync` diklik:<br>1. Setel variabel `userIsScrolling = false`.<br>2. Panggil `itemScrollController.scrollTo(index: activeIndex, duration: Duration(milliseconds: 300))`.<br>3. Jika baris lirik diklik langsung, jalankan `audioHandler.seek(line.timestamp)`. | Mengetuk tombol `Sync` langsung menggulirkan layar kembali ke baris lirik aktif dan mengaktifkan kembali *auto-scroll*. |
| **REQ-4.4** | Local Lyrics Caching | Lirik diunduh ulang dari internet setiap kali lagu diputar (pemborosan kuota). | Lakukan kueri SQLite `SELECT lyrics FROM songs WHERE uri = ?` sebelum memanggil `LyricsApiService`. Simpan lirik hasil unduhan pertama ke DB/berkas `.lrc`. | Lirik hanya diunduh **1 kali**, dan selanjutnya dibaca 100% secara *offline*. |

---

### EPIC 5: Profil Pengguna, Riwayat, & Branding Developer

#### 5.1 Layar Profil Pengguna (`UserProfileScreen`)
* **State Management:** Implementasikan variabel state `bool isEditing = false`.
* **View Mode (`isEditing == false`):** Tampilkan kartu detail profil yang rapi (Nama, Umur, Genre Favorit). **Sembunyikan tombol "Simpan Data"** dan gantikan dengan tombol **"Edit Profil"** (atau panggil modal edit).
* **Edit Mode (`isEditing == true`):** Tampilkan form input dan tombol **"Simpan Data"**. Setelah disimpan, otomatis beralih kembali ke View Mode.
* **Developer Watermark (Bagian Bawah Screen):**
  * **Foto Profil Pengembang:** Dimuat dari URL `https://ibnusinasudrajat.netlify.app/assets/img/ibnu.png`.
  * **Teks Hak Cipta:** *"Aplikasi dibuat oleh Ibnu Sina Sudrajat"*.
  * **Interaksi Klik:** Mengklik watermark akan membuka URL `https://ibnusinasudrajat.netlify.app/` di browser eksternal via `url_launcher` (`LaunchMode.externalApplication`).

```
┌───────────────────────────────────────────┐
│              PROFIL PENGGUNA              │
├───────────────────────────────────────────┤
│ [Card: Info User (Nama, Umur, Genre)]    │
│                                           │
│ [ TOMBOL: EDIT PROFIL ]                   │
│                                           │
│ ───────────────────────────────────────── │
│ ┌───────────────────────────────────────┐ │
│ │ (Foto) Aplikasi dibuat oleh          │ │
│ │        Ibnu Sina Sudrajat             │ │
│ └───────────────────────────────────────┘ │
└───────────────────────────────────────────┘
```

#### 5.2 Tombol Riwayat Pemutaran (History Routing)
* **Aksi Navigasi:** Hubungkan *callback* `onPressed` pada ikon jam/riwayat di bagian header kanan atas `HomeScreen` (`_M3TopBar`) menuju `ListeningHistoryScreen` / `RecentlyPlayedScreen`.

---

### EPIC 6: Kontrol Pemutaran & Perangkat Nirkabel (Playback & Controls)

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-6.1** | Sleep Timer Release Mode Fix | Fitur Mode Tidur tidak mematikan aplikasi pada build Release. | Buat pemanggilan native Android via MethodChannel khusus (`closeAppDeeper`) yang mengeksekusi `finishAndRemoveTask()` atau `exitProcess(0)` dari sisi Kotlin. | Mode tidur mematikan aplikasi dan membebaskan foreground service secara total pada Release Mode. |
| **REQ-6.2** | Bluetooth TWS Auto-Resume Guard | Ketika koneksi TWS/Bluetooth terputus, lagu memutar sendiri via speaker ponsel. | Konfigurasikan receiver `AudioManager.ACTION_AUDIO_BECOMING_NOISY` di Android native / `audio_service`. Paksa pemanggilan `pause()` dan hapus flag auto-resume saat TWS disconnect. | Pemutaran lagu berhenti seketika saat TWS dimatikan dan TIDAK memutar sendiri melalui speaker HP. |
| **REQ-6.3** | Restore Last Played State | Saat aplikasi dibuka kembali, lagu langsung *auto-play* secara mendadak. | Modifikasi logika pemulihan state di `IbnuTifyAudioHandler` & `playerProvider`. Muat lagu dan antrean terakhir dalam kondisi **Strictly Paused** (hanya tampil di MiniPlayer bawah). | Aplikasi memuat lagu terakhir di MiniPlayer bawah tanpa memutar suara secara otomatis. |
| **REQ-6.4** | Smart Shuffle Default | Pemutaran lagu awal masih bersifat linier. | Aktifkan Smart Shuffle sebagai default mode di `playerProvider`. Panggil `computeSmartShuffleIndices` secara otomatis saat pengguna memulai lagu. | Setiap pemutaran daftar lagu secara default terurut menggunakan algoritma Smart Shuffle. |

---

## 4. Matriks Validasi & Kriteria Pengujian Debugging (QA Matrix)

```
[Sesi Debugging Final & QA]
├── 1. Test Workout Stream    --> Lari outdoor / gerakkan HP selama 5+ menit dengan layar mati.
├── 2. Test MIUI Notification --> Cek bar notifikasi Xiaomi: ikon putih transparan & progress bar bergerak.
├── 3. Test Lyric Sync & UI   --> Klik Sync saat lirik tergeser jauh; cek ukuran font preview & footer space.
├── 4. Test Profile State     --> Simpan data profil; pastikan tombol "Simpan Data" berubah jadi View Mode.
└── 5. Test TWS & Sleep Timer --> Matikan TWS saat play; aktifkan sleep timer pada APK Release Mode.
```

*Dokumen PRD ini telah direvisi secara komprehensif dan disetujui untuk diimplementasikan secara langsung pada codebase IbnuTify.*
