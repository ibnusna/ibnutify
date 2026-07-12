import { Store } from './store.js';
import { showModal, closeModal } from './ui-modal.js';

/**
 * PAGE SUMMARY MODULE
 * Menangani logika di halaman summary.html (Halaman Konfirmasi).
 * UPDATE: Menggunakan Loading Overlay modern (bukan Modal Pop-up).
 */

const elements = {
    nis: document.getElementById("summaryNIS"),
    nama: document.getElementById("summaryNama"),
    kelas: document.getElementById("summaryKelas"),
    mapel: document.getElementById("summaryMapel"),
    waktu: document.getElementById("summaryWaktu"),
    btnStart: document.getElementById("startUjianBtn"),

    // NEW Elements
    loadingOverlay: document.getElementById("loadingOverlay"),
    mainLayout: document.getElementById("mainLayout")
};

// --- UTAMA: INISIALISASI ---

export const initSummaryPage = async () => {
    // 1. Tampilkan Loading (Safety check, meski di HTML defaultnya sudah tampil)
    toggleLoading(true);

    // DETEKSI ENVIRONMENT (LMS VS HOSTING)
    detectAndSaveOrigin();

    // Cek parameter URL
    const urlParams = new URLSearchParams(window.location.search);
    const paramNis = urlParams.get('nis');
    const paramToken = urlParams.get('token');

    try {
        // KASUS 1: LOGIN BARU (Ada parameter di URL)
        if (paramNis && paramToken) {
            await handleLoginProcess(paramNis, paramToken);
        }

        // KASUS 2: SUDAH LOGIN (Cek Session)
        // Jika login baru saja berhasil, data sudah di Store.
        if (!Store.isAuthenticated()) {
            throw new Error("Sesi tidak valid. Silakan login kembali.");
        }

        // 2. Render Data ke Layar (Saat masih tertutup loading)
        renderStudentData();

        // 3. Pasang Event Listener Tombol Mulai
        if (elements.btnStart) {
            elements.btnStart.onclick = handleStartExam;
        }

        // Update exit button
        const exitUrl = getExitUrl();
        document.querySelectorAll('.header-logout-btn').forEach(btn => {
            btn.href = exitUrl;
        });

        // 4. SEMUA SIAP -> Matikan Loading, Tampilkan Halaman
        // Beri sedikit delay agar transisi tidak terlalu "kaget" jika internet sangat cepat
        setTimeout(() => {
            toggleLoading(false);
        }, 500);

    } catch (error) {
        console.error("Init Error:", error);
        // Jika gagal total (misal tidak ada sesi), redirect
        window.location.href = getExitUrl();
    }
};

// --- LOGIC HANDLERS ---

const handleLoginProcess = async (nis, token) => {
    // NOTE: Tidak perlu showModal loading lagi, karena sudah pakai Overlay Fullscreen.

    try {
        // 1. Cek Ketersediaan API
        if (typeof validateLogin === 'undefined') {
            throw new Error("Koneksi server (google-apps.js) belum siap.");
        }

        // 2. Request ke Server
        const response = await validateLogin({ nis: nis, kodeAkses: token });

        if (response && response.isValid) {
            // 3. Simpan Data ke Store
            Store.setSiswa(response.siswa);
            Store.setUjianMeta(response.ujian);
            Store.setSavedNIS(nis);

            // 4. Bersihkan URL
            const cleanUrl = window.location.protocol + "//" + window.location.host + window.location.pathname;
            window.history.replaceState({ path: cleanUrl }, "", cleanUrl);

            // Return true menandakan sukses
            return true;
        } else {
            throw new Error("Validasi ditolak oleh server. Token atau NIS salah.");
        }

    } catch (error) {
        // Jika error saat login, tampilkan modal error (di atas loading overlay kalau perlu, 
        // atau matikan loading dulu baru show modal)

        // Matikan loading overlay agar user bisa lihat modal error
        toggleLoading(false);

        showModal({
            title: "Akses Ditolak",
            text: "Gagal masuk ujian: " + (error.message || "Data tidak valid."),
            icon: "error",
            confirmButtonText: "Kembali Login",
            onConfirm: () => {
                const exitUrl = getExitUrl();
                Store.clearAll();
                window.location.href = exitUrl;
            }
        });

        // Stop eksekusi
        throw error;
    }
};

const renderStudentData = () => {
    const siswa = Store.getSiswa();
    const meta = Store.getUjianMeta();

    if (!siswa || !meta) return;

    if (elements.nama) elements.nama.textContent = siswa["Nama Lengkap"];
    if (elements.kelas) elements.kelas.textContent = siswa.Kelas;
    if (elements.nis) elements.nis.textContent = siswa.NIS;

    if (elements.mapel) elements.mapel.textContent = meta.topik;
    if (elements.waktu) elements.waktu.textContent = meta.durasi;
};

const handleStartExam = () => {
    // Tampilkan loading lagi saat transisi ke halaman ujian
    toggleLoading(true);

    Store.clearExamSession();
    window.location.href = "ujian.html";
};

// --- HELPER: EXIT LOGIC (SMART LOGOUT) ---
const getExitUrl = () => {
    const returnUrl = sessionStorage.getItem('exam_return_url');
    if (returnUrl) {
        return returnUrl;
    }

    // 1. Cek Flag Origin dari Session (diset saat Init)
    const origin = sessionStorage.getItem('exam_origin');

    if (origin === 'lms') {
        return 'http://garudakademi.ct.ws';
    }

    // Default: Localhost / Netlify / Hosting
    return 'index.html';
};

const detectAndSaveOrigin = () => {
    const urlParams = new URLSearchParams(window.location.search);
    const returnUrl = urlParams.get('return_url');
    if (returnUrl) {
        sessionStorage.setItem('exam_return_url', returnUrl);
    }

    // 1. PRIORITAS UTAMA: Cek Session Storage
    // Jika sudah pernah terdeteksi sebagai 'lms', JANGAN diubah lagi.
    // Ini penting untuk Android WebView/Browser: Jika user me-refresh halaman, 
    // 'document.referrer' seringkali hilang/kosong. Jika kita cek ulang, 
    // sistem akan salah mengira ini 'hosting'. Jadi, sekali 'lms', tetap 'lms'.
    if (sessionStorage.getItem('exam_origin') === 'lms') {
        return;
    }

    const hostname = window.location.hostname;
    const referrer = document.referrer || "";

    // 2. DETEKSI BARU (Jika belum ada di session)
    // Cek apakah hostname saat ini ATAU pengarah (referrer) berasal dari domain LMS
    if (hostname.includes('garudakademi.ct.ws') || referrer.includes('garudakademi.ct.ws') || returnUrl) {
        sessionStorage.setItem('exam_origin', 'lms');
    } else {
        // Jika tidak ada tanda-tanda LMS, barulah kita set sebagai hosting
        sessionStorage.setItem('exam_origin', 'hosting');
    }
};

// --- HELPER: UI CONTROL ---

const toggleLoading = (show) => {
    if (show) {
        if (elements.loadingOverlay) elements.loadingOverlay.style.display = 'flex';
        if (elements.mainLayout) elements.mainLayout.style.display = 'none';
    } else {
        // Fade out animation manual handling or just simple switch
        if (elements.loadingOverlay) elements.loadingOverlay.style.display = 'none';
        if (elements.mainLayout) elements.mainLayout.style.display = 'flex';
    }
};