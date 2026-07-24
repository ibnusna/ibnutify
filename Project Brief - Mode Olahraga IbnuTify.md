# **Project Brief: Mode Olahraga (Offline GPS Tracking & BPM Pace Match Integration)**

## **1\. Judul Fitur**

Mode Olahraga IbnuTify: Pelacakan GPS Offline & Integrasi Musik Berbasis ![][image1] (Pace Match)

## **2\. Tujuan Fitur**

* Memungkinkan pengguna merekam aktivitas olahraga luar ruangan secara **100% offline** (tanpa internet) dengan perhitungan jarak, durasi, dan rute GPS yang akurat.  
* Menyediakan integrasi otomatis antara ritme olahraga dengan antrean pemutaran musik berbasis ![][image1] (Beats Per Minute) dari database lokal IbnuTify.  
* Menjaga antarmuka utama (HomeScreen) tetap bersih dan tidak terganggu (*Clean UI*) dengan menyediakan titik akses terisolasi melalui Top Bar dan Menu Opsi Lagu.

## **3\. Deskripsi Singkat**

Fitur ini adalah sistem pelacak olahraga terpadu berbasis GPS lokal dan pemutar musik pintar (*Pace Match*) untuk platform Android. Pengguna dapat memicu mode ini melalui menu titik tiga (\[...\]) pada lagu untuk memutar musik ber-tempo seirama (![][image2]), atau melalui ikon olahraga \[🏃\] di Top App Bar HomeScreen. Seluruh data riwayat latihan, metrik performa, dan koordinat rute disimpan secara aman di SQLite lokal (activities) tanpa bergantung pada koneksi internet.

## **4\. Spesifikasi Teknologi & Arsitektur**

* **Framework & Language:** Flutter (Dart)  
* **State Management:** Riverpod (flutter\_riverpod)  
* **Audio & Service Engine:** just\_audio \+ audio\_service \+ Dual Android Foreground Service (FOREGROUND\_SERVICE\_MEDIA\_PLAYBACK & FOREGROUND\_SERVICE\_LOCATION).  
* **Database:** SQLite (sqflite) \- Mengakses tabel songs (kolom bpm) dan tabel baru activities.  
* **Target OS:** Android (Minimum API 26 / Android 8.0).  
* **UI Architecture:** Native Flutter Widgets (Diadaptasi dari acuan desain HTML/CSS).

## **5\. Pengguna / Stakeholder**

* **End-User:** Pelari, pesepeda, atau pejalan kaki yang menyukai mendengarkan musik selaras ritme tanpa koneksi internet.  
* **Frontend / UI Developer:** Bertanggung jawab mengonversi acuan mockup HTML ke kode *Native Flutter Widget* serta mengelola navigasi screen.  
* **Core / Service Developer:** Bertanggung jawab atas pengelolaan LocationService (GPS Haversine), AudioHandler dual-service, dan interaksi SQLite database.

## **6\. User Flow**

### **A. Alur Memulai via Pemutar Musik (Pace Match / Auto-BPM)**

1. Pengguna sedang memutar lagu di PlayerScreen atau melihat daftar lagu.  
2. Pengguna membuka menu titik tiga (\[...\]) \-\> Memilih **"🏃 Mulai Mode Olahraga"**.  
3. Sistem membaca ![][image1] lagu tersebut dari SQLite, menguraikan antrean *playlist* lagu yang memiliki ![][image3] (untuk lari/sepeda), lalu mengarahkan ke WorkoutActiveScreen.  
4. GPS dan Timer pelacakan langsung berjalan aktif.

### **B. Alur Memulai via Top Bar (Direct Access & History)**

1. Pengguna berada di HomeScreen \-\> Mengetuk **Ikon Olahraga (\[🏃\]wajib pakai icon bukan emoji)** di Top App Bar (sebelah ikon lonceng & pengaturan).  
2. Sistem membuka WorkoutHistoryScreen (Layar Riwayat).  
3. Pengguna melihat daftar riwayat lama atau mengetuk tombol **\[+ Baru\]** untuk memilih jenis olahraga dan memulai pelacakan.

