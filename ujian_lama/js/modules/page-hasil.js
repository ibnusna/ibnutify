import { Store } from './store.js';
import { generateExplanation } from '../api.js';
import { analyzeExamOverall } from '../api_analisis.js';

/**
 * PAGE HASIL MODULE (REPAIR VERSION)
 * Perbaikan: Path Import Store disesuaikan ke './store.js' (local module)
 */

// Menggunakan Getter untuk element agar tidak error jika dijalankan di halaman lain (Login/Ujian)
const getElements = () => ({
    nama: document.getElementById("hasilNama"),
    kelas: document.getElementById("hasilKelas"),
    mapel: document.getElementById("hasilMapel"),
    nilai: document.getElementById("nilaiAkhir"),
    benar: document.getElementById("jawabanBenar"),
    salah: document.getElementById("jawabanSalah"),
    btnDownload: document.getElementById("downloadBuktiBtn"),
    btnSelesai: document.getElementById("selesaiBtn"),
    kkmBadge: document.getElementById("kkmStatusBadge")
});

// --- UTAMA: INISIALISASI ---

export const initHasilPage = async () => {
    // 1. Validasi Data Session
    const siswa = Store.getSiswa();
    const ujian = Store.getUjianMeta();
    const hasil = Store.getHasil();

    // Jika data tidak lengkap, kembalikan ke login
    if (!siswa || !ujian || !hasil) {
        window.location.href = getExitUrl();
        return;
    }

    // 2. Render Data Teks
    // --- FIX: RECALCULATE SCORE CLIENT-SIDE FOR CONSISTENCY ---
    try {
        const localSoal = Store.getSoalList();
        const jawabanSiswa = Store.getJawaban();

        if (localSoal && jawabanSiswa) {
            // Fetch keys and review data (using existing helper)
            const soalReview = await getSoalDetailForReview(localSoal, jawabanSiswa, ujian.sheetSoal);

            // Calculate Stats
            const totalSoal = soalReview.length;
            const benar = soalReview.filter(s => s.isBenar).length;
            const salah = totalSoal - benar;
            // Calculate Score (Scale 100)
            const nilai = Math.round((benar / totalSoal) * 100);

            // Update 'hasil' object
            hasil.benar = benar;
            hasil.salah = salah;
            hasil.nilai = nilai;

            // Update Store so persistence works (PDF, Refresh)
            Store.setHasil(hasil);
            console.log("Score recalculated client-side:", hasil);
        }
    } catch (e) {
        console.warn("Failed to recalculate score client-side, using server data:", e);
    }
    // -----------------------------------------------------------

    renderResultData(siswa, ujian, hasil);

    // 3. Setup Tombol Download PDF (Cek Izin Admin)
    setupDownloadButton(ujian);

    // 4. Setup Tombol Selesai/Ulangi (Cek Izin Pengulangan)
    setupFinishButton(ujian.pengulangan);

    // 5. Setup Analysis Card
    await setupAnalysisCard(ujian, hasil);

    // 6. Animasi Angka Nilai
    const el = getElements();
    animateValue(el.nilai, 0, hasil.nilai, 1500);
};

// --- LOGIKA ANALYSIS CARD (REVISED WITH KEY FETCH) ---

