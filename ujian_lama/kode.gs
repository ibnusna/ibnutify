// --- KONFIGURASI GLOBAL --- 
const SPREADSHEET = SpreadsheetApp.getActiveSpreadsheet();
const properties = PropertiesService.getScriptProperties();

// Nama Sheet Utama
const NAMA_SISWA_SHEET = "NamaSiswa";
const MASTER_UJIAN_SHEET = "MasterUjian";
const JAWABAN_SISWA_SHEET = "JawabanSiswa";

// Kredensial Admin (Hardcoded)
const ADMIN_NIS = "252606";
const ADMIN_KODE_AKSES = "anjaysukses";

// --- ROUTER UTAMA (ENTRY POINT) ---

function doGet(e) {
  return ContentService.createTextOutput(
    JSON.stringify({
      status: "success",
      message: "Web App aktif.",
    })
  ).setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  let response;
  try {
    const request = JSON.parse(e.postData.contents);
    const action = request.action;
    const payload = request.payload;

    switch (action) {
      case "validateLogin":
        response = validateLogin(payload);
        break;
      case "saveExamConfig":
        response = saveExamConfig(payload);
        break;
      case "generateKodeAkses":
        response = generateKodeAkses(payload);
        break;
      case "getSoalByKodeAkses":
        response = getSoalByKodeAkses(payload);
        break;
      case "getDashboardData":
        response = getDashboardData();
        break;
      case "submitJawaban":
        response = submitJawaban(payload);
        break;
      case "getMonitoringData":
         response = getMonitoringData(payload);
         break;
      case "getRiwayatPengulangan":
        response = getRiwayatPengulangan(payload);
        break;
      case "getSoalWithKey":
        response = getSoalWithKey(payload);
        break;
      default:
        throw new Error("Aksi tidak valid: " + action);
    }

    return ContentService.createTextOutput(
      JSON.stringify({ status: "success", data: response })
    ).setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    Logger.log(error.toString() + " at " + error.stack);
    return ContentService.createTextOutput(
      JSON.stringify({ status: "error", message: error.message })
    ).setMimeType(ContentService.MimeType.JSON);
  }
}

// --- FUNGSI HELPER SHEET ---

/**
 * Membuat nama sheet penyimpanan fisik yang unik dan aman.
 * Mengganti spasi dengan underscore agar valid sebagai nama sheet.
 * Contoh: IPA_7 + Ulangan Harian -> IPA_7_Ulangan_Harian
 */
function generateStorageName(kelas, topik) {
  if (!kelas || !topik) return kelas;
  // Bersihkan karakter aneh dan ganti spasi dengan underscore
  const cleanTopik = topik.toString().replace(/\s+/g, '_').replace(/[^a-zA-Z0-9_]/g, '');
  return `${kelas}_${cleanTopik}`;
}

/**
 * Memastikan sheet ada, jika tidak ada maka dibuat.
 * UPDATED: Menambahkan Header dengan kolom 'Tipe' untuk fitur soal baru.
 */
function ensureSheetExists(sheetName) {
  let sheet = SPREADSHEET.getSheetByName(sheetName);
  if (!sheet) {
    try {
      sheet = SPREADSHEET.insertSheet(sheetName);
      // Header Standard V2 (Support Tipe Soal Baru)
      const headers = ["No", "Tipe", "Soal", "A", "B", "C", "D", "E", "Kunci"];
      sheet.appendRow(headers);
    } catch (e) {
      // Safety net: Jika terjadi race condition (sheet sudah ada)
      sheet = SPREADSHEET.getSheetByName(sheetName);
    }
  }
  return sheet;
}


// --- FUNGSI OTENTIKASI ---

