// PENTING: Ganti URL di bawah ini dengan URL Web App BARU Anda setelah dideploy ulang.
const WEB_APP_URL =
  "https://script.google.com/macros/s/AKfycbzvC0U2-Xo-4mJgUHFnhJZjCMvRPwR9a1J0dGlH4MkVxHp9euNuC_uu1AXjXMNskRXeeQ/exec"; // GANTI URL INI


async function apiCall(action, payload = {}) {
  const requestOptions = {
    method: "POST",
    headers: { "Content-Type": "text/plain;charset=utf-8" },
    body: JSON.stringify({ action, payload }),
    redirect: "follow",
  };

  try {
    const response = await fetch(WEB_APP_URL, requestOptions);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const result = await response.json();

    if (result.status === "success") {
      return result.data;
    } else {
      throw new Error(result.message || "Terjadi kesalahan pada server.");
    }
  } catch (error) {
    console.error("API Call Error:", error.message);
    throw error;
  }
}

// --- FUNGSI-FUNGSI API ---

// Fungsi untuk memvalidasi login (NIS & Kode Akses)
const validateLogin = (credentials) => apiCall("validateLogin", credentials);

// Fungsi untuk mengambil semua data konfigurasi ujian untuk dashboard
const getDashboardData = () => apiCall("getDashboardData");

// Fungsi untuk menyimpan pengaturan ujian dan soal
const saveExamConfig = (config) => apiCall("saveExamConfig", config);

// Fungsi untuk membuat/mereset kode akses
const generateKodeAkses = (payload) => apiCall("generateKodeAkses", payload);

// Fungsi untuk mengambil soal ujian berdasarkan sheet target
const getSoalByKodeAkses = (payload) => apiCall("getSoalByKodeAkses", payload);

// Fungsi untuk mengirim jawaban siswa
const submitJawaban = (data) => apiCall("submitJawaban", data);

// Fungsi untuk mengambil data monitoring
const getMonitoringData = (payload) => apiCall("getMonitoringData", payload);

// Fungsi untuk mengambil riwayat pengulangan siswa
const getRiwayatPengulangan = (payload) => apiCall("getRiwayatPengulangan", payload);

// === FUNGSI BARU UNTUK BUKTI UJIAN ===

/**
 * Fungsi untuk mengambil soal lengkap dengan kunci jawaban
 * Digunakan untuk generate PDF bukti ujian
 * @param {object} payload - Berisi { sheetSoal }
 * @returns {Promise<object>} - Data soal lengkap dengan kunci
 */
const getSoalWithKey = (payload) => apiCall("getSoalWithKey", payload);