const setupAnalysisCard = async (ujianMeta, hasil) => {
    // 1. Cek Permission
    const izinTampil = String(ujianMeta.tampilkanJawaban || "TIDAK").toUpperCase() === "YA";
    if (!izinTampil) return;

    // 2. Ambil elemen
    const card = document.getElementById('analysisCard');
    const elOpening = document.getElementById('analysisOpening');
    const wrapperWeak = document.getElementById('wrapperWeaknesses');
    const listWeak = document.getElementById('listWeaknesses');
    const wrapperRec = document.getElementById('wrapperRecommendations');
    const listRec = document.getElementById('listRecommendations');
    const aiDeepContainer = document.getElementById('aiDeepAnalysis');

    // NEW: Loading State
    const wrapperBenar = document.getElementById('wrapperBenar');
    const wrapperSalah = document.getElementById('wrapperSalah');

    if (!card) return;

    // Show card immediately with loading state
    card.style.display = 'block';
    elOpening.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i> Sedang memuat analisis detail dari server...';

    // Hide details initially
    if (wrapperBenar) wrapperBenar.style.display = 'none';
    if (wrapperSalah) wrapperSalah.style.display = 'none';
    if (wrapperWeak) wrapperWeak.style.display = 'none';

    // 3. Ambil data lokal
    const localSoal = Store.getSoalList();
    const jawabanSiswa = Store.getJawaban();

    if (!localSoal || !jawabanSiswa) {
        elOpening.textContent = "Data tidak tersedia untuk analisis.";
        return;
    }

    try {
        // 4. FETCH KEYS FROM SERVER (Crucial Step: Replicating bukti-ujian.js logic)
        // Kita butuh fungsi getSoalDetailForReview yg memanggil API getSoalWithKey
        const soalReview = await getSoalDetailForReview(localSoal, jawabanSiswa, ujianMeta.sheetSoal);

        // 5. Generate Analisis pakai data yang sudah ada kuncinya
        const jawabanSalah = soalReview.filter(s => !s.isBenar);
        const analysis = generateSmartAnalysis(jawabanSalah, soalReview.length);

        // 6. Populate UI Summary
        elOpening.textContent = analysis.opening;

        // Weaknesses
        listWeak.innerHTML = '';
        if (analysis.weaknesses.length > 0) {
            wrapperWeak.style.display = 'block';
            analysis.weaknesses.forEach(w => {
                const li = document.createElement('li');
                li.textContent = w;
                listWeak.appendChild(li);
            });
        } else {
            wrapperWeak.style.display = 'none';
        }

        // Recommendations
        listRec.innerHTML = '';
        analysis.recommendations.forEach(r => {
            const li = document.createElement('li');
            li.textContent = r;
            listRec.appendChild(li);
        });

        // 7. CALL AI DEEP ANALYSIS (NEW)
        if (aiDeepContainer) {
            aiDeepContainer.style.display = 'block';
            aiDeepContainer.innerHTML = `
                <div class="ai-skeleton-container">
                    <div class="skeleton-header-row">
                        <div class="skeleton-circle skeleton-shimmer"></div>
                        <div class="skeleton-title-bar skeleton-shimmer"></div>
                    </div>
                    <div class="skeleton-line skeleton-shimmer" style="width: 100%"></div>
                    <div class="skeleton-line skeleton-shimmer" style="width: 95%"></div>
                    <div class="skeleton-line skeleton-shimmer" style="width: 90%"></div>
                    <div class="skeleton-line skeleton-shimmer" style="width: 85%"></div>
                </div>
            `;

            // Prepare Data for AI
            const siswaData = Store.getSiswa();

            // Extract detailed wrong questions for AI context
            // Limit to top 5 to avoid token limits if necessary, or take all if short.
            const detailedWrongAnswers = soalReview
                .filter(s => !s.isBenar)
                .map(s => {
                    // Helper to resolve answer code to text (e.g. "A" -> "Kucing")
                    const resolveText = (val) => {
                        if (!val) return "-";
                        if (s.pilihanMap) {
                            // Handle multiple answers (comma separated or array)
                            const codes = Array.isArray(val) ? val : String(val).split(',');
                            const texts = codes.map(code => {
                                const c = String(code).trim().toUpperCase();
                                return s.pilihanMap[c] ? `${c} (${s.pilihanMap[c]})` : c;
                            });
                            return texts.join(', ');
                        }
                        return val;
                    };

                    return {
                        soal: s.pertanyaan ? s.pertanyaan.replace(/<[^>]*>/g, '').substring(0, 200) : "Pertanyaan Gambar/Tidak dimuat",
                        jawabanSiswa: resolveText(s.jawabanSiswa),
                        kunci: resolveText(s.kunci)
                    };
                });

            const analysisData = {
                siswaName: siswaData ? siswaData["Nama Lengkap"] : "Siswa",
                mapel: ujianMeta.topik,
                nilai: hasil.nilai,
                benar: hasil.benar,
                salah: hasil.salah,
                detailSalah: detailedWrongAnswers // PASS THIS NEW DATA
            };

            // Non-blocking call
            analyzeExamOverall(analysisData).then(aiHtml => {
                aiDeepContainer.innerHTML = `
                    <div class="ai-result-box">
                        <div class="ai-header-small">
                            <i class="fas fa-robot text-blue-600"></i>
                            <span class="font-bold text-gray-700">Analisis Mendalam AI</span>
                        </div>
                        <div class="ai-content-body">
                            ${aiHtml}
                        </div>
                    </div>
                `;
                // Render MathJax if loaded
                if (window.MathJax) {
                    window.MathJax.typesetPromise([aiDeepContainer]).catch(err => console.log('MathJax error:', err));
                }
            }).catch(err => {
                console.error("AI Error", err);
                aiDeepContainer.innerHTML = `<div class="text-sm text-red-500">Gagal memuat analisis AI.</div>`;
            });
        }

        // 8. Render Detailed Lists
        const listBenar = document.getElementById('listSoalBenar');
        const listSalah = document.getElementById('listSoalSalah');

        if (wrapperBenar && listBenar && wrapperSalah && listSalah) {
            // Gunakan soalReview yang sudah lengkap dengan kunci & isBenar
            // Pass 'izinTampil' as third argument
            renderDetailedAnalysis(soalReview, listBenar, listSalah, wrapperBenar, wrapperSalah, izinTampil);
        }

    } catch (error) {
        console.error("Gagal memuat analisis:", error);
        elOpening.innerHTML = `<span class="text-red-600"><i class="fas fa-exclamation-triangle"></i> Gagal memuat analisis: ${error.message}</span>`;
    }
};

