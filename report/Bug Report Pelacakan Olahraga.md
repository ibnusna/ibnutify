# **🐛 Bug Report**

## **Bug Information**

| Field | Value |
| :---- | :---- |
| Bug ID | BUG-TRK-001 |
| Title | Pelacakan Olahraga (GPS & Sensor) Gagal Berjalan dan Salah Deteksi Aktivitas |
| Status | Open |
| Priority | High |
| Severity | Critical |
| Module | Workout Mode & Sensor Fusion |
| Reported By | QA / User |
| Date | 2026-08-24 |

## **Executive Summary**

Sistem pelacakan kebugaran (GPS, jarak, dan sensor langkah) berhenti berfungsi setelah beberapa detik sesi dimulai. Meskipun waktu (timer) terus berjalan (contoh: 1 jam), aplikasi hanya merekam jarak yang sangat tidak masuk akal (0.28 KM), 0 langkah, dan stuck di 2 titik GPS. Selain itu, modul *ActivityClassifier* mengalami malfungsi dengan mendeteksi aktivitas "Berlari" sebagai "Sepeda". Masalah ini muncul setelah pembaruan dari versi 1\.

## **Environment**

## **Frontend**

* Framework: Flutter  
* Version: (Sesuai versi build terakhir)  
* Browser: N/A  
* Device: Android

## **Backend**

* Framework: Dart (Local Isolate) & Python (Chaquopy)  
* Version: \-  
* PHP Version: N/A  
* Database: SQLite (Local)

## **Mobile (Jika Ada)**

* Framework: Flutter  
* Android Version: Android 12/13 (Berdasarkan UI OneUI Samsung)  
* iOS Version: N/A  
* Device Specific: Samsung SM-A037F (Galaxy A03s)

## **Current Behavior**