function validateLogin(payload) {
  const { nis, kodeAkses } = payload;
  
  // 1. Cek Login Admin
  if (nis === ADMIN_NIS && kodeAkses === ADMIN_KODE_AKSES) {
    return { isValid: true, role: "admin", message: "Selamat datang, Admin." };
  }

  // 2. Cek Login Siswa
  const siswaData = findSiswaByNis(nis);
  if (!siswaData) throw new Error("NIS tidak terdaftar. Hubungi admin.");

  const ujianData = findUjianByKodeAkses(kodeAkses);
  if (!ujianData) throw new Error("Kode Akses Ujian tidak valid atau sudah tidak aktif.");
  
  // const statusTampilan = String(ujianData.Tampilan || "MUNCUL").toUpperCase();
  // if (statusTampilan === "TIDAK") throw new Error("Ujian ini sedang tidak aktif / ditutup oleh Admin.");
  // REVISI: Tampilan hanya flag LMS, bukan blocker.

// LOGIC PENENTUAN SHEET SOAL FISIK (SMART STORAGE)
  // MasterUjian menyimpan 'IPA_7' di kolom NamaSheetSoal.
  // Tapi soal fisik ada di 'IPA_7_Ulangan_Harian'. Kita generate ulang namanya.
  const physicalSheetName = generateStorageName(ujianData.NamaSheetSoal, ujianData.TopikUjian);
  
  // Validasi keberadaan sheet fisik
  const sheetCheck = SPREADSHEET.getSheetByName(physicalSheetName);
  
  // ERROR HANDLING KHUSUS:
  // Jika sheet fisik spesifik tidak ketemu, coba fallback ke sheet induk (Backward Compatibility)
  // Ini mencegah error "Sheet tidak ditemukan" jika admin belum save ulang config.
  let finalSheetName = physicalSheetName;
  if (!sheetCheck) {
     const fallbackSheet = SPREADSHEET.getSheetByName(ujianData.NamaSheetSoal);
     if (fallbackSheet) {
         finalSheetName = ujianData.NamaSheetSoal;
     } else {
         throw new Error("Database Error: Sheet soal (" + physicalSheetName + ") belum dibuat/disimpan oleh Admin.");
     }
  }
  
  // 3. Cek Riwayat Pengerjaan
  const pengulangan = String(ujianData.Pengulangan || "TIDAK").toUpperCase();
  if (pengulangan !== "YA") {
    if (hasSiswaSubmitted(nis, ujianData.TopikUjian)) {
      throw new Error("Anda sudah pernah mengerjakan ujian dengan topik ini.");
    }
  }

  return {
    isValid: true,
    role: "siswa",
    siswa: siswaData,
ujian: {
      topik: ujianData.TopikUjian,
      durasi: ujianData.Durasi,
      sheetSoal: finalSheetName, // UPDATED: Gunakan nama sheet hasil validasi di atas
      pengulangan: pengulangan,
      tampilkanJawaban: ujianData.TampilkanJawaban || "TIDAK"
    },
    message: "Login berhasil.",
  };
}


// --- FUNGSI MANAJEMEN UJIAN (ADMIN) ---