const generateSmartAnalysis = (jawabanSalah, totalSoal) => {
    const totalSalah = jawabanSalah.length;
    const persentaseBenar = Math.round(((totalSoal - totalSalah) / totalSoal) * 100);

    let opening = "";
    if (persentaseBenar >= 85) {
        opening = "Luar biasa! Kamu menunjukkan pemahaman yang sangat baik pada materi ini dengan pencapaian di atas 85%. Pertahankan konsistensi belajar ini.";
    } else if (persentaseBenar >= 75) {
        opening = "Kerja bagus! Kamu menunjukkan pemahaman yang cukup baik. Masih ada beberapa area kecil yang perlu diperkuat untuk mencapai hasil maksimal.";
    } else {
        opening = "Tetap semangat! Kamu perlu meningkatkan pemahaman pada beberapa konsep dasar. Disarankan untuk mempelajari ulang materi dengan lebih fokus.";
    }

    // Analyze by type
    const typeCount = {
        PG: 0,
        PG_KOMPLEKS: 0,
        BENAR_SALAH: 0,
        ISIAN: 0,
        MENJODOHKAN: 0
    };

    jawabanSalah.forEach(item => {
        const tipe = item.tipe || 'PG';
        if (typeCount[tipe] !== undefined) {
            typeCount[tipe]++;
        }
    });

    const weaknesses = [];
    if (typeCount.PG > 0) weaknesses.push(`${typeCount.PG} soal Pilihan Ganda - Perkuat pemahaman konsep dan definisi`);
    if (typeCount.PG_KOMPLEKS > 0) weaknesses.push(`${typeCount.PG_KOMPLEKS} soal Pilihan Ganda Kompleks - Latih ketelitian analisis multi-jawaban`);
    if (typeCount.BENAR_SALAH > 0) weaknesses.push(`${typeCount.BENAR_SALAH} soal Benar/Salah - Tingkatkan ketelitian evaluasi pernyataan`);
    if (typeCount.ISIAN > 0) weaknesses.push(`${typeCount.ISIAN} soal Isian - Perkuat hafalan dan detail materi`);

    const recommendations = [];
    if (typeCount.PG > 0 || typeCount.PG_KOMPLEKS > 0) {
        recommendations.push("Baca kembali rangkuman materi utama.");
        recommendations.push("Latih soal-soal serupa untuk memperdalam pemahaman.");
    }
    if (typeCount.BENAR_SALAH > 0) {
        recommendations.push("Baca setiap pernyataan dengan perlahan dan hati-hati.");
    }
    if (typeCount.ISIAN > 0) {
        recommendations.push("Buat catatan kecil atau flashcard untuk mengingat istilah penting.");
    }

    if (recommendations.length === 0) {
        recommendations.push("Pertahankan metode belajarmu yang sudah efektif.");
        recommendations.push("Coba kerjakan soal-soal pengayaan untuk tantangan lebih.");
    }

    return { opening, weaknesses, recommendations };
};

// --- RENDER DETAILED ANALYSIS (REVISED V3: AI Integration) ---

