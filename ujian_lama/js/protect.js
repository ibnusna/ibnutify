const SecurityModule = (function () {
  // Konfigurasi awal
  let config = {
    violationCount: 5,
    onExamEnd: null,
    audioElement: null,
  };

  // Helper untuk mendapatkan Element aman (handle text node & document)
  const getSafeTarget = (target) => {
    if (!target) return null;
    // Jika target adalah Text Node (Type 3), ambil parent-nya
    if (target.nodeType === 3) return target.parentElement;
    // Jika target adalah Document (Type 9), kembalikan null atau body (karena document gak punya closest)
    if (target.nodeType === 9) return null;
    return target;
  };

  // Fungsi deteksi pintar perangkat iOS (iPhone, iPad, iPod)
  const isIOS = () => {
    return [
      'iPad Simulator',
      'iPhone Simulator',
      'iPod Simulator',
      'iPad',
      'iPhone',
      'iPod'
    ].includes(navigator.platform)
    // iPad pada iOS 13+ detection
    || (navigator.userAgent.includes("Mac") && "ontouchend" in document)
    || (/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream);
  };

  // Fungsi untuk mendeteksi pembukaan Developer Tools
  const devToolsDetector = () => {
    const threshold = 160;
    if (
      window.outerWidth - window.innerWidth > threshold ||
      window.outerHeight - window.innerHeight > threshold
    ) {
      handleCheatingAttempt("Developer Tools Terdeteksi");
    }
  };

  // Fungsi untuk menangani saat pengguna meninggalkan tab/jendela
  const handleVisibilityChange = () => {
    if (document.visibilityState === "hidden") {
      handleCheatingAttempt("Meninggalkan Halaman Ujian / Pindah Tab");
    }
  };

  // Peringatan Ekstra: Saat perangkat berpindah aplikasi / notifikasi (fokus hilang)
  const handleBlur = () => {
    handleCheatingAttempt("Meninggalkan Halaman Ujian / Berpindah Aplikasi");
  };

  // Fungsi untuk memblokir tombol keyboard terlarang dan copy-paste
  const handleKeyDown = (e) => {
    if (e.altKey || e.key === "Tab" || e.metaKey) {
      e.preventDefault();
      handleCheatingAttempt("Tombol Terlarang Ditekan");
    }
    if (e.ctrlKey && ["c", "v", "u"].includes(e.key.toLowerCase())) {
      e.preventDefault();
      handleCheatingAttempt("Copy-Paste Dinonaktifkan");
    }
  };

  // Fungsi untuk mencegah copy pada elemen soal
  const preventCopy = (e) => {
    const target = getSafeTarget(e.target);
    // Cek apakah target valid dan punya method closest
    if (target && typeof target.closest === 'function') {
      if (
        target.closest('.soal-pertanyaan') ||
        target.closest('.soal-pilihan')
      ) {
        e.preventDefault();
        handleCheatingAttempt("Mencoba Menyalin Soal");
      }
    }
  };

  // Fungsi untuk mencegah seleksi teks pada elemen soal
  const preventSelect = (e) => {
    const target = getSafeTarget(e.target);
    // Cek apakah target valid dan punya method closest
    if (target && typeof target.closest === 'function') {
      if (
        target.closest('.soal-pertanyaan') ||
        target.closest('.soal-pilihan')
      ) {
        e.preventDefault();
      }
    }
  };

  // Fungsi untuk mengecek dukungan Fullscreen API
  const isFullscreenSupported = () => {
    // Pengecualian khusus: iOS tidak mendukung fullscreen API secara konsisten
    if (isIOS()) return false;
    const elem = document.documentElement;
    return !!(elem.requestFullscreen || elem.mozRequestFullScreen || elem.webkitRequestFullscreen || elem.msRequestFullscreen);
  };

  // Fungsi untuk memasuki mode fullscreen (Safe Version)
  const enterFullscreen = () => {
    const elem = document.documentElement;
    const requestMethod = elem.requestFullscreen ||
      elem.mozRequestFullScreen ||
      elem.webkitRequestFullscreen ||
      elem.msRequestFullscreen;

    if (requestMethod) {
      try {
        const result = requestMethod.call(elem);
        // Browser modern mengembalikan Promise
        if (result && typeof result.catch === 'function') {
          result.catch(err => {
            // Kita suppress errornya agar tidak merah di console user
            // 'Permissions check failed' wajar terjadi di lingkungan iframe/preview
            console.warn("Fullscreen ditolak browser (aman untuk diabaikan di preview):", err.message);
          });
        }
      } catch (err) {
        // Fallback untuk browser lama
        console.warn("Fullscreen error (Sync):", err.message);
      }
    }
  };

  // Fungsi untuk menangani keluar dari fullscreen (kembali ke sistem pelanggaran)
  const handleFullscreenChange = () => {
    const fullscreenElement = document.fullscreenElement ||
      document.mozFullScreenElement ||
      document.webkitFullscreenElement ||
      document.msFullscreenElement;
    if (!fullscreenElement) {
      handleCheatingAttempt("Keluar dari mode layar penuh");
    }
  };

  // Fungsi utama untuk menangani semua jenis pelanggaran
  const handleCheatingAttempt = (reason) => {
    config.violationCount--;

    if (config.audioElement) {
      config.audioElement.play().catch(e => console.log("Audio play failed"));
    }

    if (config.violationCount <= 0) {
      // Gunakan Swal global jika tersedia
      if (typeof Swal !== 'undefined') {
        Swal.fire({
          icon: "error",
          title: "Batas Pelanggaran Tercapai!",
          text: `Anda telah melakukan pelanggaran berulang kali. Ujian Anda akan dihentikan.`,
          allowOutsideClick: false,
          allowEscapeKey: false,
        }).then(() => {
          if (config.onExamEnd) {
            config.onExamEnd();
          }
        });
      } else {
        alert("Batas pelanggaran tercapai. Ujian dihentikan.");
        if (config.onExamEnd) config.onExamEnd();
      }
      destroy();
    } else {
      if (typeof Swal !== 'undefined') {
        Swal.fire({
          icon: "warning",
          title: "Peringatan Keamanan!",
          html: `Alasan: <strong>${reason}</strong>.<br>Jangan meninggalkan halaman ujian.<br><br>Sisa kesempatan: <strong>${config.violationCount}</strong> kali.`,
          confirmButtonText: "Saya Mengerti",
          allowOutsideClick: false,
          allowEscapeKey: false,
        }).then(() => {
          if (config.audioElement) {
            config.audioElement.pause();
            config.audioElement.currentTime = 0;
          }
          if (isFullscreenSupported()) {
            enterFullscreen();
          }
        });
      }
    }
  };

  const init = (examEndCallback) => {
    config.onExamEnd = examEndCallback;
    config.audioElement = document.getElementById("violationAudio");

    // Daftarkan listener umum yang berlaku untuk semua perangkat
    document.addEventListener("visibilitychange", handleVisibilityChange);
    document.addEventListener("keydown", handleKeyDown);
    document.addEventListener("copy", preventCopy);
    document.addEventListener("selectstart", preventSelect);
    document.body.setAttribute("oncontextmenu", "return false;");

    // Deteksi cerdas: Tambahkan event listener sesuai jenis perangkat
    if (isIOS()) {
      // iOS: Gunakan Blur untuk mendeteksi pindah aplikasi karena fullscreen dimatikan
      window.addEventListener("blur", handleBlur);
    } else {
      // Perangkat Lain: Tetap gunakan deteksi resize (DevTools)
      window.addEventListener("resize", devToolsDetector);
    }

    // Logika adaptif berdasarkan dukungan fullscreen
    if (isFullscreenSupported()) {
      // --- Alur untuk Perangkat yang Mendukung Fullscreen (WAJIB) ---
      const initialModal = document.getElementById("fullscreenModal");
      const enterBtn = document.getElementById("enterFullscreenBtn");

      if (initialModal && enterBtn) {
        document.body.classList.add("modal-active");
        initialModal.style.display = "flex";
        enterBtn.addEventListener("click", () => {
          initialModal.style.display = "none";
          document.body.classList.remove("modal-active");
          enterFullscreen();
        });
      }

      // Daftarkan listener untuk mendeteksi keluar dari fullscreen
      document.addEventListener("fullscreenchange", handleFullscreenChange);
      document.addEventListener("mozfullscreenchange", handleFullscreenChange);
      document.addEventListener("webkitfullscreenchange", handleFullscreenChange);
      document.addEventListener("MSFullscreenChange", handleFullscreenChange);

    } else {
      // --- Alur untuk Perangkat Non-Fullscreen (Gimik Fitur) ---
      if (typeof Swal !== 'undefined') {
        Swal.fire({
          icon: 'info',
          title: 'Pemberitahuan Keamanan',
          html: 'Mode layar penuh tidak didukung di perangkat Anda.<br>Untuk menjaga integritas ujian, <b>pengawasan terhadap perpindahan tab/aplikasi akan ditingkatkan.</b>',
          confirmButtonText: 'Saya Mengerti',
          allowOutsideClick: false,
          allowEscapeKey: false
        });
      }
    }
  };

  // Fungsi untuk membersihkan semua listener saat ujian selesai
  const destroy = () => {
    document.removeEventListener("visibilitychange", handleVisibilityChange);
    window.removeEventListener("resize", devToolsDetector);
    window.removeEventListener("blur", handleBlur);
    document.removeEventListener("keydown", handleKeyDown);
    document.removeEventListener("copy", preventCopy);
    document.removeEventListener("selectstart", preventSelect);
    document.removeEventListener("fullscreenchange", handleFullscreenChange);
    document.removeEventListener("mozfullscreenchange", handleFullscreenChange);
    document.removeEventListener("webkitfullscreenchange", handleFullscreenChange);
    document.removeEventListener("MSFullscreenChange", handleFullscreenChange);
    document.body.removeAttribute("oncontextmenu");
  };

  return {
    init,
    destroy
  };
})();