function saveExamConfig(payload) {
  const { sheetTarget, topik, durasi, soalArray, tampilkanJawaban, pengulangan, tampilan } = payload;
  
  // 1. Tentukan Nama Sheet Penyimpanan (Storage Isolation)
  // Gunakan fungsi helper untuk membuat nama unik: IPA_7_Remedial_Bab_1
  const storageSheetName = generateStorageName(sheetTarget, topik);
  
  // 2. Simpan soal ke sheet spesifik tersebut
  if (soalArray && soalArray.length > 0) {
    const soalSheet = ensureSheetExists(storageSheetName);
    
    // AGGRESSIVE CLEAR: Hapus semua konten dan format untuk memastikan bersih
    soalSheet.clear();
    SpreadsheetApp.flush(); // Paksa perubahan diterapkan segera

    // Header mencakup 'Tipe' untuk support soal baru
    const headers = ["No", "Tipe", "Soal", "A", "B", "C", "D", "E", "Kunci"];
    soalSheet.appendRow(headers);
    
    // Batch Operations: Lebih cepat dan aman daripada appendRow loop
    // Konversi array of objects ke array of arrays
    const rows = soalArray.map(item => [
        item.no, 
        item.tipe || "PG", 
        item.soal, 
        item.a, item.b, item.c, item.d, item.e, 
        item.kunci
    ]);
    
    // Tulis sekaligus (Batch Write)
    if (rows.length > 0) {
        soalSheet.getRange(2, 1, rows.length, headers.length).setValues(rows);
    }
    SpreadsheetApp.flush(); // Pastikan data tertulis
  }
  
  // Update MasterUjian
  const masterSheet = SPREADSHEET.getSheetByName(MASTER_UJIAN_SHEET);
  const data = masterSheet.getDataRange().getValues();
  const headers = data[0];
  
  let tjIndex = headers.indexOf("TampilkanJawaban");
  let pIndex = headers.indexOf("Pengulangan");
  let tIndex = headers.indexOf("Tampilan");
  
  if (tjIndex === -1) { tjIndex = headers.length; masterSheet.getRange(1, tjIndex + 1).setValue("TampilkanJawaban"); }
  if (pIndex === -1) { pIndex = headers.length + 1; masterSheet.getRange(1, pIndex + 1).setValue("Pengulangan"); }
  if (tIndex === -1) { tIndex = headers.length + 2; masterSheet.getRange(1, tIndex + 1).setValue("Tampilan"); }
  
  // Logic Update Row berdasarkan Target Sheet (Unik per kelas/tab)
  // Asumsi: 1 Kelas hanya punya 1 Ujian Aktif dalam 1 waktu jika menggunakan logic simple ini.
  // Atau jika user mengganti topik, dia menimpa config di row yang sama untuk sheetTarget tsb.
  
  let rowIndex = -1;
  for (let i = 1; i < data.length; i++) {
    // Cari baris yang NamaSheetSoal-nya sama dengan target (misal 'IPA_7')
    // DAN TopikUjian-nya sama.
    const rowSheetTarget = String(data[i][2]).trim();
    const rowTopik = String(data[i][1]).trim();
    
    // Logic Baru: Update HANYA jika SheetTarget DAN Topik sama.
    if (rowSheetTarget === String(sheetTarget).trim() && rowTopik === String(topik).trim()) {
      rowIndex = i;
      break;
    }
  }

  let finalKodeAkses = "";

  if (rowIndex > 0) {
    // Update Config yang ada
    // Note: Topik tidak diupdate karena itu adalah key pencarian, tapi ok lah ditulis ulang.
    masterSheet.getRange(rowIndex + 1, 2).setValue(topik); 
    masterSheet.getRange(rowIndex + 1, 4).setValue(durasi);
    masterSheet.getRange(rowIndex + 1, pIndex + 1).setValue(pengulangan || "TIDAK");
    masterSheet.getRange(rowIndex + 1, tjIndex + 1).setValue(tampilkanJawaban || "TIDAK");
    masterSheet.getRange(rowIndex + 1, tIndex + 1).setValue(tampilan || "MUNCUL");
    
    // Cek Token/Kode Akses Existing
    const existingKode = String(data[rowIndex][4]).trim(); // Kolom E (Index 4)
    if (!existingKode) {
        // Jika kosong, generate baru
        finalKodeAkses = Math.floor(10000 + Math.random() * 90000).toString();
        masterSheet.getRange(rowIndex + 1, 5).setValue(finalKodeAkses);
    } else {
        finalKodeAkses = existingKode;
    }

  } else {
    // Buat Baru
    const newRowNumber = masterSheet.getLastRow() + 1;
    const maxCol = Math.max(7, tIndex); 
    const newRow = new Array(maxCol + 1).fill("");
    
    // Auto Generate Code untuk New Exam
    finalKodeAkses = Math.floor(10000 + Math.random() * 90000).toString();

    newRow[0] = newRowNumber - 1; 
    newRow[1] = topik;            
    newRow[2] = sheetTarget;     
    newRow[3] = durasi;           
    newRow[4] = finalKodeAkses; // Auto Fill Kode Akses
    newRow[pIndex] = pengulangan || "TIDAK";
    newRow[tjIndex] = tampilkanJawaban || "TIDAK";
    newRow[tIndex] = tampilan || "MUNCUL";
    masterSheet.appendRow(newRow);
  }
  
  return { 
      message: soalArray && soalArray.length > 0 ? `Soal (${soalArray.length}) berhasil disimpan.` : `Konfigurasi berhasil disimpan.`,
      kodeAkses: finalKodeAkses // Return kode akses ke frontend
  };
}

function generateKodeAkses(payload) {
  const { sheetTarget, topik } = payload; // Tambah parameter topik
  const masterSheet = SPREADSHEET.getSheetByName(MASTER_UJIAN_SHEET);
  const data = masterSheet.getDataRange().getValues();
  
  // Cari baris berdasarkan sheetTarget DAN topik
  let rowIndex = data.findIndex((row, idx) => {
      if (idx === 0) return false;
      const rowSheet = String(row[2]).trim();
      const rowTopik = String(row[1]).trim();
      
      // Jika topik dikirim, gunakan sbg filter. Jika tidak (legacy), ambil yg pertama ketemu (bahaya, tapi fallback).
      if (topik) {
          return rowSheet === String(sheetTarget).trim() && rowTopik === String(topik).trim();
      } else {
          return rowSheet === String(sheetTarget).trim();
      }
  });

  if (rowIndex === -1) throw new Error("Konfigurasi ujian tidak ditemukan untuk: " + sheetTarget + (topik ? " - " + topik : ""));
  
  const newKode = Math.floor(10000 + Math.random() * 90000).toString();
  masterSheet.getRange(rowIndex + 1, 5).setValue(newKode);
  return { newKodeAkses: newKode };
}