### **C. Alur Selesai & Penyimpanan (Save Action)**

1. Pengguna selesai berolahraga \-\> Menekan tombol **STOP / SELESAI** di WorkoutActiveScreen.  
2. Sistem mengarahkan ke WorkoutSummaryScreen yang menampilkan ringkasan jarak, durasi, rata-rata pace, serta peta rute GPS.  
3. Pengguna mengetuk tombol **\[💾 SIMPAN KE RIWAYAT SAYA\]**.  
4. Sistem memproses penulisan data ke database SQLite activities dan membawa pengguna ke WorkoutHistoryScreen.

## **7\. Feature Requirements**

### **FR-1: Clean UI & Non-Intrusive Access**

* **Mandat UI:** HomeScreen **TIDAK BOLEH** memiliki banner besar olahraga di bagian *body*.  
* Aksesibilitas olahraga dibatasi hanya pada:  
  1. Ikon \[🏃\] di Top App Bar HomeScreen.  
  2. Menu titik tiga (\[...\]) di song\_options\_bottom\_sheet.dart.

### **FR-2: HTML to Native Flutter UI Conversion Mandate**

* Developer **WAJIB** melakukan analisis terhadap dokumen/mockup HTML yang dilampirkan oleh desain.  
* Elemen visual, skema warna, tata letak (*layout*), dan hirarki antarmuka pada dokumen HTML tersebut harus dikonversi sepenuhnya menjadi komponen **Native Flutter Widget** (bukan menggunakan WebView).

### **FR-3: GPS Location Tracking & Haversine Formula**

* Mengambil titik koordinat GPS (Latitude, Longitude) secara berkala di latar belakang.  
* Menghitung akumulasi jarak aktual desimal (KM) secara otomatis menggunakan kalkulasi matematis ![][image4].

### **FR-4: Integration with Song BPM (Pace Match)**

* Saat mode olahraga dipicu, sistem harus melakukan *query* ke SQLite songs untuk menyaring lagu-lagu dengan batasan ![][image1] tertentu (misal: ![][image2] untuk Berlari/Sepeda, dan ![][image5] untuk Berjalan).

### **FR-5: Dual Foreground Service (Background Persistence)**

* Memastikan pemutaran musik dan pelacakan lokasi GPS tidak dihentikan oleh pembunuh memori OS Android (*OS Memory Killer*) saat layar HP dimatikan.

### **FR-6: Explicit Offline Data Storage**

* Menyediakan aksi konfirmasi simpan eksplisit di WorkoutSummaryScreen untuk menulis data ke SQLite, termasuk UI mapsnya.

## **8\. Struktur Database (sqflite)**

### **Tabel Baru: activities**

CREATE TABLE activities (  
  id INTEGER PRIMARY KEY AUTOINCREMENT,  
  sport\_mode TEXT NOT NULL,         \-- 'Berlari', 'Sepeda', 'Berjalan', 'Mendaki'  
  duration INTEGER NOT NULL,           \-- Total durasi dalam detik (misal: 1965\)  
  distance REAL NOT NULL,              \-- Total jarak dalam KM desimal (misal: 5.25)  
  route\_points TEXT NOT NULL,          \-- JSON String array koordinat: \[{"lat":..,"lng":..}\]  
  created\_at TEXT NOT NULL             \-- Tanggal eksekusi ISO8601 (misal: 2026-07-24T07:30:00)  
);

### **Keterkaitan Tabel Eksisting: songs**

* Mengakses kolom bpm (REAL) pada tabel songs untuk memfilter antrean lagu terintegrasi.

## **9\. Output yang Diharapkan**

1. **Penerapan UI Native Presisi:** Tampilan antarmuka Flutter native yang mengadopsi struktur visual dari dokumen acuan HTML secara rapi.  
2. **Kinerja Offline Stabil:** Pelacakan GPS dan pemutaran audio ber-BPM tinggi berjalan harmonis tanpa lag, *freeze*, atau *crash*.  
3. **Penyimpanan Data Aman:** Data aktivitas fisik tersimpan secara permanen di SQLite lokal HP pengguna.