const renderDetailedAnalysis = (soalReview, containerBenar, containerSalah, wrapBenar, wrapSalah, showKeyAllowed) => {
    containerBenar.innerHTML = '';
    containerSalah.innerHTML = '';

    let countBenar = 0;
    let countSalah = 0;

    soalReview.forEach(item => {
        // Helper: Format Answer with Text (e.g. "A. Description")
        const formatAns = (val, type) => {
            if (!val && val !== 0) return "(Tidak dijawab)";

            const renderSingle = (k) => {
                const kClean = String(k).trim().toUpperCase();
                // Jika ada map pilihan, gabungkan Key + Text
                if (item.pilihanMap && item.pilihanMap[kClean]) {
                    return `<strong>${kClean}</strong>. ${item.pilihanMap[kClean]}`;
                }
                return kClean;
            };

            if (type === 'PG_KOMPLEKS' || Array.isArray(val)) {
                // Handle array / comma-separated
                const arr = Array.isArray(val) ? val : String(val).split(',');
                return arr.map(k => renderSingle(k.trim())).join('<br>');
            }

            return renderSingle(val);
        };

        // Render Logic
        const itemDiv = document.createElement('div');
        itemDiv.className = `analysis-item ${item.isBenar ? 'correct' : 'wrong'}`;

        // 1. HEADER (Question)
        let html = `
            <div class="item-header">
                <span class="item-number">#${item.no}</span>
                <span class="item-question">${item.pertanyaan || 'Pertanyaan tidak dimuat'}</span>
            </div>
            <div class="item-details">
        `;

        // 2. CONTENT (Answer Display)
        if (item.tipe === 'BENAR_SALAH' && item.bsData && item.bsData.length > 0) {
            // TIPE: BENAR / SALAH (MODERN GRID TABLE)
            let rowsHtml = '';
            item.bsData.forEach((row, idx) => {
                const isRowCorrect = row.userVal === row.keyVal;
                // Status Class for styling
                const statusClass = isRowCorrect ? 'status-correct' : 'status-wrong';

                rowsHtml += `
                    <div class="bs-row ${statusClass}">
                        <div class="bs-statement">${row.text}</div>
                        <div class="bs-answers-wrapper">
                            <div class="bs-ans-group user">
                                <span class="bs-label">Jawabanmu</span>
                                <span class="bs-badge ${row.userVal === 'BENAR' ? 'badge-true' : 'badge-false'}">
                                    ${row.userVal || '-'}
                                </span>
                            </div>
                            ${!item.isBenar ? `
                            <div class="bs-ans-group key" id="key-container-${item.no}" style="display: ${showKeyAllowed ? 'flex' : 'none'};">
                                <span class="bs-label">Kunci</span>
                                <span class="bs-badge key-badge ${row.keyVal === 'BENAR' ? 'badge-true' : 'badge-false'}">
                                    ${row.keyVal}
                                </span>
                            </div>
                            ` : ''}
                        </div>
                    </div>
                 `;
            });

            html += `
                <div class="bs-container">
                    <div class="bs-header-row">
                        <div class="bs-h-statement">Pernyataan</div>
                        <div class="bs-h-ans">Respon Detail</div>
                    </div>
                    <div class="bs-body">
                        ${rowsHtml}
                    </div>
                </div>
                <!-- BUTTON CONTAINER (Shared for BS) -->
                <div class="explanation-action-area" id="action-area-${item.no}">
                    <!-- Button will be injected here if allowed -->
                </div>
                <div id="explanation-box-${item.no}" class="ai-explanation-box" style="display: none;">
                    <div class="ai-header">
                        <img src="img/FARA_BLACK (3).png" alt="AI Logo" class="ai-icon">
                        <span>Di Inisialisasi oleh AI</span>
                    </div>
                    <p class="ai-text" id="ai-text-${item.no}"></p>
                </div>
            `;
        }
        else if (item.tipe === 'MENJODOHKAN' && item.bsData && item.bsData.length > 0) {
            // TIPE: MENJODOHKAN (MATCHING TABLE UI)
            // Reusing bsData structure: text=Premis, userVal=UserAnswer, keyVal=CorrectAnswer
            let rowsHtml = '';
            item.bsData.forEach((row, idx) => {
                const isRowCorrect = row.userVal === row.keyVal;
                const statusClass = isRowCorrect ? 'status-correct' : 'status-wrong';

                rowsHtml += `
                    <div class="bs-row ${statusClass}">
                        <div class="bs-statement" style="font-weight:600;">${row.text}</div>
                        <div class="bs-answers-wrapper">
                            <div class="bs-ans-group user">
                                <span class="bs-label">Jawabanmu</span>
                                <span class="bs-badge ${isRowCorrect ? 'badge-true' : 'badge-false'}">
                                    ${row.userVal || '-'}
                                </span>
                            </div>
                            ${!item.isBenar ? `
                            <div class="bs-ans-group key" style="display: ${showKeyAllowed ? 'flex' : 'none'};">
                                <span class="bs-label">Kunci</span>
                                <span class="bs-badge key-badge badge-true">
                                    ${row.keyVal}
                                </span>
                            </div>
                            ` : ''}
                        </div>
                    </div>
                 `;
            });

            html += `
                <div class="bs-container">
                    <div class="bs-header-row">
                        <div class="bs-h-statement">Pasangan (Premis)</div>
                        <div class="bs-h-ans">Pencocokan</div>
                    </div>
                    <div class="bs-body">
                        ${rowsHtml}
                    </div>
                </div>
                 <!-- BUTTON CONTAINER (Shared) -->
                <div class="explanation-action-area" id="action-area-${item.no}"></div>
                <div id="explanation-box-${item.no}" class="ai-explanation-box" style="display: none;">
                    <div class="ai-header">
                        <img src="img/FARA_BLACK (3).png" alt="AI Logo" class="ai-icon">
                        <span>Di inisialisasi oleh AI</span>
                    </div>
                    <p class="ai-text" id="ai-text-${item.no}"></p>
                </div>
            `;
        }
        else {
            // TIPE: PG, ISIAN, ETC (STANDARD)
            const displayUser = formatAns(item.jawabanSiswa, item.tipe);
            const displayKey = formatAns(item.kunci, item.tipe);

            html += `
                <div class="detail-row">
                    <span class="detail-label">Jawabanmu:</span>
                    <span class="detail-value ${item.isBenar ? 'is-correct' : 'is-wrong'}">${displayUser}</span>
                </div>
                
                <!-- KEY ROW (Visible if ShowKeyAllowed) -->
                <div class="detail-row" id="key-row-${item.no}" style="display: ${showKeyAllowed ? 'flex' : 'none'};">
                    <span class="detail-label">Kunci:</span>
                    <span class="detail-value is-key">${displayKey}</span>
                </div>

                <!-- ACTION BUTTON AREA -->
                <div class="explanation-action-area" id="action-area-${item.no}">
                    <!-- Button will be injected here if allowed -->
                </div>

                <!-- AI EXPLANATION BOX -->
                <div id="explanation-box-${item.no}" class="ai-explanation-box" style="display: none;">
                    <div class="ai-header">
                        <img src="img/FARA_BLACK (3).png" alt="AI Logo" class="ai-icon">
                        <span>Di Inisialisasi oleh AI</span>
                    </div>
                    <p class="ai-text" id="ai-text-${item.no}"></p>
                </div>
            `;
        }

        html += `</div>`; // Close details
        itemDiv.innerHTML = html;

        // INJECT BUTTON LOGIC (ONLY IF TAMPILKAN JAWABAN = YA)
        const actionArea = itemDiv.querySelector(`#action-area-${item.no}`);
        if (actionArea && showKeyAllowed) {
            const btn = document.createElement('button');
            btn.className = 'btn-explain';
            btn.innerHTML = `<i class="fas fa-robot"></i> Di Inisialisasi oleh AI`;

            btn.onclick = async () => {
                // 1. UI Loading State (Skeleton)
                btn.style.display = 'none'; // Hide button immediately

                const box = itemDiv.querySelector(`#explanation-box-${item.no}`);
                const textEl = itemDiv.querySelector(`#ai-text-${item.no}`);

                if (box && textEl) {
                    box.style.display = 'block';
                    // Inject Skeleton
                    textEl.innerHTML = `
                        <div class="ai-skeleton-container" style="padding: 0; animation: none;">
                            <div class="skeleton-line skeleton-shimmer" style="width: 100%"></div>
                            <div class="skeleton-line skeleton-shimmer" style="width: 95%"></div>
                            <div class="skeleton-line skeleton-shimmer" style="width: 90%"></div>
                        </div>
                    `;
                }

                // 2. Fetch AI Explanation
                try {
                    // Prepare Data
                    const rawSoal = item.pertanyaan;
                    const rawJwb = formatAns(item.jawabanSiswa, item.tipe).replace(/<[^>]*>/g, '');
                    const rawKey = formatAns(item.kunci, item.tipe).replace(/<[^>]*>/g, '');

                    // Call API with Retry Callback
                    const explanation = await generateExplanation(
                        rawSoal,
                        rawJwb,
                        rawKey,
                        (attempt, max) => {
                            // Optional: Update loading text if needed, but skeleton is fine
                        }
                    );

                    // 4. Show Explanation Box (Existing logic references 'box' and 'textEl' again)

                    const box = itemDiv.querySelector(`#explanation-box-${item.no}`);
                    const textEl = itemDiv.querySelector(`#ai-text-${item.no}`);

                    if (box && textEl) {

                        // Check for Error / Debug Message
                        const isError = explanation.includes("[") && explanation.includes("ERROR]");

                        if (isError) {
                            textEl.innerHTML = explanation; // Error usually has newlines, let it be (pre-wrap handles it)
                            textEl.style.color = '#dc2626'; // Red text
                            textEl.style.fontFamily = 'monospace';
                            textEl.style.whiteSpace = 'pre-wrap';
                            textEl.style.fontSize = '0.85rem';

                            btn.innerHTML = `<i class="fas fa-sync-alt"></i> Coba Antre Lagi`;
                            btn.disabled = false;
                        } else {
                            // SUCCESS: Parse Markdown to HTML
                            textEl.innerHTML = parseMarkdown(explanation);

                            textEl.style.color = '#334155';
                            textEl.style.fontFamily = 'inherit';
                            textEl.style.whiteSpace = 'normal';
                            textEl.style.fontSize = '1rem';

                            // Render MathJax if available
                            if (window.MathJax && window.MathJax.typesetPromise) {
                                window.MathJax.typesetPromise([textEl]).catch(err => console.log('MathJax error:', err));
                            }

                            box.style.display = 'block';
                            box.classList.add('slide-down');
                            btn.style.display = 'none'; // Success: Hide button
                        }

                        // Always show box
                        box.style.display = 'block';
                        box.classList.add('slide-down');
                    }

                } catch (err) {
                    console.error(err);
                    btn.innerHTML = `<i class="fas fa-exclamation-circle"></i> Error. Coba Lagi`;
                    btn.disabled = false;
                }
            };

            actionArea.appendChild(btn);
        }

        if (item.isBenar) {
            containerBenar.appendChild(itemDiv);
            countBenar++;
        } else {
            containerSalah.appendChild(itemDiv);
            countSalah++;
        }
    });

    // Toggle Wrapper Visibility
    wrapBenar.style.display = countBenar > 0 ? 'block' : 'none';
    wrapSalah.style.display = countSalah > 0 ? 'block' : 'none';
};

