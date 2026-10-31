# Product Requirement Document (PRD)

## IbnuTify - AI Downloader, Auto-Play Library, & Playlist Queue Priority

**Versi Dokumen:** 4.0.0 (Dedicated Focus Release)  
**Tanggal:** 31 Oktober 2026  
**Status:** Approved for Implementation  
**Target Platform:** Android (Flutter + Chaquopy Python Bridge)  

---

## 1. Ringkasan Eksekutif (Executive Summary)

Dokumen PRD Versi 4.0.0 ini secara khusus memusatkan perhatian pada **4 area perbaikan utama** terkait mekanisme pengunduhan media via AI Moods, sinkronisasi UI real-time, penyegaran pustaka lokal (library rescan) dengan *immediate auto-play*, pemulihan API AI multi-tier, serta perbaikan prioritas antrean pemutaran playlist.

---

## 2. Analisis Akar Masalah (Root Cause Analysis)

### 2.1 Freeze UI Pengunduh Playlist & Kebocoran Teks Chat
* **Bukti Log Python:**
  ```text
  --- Downloading track 1/9: Anggis Devaki - Dirimu Yang Dulu -> Track downloaded OK
  --- Downloading track 2/9: Natasya Sabella - Menerima Luka -> Track downloaded OK
  --- Downloading track 3/9: Aku Jeje - Lihat Kebunku ...
  ```
   Skrip Python `download_playlist` di Chaquopy terbukti berjalan secara sekuensial mengunduh lagu 1, 2, 3, dst.
* **Akar Masalah UI Freeze:** Callback `MethodChannel` (`onTrackChange`) dari Chaquopy tidak memperbarui `DownloadState` di Riverpod setiap kali lagu berganti. Widget UI (`_DownloadSystemBubble`) hanya menerima pemicu (*event*) awal pada track 1 dan tidak pernah dipaksa melakukan *re-render* untuk track 2 hingga 9.
* **Akar Masalah Kebocoran Teks (Chat Leak):** Pada `AIChatScreen`, string tautan Spotify pengguna di-render dua kali: sekali di dalam *User Chat Bubble* dan sekali lagi sebagai teks mentah (*unwrapped String*) di atas *System Download Card* (`image_70b67e.png`).

### 2.2 Pustaka Lokal (Library) Tidak Auto-Refresh & Tidak Auto-Play
* **Akar Masalah:** Setelah lagu (single atau playlist) selesai diunduh, berkas `.mp3` fisik tersimpan di `/storage/emulated/0/Download/Ibnutify/`, tetapi basis data SQLite `songs` tidak secara otomatis memicu `scanLocalSongs()`. Pengguna terpaksa mematikan (*force close*) aplikasi agar lagu muncul.
* **Akar Masalah Button "Lihat Library":** Tombol "Lihat Library" pada UI unduhan belum memiliki *event handler* yang memicu rescan SQLite sekaligus memutar lagu yang baru diunduh secara langsung.

### 2.3 AI API Fallback Terlalu Agresif
* **Akar Masalah:** Objek `GeminiDatasource` langsung melakukan *catch block* ke `LocalFallbackResponse` pada kegagalan HTTP pertama tanpa mencoba rotasi API Key atau model cadangan (seperti OpenRouter API).

### 2.4 Prioritas Antrean Pemutaran Playlist (Playlist Queue Isolation)
* **Akar Masalah:** Saat pengguna memutar sebuah Playlist, algoritma Smart Shuffle memasukkan seluruh lagu dari perpustakaan global ke dalam antrean aktif, sehingga lagu-lagu di luar playlist ikut terputar secara acak sebelum playlist selesai.

---

## 3. Spesifikasi Fitur & Perbaikan Detail

```
[ Flow Pengunduhan Playlist & Auto-Play ]

  Python (yt-dlp) ──(Progress Callback)──> Kotlin MethodChannel ──> Riverpod DownloadNotifier
                                                                            │
                                                                   (Update UI Real-Time)
                                                                            │
  Completion / Klik "Lihat Library" ──> SQLite Rescan ──> Play Song/Playlist Directly!
```

### EPIC 1: Synchronized Playlist Downloader & Chat UI Fix

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-1.1** | Real-time Playlist Track Progress Stream | Log menunjukkan Python mengunduh track 1, 2, 3 (`Dirimu Yang Dulu`, `Menerima Luka`, dst), tetapi UI terus menampilkan track 1/9 (`image_70b67e.png`). | 1. Modifikasi skrip `download_playlist()` di Python agar memanggil callback `native_bridge.on_track_progress(current_index, total_tracks, track_title, artist, cover_url)` pada setiap awal iterasi loop lagu.<br>2. Sambungkan callback native ke `MethodChannel` stream di Dart (`com.ibnutify.ml/audio`).<br>3. Di Flutter `DownloadNotifier`, perbarui `state = state.copyWith(...)` setiap ada payload progress baru agar UI kartu lagu langsung berganti mengikuti lagu yang sedang diproses. | Kartu UI unduhan memperbarui judul lagu, nama artis, cover album, dan indikator persentase (`X/Y lagu`) secara real-time setiap kali lagu berganti. |
| **REQ-1.2** | Perbaikan Kebocoran Teks Chat (Chat Bubble Leak) | Input tautan pengguna (`https://open.spotify.com/playlist/...`) bocor dan tampil sebagai teks mentah di luar bubble obrolan (`image_70b67e.png`). | 1. Pindai widget builder di `AIChatScreen` dan `AIChatMessageTile`.<br>2. Hapus pengkondisian `Text(message.content)` duplikat yang dirender di luar komponen `ChatBubble`.<br>3. Pastikan string tautan pengguna HANYA muncul 1x di dalam *Right-Aligned User Bubble*. | Tautan pengguna hanya tampil rapi dalam bubble chat pengguna (kanan) dan tidak ada teks tautan mentah yang melayang di atas kartu sistem. |

