import { Store } from './store.js';
import { prepareQuestions, shuffleArray, getExamStats, formatSubmitData } from './exam-core.js';

/**
 * PAGE UJIAN MODULE (UPGRADED UI)
 * Mengontrol logika interaksi GARA Exam Arena.
 * Mendukung rendering 4 Tipe Soal: PG, PG Kompleks, Benar/Salah, Isian.
 */

const elements = {
    // LAYERS
    loadingOverlay: document.getElementById('loadingOverlay'),
    gatewayOverlay: document.getElementById('gatewayOverlay'),
    mainContainer: document.getElementById('mainExamContainer'),

    // GATEWAY
    btnEnterFullscreen: document.getElementById('btnEnterFullscreen'),

    // HEADER & INFO
    mapelName: document.getElementById('mapelName'),
    timerDisplay: document.getElementById('timerDisplay'),
    userName: document.getElementById('userName'),

    // CONTENT AREA
    displayNoSoal: document.getElementById('displayNoSoal'),
    questionImageContainer: document.getElementById('questionImageContainer'),
    questionText: document.getElementById('questionText'),
    optionsContainer: document.getElementById('optionsContainer'),

    // NAVIGATION CONTROLS
    btnPrev: document.getElementById('btnPrev'),
    btnNext: document.getElementById('btnNext'),
    btnSubmit: document.getElementById('btnSubmit'),
    checkRagu: document.getElementById('checkRagu'),

    // MOBILE MODAL
    btnOpenSoalMobile: document.getElementById('btnOpenSoalMobile'),
    modalDaftarSoal: document.getElementById('modalDaftarSoal'),
    btnCloseModalSoal: document.getElementById('btnCloseModalSoal'),

    // NAVIGATION GRIDS
    sidebarNavGrid: document.getElementById('sidebarNavGrid'),
    mobileNavGrid: document.getElementById('mobileNavGrid'),

    // FONT CONTROLS
    fontButtons: document.querySelectorAll('.btn-font'),

    // SIDEBAR TOGGLE
    btnToggleSidebar: document.getElementById('btnToggleSidebar')
};

let isSubmitting = false;

// =========================================
// 1. INISIALISASI
// =========================================

export const initUjianPage = async () => {
    if (!Store.isAuthenticated()) {
        window.location.href = 'index.html';
        return;
    }

    const siswa = Store.getSiswa();
    const meta = Store.getUjianMeta();

    if (elements.userName) elements.userName.textContent = siswa["Nama Lengkap"] || "Peserta";
    if (elements.mapelName) elements.mapelName.textContent = meta.topik;

    let soalList = Store.getSoalList();

    toggleLayer('loading');

    // Fetch & Prepare Data (Hanya jika belum ada di Store)
    if (soalList.length === 0) {
        try {
            if (typeof getSoalByKodeAkses !== 'function') throw new Error("Koneksi server terputus.");

            // Delay UX
            await new Promise(r => setTimeout(r, 800));

            const rawData = await getSoalByKodeAkses({ sheetSoal: meta.sheetSoal });
            const formatted = prepareQuestions(rawData.soal);

            // --- LOGIKA ACAK (SHUFFLE) DILAKUKAN DI SINI ---

            // 1. Acak urutan Soal
            let shuffledQuestions = shuffleArray(formatted);

            // 2. Acak urutan Opsi Jawaban (Hanya untuk PG Biasa & PG Kompleks)
            // Untuk Benar/Salah (Tabel) dan Isian, urutan opsi/pernyataan TIDAK diacak (Fixed per user request)
            shuffledQuestions = shuffledQuestions.map(soal => {
                if (soal.tipe === 'ISIAN' || soal.tipe === 'BENAR_SALAH') {
                    // Isian & Benar Salah tidak diacak opsinya
                    return soal;
                }
                if (soal.tipe === 'MENJODOHKAN') {
                    // MENJODOHKAN: Acak hanya sisi KANAN (Target/Jawaban)
                    // Kita extract dulu array jawaban dari pairs
                    const rightSide = soal.pairs.map(p => ({
                        id: p.id,
                        text: p.right
                    }));
                    // Acak array jawaban
                    const shuffledRight = shuffleArray(rightSide);

                    // Simpan state acak ini di properti baru 'shuffledPairs' atau 'shuffledRight'
                    // Agar saat render ulang tidak berubah-ubah.
                    return {
                        ...soal,
                        shuffledRight: shuffledRight
                    };
                }
                return {
                    ...soal,
                    pilihan: shuffleArray([...soal.pilihan]) // Acak opsi A-E (PG Biasa)
                };
            });

            // Simpan urutan acak ini ke Store (Permanen selama sesi)
            soalList = shuffledQuestions;
            Store.setSoalList(soalList);

            Store.initJawaban(soalList.length);
            Store.initRaguRagu(soalList.length);
            Store.setCurrentIndex(0);

        } catch (error) {
            Swal.fire({
                icon: 'error',
                title: 'Gagal Memuat Soal',
                text: error.message,
                confirmButtonText: 'Kembali',
                confirmButtonColor: '#d33'
            }).then(() => window.location.href = 'index.html');
            return;
        }
    }

    toggleLayer('gateway');
    setupGatewayEvents(meta.durasi);
};

