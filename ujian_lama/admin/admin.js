// --- FULL ADMIN DASHBOARD LOGIC ---

let globalDashboardData = [];
let currentKelas = "";
let currentTopik = "";

document.addEventListener("DOMContentLoaded", () => {
    initDashboard();

    // Event Listeners for Filters
    document.getElementById("filterSheet").addEventListener("change", handleSheetChange);
    document.getElementById("filterTopik").addEventListener("change", handleTopikChange);

    // Event Listeners for Modal
    document.getElementById("soalInputText").addEventListener("input", updateCounter);
    document.getElementById("btnSimpan").addEventListener("click", handleSaveConfig);
});

async function initDashboard() {
    Swal.fire({
        title: "Memuat Dashboard...",
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    try {
        globalDashboardData = await getDashboardData();
        populateSheetDropdown();
        Swal.close();
    } catch (error) {
        console.error(error);
        Swal.fire("Gagal", "Gagal memuat data dari server: " + error.message, "error");
    }
}

function populateSheetDropdown() {
    const sheetSelect = document.getElementById("filterSheet");
    // Extract unique NamaSheetSoal
    const sheets = [...new Set(globalDashboardData.map(item => item.NamaSheetSoal))].filter(Boolean);
    
    sheetSelect.innerHTML = '<option value="">-- Pilih Kelas Target --</option>';
    sheets.forEach(sheet => {
        sheetSelect.innerHTML += `<option value="${sheet}">${sheet}</option>`;
    });
}

function handleSheetChange(e) {
    currentKelas = e.target.value;
    const topikSelect = document.getElementById("filterTopik");
    
    if (!currentKelas) {
        topikSelect.innerHTML = '<option value="">Pilih Kelas Dahulu</option>';
        topikSelect.disabled = true;
        resetMainView();
        return;
    }

    // Filter topiks based on selected class
    const topiks = globalDashboardData.filter(item => item.NamaSheetSoal === currentKelas);
    
    topikSelect.innerHTML = '<option value="">-- Pilih Topik Ujian --</option>';
    topiks.forEach(item => {
        topikSelect.innerHTML += `<option value="${item.TopikUjian}">${item.TopikUjian}</option>`;
    });
    
    topikSelect.disabled = false;
    resetMainView();
}

function handleTopikChange(e) {
    currentTopik = e.target.value;
    if (!currentTopik) {
        resetMainView();
        return;
    }

    const config = globalDashboardData.find(item => item.NamaSheetSoal === currentKelas && item.TopikUjian === currentTopik);
    if (config) {
        updateMainView(config);
        loadMonitoringTable();
    }
}

function updateMainView(config) {
    document.getElementById("dashTitle").innerText = `${config.NamaSheetSoal}`;
    document.getElementById("dashSubtitle").innerText = `Topik: ${config.TopikUjian}`;
    
    const token = config.KodeAksesAktif || "-----";
    document.getElementById("displayToken").innerText = token;
    
    document.getElementById("btnRegenerateToken").classList.remove("hidden");
    document.getElementById("btnEditTopik").classList.remove("hidden");

    // Update Sidebar Info
    const statusHtml = config.Tampilan === "MUNCUL" ? '<span class="text-green-600">Aktif</span>' : '<span class="text-red-500">Draft</span>';
    document.getElementById("infoUjianList").innerHTML = `
        <li class="flex justify-between"><span>Status:</span> <span class="font-bold">${statusHtml}</span></li>
        <li class="flex justify-between"><span>Durasi:</span> <span class="font-bold">${config.Durasi} Menit</span></li>
        <li class="flex justify-between"><span>Remedial:</span> <span class="font-bold">${config.Pengulangan === "YA" ? "Boleh" : "Tidak"}</span></li>
        <li class="flex justify-between"><span>Tampil Kunci:</span> <span class="font-bold">${config.TampilkanJawaban === "YA" ? "Ya" : "Tidak"}</span></li>
    `;
}

function resetMainView() {
    document.getElementById("dashTitle").innerText = "Pilih Ujian di Panel Kiri";
    document.getElementById("dashSubtitle").innerText = "Menunggu pemilihan kelas dan topik...";
    document.getElementById("displayToken").innerText = "------";
    document.getElementById("btnRegenerateToken").classList.add("hidden");
    document.getElementById("btnEditTopik").classList.add("hidden");
    document.getElementById("monitoringTbody").innerHTML = `<tr><td colspan="6" class="px-6 py-10 text-center text-gray-400">Pilih Kelas dan Topik di panel kiri untuk melihat data.</td></tr>`;
    document.getElementById("infoUjianList").innerHTML = `
        <li class="flex justify-between"><span>Status:</span> <span class="font-bold">-</span></li>
        <li class="flex justify-between"><span>Durasi:</span> <span class="font-bold">-</span></li>
        <li class="flex justify-between"><span>Remedial:</span> <span class="font-bold">-</span></li>
        <li class="flex justify-between"><span>Kunci Jawaban:</span> <span class="font-bold">-</span></li>
    `;
}

async function loadMonitoringTable() {
    const tbody = document.getElementById("monitoringTbody");
    tbody.innerHTML = `<tr><td colspan="6" class="px-6 py-10 text-center text-blue-500"><i class="fa-solid fa-spinner fa-spin mr-2"></i> Memuat data siswa...</td></tr>`;
    
    try {
        const data = await getMonitoringData({ topikUjian: currentTopik });
        
        if (data.length === 0) {
            tbody.innerHTML = `<tr><td colspan="6" class="px-6 py-10 text-center text-gray-500">Belum ada siswa yang mengumpulkan jawaban.</td></tr>`;
            return;
        }

        let html = '';
        data.forEach((item, index) => {
            html += `
                <tr class="hover:bg-blue-50 transition-colors">
                    <td class="px-6 py-3 text-center font-bold text-gray-500">${index + 1}</td>
                    <td class="px-6 py-3 font-mono text-sm">${item.NIS}</td>
                    <td class="px-6 py-3 font-semibold text-gray-800">${item["Nama Lengkap"]}</td>
                    <td class="px-6 py-3">${item.Kelas}</td>
                    <td class="px-6 py-3 text-center font-black text-blue-700 text-lg">${item.Nilai}</td>
                    <td class="px-6 py-3 text-right text-xs text-gray-500">${new Date(item.Timestamp).toLocaleString("id-ID")}</td>
                </tr>
            `;
        });
        tbody.innerHTML = html;
    } catch (error) {
        tbody.innerHTML = `<tr><td colspan="6" class="px-6 py-10 text-center text-red-500">Gagal memuat data: ${error.message}</td></tr>`;
    }
}

function refreshMonitoring() {
    if (currentTopik) loadMonitoringTable();
}

async function regenerateToken() {
    if (!currentKelas || !currentTopik) return;
    
    const res = await Swal.fire({
        title: 'Buat Token Baru?',
        text: "Token lama akan hangus dan siswa harus menggunakan token yang baru.",
        icon: 'warning',
        showCancelButton: true,
        confirmButtonText: 'Ya, Buat Baru'
    });

    if (!res.isConfirmed) return;

    Swal.fire({ title: "Memproses...", didOpen: () => Swal.showLoading() });
    
    try {
        const response = await generateKodeAkses({ sheetTarget: currentKelas, topik: currentTopik });
        document.getElementById("displayToken").innerText = response.newKodeAkses;
        
        // Update local state
        const configIndex = globalDashboardData.findIndex(item => item.NamaSheetSoal === currentKelas && item.TopikUjian === currentTopik);
        if (configIndex > -1) {
            globalDashboardData[configIndex].KodeAksesAktif = response.newKodeAkses;
        }
        
        Swal.fire("Berhasil", "Kode Akses baru: " + response.newKodeAkses, "success");
    } catch (error) {
        Swal.fire("Gagal", error.message, "error");
    }
}

// ==========================================
// MODAL & EDITOR LOGIC
// ==========================================

function openModal(isEdit = false) {
    document.getElementById("editorModalBackdrop").classList.add("active");
    document.getElementById("editorModal").classList.add("active");
    document.body.style.overflow = 'hidden';

    if (!isEdit) {
        document.getElementById("modalTitleText").innerText = "Buat Konfigurasi Ujian Baru";
        document.getElementById("configForm").reset();
        document.getElementById("soalInputText").value = "";
        updateCounter();
    }
}

function closeModal() {
    document.getElementById("editorModalBackdrop").classList.remove("active");
    document.getElementById("editorModal").classList.remove("active");
    document.body.style.overflow = '';
}

function editCurrentTopik() {
    if (!currentKelas || !currentTopik) return;
    
    const config = globalDashboardData.find(item => item.NamaSheetSoal === currentKelas && item.TopikUjian === currentTopik);
    if (!config) return;

    document.getElementById("modalTitleText").innerText = `Edit Konfigurasi: ${currentTopik}`;
    document.getElementById("sheetTarget").value = config.NamaSheetSoal;
    document.getElementById("topikUjian").value = config.TopikUjian;
    document.getElementById("durasi").value = config.Durasi;
    document.getElementById("tampilkanJawaban").value = config.TampilkanJawaban || "TIDAK";
    document.getElementById("pengulangan").value = config.Pengulangan || "TIDAK";
    document.getElementById("statusTampilan").value = config.Tampilan || "MUNCUL";
    
    // As we can't easily fetch back raw text from GS arrays purely for editing in this basic version,
    // we let the user know they are overwriting if they type.
    document.getElementById("soalInputText").value = "";
    document.getElementById("soalInputText").placeholder = "Jika Anda tidak ingin merubah soal, kosongkan area ini. Jika Anda mengisi area ini, seluruh soal sebelumnya untuk topik ini akan TERTIMPA (Overwritten).";
    
    updateCounter();
    openModal(true);
}

function updateCounter() {
    const text = document.getElementById("soalInputText").value;
    const tempSoal = parseSoalFromText(text);
    document.getElementById("counterSoal").innerText = `${tempSoal.length} Soal Terdeteksi`;
}

async function handleSaveConfig() {
    const sheetTarget = document.getElementById("sheetTarget").value.trim();
    const topik = document.getElementById("topikUjian").value.trim();
    const durasi = parseInt(document.getElementById("durasi").value);
    const tampilkanJawaban = document.getElementById("tampilkanJawaban").value;
    const pengulangan = document.getElementById("pengulangan").value;
    const tampilan = document.getElementById("statusTampilan").value;
    const rawText = document.getElementById("soalInputText").value.trim();

    if (!sheetTarget || !topik || !durasi) {
        Swal.fire("Data Belum Lengkap", "Pastikan Kelas Target, Topik, dan Durasi diisi!", "warning");
        return;
    }

    const soalArray = parseSoalFromText(rawText);
    
    // If text is present but parser finds 0, show error
    if (rawText.length > 0 && soalArray.length === 0) {
        Swal.fire("Format Soal Salah", "Sistem tidak dapat mendeteksi pemisah 'Kunci Jawaban:'. Silakan cek panduan format.", "error");
        return;
    }

    const res = await Swal.fire({
        title: 'Simpan Konfigurasi?',
        html: `Anda akan menyimpan konfigurasi untuk topik <b>${topik}</b>.<br>Soal baru yang akan diunggah: <b>${soalArray.length} soal</b>.`,
        icon: 'question',
        showCancelButton: true,
        confirmButtonText: 'Ya, Simpan!'
    });

    if (!res.isConfirmed) return;

    Swal.fire({ title: "Menyimpan Data...", allowOutsideClick: false, didOpen: () => Swal.showLoading() });

    try {
        const payload = { sheetTarget, topik, durasi, soalArray, tampilkanJawaban, pengulangan, tampilan };
        const response = await saveExamConfig(payload);
        
        closeModal();
        Swal.fire({
            icon: "success",
            title: "Sukses!",
            html: `Data berhasil disimpan.<br><br><b>KODE AKSES:</b><br><span style="font-size:2rem; font-weight:bold; color:#1d4ed8;">${response.kodeAkses}</span>`
        });

        // Refresh Dashboard Data behind the scenes
        initDashboard();
        
    } catch (error) {
        Swal.fire("Gagal", error.message, "error");
    }
}

/**
 * SMART PARSER FUNCTION
 */
function parseSoalFromText(text) {
    if (!text) return [];

    text = text.trim();
    const questions = [];
    let number = 1;

    // Gunakan regex yang toleran terhadap spasi sebelum titik dua
    const separatorRegex = /Kunci\s+Jawaban\s*:\s*(.*?)(?:\n|$)/gi;

    let lastIndex = 0;
    let match;

    while ((match = separatorRegex.exec(text)) !== null) {
        const endIndex = match.index + match[0].length;
        let rawBlock = text.substring(lastIndex, match.index).trim();
        let rawKunci = match[1].trim(); 

        rawBlock = rawBlock.replace(/^[\d]+\s*[.)]\s*/, '');
        const lines = rawBlock.split('\n').map(l => l.trim()).filter(Boolean);

        let soalText = "";
        let options = {};
        let isPG = false;
        let tipe = "PG"; 

        lines.forEach(line => {
            const optMatch = line.match(/^([A-E])\s*[.)]\s*(.*)/i);
            if (optMatch) {
                isPG = true;
                options[optMatch[1].toUpperCase()] = optMatch[2];
            } else {
                soalText += (soalText ? "\n" : "") + line;
            }
        });

        if (soalText.toUpperCase().includes("[TIPE:MENJODOHKAN]")) {
            tipe = "MENJODOHKAN";
        } else if (soalText.toUpperCase().includes("[TIPE:BENAR_SALAH]") || soalText.toUpperCase().includes("[TIPE:BENAR-SALAH]")) {
            tipe = "BENAR_SALAH";
        } else if (!isPG && rawKunci.length > 0) {
            tipe = "ISIAN";
        } else if (isPG && rawKunci.includes(',')) {
            tipe = "PG_KOMPLEKS";
        }

        if (soalText) {
            questions.push({
                no: number++,
                tipe: tipe,
                soal: soalText,
                a: options.A || "",
                b: options.B || "",
                c: options.C || "",
                d: options.D || "",
                e: options.E || "",
                kunci: rawKunci.toUpperCase()
            });
        }
        lastIndex = endIndex;
    }
    return questions;
}
