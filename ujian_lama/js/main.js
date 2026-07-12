/**
 * MAIN ENTRY POINT
 * Menggantikan 'app-siswa.js'.
 * Bertugas sebagai router sederhana untuk memanggil modul yang sesuai dengan halaman aktif.
 */

import { initSummaryPage } from './modules/page-summary.js';
import { initUjianPage } from './modules/page-ujian.js';
import { initHasilPage } from './modules/page-hasil.js';

document.addEventListener("DOMContentLoaded", () => {
    // Ambil nama file dari URL (contoh: 'ujian.html')
    const path = window.location.pathname.split("/").pop();

    console.log(`[App] Current Page: ${path || 'root'}`);

    // Router Logic
    // Mencocokkan nama file dengan fungsi inisialisasi modul
    if (path === "summary.html" || path === "") {
        // Halaman Konfirmasi / Root
        initSummaryPage();
    } else if (path === "ujian.html") {
        // Halaman Ujian Utama
        initUjianPage();
    } else if (path === "hasil.html") {
        // Halaman Hasil & Download PDF
        initHasilPage();
    }
});