---

### EPIC 2: Post-Download Rescan & Immediate Auto-Play

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-2.1** | Automatic Storage & Database Rescan | Lagu yang selesai diunduh tidak langsung muncul di pustaka aplikasi tanpa restart. | 1. Setelah status unduhan (single atau playlist) mencapai `100% Completed`, panggil fungsi `ref.read(songsProvider.notifier).rescanLibrary()`.<br>2. Pemicu rescan akan memindai folder `/Download/Ibnutify/`, mengindeks berkas `.mp3` baru ke SQLite `songs`, dan mengekstrak ID3 Tag-nya. | Pustaka lagu lokal di SQLite dan UI `LibraryScreen` langsung ter-update secara instan tanpa perlu mematikan aplikasi. |
| **REQ-2.2** | Auto-Play Single & Playlist / "Lihat Library" Action | Klik tombol "Lihat Library" atau unduhan selesai tidak memutar lagu yang baru saja diunduh. | 1. Ketika tombol **"Lihat Library"** diklik (atau saat unduhan selesai otomatis):<br>   a. Jalankan rescan basis data.<br>   b. Cari `SongModel` dari lagu/playlist yang baru diunduh berdasarkan `uri` atau `path`.<br>   c. Panggil `playerProvider.notifier.playSong(newSong)` untuk **Single Track**, atau `playerProvider.notifier.playPlaylist(newPlaylistSongs)` untuk **Playlist**.<br>2. Alihkan navigasi UI langsung ke `PlayerScreen` atau buka `MiniPlayer`. | Mengetuk "Lihat Library" (atau penyelesaian unduhan) secara otomatis memicu pemutaran lagu/playlist yang baru diunduh detik itu juga. |

---

### EPIC 3: AI Moods Multi-Tier API Failover Engine

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-3.1** | Multi-Tier AI Provider Rotation | API AI Moods sering gagal dan langsung mundur ke fallback lokal (`Exception: No endpoints found`). | 1. Implementasikan pola *Circuit Breaker* dan rotasi API di `GeminiDatasource`:<br>   - **Tier 1:** Gemini 3 Flash Primary API Key.<br>   - **Tier 2:** Gemini 3 Flash Secondary Backup Key.<br>   - **Tier 3:** OpenRouter API (`google/gemma-2-9b-it:free` atau `meta-llama/llama-3-8b-instruct:free`).<br>   - **Tier 4:** Local Heuristic Parser (Hanya jika Tier 1-3 gagal total).<br>2. Cetak log debug transparan jika terjadi pergantian Tier tanpa menghentikan flow obrolan. | Fitur obrolan AI Moods dan ekstraksi playlist berjalan stabil tanpa pernah mendadak gagal ke fallback lokal selama ada koneksi internet. |

---

### EPIC 4: Playlist Queue Priority & Smart Shuffle Scope

| ID | Modul / Fitur | Deskripsi Masalah | Spesifikasi Perbaikan & Solusi Teknis | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-4.1** | Strictly Isolated Playlist Queue | Saat memutar lagu dari daftar Playlist, lagu di luar playlist ikut terputar acak mengacaukan urutan playlist. | 1. Ketika pengguna memutar sebuah Playlist (misal: "My Playlist #20"):<br>   a. Buat antrean terisolasi (`PlaylistQueue`) yang **hanya berisi lagu-lagu dalam playlist tersebut**.<br>   b. Jika Smart Shuffle aktif, jalankan `computeSmartShuffleIndices()` **hanya pada scope lagu-lagu di dalam playlist tersebut**.<br>   c. Lagu-lagu perpustakaan luar HANYA boleh diputar jika seluruh lagu dalam playlist tersebut telah selesai diputar habis.<br>2. Saat pengguna menekan *Next*, pastikan lagu berikutnya tetap berasal dari anggota playlist aktif. | Pemutaran playlist memprioritaskan seluruh lagu anggota playlist terlebih dahulu hingga habis sebelum berpindah ke lagu luar. |

---

## 4. Rencana Pengujian Teknis (QA Checklist)

```text
[ Sesi Pengujian QA Versi 4.0.0 ]
│
├── 1. Test Playlist Downloader Progress UI
│    └── Unduh playlist Spotify (9 lagu). Pastikan UI berpindah dari Track 1/9 -> 2/9 -> 3/9 secara real-time.
│
├── 2. Test Chat Bubble Text Leakage
│    └── Paste URL playlist Spotify di AI Chat. Pastikan tautan HANYA ada di dalam User Bubble kanan.
│
├── 3. Test Rescan & Auto-Play "Lihat Library"
│    └── Setelah lagu selesai diunduh, ketuk "Lihat Library". Pastikan lagu yang baru diunduh LANGSUNG berbunyi/diputar.
│
├── 4. Test Multi-Tier AI API Rotation
│    └── Simulasikan API Key Tier 1 error. Pastikan sistem otomatis switch ke Tier 2/OpenRouter tanpa crash.
│
└── 5. Test Playlist Priority Queue
     └── Putar "My Playlist #20". Tekan Next berulang kali. Pastikan hanya lagu dalam playlist tersebut yang terputar.
```
