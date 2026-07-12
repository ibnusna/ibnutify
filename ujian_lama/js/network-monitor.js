/**
 * NETWORK STATE LOGIC LAYER (GLOBAL)
 * Bertugas memantau koneksi di halaman UTAMA (index, ujian, dll).
 * Jika OFFLINE -> Simpan URL -> Redirect ke eror.html
 */

(function () {
    'use strict';

    const ERROR_PAGE_URL = 'eror.html';

    function handleOffline() {
        console.warn('[Network] Connection lost! Redirecting to error page...');

        // 1. Simpan URL saat ini agar bisa kembali check-in
        // Jangan simpan jika kita sudah di halaman error (loop prevention)
        if (window.location.pathname.indexOf(ERROR_PAGE_URL) === -1) {
            sessionStorage.setItem('last_active_page', window.location.href);
        }

        // 2. Redirect Paksa
        window.location.replace(ERROR_PAGE_URL);
    }

    // Pasang Event Listener
    window.addEventListener('offline', handleOffline);

    // Cek status awal saat script dimuat (double check)
    if (!navigator.onLine) {
        handleOffline();
    }

    console.log('[Network] Monitor aktif. Menunggu sinyal offline...');
})();