const setupGatewayEvents = (durasiMenit) => {
    elements.btnEnterFullscreen.onclick = () => {
        requestFullScreenAndStart(durasiMenit);
    };
};

const requestFullScreenAndStart = async (durasiMenit) => {
    try {
        const docEl = document.documentElement;
        if (docEl.requestFullscreen) await docEl.requestFullscreen();
        else if (docEl.webkitRequestFullscreen) await docEl.webkitRequestFullscreen();
        else if (docEl.msRequestFullscreen) await docEl.msRequestFullscreen();
    } catch (err) {
        console.warn("Fullscreen skipped/failed:", err);
    }

    toggleLayer('main');
    setupTimer(durasiMenit);

    // --- RECOVERY LOGIC START ---
    try {
        const siswa = Store.getSiswa();
        // Pastikan MemoryModule ada (Global Scope)
        if (typeof MemoryModule !== 'undefined' && siswa) {
            MemoryModule.init(siswa["Nama Lengkap"], siswa["NIS"] || "000");
            const savedProgress = MemoryModule.loadProgress();

            if (savedProgress && savedProgress.jawabanSiswa) {
                // Pulihkan jawaban satu per satu
                savedProgress.jawabanSiswa.forEach((ans, idx) => {
                    if (ans !== null && ans !== undefined) {
                        Store.saveJawaban(idx, ans);
                    }
                });
                console.log("Status: Progres ujian berhasil dipulihkan dari lokal.");

                // Toast notifikasi kecil
                const Toast = Swal.mixin({
                    toast: true,
                    position: 'top-end',
                    showConfirmButton: false,
                    timer: 3000,
                    timerProgressBar: true,
                });
                Toast.fire({
                    icon: 'success',
                    title: 'Progres ujian dipulihkan'
                });
            }
        }
    } catch (e) {
        console.warn("Recovery failed:", e);
    }
    // --- RECOVERY LOGIC END ---

    renderCurrentSoal();
    renderNavigationGrids();
    attachExamEventListeners();

    // Setup Network Listeners
    setupNetworkListeners();

    if (typeof SecurityModule !== 'undefined') {
        SecurityModule.init(() => forceSubmit("Waktu Habis / Pelanggaran"));
    }
};

// =========================================
// 2. LOGIKA RENDER (TAMPILAN) - UPGRADED
// =========================================