// EXPOSE TO WINDOW for ES Modules
window.SecurityModule = SecurityModule;

/**
 * PROTECT MODULE
 * Mematikan Klik Kanan, Copy-Paste, Selection, dan Shortcut Keyboard.
 */
(function () {
  "use strict";

  const blockEvent = (e) => {
    e.preventDefault();
    e.stopPropagation();
    return false;
  };

  // 1. Matikan Klik Kanan (Context Menu)
  document.addEventListener('contextmenu', blockEvent);

  // 2. Matikan Seleksi Teks (Highlight) & Dragging
  document.addEventListener('selectstart', blockEvent);
  document.addEventListener('dragstart', blockEvent);

  // 3. Matikan Event Copy, Cut, Paste
  document.addEventListener('copy', blockEvent);
  document.addEventListener('cut', blockEvent);
  document.addEventListener('paste', blockEvent);

  // 4. Matikan Shortcut Keyboard Berbahaya (Ctrl+C, Ctrl+U, F12, dll)
  document.addEventListener('keydown', (e) => {
    // Daftar tombol yang dilarang kombinasi dengan CTRL
    const forbiddenKeys = ['u', 's', 'c', 'v', 'x', 'p', 'a', 'shift', 'i', 'j'];

    // Block F12 (DevTools)
    if (e.key === 'F12' || e.keyCode === 123) {
      blockEvent(e);
    }

    // Block Ctrl + Key
    if (e.ctrlKey || e.metaKey) {
      if (forbiddenKeys.includes(e.key.toLowerCase())) {
        blockEvent(e);
      }
    }
  });

  console.log("🛡️ GARA Security Shield: Active");
})();