// --- API HELPER (From bukti-ujian.js) ---

async function getSoalDetailForReview(shuffledSoal, jawabanSiswa, sheetSoal) {
    let serverSoal = [];

    // Helper Call API
    const callApi = async (act, pl) => {
        // Coba akses API global (biasanya di window.apiCall dari main.js/google-apps.js)
        if (typeof window.apiCall === 'function') return await window.apiCall(act, pl);
        if (typeof window.callApiInternal === 'function') return await window.callApiInternal(act, pl);

        // Fallback for development if window.apiCall not ready
        console.warn("API Function not found, returning local data.");
        return { soal: shuffledSoal };
    };

    try {
        const res = await callApi("getSoalWithKey", { sheetSoal });
        if (res && res.soal) {
            serverSoal = res.soal;
        } else {
            serverSoal = shuffledSoal;
        }
    } catch (e) {
        console.warn("Gagal fetch kunci, fallback local data", e);
        serverSoal = shuffledSoal;
    }

    const serverMap = {};
    serverSoal.forEach(s => { serverMap[s.no] = s; });

    return shuffledSoal.map((soalLocal, idx) => {
        // Map based on Original Index + 1 (Database Number)
        const dbNo = soalLocal.originalIndex + 1;
        const soalDB = serverMap[dbNo] || {};

        // Use Type & Key from Server if available, else local (which might be empty)
        const tipe = soalDB.tipe || soalLocal.tipe || "PG";
        const kunci = String(soalDB.kunci || "").toUpperCase(); // KUNCI UTAMA DARI SINI
        const userJwb = jawabanSiswa[soalLocal.originalIndex];

        let isBenar = false;
        let bsData = [];

        // 1. CONSTRUCT PILIHAN MAP (Key -> Text)
        // Cek soalLocal.pilihan (dari session)
        const pilihanMap = {};
        if (soalLocal.pilihan && Array.isArray(soalLocal.pilihan)) {
            soalLocal.pilihan.forEach(p => {
                // Map key (e.g. "A") to text (e.g. "Jawaban A")
                if (p.key && p.text) {
                    pilihanMap[String(p.key).toUpperCase()] = p.text;
                }
            });
        }

        // 2. LOGIC PENILAIAN & MAPPING
        if (tipe === 'BENAR_SALAH') {
            const kunciArr = kunci.split(',').map(k => k.trim());
            // Karena Benar/Salah tidak diacak (fixed in page-ujian.js), urutan visual = urutan asli
            let userAnswers = Array.isArray(userJwb) ? userJwb : String(userJwb || "").split(',');

            // Pastikan panjang array sama dengan kunci
            while (userAnswers.length < kunciArr.length) userAnswers.push("");

            const statementKeys = ["a", "b", "c", "d", "e"];
            isBenar = true; // Start true, set false if ANY mismatch

            // Build bsData for Table
            bsData = statementKeys.map((k, i) => {
                // Stop jika index melebihi kunci
                if (i >= kunciArr.length) return null;

                const stmt = soalDB[k] || `Pernyataan ${i + 1}`;
                const kVal = String(kunciArr[i] || "").toUpperCase().trim();
                const uVal = String(userAnswers[i] || "").toUpperCase().trim();

                // STRICT CHECK: Jika ada satu saja yang beda, maka Salah semua
                if (uVal !== kVal) isBenar = false;

                return { text: stmt, userVal: uVal, keyVal: kVal };
            }).filter(item => item !== null);

        } else if (tipe === 'MENJODOHKAN') {
            // TIPE: MENJODOHKAN
            // soalDB.pairs structure: [{id, left, right}, ...]
            // userJwb structure: ["Answer1", "Answer2", ...] associated by index

            const pairs = soalDB.pairs || [];
            // Jika pairs kosong (misal dari localstorage sebelum update), coba parsing manual fallback?
            // Tapi asumsi backend sudah benar.

            let userAnswers = Array.isArray(userJwb) ? userJwb : [];
            isBenar = true;

            bsData = pairs.map((p, i) => {
                const uVal = String(userAnswers[i] || "").trim(); // Case sensitive? User click is exact text
                const kVal = String(p.right || "").trim();

                // Strict verification
                if (uVal !== kVal) isBenar = false;

                return {
                    text: p.left,
                    userVal: uVal,
                    keyVal: kVal
                };
            });

            // Jika array kosong, dianggap salah
            if (pairs.length === 0) isBenar = false;

        } else {
            // NON-BS
            if (tipe === 'PG_KOMPLEKS') {
                const kSet = String(kunci).split(',').map(s => s.trim()).sort().join(',');
                const uSet = Array.isArray(userJwb) ? userJwb.sort().join(',') : String(userJwb || "").toUpperCase();
                isBenar = kSet === uSet;
            } else {
                const kClean = String(kunci).trim();
                const uClean = String(userJwb || "").toUpperCase().trim();
                isBenar = kClean === uClean;
            }
        }

        return {
            no: idx + 1,
            pertanyaan: soalLocal.pertanyaan,
            tipe: tipe,
            jawabanSiswa: userJwb,
            kunci: kunci,
            isBenar: isBenar,
            bsData: bsData,
            pilihanMap: pilihanMap
        };
    });
}