* Waktu (timer) berjalan normal.  
* Jarak (KM) tidak bertambah atau sangat melenceng (berlari 20km tercatat 0km; 1 jam tercatat 0.28km).  
* Indikator Pace (--'--"/km atau angka absurd seperti 218'51"/km).  
* Sensor Pedometer mati total (0 Langkah, \-- spm).  
* Peta hanya menangkap titik awal (stuck di "2 titik GPS").  
* Klasifikasi aktivitas salah (Mode Berlari terdeteksi sebagai Sepeda).

## **Expected Behavior**

* GPS terus merekam rute secara *real-time* dan menambah titik koordinat selama pengguna bergerak.  
* Jarak, Pace, dan Langkah (Pedometer) terhitung akurat sesuai dengan pergerakan fisik.  
* Sistem pendeteksi aktivitas (ActivityClassifier) mengunci mode sesuai pilihan pengguna atau mendeteksi gerakan langkah dengan benar.

## **Reproduction Steps**

1. Buka aplikasi dan masuk ke menu Olahraga.  
2. Pilih mode "Berlari".  
3. Tekan tombol Mulai (Terdapat jeda saat mencari GPS).  
4. Lakukan aktivitas berlari secara nyata selama lebih dari 10 menit.  
5. Kunci layar (Lock Screen) atau biarkan aplikasi menyala.  
6. Cek layar: Waktu terus berjalan, tetapi Jarak, Langkah, dan Titik GPS terhenti.  
7. Muncul teks indikator salah: "Terdeteksi: Sepeda".

Hasil:

Data olahraga gagal terekam sepenuhnya.

## **Frequency**

* \[x\] Selalu terjadi  
* \[ \] Kadang terjadi  
* \[ \] Sulit direproduksi

Keterangan:

Terjadi 100% setiap percobaan pada versi aplikasi saat ini.

## **Error Message**

*(Tidak ada error log crash yang terlihat di UI karena ini adalah silent failure di background, namun simulasi log di background isolate menunjukkan hal berikut:)*

W/ActivityManager: Background execution not allowed: receiving Intent { act=android.location.PROVIDERS\_CHANGED }  
E/SensorFusionEngine: Failed to receive accelerometer data in background isolate.  
W/ActivityClassifier: 0 steps detected over 60 seconds, falling back to Cycling heuristic.

## **Stack Trace**

\#0      SensorFusionEngine.\_onLocationUpdate (package:ibnutify/services/SensorFusionEngine.dart:142)  
\#1      WorkoutTaskHandler.onRepeatEvent (package:ibnutify/services/WorkoutTaskHandler.dart:88)  
\#2      FlutterForegroundTask.\_methodCallHandler (package:flutter\_foreground\_task/flutter\_foreground\_task.dart:210)  
... (Background Isolate Silently Terminated by OS)

## **Screenshots / Video**

## **Before Error**

* (User menekan tombol mulai, timer 00:00:19, jarak 0.00 KM, 2 titik GPS) \-\> Sesuai referensi image\_0c4385.png.

## **After Error**

* (Timer 01:00:14, jarak 0.28 KM, langkah 0, 2 titik GPS, Terdeteksi: Sepeda) \-\> Sesuai referensi image\_0c4423.png.  
* (Riwayat olahraga menunjukkan pace 1823'54"/km) \-\> Sesuai referensi image\_0c3800.png.

## **Related Files**

1. lib/services/WorkoutTaskHandler.dart (Isolate untuk background tracking)  
2. lib/services/SensorFusionEngine.dart (Logika perhitungan GPS dan Langkah)  
3. lib/services/ActivityClassifier.dart (Algoritma pendeteksi aktivitas)  
4. android/app/src/main/AndroidManifest.xml (Konfigurasi izin lokasi latar belakang)

## **Related Database Tables**

* activities

## **Last Changes**

Menambahkan beberapa fitur baru setelah versi 1 (kemungkinan integrasi library musik just\_audio\_background yang memicu konflik Service, atau update logika SensorFusion).

## **Suspected Cause**

1. **Background Isolate Suspension:** Android OS membunuh akses lokasi dan sensor (Pedometer) pada *background isolate* karena tidak adanya izin ACCESS\_BACKGROUND\_LOCATION yang valid, atau karena bentrokan status *Foreground Service* dengan pemutar musik. Waktu (timer) tetap berjalan karena dihitung di UI (Main Thread), bukan di Isolate.  
2. **Activity Classifier Bug:** Karena pedometer mati (0 langkah), *heuristik ActivityClassifier* berasumsi pengguna sedang meluncur/bersepeda tanpa melangkah, sehingga secara paksa menimpa status "Berlari" menjadi "Sepeda".

## **Investigation Notes**

* Waktu (Timer) berhasil dihitung di *Main Thread*.  
* *Background Isolate* untuk GPS dan Pedometer mati mendadak setelah titik ke-2.  
* Kalkulasi Pace rusak karena pembagian (Jarak / Waktu) mendekati nol (Division by Zero/NaN handling).  
* Perhitungan Kalori tetap berjalan menggunakan *fallback* durasi, meskipun tidak ada pergerakan.

## **Impact Analysis**

Siapa yang terdampak?

* Semua Pengguna (User) yang menggunakan fitur Olahraga.

## **Business Impact**

Fitur utama (Unique Selling Proposition) dari aplikasi ini mati total. Pengguna merasa tertipu karena usahanya (berlari 20km/1 jam) tidak dihargai oleh aplikasi, berisiko menyebabkan *uninstall* massal dan turunnya retensi pengguna.

## **AI Debugging Instructions**

## **Mandatory Rules**

1. Jangan langsung mengubah kode.  
2. Lakukan root cause analysis terlebih dahulu.  
3. Buat minimal 5 hipotesis penyebab.  
4. Validasi setiap hipotesis menggunakan bukti kode.  
5. Jangan membuat asumsi.  
6. Jangan menghapus kode tanpa alasan.  
7. Jangan melakukan refactor yang tidak berkaitan.  
8. Lakukan re-check sebelum implementasi.

## **Required Investigation Workflow**

AI wajib mengikuti urutan berikut:

1. Read Code  
2. Trace Flow  
3. Create Hypothesis  
4. Validate Hypothesis  
5. Find Root Cause  
6. Create Fix Plan  
7. Risk Analysis  
8. Implement Fix  
9. Re-Test  
10. Final Report

## **Success Criteria**

Bug dianggap selesai jika:

* Bug tidak muncul lagi (Tracking berjalan mulus hingga \>1 jam di background).  
* Tidak ada error baru (Crash pemutar musik tidak kambuh).  
* Semua test lulus (Perhitungan jarak akurat dan sensor langkah terbaca).  
* Fitur lain tidak rusak.  
* Root cause teridentifikasi.