const renderCurrentSoal = (animate = true) => {
    const currentIndex = Store.getCurrentIndex();
    const soalList = Store.getSoalList();
    const currentSoal = soalList[currentIndex];

    if (!currentSoal) return;

    // A. Render Badge Tipe Soal
    elements.displayNoSoal.textContent = currentIndex + 1;

    let tipeLabel = "";
    if (currentSoal.tipe === "PG_KOMPLEKS") tipeLabel = `<span class="badge-tipe" style="font-size:0.7em; background:#e0f2fe; color:#0284c7; padding:2px 8px; border-radius:4px; margin-right:8px;">Pilih Lebih Dari Satu</span>`;
    if (currentSoal.tipe === "BENAR_SALAH") tipeLabel = `<span class="badge-tipe" style="font-size:0.7em; background:#f0fdf4; color:#16a34a; padding:2px 8px; border-radius:4px; margin-right:8px;">Tentukan Benar/Salah</span>`;
    if (currentSoal.tipe === "ISIAN") tipeLabel = `<span class="badge-tipe" style="font-size:0.7em; background:#fefce8; color:#ca8a04; padding:2px 8px; border-radius:4px; margin-right:8px;">Isian Angka</span>`;
    if (currentSoal.tipe === "MENJODOHKAN") tipeLabel = `<span class="badge-tipe" style="font-size:0.7em; background:#e0e7ff; color:#4338ca; padding:2px 8px; border-radius:4px; margin-right:8px;">Jodohkan Pasangan</span>`;

    // A.1. Deteksi & Ekstrak Gambar (New Feature: DOM Based)
    // FIX: Menggunakan DOM Parser untuk menangkap <a><img></a> pattern dan membersihkannya
    let cleanPertanyaan = currentSoal.pertanyaan || "";

    // 1. Buat temporary container
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = cleanPertanyaan;

    // 2. Cari semua link ke ibb.co.com
    const links = tempDiv.querySelectorAll('a[href*="ibb.co.com"]');
    const processedIds = new Set();

    // Reset Container Gambar
    elements.questionImageContainer.innerHTML = '';
    elements.questionImageContainer.classList.add('hidden');

    if (links.length > 0) {
        elements.questionImageContainer.classList.remove('hidden');

        links.forEach(link => {
            const href = link.getAttribute('href');
            // Extract ID from href: https://ibb.co.com/ID
            // Split by '/' and take last valid segment
            const parts = href.split('/').filter(p => p.trim() !== '');
            const imageId = parts[parts.length - 1];

            if (imageId && !processedIds.has(imageId)) {
                processedIds.add(imageId);

                // Construct Direct Link (HD)
                const directLink = `https://i.ibb.co.com/${imageId}/cover.png`;

                // Render Gambar HD
                const imgWrapper = document.createElement('div');
                imgWrapper.className = 'q-image-wrapper';

                const img = document.createElement('img');
                img.src = directLink;
                img.alt = "Gambar Soal";

                img.onerror = function () {
                    console.log('Failed loading image:', directLink);
                };

                imgWrapper.appendChild(img);
                elements.questionImageContainer.appendChild(imgWrapper);
            }

            // 3. Hapus Element <a> (dan img didalamnya) dari Text Soal
            link.remove();
        });

        // 4. Update cleanPertanyaan dengan sisa HTML yang sudah dibersihkan
        cleanPertanyaan = tempDiv.innerHTML;
    }

    // --- RENDERER KHUSUS PER TIPE ---

    /**
     * 1. PILIHAN GANDA BIASA (Radio Single)
     */
    const renderPGBiasa = (soal, jawabanUser) => {
        const visualLabels = ["A", "B", "C", "D", "E"];

        soal.pilihan.forEach((opt, idx) => {
            const isSelected = jawabanUser === opt.key;
            const btn = document.createElement('div');
            btn.className = `option-card ${isSelected ? 'selected' : ''}`;

            // Simpan KEY tunggal ("A")
            btn.onclick = () => handleAnswerSimple(soal.originalIndex, opt.key);

            const labelText = visualLabels[idx] || String.fromCharCode(65 + idx);
            btn.innerHTML = `
            <div class="opt-label">${labelText}</div>
            <div class="opt-text">${opt.text}</div>
        `;
            elements.optionsContainer.appendChild(btn);
        });
    };

    /**
     * 2. PILIHAN GANDA KOMPLEKS (Checkbox Multiple)
     */
    const renderPGKompleks = (soal, jawabanUser) => {
        // jawabanUser diharapkan Array ["A", "C"]. Jika null/string, ubah ke array.
        const currentAnswers = Array.isArray(jawabanUser) ? jawabanUser : [];

        soal.pilihan.forEach((opt) => {
            const isSelected = currentAnswers.includes(opt.key);

            const btn = document.createElement('div');
            // Gunakan styling mirip option-card tapi indikatornya kotak (checkbox style)
            btn.className = `option-card ${isSelected ? 'selected' : ''}`;
            btn.style.cursor = "pointer";

            btn.onclick = () => handleAnswerMulti(soal.originalIndex, opt.key);

            // Icon Checkbox Manual
            const icon = isSelected ? '<i class="fas fa-check-square"></i>' : '<i class="far fa-square"></i>';

            btn.innerHTML = `
            <div class="opt-label" style="background:none; border:none; color:inherit; font-size:1.2rem;">${icon}</div>
            <div class="opt-text">${opt.text}</div>
        `;
            elements.optionsContainer.appendChild(btn);
        });
    };

    /**
     * 3. BENAR - SALAH (MODERN CARD STYLE - MOBILE FRIENDLY)
     */
    const renderBenarSalah = (soal, jawabanUser) => {
        // Ambil jawaban saat ini untuk keperluan rendering awal
        const currentAnswers = Array.isArray(jawabanUser) ? jawabanUser : new Array(soal.pilihan.length).fill(null);

        const container = document.createElement('div');
        container.className = 'bs-container';
        container.style.cssText = "display: flex; flex-direction: column; gap: 16px;";

        elements.optionsContainer.appendChild(container);

        soal.pilihan.forEach((opt, idx) => {
            const val = currentAnswers[idx];
            const groupName = `bs_row_${soal.originalIndex}_${idx}`;

            const card = document.createElement('div');
            card.className = 'bs-card-item';
            card.style.cssText = `
            background: #ffffff;
            border: 1px solid var(--color-border);
            border-radius: 12px;
            padding: 16px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.03);
            transition: transform 0.2s;
        `;

            const statement = document.createElement('div');
            statement.innerHTML = `<strong style="color:var(--color-primary); margin-right:5px;">${idx + 1}.</strong> ${opt.text}`;
            statement.style.marginBottom = "12px";
            statement.style.fontSize = "0.95rem";
            statement.style.lineHeight = "1.5";
            statement.style.color = "var(--color-text-main)";

            const btnGroup = document.createElement('div');
            btnGroup.className = 'bs-options';
            btnGroup.style.cssText = "display: grid; grid-template-columns: 1fr 1fr; gap: 10px;";

            const createButton = (label, value) => {
                const isChecked = val === value;
                const labelEl = document.createElement('label');

                // Visual Styles Logic
                let bg = isChecked ? (value === 'BENAR' ? '#dcfce7' : '#fee2e2') : '#f8fafc';
                let border = isChecked ? (value === 'BENAR' ? '#16a34a' : '#dc2626') : '#e2e8f0';
                let text = isChecked ? (value === 'BENAR' ? '#15803d' : '#b91c1c') : '#64748b';
                let weight = isChecked ? '700' : '500';

                labelEl.style.cssText = `
                display: flex; align-items: center; justify-content: center; gap: 8px;
                padding: 10px; border: 2px solid ${border}; background: ${bg}; color: ${text};
                font-weight: ${weight}; border-radius: 8px; cursor: pointer;
                transition: all 0.2s; user-select: none;
            `;

                const icon = value === 'BENAR' ? '<i class="fas fa-check"></i>' : '<i class="fas fa-times"></i>';
                labelEl.innerHTML = `${icon} <span>${label}</span>`;

                const input = document.createElement('input');
                input.type = 'radio';
                input.name = groupName;
                input.value = value;
                input.checked = isChecked;
                input.style.display = 'none';

                input.onclick = () => {
                    const buttonsInGroup = btnGroup.querySelectorAll('label');
                    buttonsInGroup.forEach(lbl => {
                        lbl.style.background = '#f8fafc';
                        lbl.style.borderColor = '#e2e8f0';
                        lbl.style.color = '#64748b';
                        lbl.style.fontWeight = '500';
                    });
                    labelEl.style.background = value === 'BENAR' ? '#dcfce7' : '#fee2e2';
                    labelEl.style.borderColor = value === 'BENAR' ? '#16a34a' : '#dc2626';
                    labelEl.style.color = value === 'BENAR' ? '#15803d' : '#b91c1c';
                    labelEl.style.fontWeight = '700';

                    handleAnswerBenarSalah(soal.originalIndex, idx, value);
                };

                labelEl.appendChild(input);
                return labelEl;
            };

            btnGroup.appendChild(createButton("BENAR", "BENAR"));
            btnGroup.appendChild(createButton("SALAH", "SALAH"));

            card.appendChild(statement);
            card.appendChild(btnGroup);
            container.appendChild(card);
        });
    };

    /**
     * 4. ISIAN SINGKAT (Input Number Only)
     */
    const renderIsian = (soal, jawabanUser) => {
        const wrapper = document.createElement('div');
        wrapper.className = "isian-container";

        const label = document.createElement('label');
        label.className = "isian-label";
        label.innerText = "Jawaban Anda (Angka):";

        const input = document.createElement('input');
        input.type = "number"; // WAJIB NUMBER
        input.className = "isian-input";
        input.placeholder = "Ketik angka di sini...";
        input.value = jawabanUser || "";

        // Event Input dengan Debounce
        let timeout = null;
        input.oninput = (e) => {
            const val = e.target.value;
            clearTimeout(timeout);
            timeout = setTimeout(() => {
                handleAnswerSimple(soal.originalIndex, val);
            }, 300);
        };

        wrapper.appendChild(label);
        wrapper.appendChild(input);
        elements.optionsContainer.appendChild(wrapper);
    };

    /**
     * 5. MENJODOHKAN (MATCHING UI)
     */
    const renderMenjodohkan = (soal, jawabanUser) => {
        // Init Jawaban User (Array of Strings/IDs corresponding to Left Side Index)
        // jawabanUser = ["Jakarta", "Tokyo", ...]
        const currentAnswers = Array.isArray(jawabanUser) ? jawabanUser : new Array(soal.pairs.length).fill(null);

        // Container Utama
        const container = document.createElement('div');
        container.className = "matching-container";

        // --- AREA PASANGAN (Grid Premis - Slot) ---
        soal.pairs.forEach((pair, idx) => {
            const row = document.createElement('div');
            row.className = "matching-row";

            // Kiri: Premis
            const leftCard = document.createElement('div');
            leftCard.className = "premise-card";
            leftCard.innerHTML = pair.left;

            // Kanan: Slot Jawaban
            const slot = document.createElement('div');
            slot.className = "answer-slot";
            slot.dataset.idx = idx; // Connect to index 0,1,2..

            const filledVal = currentAnswers[idx];
            if (filledVal) {
                slot.classList.add('filled');
                slot.innerHTML = `<span style="color:var(--color-primary); font-weight:bold;">${filledVal}</span> <i class="fas fa-times" style="margin-left:8px; color:#ef4444; cursor:pointer;"></i>`;

                // Event Hapus Jawaban (Klik X atau Slot)
                slot.onclick = () => {
                    handleAnswerMenjodohkan(soal.originalIndex, idx, null);
                };
            } else {
                slot.innerHTML = `<span style="color:#cbd5e1; font-size:0.8rem;">Letakkan di sini</span>`;

                // Event Klik Slot Kosong (Untuk menaruh pilihan yang SEDANG DIPILIH)
                slot.onclick = () => {
                    // Cek apakah ada opsi yang sedang dipilih (active selection)
                    const selectedOption = document.querySelector('.match-option.selected');
                    if (selectedOption) {
                        const val = selectedOption.dataset.val;
                        handleAnswerMenjodohkan(soal.originalIndex, idx, val);
                    }
                };
            }

            row.appendChild(leftCard);
            row.appendChild(slot);
            container.appendChild(row);
        });

        // --- AREA OPSI JAWABAN (POOL) ---
        const poolDiv = document.createElement('div');
        poolDiv.className = "matching-pool";
        poolDiv.innerHTML = `<div class="pool-label">Pilihan Jawaban (Klik untuk memilih)</div>`;

        const gridDiv = document.createElement('div');
        gridDiv.className = "pool-grid";

        // Render opsi yang SUDAH DIACAK di awal (stored in shuffledRight)
        if (soal.shuffledRight) {
            soal.shuffledRight.forEach(opt => {
                // Skips rendering IF already used (placed) in any slot
                // Kecuali user ingin boleh memilih ganda? (Biasanya matching 1-to-1)
                // Kita buat 1-to-1: Jika sudah ada di currentAnswers, jangan tampilkan di pool (atau disable)
                const isUsed = currentAnswers.includes(opt.text);

                if (!isUsed) {
                    const btn = document.createElement('div');
                    btn.className = "match-option";
                    btn.textContent = opt.text;
                    btn.dataset.val = opt.text;

                    btn.onclick = () => {
                        // Toggle Selection Mode
                        document.querySelectorAll('.match-option').forEach(el => el.classList.remove('selected'));
                        btn.classList.add('selected');
                    };

                    gridDiv.appendChild(btn);
                }
            });
        }

        poolDiv.appendChild(gridDiv);
        container.appendChild(poolDiv);

        elements.optionsContainer.appendChild(container);
    };

    // --- FINAL RENDER EXECUTION ---
    // ANIMATION TRIGGER: Reset classes first IF animating
    if (animate) {
        elements.questionText.classList.remove('animate-enter');
        elements.optionsContainer.classList.remove('animate-enter-delay-1');

        // Force Reflow
        void elements.questionText.offsetWidth;
    }

    elements.questionText.innerHTML = tipeLabel + cleanPertanyaan;
    elements.optionsContainer.innerHTML = '';

    const jawabanUser = Store.getJawaban()[currentSoal.originalIndex];

    switch (currentSoal.tipe) {
        case 'PG_KOMPLEKS': renderPGKompleks(currentSoal, jawabanUser); break;
        case 'BENAR_SALAH': renderBenarSalah(currentSoal, jawabanUser); break;
        case 'ISIAN': renderIsian(currentSoal, jawabanUser); break;
        case 'MENJODOHKAN': renderMenjodohkan(currentSoal, jawabanUser); break;
        default: renderPGBiasa(currentSoal, jawabanUser); break;
    }

    const raguStatus = Store.getRaguRagu();
    elements.checkRagu.checked = !!raguStatus[currentSoal.originalIndex];
    updateNavButtons(currentIndex, soalList.length);
    highlightActiveGrid(currentIndex);

    // Apply Animation Classes (FIX: Use doubleRAF or setTimeout to guarantee reflow)
    if (animate) {
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                elements.questionText.classList.add('animate-enter');
                elements.optionsContainer.classList.add('animate-enter-delay-1');
            });
        });
    }
};

