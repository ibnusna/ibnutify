# **BRIEF PROJECT IBNUTIFY: SMART OFFLINE MUSIC PLAYER**

Dokumen ini disusun sebagai acuan teknis pengembangan fitur manajemen data pintar dan pengelompokan musik otomatis untuk aplikasi Android **IbnuTify** berbasis Flutter.

## **1\. Judul Fitur**

**Fitur Manajemen Pustaka Musik Pintar (Daily Mix, Song Era, dan Sistem Scoring On Repeat) pada Aplikasi IbnuTify**

## **2\. Tujuan Fitur**

* **Memperbaiki Logika Pemutaran:** Mengganti logika "Top Song" lama yang salah menjadi sistem pelacakan otomatis berdasarkan bobot interaksi asli pengguna (On Repeat).  
* **Otomatisasi Daily Mix:** Mengelompokkan berkas .mp3 lokal pengguna ke dalam kelompok kategori (*Daily Mix*) yang harmonis secara otomatis menggunakan *Machine Learning offline*.  
* **Klasifikasi Dekade Musik:** Mengelompokkan lagu berdasarkan era dekade rilisnya (*Song Era*) dengan membaca metadata internal berkas secara otomatis.  
* **Bekerja 100% Offline:** Memastikan seluruh proses pemindaian, analisis audio, dan pengelompokan berjalan langsung di dalam perangkat Android tanpa memerlukan koneksi internet.

## **3\. Deskripsi Singkat Fitur**

Fitur ini bertindak sebagai otak pengelola pustaka lagu lokal pada aplikasi IbnuTify. Sistem akan memindai folder musik lokal di Android, mengekstrak fitur fisik audio (seperti tempo/BPM dan warna suara) menggunakan modul Python yang ditanam via Chaquopy, serta membaca metadata tahun rilis.

Data ini diolah dengan algoritma K-Means Clustering untuk memisahkan lagu ke beberapa klaster *Daily Mix*. Aplikasi juga merekam setiap aktivitas memutar musik ke database lokal untuk menyusun daftar *On Repeat* yang akurat secara real-time.

## **4\. Pengguna / Stakeholder**

* **Pengguna Akhir (User Aplikasi IbnuTify):** Penikmat musik yang memutar lagu lokal dengan pengalaman navigasi dan daftar putar dinamis layaknya Spotify.

## **5\. Flow Penggunaan / User Flow**

### **A. Alur Sistem & Latar Belakang (System Background Ingestion)**

1. **Pemberian Izin:** Pengguna membuka aplikasi pertama kali dan menyetujui izin akses memori internal perangkat (*Storage Permission*).  
2. **Pemindaian Berkas:** Aplikasi Flutter memindai dan mencatat semua lokasi path dari berkas berkestensi .mp3 di folder terpilih.  
3. **Analisis Audio:** Jalur file (*file path*) dikirimkan ke modul Python internal (via Chaquopy).  
4. **Ekstraksi Karakter:** Modul Python menggunakan pustaka *Librosa* untuk membaca data tahun rilis (ID3 Tag) serta mendeteksi ketukan musik (BPM) dan pola warna frekuensi.  
5. **Proses Klasterisasi:** Python menjalankan algoritma K-Means untuk menentukan kelompok (cluster\_id) lagu tersebut.  
6. **Penyimpanan Lokal:** Hasil klasifikasi dikirim kembali ke Flutter lalu disimpan ke dalam database SQLite (Sqflite).

### **B. Alur Pengguna (User UI Flow)**

1. **Membuka Beranda:** Pengguna membuka aplikasi IbnuTify.  
2. **Memuat Playlist:** Halaman beranda memanggil data dari database lokal secara asinkron dan membaginya ke dalam kartu kategori: *Daily Mix*, *Song Era*, dan *On Repeat*.  
3. **Memutar Musik:** Pengguna memilih salah satu daftar putar dan memutar lagu di dalamnya menggunakan package just\_audio.  
4. **Perekaman Log:** Sistem mencatat durasi putar di latar belakang untuk menghitung ulang skor popularitas lagu tersebut secara berkala.

## **6\. Kebutuhan Fitur (Feature Requirements)**

### **A. Fitur Sistem & Analisis (Backend Engine)**

