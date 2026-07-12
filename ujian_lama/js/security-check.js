const SecurityCheckModule = (function () {
  const STORAGE_KEY_PREFIX = "ujian_selesai_";

  /**
   * Membuat kunci unik untuk localStorage berdasarkan nama dan kelas.
   * @param {string} nama Nama siswa.
   * @param {string} kelas Kelas siswa.
   * @returns {string} Kunci unik untuk localStorage.
   */
  function generateStorageKey(nama, kelas) {
    const normalizedNama = nama.trim().toLowerCase();
    const normalizedKelas = kelas.trim().toLowerCase();
    return `${STORAGE_KEY_PREFIX}${normalizedNama}_${normalizedKelas}`;
  }

  /**
   * Memeriksa localStorage untuk melihat apakah siswa sudah ditandai selesai.
   * @param {string} nama Nama siswa.
   * @param {string} kelas Kelas siswa.
   * @returns {boolean} True jika sudah selesai, false jika belum.
   */
  function hasCompletedLocally(nama, kelas) {
    const key = generateStorageKey(nama, kelas);
    return localStorage.getItem(key) === "true";
  }

  /**
   * Menandai siswa sebagai telah menyelesaikan ujian di localStorage.
   * @param {string} nama Nama siswa.
   * @param {string} kelas Kelas siswa.
   */
  function markAsCompleted(nama, kelas) {
    const key = generateStorageKey(nama, kelas);
    localStorage.setItem(key, "true");
  }

  return {
    hasCompletedLocally,
    markAsCompleted,
  };
})();
