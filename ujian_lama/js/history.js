/**
 * Memverifikasi riwayat ujian siswa dengan memanggil API.
 * Fungsi ini akan menonaktifkan tombol mulai jika siswa sudah mengerjakan.
 */
async function verifyExamHistory() {
  const namaSiswa = sessionStorage.getItem("siswaNama");
  const startBtn = document.getElementById("startFullscreenBtn");

  // Pastikan nama siswa dan tombol ada di halaman
  if (!namaSiswa || !startBtn) {
    console.error(
      "Nama siswa atau tombol mulai tidak ditemukan di halaman summary."
    );
    return;
  }

  try {
    // Tampilkan status loading di tombol untuk UX yang lebih baik
    startBtn.disabled = true;
    startBtn.innerHTML =
      '<i class="fas fa-spinner fa-spin"></i> Memuat Soal...';

    const result = await checkStudentHistory(namaSiswa);

    if (result.hasSubmitted) {
      // Jika siswa DITEMUKAN sudah mengerjakan
      startBtn.textContent = "Ujian Telah Selesai";
      // Tombol sudah dalam keadaan disabled, tidak perlu diubah.

      Swal.fire({
        title: "Anda Sudah Mengerjakan Ujian",
        text: "Anda telah menyelesaikan ujian ini dan tidak dapat mengulanginya.",
        icon: "error",
        confirmButtonText: "Mengerti",
        allowOutsideClick: false,
      });
    } else {
      // Jika siswa BELUM mengerjakan, aktifkan kembali tombol
      startBtn.disabled = false;
      startBtn.innerHTML = 'Mulai Ujian <i class="fas fa-play"></i>';
    }
  } catch (error) {
    // Jika terjadi error saat fetch, jangan halangi siswa, tapi beri notifikasi.
    console.error("Gagal memeriksa riwayat ujian:", error);
    startBtn.disabled = true; // Non-aktifkan tombol jika pengecekan gagal
    startBtn.textContent = "Gagal Memeriksa";

    Swal.fire({
      title: "Gagal Memeriksa Riwayat",
      text: "Tidak dapat terhubung ke server untuk verifikasi. Silakan muat ulang halaman atau hubungi admin.",
      icon: "warning",
      confirmButtonText: "Tutup",
    });
  }
}
