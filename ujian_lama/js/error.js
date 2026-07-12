/**
 * RECOVERY LOGIC (ERROR PAGE)
 * Bertugas memantau status koneksi saat di halaman eror.
 * Jika ONLINE -> Redirect kembali ke halaman terakhir (last_active_page).
 */

(function () {
    'use strict';

    const btnReload = document.getElementById('reloadBtn');
    const icon = document.getElementById('btnIcon');
    const text = document.getElementById('btnText');
    const mainWindow = document.getElementById('main-window');
    const DEFAULT_PAGE = 'index.html';

    // --- UTILS ---

    function getRedirectTarget() {
        const lastPage = sessionStorage.getItem('last_active_page');
        // Validasi agar tidak loop ke eror.html sendiri
        if (lastPage && lastPage.indexOf('eror.html') === -1) {
            return lastPage;
        }
        return DEFAULT_PAGE;
    }

    function setUIState(state) {
        if (!btnReload || !icon || !text || !mainWindow) return;

        if (state === 'checking') {
            btnReload.disabled = true;
            icon.classList.add('spin-anim');
            text.innerText = "Memeriksa...";
            mainWindow.classList.remove('shake');
        } else if (state === 'online') {
            text.innerText = "Terhubung!";
            icon.classList.remove('spin-anim');
            btnReload.disabled = false;
        } else if (state === 'offline') {
            text.innerText = "Coba Lagi";
            icon.classList.remove('spin-anim');
            btnReload.disabled = false;

            // Effect shake
            mainWindow.classList.add('shake');
            setTimeout(() => mainWindow.classList.remove('shake'), 500);
        }
    }

    // --- CORE LOGIC ---

    async function attemptRecovery() {
        setUIState('checking');

        // Simulasi delay sedikit biar smooth transisinya, 
        // dan memastikan navigator.onLine sudah update.
        await new Promise(r => setTimeout(r, 1000));

        // Cek Koneksi Real
        if (navigator.onLine) {
            // ONLINE!
            setUIState('online');

            console.log('[Recovery] Connection restored. Redirecting...');
            const target = getRedirectTarget();

            setTimeout(() => {
                window.location.replace(target);
            }, 500);

        } else {
            // MASIH OFFLINE
            setUIState('offline');
            console.warn('[Recovery] Still offline.');
        }
    }

    // --- EVENT LISTENERS ---

    // 1. Tombol Manual
    if (btnReload) {
        btnReload.onclick = (e) => {
            e.preventDefault(); // Mencegah form submit default jika ada
            attemptRecovery();
        };
    }

    // 2. Auto-Detect saat 'online' event trigger
    window.addEventListener('online', () => {
        console.log('[Recovery] Online event detected!');

        // Update UI Text agar user tahu koneksi sudah ada
        const title = document.querySelector('.error-title');
        const desc = document.querySelector('.error-desc');

        if (title) title.innerText = "Koneksi Pulih";
        if (desc) desc.innerText = "Internet Anda sudah kembali. Mengalihkan...";

        // Langsung coba recovery otomatis
        attemptRecovery();
    });

    // 3. Interval Check (Opsional, sebagai fallback jika event listener gagal)
    setInterval(() => {
        if (navigator.onLine) {
            // Jangan spam check jika sudah proses redirect
            if (text && text.innerText !== "Terhubung!") {
                // attemptRecovery(); // Opsional: Auto-redirect tanpa interaksi
                // Untuk UX lebih sopan, kita biarkan event 'online' yg handle atau user klik.
                // Tapi kalau mau agresif, bisa uncomment baris atas.
            }
        }
    }, 5000);

})();
