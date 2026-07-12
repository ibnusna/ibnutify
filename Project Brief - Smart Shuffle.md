# **Project Brief: Implementasi Smart Shuffle (Fewer Repeats)**

## **1\. Judul Fitur**

Smart Shuffle: Optimisasi Antrean Acak Berbasis Perilaku (*Offline-First*)

## **2\. Tujuan Fitur**

Menghadirkan pengalaman mendengarkan musik yang lebih dinamis dan tidak membosankan dengan mengganti algoritma pengacak murni (True Random) menjadi sistem cerdas. Fitur ini bertujuan untuk menghindari pengulangan lagu dalam waktu berdekatan, memberi jarak pada lagu dari artis yang sama, dan membaca preferensi pengguna (*skip* vs *completion*) secara lokal tanpa bergantung pada koneksi internet.

## **3\. Deskripsi Singkat**

Pengembangan sistem *shuffle* bawaan pada playerProvider dan just\_audio di aplikasi IbnuTify. Ketika tombol *shuffle* ditekan, sistem tidak lagi sekadar mengacak baris lagu. Sistem akan menghasilkan beberapa kandidat urutan, menyaringnya berdasarkan riwayat putar (Freshness Scoring), memprioritaskan lagu berdasarkan interaksi (Engagement Weighting), dan memisahkan lagu dari artis yang sama (Dithering). Fitur ini berjalan otomatis dan permanen setiap kali mode acak diaktifkan.

## **4\. Pengguna/Stakeholder**

* **End-User (Pengguna Aplikasi):** Mendapatkan pengalaman pemutaran musik yang terasa lebih "mengerti selera" dan tidak repetitif.  
* **Developer Frontend/State (Flutter/Riverpod):** Bertanggung jawab menghubungkan *trigger* tombol *shuffle* ke algoritma baru dan mengontrol status antrean.  
* **Developer Backend Core/Service (Dart/SQLite):** Bertanggung jawab membuat sistem *tracker* di AudioHandler dan algoritma pembobotan *array*.

## **5\. User Flow**

1. Pengguna sedang memutar lagu di screen song/membuka sebuah *Playlist*, *Album*, atau halaman *All Songs*.  
2. Pengguna menekan tombol "Shuffle" (Acak) yang ada di tombol acak.  
3. (Sistem memproses antrean di latar belakang dalam hitungan milidetik).  
4. Pemutaran dimulai. Pengguna mendengarkan musik dengan urutan yang sudah dioptimasi.  
5. Jika pengguna menekan "Skip Next" sebelum lagu berjalan 30 detik, sistem diam-diam mencatatnya sebagai interaksi negatif.  
6. Jika pengguna mendengarkan lagu sampai habis, sistem diam-diam mencatatnya sebagai interaksi positif.

## **6\. Flow Sistem**

1. **Trigger:** playerProvider menerima perintah *Shuffle Mode: ON*.  
2. **Multi-Sequence Generation:** Fungsi pengacak membuat 3-5 variasi susunan *array* daftar lagu.  
3. **Data Fetching:** Sistem mengambil data dari SQLite (tabel songs untuk skor interaksi & tabel listening\_history untuk daftar putar 24 jam terakhir).  
4. **Scoring & Eliminasi:** \- *Freshness Filter:* Menurunkan skor kandidat urutan yang menaruh lagu yang baru diputar kemarin di urutan awal.  
   * *Engagement Filter:* Menurunkan lagu dengan *skip rate* tinggi ke urutan bawah.  
5. **Dithering (Penyebaran Artis):** Pada kandidat urutan terbaik, sistem melakukan pengecekan berulang (*looping*). Jika ada lagu dengan *metadata* artist yang sama berada dalam jarak \< 3 indeks, lagu tersebut digeser/ditukar posisinya.  
6. **Execution:** Urutan akhir yang sudah matang diserahkan ke *queue* just\_audio via AudioHandler.  
7. **Tracking Loop:** Selama lagu berputar, *stream listener* di AudioHandler terus berjalan untuk merekam *Skip* atau *Completion* ke dalam *database*.

## **6\. Feature Requirements**

* **Audio Tracker Service:** Modifikasi pada AudioHandler untuk membaca PlaybackEvent dan durasi pemutaran untuk mendeteksi *skip* (\< 30 detik) dan *completion* (\> 90% durasi total).  
* **Offline Scoring Engine:** Logika komputasi (bisa di Dart menggunakan *Isolate* agar tidak *blocking* UI, atau via Python/Chaquopy) untuk menghitung bobot setiap lagu di dalam *playlist*.  
* **Seamless Integration:** Menghapus logika bawaan *shuffle* milik just\_audio dan menggantinya dengan injeksi antrean kustom yang sudah diurutkan berdasarkan algoritma di atas.

## **7\. Struktur Database**

Pembaruan pada skema SQLite (sqflite) yang sudah ada:

**A. Modifikasi Tabel Saat Ini (songs)**

* Tambah kolom skip\_count (INTEGER) \- *Default: 0*  
* Tambah kolom completion\_count (INTEGER) \- *Default: 0*

**B. Pembuatan Tabel Baru (listening\_history)**

* id (INTEGER PRIMARY KEY AUTOINCREMENT)  
* song\_id (INTEGER) \-\> *Foreign key ke tabel songs*  
* timestamp (INTEGER) \-\> *Waktu pemutaran (Epoch Unix)*  
* duration\_listened (INTEGER) \-\> *Durasi didengarkan dalam milidetik (Opsional, untuk akurasi data)*

## **8\. Output yang Diharapkan**

* **Lagu Segar di Awal:** Saat diacak, 5-10 lagu pertama di antrean dipastikan adalah lagu yang jarang atau belum didengar oleh pengguna dalam 24 jam terakhir.  
* **Transisi Artis Alami:** Pengguna tidak akan menemui 2 atau 3 lagu dari penyanyi/band yang sama diputar secara berturut-turut.  
* **Penguburan Lagu yang Sering Di-skip:** Lagu yang sering dilewati dalam 30 detik pertama akan secara otomatis tenggelam ke bagian paling bawah dari urutan antrean acak.

## **9\. Rules / Constraint**

* **100% Offline-First:** Semua pemrosesan riwayat putar dan algoritma pengurutan **wajib** dilakukan di perangkat (on-device) menggunakan SQLite dan Dart/Python. Tidak boleh ada pengiriman data ke server/API.  
* **No UI Toggle:** Algoritma ini berjalan secara implisit/tersembunyi (Default \= ON saat tombol shuffle aktif). Jangan menambahkan *switch* "Smart Shuffle" di menu pengaturan UI.  
* **Performance / Non-Blocking:** Mengingat IbnuTify menargetkan aplikasi yang *fluid* (60fps), jika jumlah lagu dalam *playlist* sangat banyak (misal \>1000 lagu), pembuatan kandidat *array* (Multi-Sequence Generation) harus dieksekusi di *background thread* (menggunakan Dart compute / Isolate atau dilempar ke Kotlin via *MethodChannel*) agar tidak membuat layar *freeze*.