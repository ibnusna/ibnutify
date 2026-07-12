/**
 * RUANG UJIAN - ENVIRONMENT IDENTITY
 * 
 * Skrip ini berfungsi untuk mendeteksi apakah website dibuka melalui:
 * 1. Aplikasi Desktop "Ruang Ujian" (Electron/WebView2)
 * 2. Browser Standar (Chrome, Edge, Firefox, dll)
 * 
 * Jika terdeteksi di dalam aplikasi, skrip ini akan menyuntikkan class
 * khusus ke <html> agar CSS bisa menyembunyikan elemen navigasi keluar.
 */

// Fungsi Utama Deteksi
function checkEnvironment() {
    // 1. Cek Global Variable (Disuntikkan oleh Preload Electron)
    const isElectronApp = window.isRuangUjian === true;

    // 2. Cek User Agent (String unik 'RuangUjian')
    const isUserAgentMatch = navigator.userAgent.includes('RuangUjian');

    // Kriteria: Salah satu terpenuhi dianggap Mode Aplikasi
    const isAppMode = isElectronApp || isUserAgentMatch;

    const htmlEl = document.documentElement;

    if (isAppMode) {
        // --- MODE APLIKASI ---
        htmlEl.classList.add('is-ruang-ujian');
        console.log("%c[Ruang Ujian] Mode Aplikasi Terdeteksi: Navigasi eksternal dimatikan.", "color: green; font-weight: bold;");
    } else {
        // --- MODE BROWSER BIASA ---
        htmlEl.classList.add('is-standard-browser');
        console.log("%c[Ruang Ujian] Mode Browser Standar.", "color: blue;");
    }
}

// Jalankan segera setelah DOM siap
// Gunakan 'interactive' atau 'DOMContentLoaded' agar lebih cepat dari 'load'
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', checkEnvironment);
} else {
    checkEnvironment();
}