// =========================================
// 3. EVENT HANDLERS (LOGIC JAWABAN)
// =========================================

const handleAnswerSimple = (originalIndex, value) => {
    Store.saveJawaban(originalIndex, value);

    // AUTOSAVE
    if (typeof MemoryModule !== 'undefined') {
        MemoryModule.saveProgress(Store.getSoalList(), Store.getJawaban());
    }

    // Render ulang navigasi grid saja, jangan render soal agar fokus input tidak hilang (khusus Isian)
    const currentSoal = Store.getSoalList()[Store.getCurrentIndex()];
    if (currentSoal.tipe !== 'ISIAN') {
        renderCurrentSoal(false); // NO ANIMATION when answering
    }
    renderNavigationGrids();
};

/** Handle Jawaban Multi (PG Kompleks) */
const handleAnswerMulti = (originalIndex, key) => {
    let current = Store.getJawaban()[originalIndex];
    if (!Array.isArray(current)) current = [];

    // Toggle Logic
    if (current.includes(key)) {
        current = current.filter(k => k !== key); // Hapus jika ada
    } else {
        current.push(key); // Tambah jika belum
    }

    Store.saveJawaban(originalIndex, current);

    // AUTOSAVE
    if (typeof MemoryModule !== 'undefined') {
        MemoryModule.saveProgress(Store.getSoalList(), Store.getJawaban());
    }

    renderCurrentSoal();
    renderNavigationGrids();
};