// --- RENDER DATA ---

const renderResultData = (siswa, ujian, hasil) => {
    const el = getElements();
    if (el.nama) el.nama.textContent = siswa["Nama Lengkap"];
    if (el.kelas) el.kelas.textContent = siswa.Kelas;
    if (el.mapel) el.mapel.textContent = ujian.topik;

    if (el.benar) el.benar.textContent = hasil.benar;
    if (el.salah) el.salah.textContent = hasil.salah;

    // Set default value sebelum animasi
    if (el.nilai) el.nilai.textContent = "0";

    // KKM Logic
    const kkm = 80; // Hardcoded based on requirements/bukti-ujian.js
    const isLulus = hasil.nilai >= kkm;

    if (el.kkmBadge) {
        if (isLulus) {
            el.kkmBadge.innerHTML = `
                <div class="kkm-badge lulus">
                    <i class="fas fa-check-circle"></i>
                    <span>TUNTAS (KKM ${kkm})</span>
                </div>
            `;
        } else {
            el.kkmBadge.innerHTML = `
                <div class="kkm-badge tidak-lulus">
                    <i class="fas fa-times-circle"></i>
                    <span>BELUM TUNTAS (KKM ${kkm})</span>
                </div>
            `;
        }
    }
};

// --- LOGIKA TOMBOL DOWNLOAD BUKTI (DENGAN AUTO-LOADER) ---

