/**
 * EXAM CORE MODULE
 * Berisi logika murni (Pure Functions) untuk manipulasi data ujian.
 * Tidak boleh ada kode manipulasi DOM di sini.
 * * UPGRADE: Mendukung Tipe Soal Baru (PG Kompleks, Benar/Salah, Isian)
 */

/**
 * Mengacak urutan array menggunakan algoritma Fisher-Yates
 * @param {Array} array - Array asli
 * @returns {Array} Array baru yang sudah diacak
 */
export const shuffleArray = (array) => {
    // Clone array agar tidak memutasi source asli secara tidak sengaja
    const newArray = [...array];
    for (let i = newArray.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [newArray[i], newArray[j]] = [newArray[j], newArray[i]];
    }
    return newArray;
};

/**
 * Mengubah format data soal mentah dari server menjadi format aplikasi yang lebih terstruktur.
 * Menambahkan 'originalIndex' agar jawaban tetap sinkron meskipun diacak.
 * Menambahkan 'tipe' agar UI tahu cara merendernya.
 * * @param {Array} rawSoalList - List soal mentah dari server/JSON
 * @returns {Array} List soal yang sudah diformat
 */
export const prepareQuestions = (rawSoalList) => {
    if (!Array.isArray(rawSoalList)) return [];

    return rawSoalList.map((soal, index) => {
        const pilihan = ["a", "b", "c", "d", "e"]
            .filter(key => soal[key])
            .map((key, idx) => ({ // ✅ Tambah tracking index asli
                key: key.toUpperCase(),
                originalKey: key.toUpperCase(),
                originalIndex: idx, // ✅ TRACKING URUTAN ASLI PERNYATAAN
                text: soal[key]
            }));

        return {
            originalIndex: index,
            tipe: soal.tipe || "PG",
            pertanyaan: soal.soal,
            pilihan: pilihan,
            kunciJawaban: soal.kunci,
            pairs: soal.pairs // ✅ Passing 'pairs' data for MENJODOHKAN
        };
    });
};

/**
 * Helper untuk mengecek apakah jawaban dianggap "Terisi".
 * Mendukung String (PG/Isian) dan Array (PG Kompleks/BS).
 */
const isAnswerFilled = (val) => {
    // Cek Null/Undefined/String Kosong
    if (val === null || val === undefined || val === "") return false;

    // Cek Array Kosong (untuk PG Kompleks / Checkbox / Menjodohkan)
    if (Array.isArray(val)) return val.length > 0 && val.some(v => v !== null && v !== undefined && v !== "");

    return true;
};

/**
 * Menghitung statistik pengerjaan saat ini.
 * Digunakan untuk menampilkan peringatan "Masih ada soal kosong" saat mau submit.
 * * @param {Array} jawaban - Array jawaban siswa (panjang = total soal)
 * @param {Array} raguRagu - Array status ragu-ragu
 * @returns {Object} { total, terisi, kosong, ragu }
 */
export const getExamStats = (jawaban, raguRagu, totalSoal) => {
    // Pastikan input adalah array
    let safeJawaban = Array.isArray(jawaban) ? jawaban : [];
    let safeRagu = Array.isArray(raguRagu) ? raguRagu : [];

    // Jika ada cache berlebih dari ujian sebelumnya, potong sesuai total soal saat ini
    if (totalSoal && totalSoal > 0) {
        safeJawaban = safeJawaban.slice(0, totalSoal);
        safeRagu = safeRagu.slice(0, totalSoal);
    }

    const total = totalSoal || safeJawaban.length;

    // Gunakan helper isAnswerFilled yang sudah diupgrade
    const terisi = safeJawaban.filter(isAnswerFilled).length;

    const ragu = safeRagu.filter(r => r === true).length;
    const kosong = total - terisi;

    return { total, terisi, kosong, ragu };
};

/**
 * Memformat payload data final untuk dikirim ke API submitJawaban.
 * * @param {Object} siswa - Data siswa (dari Store)
 * @param {Object} meta - Data meta ujian (dari Store)
 * @param {Array} jawaban - Array jawaban siswa
 * @returns {Object} Objek payload siap kirim
 */
export const formatSubmitData = (siswa, meta, jawaban, soalList) => {
    // Potong array jawaban jika panjangnya melebihi jumlah soal (pencegahan bug cache)
    const limitedJawaban = jawaban.slice(0, soalList.length);

    const cleanedJawaban = limitedJawaban.map((val, originalIdx) => {
        // Cari soal yang memiliki originalIndex yang sesuai
        const soal = soalList.find(s => s.originalIndex === originalIdx);

        if (!soal) {
            return "";
        }

        if (val === null || val === undefined || val === "") {
            return "";
        }

        // ✅ KHUSUS BENAR/SALAH: Kembalikan ke urutan asli
        if (soal.tipe === "BENAR_SALAH" && Array.isArray(val)) {
            // 1. Siapkan wadah untuk jawaban urutan asli, default "" (empty string)
            const originalOrder = new Array(soal.pilihan.length).fill("");

            // 2. Loop berdasarkan urutan visual (karena array 'val' mengikuti urutan visual soal)
            soal.pilihan.forEach((opt, visualIdx) => {
                // Ambil jawaban user. Gunakan '|| ""' untuk jaga-jaga jika array sparse/bolong
                const studentAnswer = val[visualIdx] || "";

                // Masukkan ke slot index original-nya
                originalOrder[opt.originalIndex] = studentAnswer;
            });

            return originalOrder;
        }

        // ✅ KHUSUS MENJODOHKAN
        if (soal.tipe === "MENJODOHKAN" && Array.isArray(val)) {
            return val;
        }

        // PG Kompleks & PG Biasa (tetap sama)
        if (Array.isArray(val)) {
            return val.map(subVal => {
                if (subVal === null || subVal === undefined || subVal === "") return "";

                const matchedOption = soal.pilihan.find(p => p.key === subVal);
                return matchedOption ? matchedOption.originalKey : subVal;
            });
        }

        if (soal.tipe === "PG") {
            const matchedOption = soal.pilihan.find(p => p.key === val);
            return matchedOption ? matchedOption.originalKey : val;
        }

        return val;
    });

    return {
        nis: siswa.NIS,
        nama: siswa["Nama Lengkap"],
        kelas: siswa.Kelas,
        topik: meta.topik,
        sheetSoal: meta.sheetSoal,
        jawaban: cleanedJawaban
    };
};