/** Handle Jawaban Benar Salah (Array Index Update) */
/** Handle Jawaban Benar Salah (Fixed: Ambil data fresh dari Store) */
const handleAnswerBenarSalah = (originalIndex, rowIdx, value) => {
    const allAnswers = Store.getJawaban();
    let currentData = allAnswers[originalIndex];

    // Ambil data soal untuk tahu berapa jumlah baris (supaya array tidak bolong/sparse)
    const targetSoal = Store.getSoalList().find(s => s.originalIndex === originalIndex);
    const totalRows = targetSoal ? targetSoal.pilihan.length : 0;

    // Jika data belum ada atau panjangnya tidak sesuai, inisialisasi dengan NULL
    if (!Array.isArray(currentData) || currentData.length !== totalRows) {
        currentData = new Array(totalRows).fill(null);
    }

    const newArray = [...currentData];
    newArray[rowIdx] = value; // Update nilai

    Store.saveJawaban(originalIndex, newArray);

    // AUTOSAVE
    if (typeof MemoryModule !== 'undefined') {
        MemoryModule.saveProgress(Store.getSoalList(), Store.getJawaban());
    }

    // UPDATE UI LANGSUNG TANPA RENDER ULANG SOAL
    renderNavigationGrids();

    // Update visual tombol yang diklik (agar langsung hijau/merah)
    const currentSoal = Store.getSoalList()[Store.getCurrentIndex()];
    if (currentSoal && currentSoal.originalIndex === originalIndex) {
        updateBenarSalahVisual(rowIdx, value);
    }
};