function getDashboardData() {
    const masterSheet = SPREADSHEET.getSheetByName(MASTER_UJIAN_SHEET);
    if (masterSheet.getLastRow() < 2) return [];
    const data = masterSheet.getRange(2, 1, masterSheet.getLastRow() - 1, masterSheet.getLastColumn()).getValues();
    const headers = masterSheet.getRange(1, 1, 1, masterSheet.getLastColumn()).getValues()[0];
    return data.map(row => {
        let obj = {};
        headers.forEach((header, i) => obj[header] = row[i]);
        return obj;
    });
}

// --- FUNGSI AKSES SOAL (SISWA) ---

function getSoalByKodeAkses(payload) {
  const { sheetSoal } = payload;
  const soalData = getSheetData(sheetSoal);
  
  const formattedSoal = soalData.map((s) => {
    const tipe = String(s["Tipe"] || "PG").toUpperCase();
    let pairs = [];

    // DATA PARSING KHUSUS TIPE MENJODOHKAN
    // Cek Tipe di kolom Tipe ATAU di dalam string Soal (sesuai request user)
    const isMatchingType = tipe === "MENJODOHKAN" || String(s["Soal"] || "").includes("[TIPE:MENJODOHKAN]");
    
    if (isMatchingType) {
      // Override tipe jika terdeteksi via tag di Soal
      // Override tipe logic handled in return statement below.

      
      // Loop kolom A-E
      ["A", "B", "C", "D", "E"].forEach((col, idx) => {
         const raw = String(s[col] || "");
         if (raw.includes(":")) {
           const parts = raw.split(":");
           if (parts.length >= 2) {
             pairs.push({
               id: "p" + (idx + 1),
               left: parts[0].trim(),
               right: parts.slice(1).join(":").trim() // Join kembali jika ada titik dua lain
             });
           }
         }
      });
    }

    return {
      no: s["No"],
      tipe: isMatchingType ? "MENJODOHKAN" : tipe, 
      soal: s["Soal"],
      a: s["A"],
      b: s["B"],
      c: s["C"],
      d: s["D"],
      e: s["E"],
      pairs: pairs.length > 0 ? pairs : undefined // Include pairs only if exists
    };
  });

  // FILTER DUPLICATES (Ambil yang terakhir jika ada Nomor Ganda)
  const uniqueMap = new Map();
  formattedSoal.forEach(item => {
    if (item.no) {
        uniqueMap.set(String(item.no), item);
    }
  });

  // Convert back to array & Sort by Number
  const uniqueSoal = Array.from(uniqueMap.values()).sort((a, b) => parseInt(a.no) - parseInt(b.no));

  return { soal: uniqueSoal };
}



function getMonitoringData(payload) {
    const { topikUjian } = payload;
    const allJawaban = getSheetData(JAWABAN_SISWA_SHEET);
    const filteredJawaban = allJawaban.filter(row => row["Topik Ujian"] === topikUjian);
    return filteredJawaban.map(item => ({
        "NIS": item.NIS,
        "Nama Lengkap": item["Nama Lengkap"],
        "Kelas": item.Kelas,
        "Status": "Selesai",
        "Nilai": item.Nilai,
        "Timestamp": item.Timestamp
    }));
}

// --- FUNGSI BANTUAN (HELPERS) ---

function getSheetData(sheetName) {
  const sheet = SPREADSHEET.getSheetByName(sheetName);
  if (!sheet || sheet.getLastRow() < 2) return [];
  
  const data = sheet.getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn()).getValues();
  const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  
  return data.map((row) => {
    let obj = {};
    headers.forEach((header, i) => (obj[header] = row[i]));
    return obj;
  }).filter(obj => obj["No"] && String(obj["No"]).trim() !== ""); // Filter Baris Kosong
}

function findSiswaByNis(nis) {
  const siswaList = getSheetData(NAMA_SISWA_SHEET);
  return siswaList.find(s => String(s.NIS).trim() === String(nis).trim());
}

function findUjianByKodeAkses(kodeAkses) {
  const ujianList = getSheetData(MASTER_UJIAN_SHEET);
  return ujianList.find(u => String(u.KodeAksesAktif).trim() === String(kodeAkses).trim());
}