const setupDownloadButton = (ujianMeta) => {
    const el = getElements();
    if (!el.btnDownload) return;

    // Cek Konfigurasi Admin: "Tampilkan Jawaban?"
    const izinDownload = String(ujianMeta.tampilkanJawaban || "TIDAK").toUpperCase() === "YA";

    if (izinDownload) {
        el.btnDownload.style.display = 'inline-flex';

        el.btnDownload.onclick = async () => {
            // Tampilkan loading text
            const originalText = el.btnDownload.innerHTML;
            el.btnDownload.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Memuat...';
            el.btnDownload.disabled = true;

            try {
                // AUTO-HEALING: Cek apakah fungsi PDF ada? Jika tidak, load script-nya manual
                if (typeof window.generateBuktiUjian !== 'function') {
                    console.warn("PDF Generator belum dimuat, mencoba load manual...");
                    await loadScript('js/bukti-ujian.js');
                }

                // Cek lagi setelah load
                if (typeof window.generateBuktiUjian === 'function') {
                    await window.generateBuktiUjian();
                } else {
                    throw new Error("Gagal memuat modul PDF Generator.");
                }
            } catch (error) {
                console.error(error);
                safeSwalFire('Error', 'Gagal memproses PDF: ' + error.message, 'error');
            } finally {
                // Restore tombol
                el.btnDownload.innerHTML = originalText;
                el.btnDownload.disabled = false;
            }
        };
    } else {
        el.btnDownload.style.display = 'none';
    }
};

// --- LOGIKA TOMBOL SELESAI / PENGULANGAN ---

const setupFinishButton = (izinPengulangan) => {
    const el = getElements();
    if (!el.btnSelesai) return;

    const isRemedialAllowed = String(izinPengulangan || "TIDAK").toUpperCase() === "YA";

    // Helper untuk mencegah klik ganda & memberi feedback visual
    const executeLogoutWithFeedback = () => {
        // 1. Ubah Teks & Icon jadi Loading
        el.btnSelesai.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i> Memproses...';
        // 2. Matikan tombol agar tidak bisa diklik lagi
        el.btnSelesai.disabled = true;
        el.btnSelesai.style.opacity = '0.7';
        el.btnSelesai.style.cursor = 'not-allowed';

        // 3. Eksekusi Logout (dengan delay super singkat agar UI sempat update)
        setTimeout(() => {
            doLogout();
        }, 100);
    };

    if (isRemedialAllowed) {
        // MODE: BISA MENGULANG
        el.btnSelesai.innerHTML = '<i class="fas fa-redo mr-2"></i> Selesai / Ulangi';
        el.btnSelesai.classList.remove('btn-danger');
        el.btnSelesai.classList.add('btn-primary');

        el.btnSelesai.onclick = () => {
            safeSwalFire({
                title: 'Konfirmasi',
                text: "Apa langkah Anda selanjutnya?",
                icon: 'question',
                showDenyButton: true,
                showCancelButton: true,
                confirmButtonText: 'Ulangi Ujian',
                denyButtonText: 'Keluar (Logout)',
                cancelButtonText: 'Batal',
                confirmButtonColor: '#3085d6', // Biru
                denyButtonColor: '#d33'         // Merah
            }).then((result) => {
                if (result.isConfirmed) {
                    doRepeatExam();
                } else if (result.isDenied) {
                    executeLogoutWithFeedback();
                }
            });
        };
    } else {
        // MODE: TIDAK BISA MENGULANG (Logout Only)
        el.btnSelesai.innerHTML = '<i class="fas fa-sign-out-alt mr-2"></i> Logout / Selesai';
        el.btnSelesai.classList.add('btn-danger');

        el.btnSelesai.onclick = () => {
            safeSwalFire({
                title: 'Selesai Ujian?',
                text: "Anda akan keluar dari sesi ini.",
                icon: 'warning',
                showCancelButton: true,
                confirmButtonText: 'Ya, Keluar',
                cancelButtonText: 'Batal',
                confirmButtonColor: '#d33'
            }).then((result) => {
                if (result.isConfirmed) {
                    executeLogoutWithFeedback();
                }
            });
        };
    }
};