/** Handle Jawaban Menjodohkan */
const handleAnswerMenjodohkan = (originalIndex, slotIdx, value) => {
    const allAnswers = Store.getJawaban();
    let currentData = allAnswers[originalIndex];

    // Get total slots from pairs count
    const targetSoal = Store.getSoalList().find(s => s.originalIndex === originalIndex);
    const totalSlots = targetSoal ? targetSoal.pairs.length : 0;

    if (!Array.isArray(currentData) || currentData.length !== totalSlots) {
        currentData = new Array(totalSlots).fill(null);
    }

    const newArray = [...currentData];
    newArray[slotIdx] = value;

    Store.saveJawaban(originalIndex, newArray);
    if (typeof MemoryModule !== 'undefined') {
        MemoryModule.saveProgress(Store.getSoalList(), Store.getJawaban());
    }

    // Render ulang soal untuk update UI (pindahkan dari pool ke slot)
    renderCurrentSoal(false); // No animation
    renderNavigationGrids();
};

const toggleRagu = (e) => {
    const currentSoal = Store.getSoalList()[Store.getCurrentIndex()];
    Store.setRaguRagu(currentSoal.originalIndex, e.target.checked);
    renderNavigationGrids();
};

const handleNav = (direction) => {
    const current = Store.getCurrentIndex();
    const total = Store.getSoalList().length;
    let next = current + direction;
    if (next >= 0 && next < total) {
        Store.setCurrentIndex(next);
        renderCurrentSoal();
    }
};

const updateNavButtons = (currentIndex, total) => {
    // Prev
    elements.btnPrev.disabled = currentIndex === 0;
    if (currentIndex === 0) elements.btnPrev.classList.add('opacity-50', 'cursor-not-allowed');
    else elements.btnPrev.classList.remove('opacity-50', 'cursor-not-allowed');

    // Next / Submit Logic
    const stats = getExamStats(Store.getJawaban(), Store.getRaguRagu(), total);
    const isLastQuestion = currentIndex === total - 1;
    // Cek apakah SEMUA soal sudah dianggap terisi (IsAnswerFilled di core sudah menghandle array kosong)
    const isAllAnswered = stats.kosong === 0;

    if (isLastQuestion) {
        elements.btnNext.style.display = 'none';
        if (isAllAnswered) {
            elements.btnSubmit.classList.remove('hidden');
            elements.btnSubmit.style.display = 'flex';
        } else {
            elements.btnSubmit.classList.add('hidden');
            elements.btnSubmit.style.display = 'none';
        }
    } else {
        elements.btnNext.style.display = 'flex';
        elements.btnSubmit.classList.add('hidden');
        elements.btnSubmit.style.display = 'none';
    }
};

// =========================================
// 4. NAVIGATION & SUBMISSION SYSTEM
// =========================================

