document.addEventListener("DOMContentLoaded", function () {
  const nisInput = document.getElementById("nisInput");
  const kodeAksesInput = document.getElementById("kodeAksesInput");
  const submitBtn = document.getElementById("submitBtn");

  // === FITUR BARU: MUAT NIS DARI LOCALSTORAGE ===
  // Saat halaman dimuat, cek apakah ada NIS yang tersimpan
  const savedNIS = localStorage.getItem("savedNIS");
  if (savedNIS) {
    nisInput.value = savedNIS;
    // Fokuskan ke input kode akses agar lebih cepat
    kodeAksesInput.focus();
  }
  // ===========================================

  // Kredensial Admin (hardcoded)
  const ADMIN_NIS = "252606";
  const ADMIN_KODE_AKSES = "7654";

  const handleLogin = () => {
    const nis = nisInput.value.trim();
    const kodeAkses = kodeAksesInput.value.trim();

    if (!nis || !kodeAkses) {
      Swal.fire("Data Tidak Lengkap", "Harap isi NIS dan Kode Akses.", "warning");
      return;
    }
    
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Memproses...';

    // Cek login admin
    if (nis === ADMIN_NIS && kodeAkses === ADMIN_KODE_AKSES) {
      sessionStorage.setItem("role", "admin");
      Swal.fire({
        icon: "success",
        title: "Login Admin Berhasil!",
        text: "Mengarahkan ke dashboard...",
        showConfirmButton: false,
        timer: 1500,
      }).then(() => {
        window.location.href = "dashboard.html"; // Arahkan ke halaman admin
      });
      return;
    }

    // Validasi login siswa
    validateLogin({ nis, kodeAkses })
      .then((response) => {
        if (response.isValid) {
          // === FITUR BARU: SIMPAN NIS KE LOCALSTORAGE ===
          // Simpan NIS ke localStorage setelah login berhasil
          localStorage.setItem("savedNIS", nis);
          // ============================================

          sessionStorage.setItem("role", "siswa");
          sessionStorage.setItem("siswaData", JSON.stringify(response.siswa));
          sessionStorage.setItem("ujianData", JSON.stringify(response.ujian));
          
          Swal.fire({
            icon: "success",
            title: "Login Berhasil!",
            text: `Selamat datang, ${response.siswa['Nama Lengkap']}. Mengarahkan ke halaman konfirmasi...`,
            showConfirmButton: false,
            timer: 2000,
          }).then(() => {
            window.location.href = "summary.html";
          });
        }
      })
      .catch((error) => {
        Swal.fire("Login Gagal", error.message, "error");
      })
      .finally(() => {
        submitBtn.disabled = false;
        submitBtn.innerHTML = 'Masuk <i class="fas fa-arrow-right-to-bracket"></i>';
      });
  };

  submitBtn.addEventListener("click", handleLogin);

  // Memungkinkan login dengan menekan tombol Enter
  nisInput.addEventListener("keyup", function (event) {
    if (event.key === "Enter") {
      event.preventDefault();
      kodeAksesInput.focus();
    }
  });
  kodeAksesInput.addEventListener("keyup", function (event) {
    if (event.key === "Enter") {
      event.preventDefault();
      handleLogin();
    }
  });
});
