const MemoryModule = (function () {
  const STORAGE_KEY_PREFIX = "ujian_progress_";
  let studentId = "";

  /**
   * Menginisialisasi modul dengan ID unik siswa.
   * @param {string} namaSiswa - Nama lengkap siswa.
   * @param {string} nis - NIS siswa sebagai pengenal unik.
   */
  const init = (namaSiswa, nis) => {
    // Memastikan data yang masuk adalah string sebelum diproses
    const cleanNama = typeof namaSiswa === 'string' ? namaSiswa.trim() : "Peserta";
    const cleanNIS = typeof nis === 'string' ? nis.trim() : "000";

    // Membuat ID unik untuk kunci localStorage
    // Ganti spasi dengan underscore dan hapus karakter aneh
    const safeNama = cleanNama.replace(/[^a-zA-Z0-9]/g, "_");
    const safeNIS = cleanNIS.replace(/[^a-zA-Z0-9]/g, "");

    studentId = `${STORAGE_KEY_PREFIX}${safeNama}_${safeNIS}`;
  };


  /**
   * Menyimpan progres ujian saat ini ke localStorage.
   * @param {Array} originalSoal - Array soal asli (tidak diacak).
   * @param {Array} jawabanSiswa - Array jawaban siswa.
   */
  const saveProgress = (originalSoal, jawabanSiswa) => {
    if (!studentId) return;
    try {
      // Pastikan jawabanSiswa valid sebelum disimpan
      const cleanJawaban = jawabanSiswa.map(ans => {
        // Jika array (PG Kompleks), pastikan tersimpan sebagai array
        if (Array.isArray(ans)) return ans;
        // Jika null/undefined, simpan null
        if (ans === undefined || ans === null) return null;
        // Lainnya simpan value langsung (string/number/boolean)
        return ans;
      });

      const progress = {
        // Hanya simpan jawaban index-based (karena urutan soal diacak di page-ujian,
        // tapi kita simpan berdasarkan originalIndex di Store, jadi array jawaban sudah map ke originalIndex)
        jawabanSiswa: cleanJawaban,
        timestamp: new Date().getTime(),
      };

      // Gunakan JSON.stringify dengan error handling implisit
      const serialized = JSON.stringify(progress);
      localStorage.setItem(studentId, serialized);
    } catch (e) {
      console.error("Gagal menyimpan progres ujian (Quota/Format):", e);
    }
  };

  /**
   * Memuat progres ujian yang tersimpan dari localStorage.
   * @returns {Object|null} - Objek progres yang tersimpan atau null jika tidak ada.
   */
  const loadProgress = () => {
    if (!studentId) return null;
    try {
      const savedData = localStorage.getItem(studentId);
      if (!savedData) return null;

      const parsedData = JSON.parse(savedData);

      // Validasi struktur data dasar
      if (parsedData && Array.isArray(parsedData.jawabanSiswa)) {
        return parsedData;
      }
      return null;
    } catch (e) {
      console.error("Gagal memuat progres ujian (Corrupt Data):", e);
      // Hapus data korup agar tidak error terus menerus
      localStorage.removeItem(studentId);
      return null;
    }
  };

  /**
   * Menghapus progres ujian dari localStorage setelah ujian selesai.
   */
  const clearProgress = () => {
    if (!studentId) return;
    localStorage.removeItem(studentId);
  };

  return {
    init,
    saveProgress,
    loadProgress,
    clearProgress,
  };
})();