const renderNavigationGrids = () => {
    const soalList = Store.getSoalList();
    const jawaban = Store.getJawaban();
    const ragu = Store.getRaguRagu();

    const createGridItem = (idx, originalIdx) => {
        // Cek Is Filled (Support Array & String)
        const val = jawaban[originalIdx];
        let isAnswered = false;

        if (Array.isArray(val)) isAnswered = val.length > 0; // Untuk PGK & BS
        else isAnswered = (val !== null && val !== "");      // Untuk PG & Isian

        const isRagu = ragu[originalIdx];

        const btn = document.createElement('div');
        btn.textContent = idx + 1;
        btn.dataset.idx = idx;

        let cls = "nav-item-box";
        if (isRagu) cls += " ragu";
        else if (isAnswered) cls += " done";

        btn.className = cls;
        btn.onclick = () => {
            Store.setCurrentIndex(idx);
            renderCurrentSoal();
            closeMobileModal();
        };
        return btn;
    };

    elements.sidebarNavGrid.innerHTML = '';
    elements.mobileNavGrid.innerHTML = '';

    soalList.forEach((soal, idx) => {
        elements.sidebarNavGrid.appendChild(createGridItem(idx, soal.originalIndex));
        elements.mobileNavGrid.appendChild(createGridItem(idx, soal.originalIndex));
    });
};

const highlightActiveGrid = (currentIndex) => {
    document.querySelectorAll('.nav-item-box.active').forEach(el => el.classList.remove('active'));
    const targets = document.querySelectorAll(`.nav-item-box[data-idx="${currentIndex}"]`);
    targets.forEach(el => el.classList.add('active'));
};

const openMobileModal = () => {
    elements.modalDaftarSoal.classList.remove('hidden');
};

const closeMobileModal = () => {
    elements.modalDaftarSoal.classList.add('hidden');
};

const handleFontResize = (sizeClass) => {
    // Reset classes
    elements.questionText.classList.remove('text-sm', 'text-base', 'text-lg', 'text-xl');

    // Determine size
    let newSize = '1rem'; // Default: Base/Medium
    if (sizeClass.contains('sm')) newSize = '0.875rem';
    if (sizeClass.contains('lg')) newSize = '1.25rem';

    // Apply to Question Text & Options
    elements.questionText.style.fontSize = newSize;
    elements.optionsContainer.style.fontSize = newSize;
};

const handleSidebarToggle = () => {
    elements.mainContainer.classList.toggle('sidebar-closed');
    // Optional: Switch icon if needed, but 'bars' works for both open/menu
};


const confirmSubmit = () => {
    const totalSoal = Store.getSoalList().length;
    const stats = getExamStats(Store.getJawaban(), Store.getRaguRagu(), totalSoal);

    if (stats.kosong > 0) {
        Swal.fire({
            icon: 'error',
            title: 'Belum Selesai!',
            text: `Masih ada ${stats.kosong} soal yang belum dijawab.`
        });
        return;
    }

    let title = 'Konfirmasi Selesai';
    let htmlMsg = 'Apakah Anda yakin ingin mengakhiri ujian ini?';
    let iconType = 'question';
    let confirmColor = '#3085d6';

    if (stats.ragu > 0) {
        title = 'Masih Ragu-ragu';
        htmlMsg = `Masih ada <b>${stats.ragu} soal</b> bertanda kuning (Ragu-ragu).<br>Yakin ingin mengumpulkan?`;
        iconType = 'warning';
        confirmColor = '#fbbd05';
    }

    Swal.fire({
        title: title,
        html: htmlMsg,
        icon: iconType,
        showCancelButton: true,
        confirmButtonColor: confirmColor,
        cancelButtonColor: '#aaa',
        confirmButtonText: 'Ya, Selesai',
        cancelButtonText: 'Batal'
    }).then((result) => {
        if (result.isConfirmed) {
            processSubmit();
        }
    });
};

const forceSubmit = (reason) => {
    Swal.fire({
        title: 'Waktu Habis!',
        text: `${reason}. Jawaban Anda akan dikirim otomatis.`,
        icon: 'info',
        timer: 3000,
        showConfirmButton: false,
        allowOutsideClick: false
    }).then(() => {
        processSubmit();
    });
};