// --- AKSI & UTILS ---

const doRepeatExam = () => {
    // Hanya bersihkan data sesi ujian, tapi biarkan data Login (Siswa) tetap ada
    Store.clearExamSession();
    window.location.href = "summary.html";
};

const doLogout = () => {
    // 1. HITUNG URL TUJUAN DULU (PENTING!)
    // Kita harus tahu mau kemana sebelum 'membakar' jembatan (menghapus session)
    const targetUrl = getExitUrl();

    // 2. Hapus semua data (Siswa, Ujian, Jawaban, dan Flag Origin)
    Store.clearAll();

    // 3. Eksekusi Pindah Halaman
    // Menggunakan 'replace' agar user tidak bisa tekan tombol Back browser untuk kembali ke ujian
    window.location.replace(targetUrl);
};

const getExitUrl = () => {
    // LOGIKA PENENTUAN ARAH KELUAR (LMS vs HOSTING)
    
    const returnUrl = sessionStorage.getItem('exam_return_url');
    if (returnUrl) {
        return returnUrl;
    }

    // A. Ambil Flag dari Session (Diset saat awal di page-summary.js)
    const origin = sessionStorage.getItem('exam_origin');

    // B. Fallback Safety: Cek Referrer 
    // (Jaga-jaga jika flag session hilang/korup, kita cek jejak terakhir)
    const referrer = document.referrer || "";

    // KONDISI LMS:
    // Jika flag session = 'lms' ATAU Referrer mengandung domain LMS
    if (origin === 'lms' || referrer.includes('garudakademi.ct.ws')) {
        return 'http://garudakademi.ct.ws';
    }

    // KONDISI DEFAULT (HOSTING / LOCALHOST / NETLIFY):
    // Jika tidak terdeteksi sebagai LMS, kembalikan ke halaman Login aplikasi (index.html)
    return 'index.html';
};

const animateValue = (obj, start, end, duration) => {
    if (!obj) return;
    let startTimestamp = null;
    const step = (timestamp) => {
        if (!startTimestamp) startTimestamp = timestamp;
        const progress = Math.min((timestamp - startTimestamp) / duration, 1);
        obj.innerHTML = Math.floor(progress * (end - start) + start);
        if (progress < 1) {
            window.requestAnimationFrame(step);
        }
    };
    window.requestAnimationFrame(step);
};

// Helper: Load Script Dinamis (Penyelamat jika script tidak ada di HTML)
const loadScript = (src) => {
    return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = src;
        script.onload = () => resolve();
        script.onerror = () => reject(new Error(`Script load error for ${src}`));
        document.head.appendChild(script);
    });
};

// Helper: Safe Swal (Agar tidak error jika SweetAlert belum terload di login page)
const safeSwalFire = (options, text, icon) => {
    if (typeof Swal !== 'undefined') {
        // Support shorthand (title, text, icon) or object
        if (typeof options === 'string') {
            return Swal.fire(options, text, icon);
        }
        return Swal.fire(options);
    } else {
        // Fallback native alert/confirm
        if (typeof options === 'object' && options.title) {
            const isConfirmed = confirm(`${options.title}\n${options.text}`);
            // Mock promise structure for .then()
            return Promise.resolve({
                isConfirmed: isConfirmed,
                isDenied: !isConfirmed && options.showDenyButton
            });
        }
        alert(options);
        return Promise.resolve({});
    }
};

// Helper: Simple Markdown Parser (Bold, Italic, Header, List, Latex-like)
const parseMarkdown = (text) => {
    if (!text) return "";

    // 1. Escape HTML (prevent injection, but keep basic structure safe later)
    let html = text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");

    // 2. Bold (**text**)
    html = html.replace(/\*\*(.*?)\*\*/g, '<b>$1</b>');

    // 3. Italic (*text*)
    html = html.replace(/\*(.*?)\*/g, '<i>$1</i>');

    // 4. Headers (# Title) - Convert to h4 for subtitle size
    html = html.replace(/^#\s+(.*$)/gm, '<h4 class="font-bold text-lg mt-2">$1</h4>');
    html = html.replace(/^##\s+(.*$)/gm, '<h5 class="font-bold text-md mt-2">$1</h5>');

    // 5. Bullet Points (* Item)
    html = html.replace(/^\*\s+(.*$)/gm, '<li class="ml-4">$1</li>');

    // 6. LaTeX / Math Handling (Minimal fix for display)
    // Convert \[ ... \] block to centered div
    html = html.replace(/\\\[(.*?)\\\]/gs, '<div class="math-block text-center my-2">$$$1$$</div>');
    // Convert \( ... \) inline to normal MathJax delimiter
    html = html.replace(/\\\((.*?)\\\)/g, '$$$1$$');

    // 7. Newlines to <br> (but not inside lists/headers)
    html = html.replace(/\n/g, '<br>');

    return html;
};