function hasSiswaSubmitted(nis, topik) {
    const jawabanSheet = SPREADSHEET.getSheetByName(JAWABAN_SISWA_SHEET);
    if (jawabanSheet.getLastRow() < 2) return false;
    const data = jawabanSheet.getRange(2, 1, jawabanSheet.getLastRow() - 1, jawabanSheet.getLastColumn()).getValues();
    return data.some(row => String(row[4]).trim() === String(nis).trim() && row[6] === topik);
}

function countSiswaAttempts(nis, topik) {
  const jawabanSheet = SPREADSHEET.getSheetByName(JAWABAN_SISWA_SHEET);
  if (jawabanSheet.getLastRow() < 2) return 0;
  const data = jawabanSheet.getRange(2, 1, jawabanSheet.getLastRow() - 1, jawabanSheet.getLastColumn()).getValues();
  return data.filter(row => String(row[4]).trim() === String(nis).trim() && row[6] === topik).length;
}

function getRiwayatPengulangan(payload) {
  const { nis, topik } = payload;
  const allJawaban = getSheetData(JAWABAN_SISWA_SHEET);
  return allJawaban
    .filter(row => String(row.NIS).trim() === String(nis).trim() && row["Topik Ujian"] === topik)
    .map(row => ({
      timestamp: row.Timestamp,
      nilai: row.Nilai,
      percobaan: row["Percobaan Ke"] || 1
    }))
    .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
}

function getSoalWithKey(payload) {
  const { sheetSoal } = payload;
  const soalData = getSheetData(sheetSoal);
  const formattedSoal = soalData.map((s) => {
    let pairs = [];
    const tipe = String(s["Tipe"] || "PG").toUpperCase();
    const isMatching = tipe === "MENJODOHKAN" || String(s["Soal"] || "").includes("[TIPE:MENJODOHKAN]");
    
    if (isMatching) {
       ["A", "B", "C", "D", "E"].forEach((col, idx) => {
          const raw = String(s[col] || "");
          if (raw.includes(":")) {
             const parts = raw.split(":");
             pairs.push({
                id: "p" + (idx + 1),
                left: parts[0].trim(),
                right: parts.slice(1).join(":").trim()
             });
          }
       });
    }

    return {
      no: s["No"],
      tipe: isMatching ? "MENJODOHKAN" : tipe,
      soal: s["Soal"],
      a: s["A"],
      b: s["B"],
      c: s["C"],
      d: s["D"],
      e: s["E"],
      kunci: String(s["Kunci"]).toUpperCase(),
      pairs: pairs.length > 0 ? pairs : undefined // Return pairs specifically for key checking
    };
  });

  // FILTER DUPLICATES (Ambil yang terakhir jika ada Nomor Ganda)
  const uniqueMap = new Map();
  formattedSoal.forEach(item => {
    if (item.no) { // Pastikan ada nomor
        uniqueMap.set(String(item.no), item);
    }
  });

  const uniqueSoal = Array.from(uniqueMap.values()).sort((a, b) => parseInt(a.no) - parseInt(b.no));

  return { soal: uniqueSoal };
}