const processSubmit = async () => {
    if (isSubmitting) return;
    isSubmitting = true;

    Swal.fire({
        title: 'Mengirim Jawaban',
        text: 'Aplikasinya jangan ditutup yak',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    if (typeof stopTimer === 'function') stopTimer();
    if (typeof SecurityModule !== 'undefined') SecurityModule.destroy();

    const siswa = Store.getSiswa();
    const meta = Store.getUjianMeta();
    const jawaban = Store.getJawaban();
    const soalList = Store.getSoalList(); // AMBIL DATA SOAL
    const payload = formatSubmitData(siswa, meta, jawaban, soalList); // KIRIM KE FORMATTER

    try {
        if (typeof submitJawaban !== 'function') throw new Error("API submitJawaban not found");

        const result = await submitJawaban(payload);

        Store.setHasil(result);
        Store.cleanupAfterSubmit();

        // Hapus data autosave agar bersih
        if (typeof MemoryModule !== 'undefined') {
            MemoryModule.clearProgress();
        }

        Swal.fire({
            icon: 'success',
            title: 'Terkirim!',
            text: 'Ujian telah berhasil diselesaikan.',
            timer: 1500,
            showConfirmButton: false
        }).then(() => {
            window.location.href = 'hasil.html';
        });

    } catch (err) {
        isSubmitting = false;
        Swal.fire({
            icon: 'error',
            title: 'Gagal Mengirim',
            text: `Terjadi kesalahan: ${err.message}`,
            confirmButtonText: 'Coba Lagi',
            showCancelButton: true,
            cancelButtonText: 'Batal'
        }).then((result) => {
            // Logic Baru SweetAlert2
            if (result.isConfirmed) {
                processSubmit(); // Panggil ulang fungsi jika user klik Coba Lagi
            }
        });
    }
};

const setupTimer = (durasiMenit) => {
    if (typeof startTimer === 'function') {
        startTimer(durasiMenit, elements.timerDisplay, () => forceSubmit("Waktu Habis"));
    }
};

const toggleLayer = (layerName) => {
    elements.loadingOverlay.classList.add('hidden');
    elements.gatewayOverlay.classList.add('hidden');
    elements.mainContainer.classList.add('hidden');

    if (layerName === 'loading') elements.loadingOverlay.classList.remove('hidden');
    if (layerName === 'gateway') elements.gatewayOverlay.classList.remove('hidden');
    if (layerName === 'main') elements.mainContainer.classList.remove('hidden');
};

/**
 * Update visual tombol Benar/Salah tanpa render ulang seluruh soal
 */
const updateBenarSalahVisual = (rowIdx, value) => {
    // Cari container Benar/Salah yang sedang aktif
    const container = elements.optionsContainer.querySelector('.bs-container');
    if (!container) return;

    const cards = container.querySelectorAll('.bs-card-item');
    if (!cards[rowIdx]) return;

    const btnGroup = cards[rowIdx].querySelector('.bs-options');
    if (!btnGroup) return;

    const labels = btnGroup.querySelectorAll('label');

    // Reset semua tombol di grup ini
    labels.forEach(lbl => {
        lbl.style.background = '#f8fafc';
        lbl.style.borderColor = '#e2e8f0';
        lbl.style.color = '#64748b';
        lbl.style.fontWeight = '500';

        const input = lbl.querySelector('input');
        if (input) input.checked = false;
    });

    // Set tombol yang dipilih
    labels.forEach(lbl => {
        const input = lbl.querySelector('input');
        if (input && input.value === value) {
            input.checked = true;
            lbl.style.background = value === 'BENAR' ? '#dcfce7' : '#fee2e2';
            lbl.style.borderColor = value === 'BENAR' ? '#16a34a' : '#dc2626';
            lbl.style.color = value === 'BENAR' ? '#15803d' : '#b91c1c';
            lbl.style.fontWeight = '700';
        }
    });
};

const attachExamEventListeners = () => {
    elements.btnNext.onclick = () => handleNav(1);
    elements.btnPrev.onclick = () => handleNav(-1);
    elements.checkRagu.onchange = toggleRagu;
    elements.btnSubmit.onclick = confirmSubmit;

    elements.btnOpenSoalMobile.onclick = openMobileModal;
    elements.btnCloseModalSoal.onclick = closeMobileModal;
    elements.modalDaftarSoal.onclick = (e) => {
        if (e.target === elements.modalDaftarSoal) closeMobileModal();
    };

    elements.fontButtons.forEach(btn => {
        btn.onclick = function () {
            handleFontResize(this.classList);
        };
    });

    if (elements.btnToggleSidebar) {
        elements.btnToggleSidebar.onclick = handleSidebarToggle;
    }
};

// =========================================
// 5. NETWORK STATUS LISTENER (NEW)
// =========================================
const setupNetworkListeners = () => {
    // [DEPRECATED] Banner logic replaced by Global Offline Redirect (network-monitor.js)
    /*
    const banner = document.getElementById('offlineBanner');
    const btnSubmit = document.getElementById('btnSubmit');

    const updateStatus = () => {
        if (navigator.onLine) {
            // Online
            if (banner) banner.classList.add('hidden');
            if (btnSubmit) {
                btnSubmit.disabled = false;
                btnSubmit.classList.remove('opacity-50', 'cursor-not-allowed');
                btnSubmit.title = "Kirim Jawaban";
            }
            console.log("Network Status: ONLINE. Sync restored.");
        } else {
            // Offline
            if (banner) banner.classList.remove('hidden');
            if (btnSubmit) {
                btnSubmit.disabled = true;
                btnSubmit.classList.add('opacity-50', 'cursor-not-allowed');
                btnSubmit.title = "Koneksi terputus. Tidak dapat mengirim jawaban.";
            }
            console.warn("Network Status: OFFLINE. Submit locked.");
        }
    };

    window.addEventListener('online', updateStatus);
    window.addEventListener('offline', updateStatus);

    // Cek status awal saat load
    updateStatus();
    */
    console.log("Legacy Network Listener Disabled. Using Global Monitor.");
};