## **10\. Rules / Constraint (Aturan & Batasan)**

1. **Clean Main Interface Rule:** Dilarang menempatkan widget berukuran besar terkait olahraga di *body* HomeScreen. UI utama IbnuTify harus tetap berfokus sebagai pemutar musik.  
2. **100% Offline & On-Device Processing:** Dilarang menggunakan API/SDK pihak ketiga yang membutuhkan koneksi internet (seperti Google Maps API online). Pengabaian peta online dapat diwakili dengan renderer koordinat *canvas/offline path*.  
3. **Strict HTML Analysis Directive:** Saat dokumen HTML dilampirkan, developer harus menguraikan struktur *CSS/DOM*\-nya untuk diterjemahkan ke *Flexbox/Column/Row/Container* Flutter secara tepat.  
4. **GPS Permission & Fallback Handling:** Jika izin lokasi ditolak pengguna, sistem wajib memberikan dialog peringatan tanpa membuat aplikasi *force close*.  
5. Dilarang pakai emoji semua wajib pakai icon  
6. Transisi harus mulus semua  
7. Wajib melakukan debugging analyze jika sudah beres dan jalankan flutter run untuk debug

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADMAAAAaCAYAAAAaAmTUAAADHklEQVR4Xu2WTUiUURSGR6Oy6L9m0ej46czQxBQpDhW0iqI/Cgqi2rQSKnSTizZCEbUIoggiaBX0R4s2UlBSStivZeCmhVIEQWSaRAVhYhL2nPHcPN6cmWj9vXC4977vOeeee+fe+00kEiJEiBCC6urqNUEQtGMfsTGsR8c5q6ysfK/9dTauqqqqDO0e/FuNG7Bx2Gf0+/jVuhi4s1if+o+hH7A5LbLZ7HR8Hqrvd+1PqiEvcLyugUstH4/Hk3DD2Jfy8vLFVhNQbIPGNVo+lUrNg+vG+mOx2BLHa75nGnPSxliQdxfWhs8o7QJfLwiC3hH00ucF7GCXTE4hq30t0E3AJzOFdkG1P7+ALr4RG6F/1fo7cFpqiMniM4Q98fWCoMiVulNnfE2TitbLcJonl8IPyFH0+BzQOiSWorc6jv7NioqKFO0r7LH1F8jxIt9BbKNuxHHfpyBI2qQFb3BcJpOZITsKN0j7KJFILLMxAuLW6oRXfA1uheZ8wLBE6RLG3dKhbcH6JiLGQdxeFjuL9pRuxHrfpyAIuqsTywTnsGMku0z7lWQnfH8H9KMaV+847spMYjfpzt+290Ufm4saK4/BWDQaneN0/Gvhtqku92oIrszpRcFkswkapoBbvia7gjaKXfM1QTDx2rwIxl+wXuwn1krsTt8frhltt/ZzDwcLXCVj+TXgTks/nU7P1XlbbXxRkGyzJCVRk68JtFDRl1ueYzcf/lcwxVHJB3K0UfQi7W/RvLlF06/nV41Kn43dIRp2xMYXheyG7lCNrwnQ+kWXS2t5JtyjE16yfD7IccL3qRtLPl1ME7kSgR4vgasJq3PcP4GATinY5wVMsl+TtvuaLEKL2edrU0F+AXeMBPpRlG/I+cD7BbSmQbqlli8InuSYFnvD8vo8Hob/QdslflYXBPrld8emCOQJb6HwQ5aEe431MMdCxyWTybgsMshzT/8CjnXB+F2QyyqL+RCYvyJM+kbON9YQMd8WPSod2DeNk3jxbzbpJ0F3/pP6S5F3nCaPDuPt2pfv2XNsxPh2ygs4kS1EiBAhQoQI8d/4DYbEBrHcYa1EAAAAAElFTkSuQmCC>