function submitJawaban(payload) {
  const { nis, nama, kelas, topik, sheetSoal, jawaban } = payload;
  
  // Ambil data soal dari sheet
  const soalData = getSheetData(sheetSoal);
  let benar = 0;

  // 1. CLEANING JAWABAN (Ubah null jadi string kosong untuk keamanan)
  const safeJawaban = jawaban.map(val => {
    if (val === null || val === undefined) return "";
    if (Array.isArray(val)) {
      return val.map(subVal => (subVal === null || subVal === undefined) ? "" : subVal);
    }
    return val;
  });

  // 2. VALIDASI & PENILAIAN
  soalData.forEach((soal, index) => {
    // Gunakan safeJawaban yang sudah dibersihkan
    const jawabanSiswa = safeJawaban[index];
    const kunciJawaban = String(soal["Kunci"]).toUpperCase().trim();
    // Default ke PG jika tidak ada Tipe
    let tipeSoal = String(soal["Tipe"] || "PG").toUpperCase();
    
    // Override jika ada tag khusus di Soal
    if (String(soal["Soal"] || "").includes("[TIPE:MENJODOHKAN]")) {
        tipeSoal = "MENJODOHKAN";
    }
    
    if (tipeSoal === "MENJODOHKAN") {
       // --- LOGIKA MENJODOHKAN ---
       // 1. Parsing Kunci Real-time dari Kolom A-E (Ambil Sisi Kanan / Target)
       let validPairs = [];
       ["A", "B", "C", "D", "E"].forEach(col => {
          const raw = String(soal[col] || "");
          if (raw.includes(":")) {
             // Format: "Premis : Target" -> Ambil Target
             const parts = raw.split(":");
             // Join kembali antisipasi jika ada titik dua di dalam text target
             validPairs.push(parts.slice(1).join(":").trim().toUpperCase());
          }
       });

       // 2. Normalisasi Jawaban Siswa (Harus Array of Strings)
       const studentArr = Array.isArray(jawabanSiswa) 
          ? jawabanSiswa.map(val => String(val || "").toUpperCase().trim())
          : [];

       // 3. Validasi (Strict Sequence Match)
       if (validPairs.length > 0 && validPairs.length === studentArr.length) {
          const isCorrect = validPairs.every((kunci, idx) => kunci === studentArr[idx]);
          if (isCorrect) benar++;
       }
    } else {
        // --- LOGIKA STANDARD (PG, PG_KOMPLEKS, ISIAN, BENAR_SALAH) ---
        if (checkAnswer(tipeSoal, jawabanSiswa, kunciJawaban)) {
            benar++;
        }
    }
  });

  // 3. HITUNG NILAI
  const nilaiMurni = soalData.length > 0 ? Math.round((benar / soalData.length) * 100) : 0;

  // 4. Logika Remedial / Pengurangan Nilai (Penalty)
  const attemptCount = countSiswaAttempts(nis, topik);
  const currentAttempt = attemptCount + 1;
  
  let nilaiAkhir = nilaiMurni;
  // Jika percobaan >= 4, kurangi 3 poin (sesuai aturan Anda sebelumnya)
  if (currentAttempt >= 4) {
      nilaiAkhir = Math.max(0, nilaiMurni - 3);
  }
  
  // 5. SIMPAN KE SPREADSHEET
  const jawabanSheet = SPREADSHEET.getSheetByName(JAWABAN_SISWA_SHEET);
  // Cek row terakhir
  const lastRow = jawabanSheet.getLastRow();
  const newRowNumber = lastRow > 0 ? lastRow : 1;
  
  // Format Tanggal
  const timestamp = new Date();
  
  jawabanSheet.appendRow([
      newRowNumber,       // No
      timestamp,          // Timestamp
      nama,               // Nama Lengkap
      kelas,              // Kelas
      nis,                // NIS
      sheetSoal,          // NamaSheetSoal
      topik,              // Topik Ujian
      JSON.stringify(safeJawaban), // Jawaban (JSON String)
      nilaiAkhir,         // Nilai
      currentAttempt,     // Percobaan Ke
  ]);

  // Return data ke Frontend
  return {
    nilai: nilaiAkhir,
    benar: benar,
    salah: soalData.length - benar,
    percobaan: currentAttempt,
  };
}

/**
 * Helper Logic Penilaian Cerdas (Strict & Robust)
 * Mengantisipasi input null/undefined dari frontend.
 */
function checkAnswer(tipe, studentAns, key) {
    // 0. Safety Check Awal
    if (studentAns === null || studentAns === undefined || studentAns === "") return false;

    // Helper untuk membersihkan string (Trim, Uppercase, handle null)
    const cleanStr = (s) => String(s || "").trim().toUpperCase();

    // 1. TIPE ISIAN (Case Insensitive)
    if (tipe === 'ISIAN') {
        return cleanStr(studentAns) === cleanStr(key);
    }
    
    // 2. PARSING KUNCI JAWABAN (Selalu dipisah koma)
    const kSplit = String(key).split(',').map(cleanStr);
    
    // 3. PARSING JAWABAN SISWA
    let aSplit = [];
    if (Array.isArray(studentAns)) {
        // Handle array (dari Checkbox/Tabel Benar Salah)
        aSplit = studentAns.map(cleanStr);
    } else {
        // Handle string (Fallback/Legacy)
        aSplit = String(studentAns).split(',').map(cleanStr);
    }

    // Syarat Mutlak: Jumlah jawaban harus sama dengan jumlah kunci
    if (kSplit.length !== aSplit.length) return false;

    // 4. PENILAIAN BERDASARKAN TIPE
    
    // TIPE BENAR_SALAH: URUTAN PENTING (Sequence Match)
    if (tipe === 'BENAR_SALAH') {
         return kSplit.every((val, idx) => val === aSplit[idx]);
    }

    // TIPE PG & PG_KOMPLEKS: URUTAN TIDAK PENTING (Set Match)
    kSplit.sort();
    aSplit.sort(); 
    return kSplit.every((val, idx) => val === aSplit[idx]);
}