* **ID3 Tag Reader:** Kemampuan mengekstrak metadata bawaan berkas .mp3 (Judul, Artis, Album, Tahun Rilis).  
* **Acoustic Analyzer:** Pengekstrak nilai ketukan per menit (BPM) dan karakteristik warna suara (*timbre*).  
* **K-Means Clusterer:** Logika pembagian otomatis file musik lokal menjadi beberapa kelompok daftar putar tanpa menggunakan server internet.  
* **Sistem Logika Scoring On Repeat (Sederhana & Akurat):**  
  * Jika lagu diputar hingga mencapai atau lebih dari 80 persen durasi aslinya, maka skor lagu tersebut bertambah 10 poin (+10).  
  * Jika lagu dilewati (di-skip) saat baru didengarkan kurang dari 30 detik, maka skor lagu tersebut dikurangi 5 poin (-5).  
  * Daftar putar *On Repeat* dikonfigurasi untuk hanya mengambil 20 lagu teratas dengan akumulasi skor tertinggi dalam kurun waktu 7 hari terakhir.

### **B. Fitur Antarmuka Pengguna (Frontend UI)**

* **Dynamic Mix Cards:** Menampilkan deretan kartu *Daily Mix 01*, *Daily Mix 02*, dst., pada halaman utama.  
* **Era Categorization:** Pengelompokan visual untuk era rilis musik (seperti *2010s Mix*, *2020s Mix*) berdasarkan data tahun yang telah diekstrak.  
* **Search & Filter:** Kolom pencarian lagu dan penyaringan berdasarkan nama artis atau judul di setiap daftar putar dinamis.

## **7\. Struktur Database**

Penyimpanan data lokal diatur menggunakan database relasional **SQLite** melalui plugin sqflite di Flutter.

### **Tabel: songs**

Menyimpan data mentah lagu hasil pemindaian dan ekstraksi.

| Nama Kolom | Tipe Data | Keterangan |
| :---- | :---- | :---- |
| id | INTEGER, PK, AUTOINCREMENT | Kunci utama unik setiap lagu |
| title | VARCHAR(255) | Judul lagu (dari ID3 Tag) |
| artist | VARCHAR(255) | Nama penyanyi atau grup musik |
| file\_path | TEXT, UNIQUE | Alamat path lokasi file fisik di memori HP |
| release\_year | INTEGER | Tahun rilis musik (untuk filter dekade/era) |
| cluster\_id | INTEGER (NULLABLE) | ID kelompok hasil analisis K-Means (Daily Mix) |
| score | INTEGER (DEFAULT 0\) | Akumulasi nilai interaksi putar dari pengguna |

### **Tabel: play\_logs**

Mencatat riwayat aktivitas pemutaran untuk kalkulasi kebiasaan dengar pengguna.

| Nama Kolom | Tipe Data | Keterangan |
| :---- | :---- | :---- |
| id | INTEGER, PK, AUTOINCREMENT | Kunci utama unik untuk log pemutaran |
| song\_id | INTEGER, FK | Berelasi ke kolom songs.id |
| timestamp | DATETIME | Waktu ketika lagu tersebut mulai diputar |
| duration\_played | INTEGER | Durasi lamanya lagu didengarkan dalam detik |

## **8\. Output yang Diharapkan**

* **Arsitektur Kode Flutter:** Kode bersih (*clean code*) yang menangani inisialisasi database lokal (sqflite), sinkronisasi pemutaran latar belakang (just\_audio), dan pengelolaan state antarmuka.  
* **Skrip Python Offline (Chaquopy):** Kode ekstraksi audio menggunakan librosa dan model matematika K-Means menggunakan library scikit-learn yang dapat dieksekusi secara asinkron.  
* **Desain UI Glassmorphic:** Kerangka antarmuka beranda IbnuTify yang memvisualisasikan daftar putar dengan desain yang modern dan responsif untuk Android.

## **9\. Rules / Constraint**

* **No Internet Dependency:** Seluruh sistem wajib bekerja 100 persen secara lokal di dalam HP tanpa bergantung pada server API luar maupun koneksi data seluler.  
* **Asynchronous UI Thread:** Proses ekstraksi gelombang audio yang memakan memori wajib berjalan di thread latar belakang (*Background Isolate*) agar layar aplikasi tidak terasa macet (*freezing*) saat memproses lagu.  
* **Safety Refactoring:** Jangan menghapus atau mengubah sistem navigasi dan fungsi dasar pemutar musik yang sudah berfungsi dengan baik di kode proyek IbnuTify yang saat ini sudah berjalan.