[image2]: <data:image/png;base64,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>

[image3]: <data:image/png;base64,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>

[image4]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGIAAAAaCAYAAABM1ImiAAAEmklEQVR4Xu2Ye4iVRRjGz6rdL2iwLezlzLcXWt0ogi0UojSCiorEMDBNiC7/RBBFFw0kkrKLJV3ULIPubBG5SqTmuhqVdDGLKLYyMqi06I9Sgg0Vsd+z8842O551TyDIxjzwMjPP887MO9833ztzTqmUkZGRkZGRMXpQLpfPd871YHuwg1h/URTvY5ch16Cvh+sz7QD8p9gj6TijEaynmbVsxx5OtaMGglplD7u5gjZbGgHPS7XRDDZZC+vaxbqmp9rRQg0B/Y59ngoC/Ct6EU1NTeelWsYRBDtisu34Sp/oOLTd2K/Ux6RixhEED3mBXgSf6sWpxsuZaimrK9UCLHX16GyhfA67F1sS9NbW1tNpL8M+Y465gaf+LtxboR0ANwntGcrN2DZsaaTdivVim5hvCmU3thF7MB6js7PzGHGmaZyujo6OY6XZxtO5uCWORzrtF+H7KB+qra092fn1KG1/QL/5uNUMTmJwh4n3P8Ee4MER7Ja0nwC/mCB+cna2UN4gfwtaUNrrJa21Uj6O/Rz64rNBvm1tbcdF3Dy4XyjPCRztrczR4fyCX7C6YvoKv/GUD6jd2Nh4WtRnZWGXCjZCE+3vsdk0x1J+yJynUi7GdkV9bsKudrYGbC1x10tjrFniNHfwN37YeGO/EWEL0aSbUk2Af8/0SRW0y027MXDNzc0XimPcqWqzkAtoL6RaA7edenfwJdgzaX8b2tTnqC99rlIb/+MZ7xK4dTTH4X9f2d/yBvzQp1m/x1yyUWj/JV71hoaGRurLtVbFV9jOhvsOeznqs0pzYk9Q79fmCRrzztSc8QMeKd7gVxXCBAxyf6rV1dWdhHYA25lqAvxH2N/aXRGntLSP3XlC7GsBap5ZgaNewL0W2tS3ygdbgi0kthW4XKsFBh9BPPofVMfGfAz37wbSdXwDD+vcRL/I4rk05k37Ansn4Z7HdiRcVfFWBedz93Dnw3SbaGWq2actTW9/EM7n3kO+LpunX3k3cIw/P34x6PuJY3VoDwf8+ui3JuVj2Ll0h2LH/lSfWHf+JvhjKXmZrKvW1nVn4LSpaO8mtkWxb7XxVgUFiO1Nd7BpT1tQc1LNDrIhX5JyNNw+caY/FTTqW7CNoV3yt7FeHaqRzw+uwktXCgv5v6WlpWwx3ZX6Ccw9De037cyIu91FKdBS1V7GvafkU+azQYO7RuMz31kRN9fWOpH5z3A+1VYVb1XQwLaozakmOP+J6muZkGqC+jHGk9bUg33V/K/DblYZfKm/jrbNHrzy8zL6Tgm6APco9iX8+MDR70q4j8PC0K7XHMP9psH/Nud/pE1U225P3XqYwYf2DI1hL2SGYo205e7QFLQU+0b1sr9VDZyX1cR7WNBxMh0+ocN+BYTtxHrKPj2NQV/j/OcsTaZ0M+R6aOMU8G9ja+m7Wgdz2V9JdxT+Sxm86nFGtMN/LQ2fFdjMaKgBwE2wufZonMLfqhYUUc6Fv1vzlSpcI4X29vZT8H8Jnzcp38B/kR5O7FNfX38iepfzh/OQfwu0Dpd8bcR+tsWla+wVke+I8WZkZGRkZGRkZGRkZGT8D/EP/mqVK7E/MikAAAAASUVORK5CYII=>

[image5]: <data:image/png;base64,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>