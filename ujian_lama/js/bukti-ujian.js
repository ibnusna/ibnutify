/**
 * bukti-ujian-v2.js
 * Enhanced PDF Generator - Formal Academic Document
 * 
 * FITUR BARU:
 * - Pengelompokan soal berdasarkan tipe (PG, PG_KOMPLEKS, BENAR_SALAH, ISIAN)
 * - Header tipe soal dengan box border dan bold
 * - Analisis & Rekomendasi otomatis
 * - Ringkasan hasil ujian yang informatif
 * - Footer formal dengan tanda tangan digital
 * - Typography hierarchy profesional
 */

async function generateBuktiUjian() {
    try {
        // 1. DATA FETCHING & VALIDATION
        const siswaData = JSON.parse(sessionStorage.getItem("siswaData"));
        const ujianData = JSON.parse(sessionStorage.getItem("ujianData"));
        const hasilUjian = JSON.parse(sessionStorage.getItem("hasilUjian"));
        const jawabanSiswa = JSON.parse(sessionStorage.getItem("jawabanSiswa"));
        const shuffledSoal = JSON.parse(sessionStorage.getItem("shuffledSoal"));

        if (!siswaData || !ujianData || !hasilUjian) {
            throw new Error("Data ujian tidak lengkap. Harap refresh halaman.");
        }

        // 2. INIT PDF
        if (!window.jspdf) throw new Error("Library PDF Generator belum dimuat.");
        const { jsPDF } = window.jspdf;

        const doc = new jsPDF('p', 'mm', 'a4');
        const config = {
            pageWidth: doc.internal.pageSize.getWidth(),
            pageHeight: doc.internal.pageSize.getHeight(),
            margin: 20,
            lineHeight: 6,
            currY: 20,
            colors: {
                primary: [11, 87, 208],
                text: [33, 37, 41],
                green: [25, 135, 84],
                red: [220, 53, 69],
                lightGray: [248, 249, 250],
                darkGray: [100, 100, 100],
                borderGray: [200, 200, 200]
            }
        };

        // 3. RENDER CONTENT
        renderHeader(doc, config);
        renderStudentInfo(doc, config, siswaData, ujianData, hasilUjian);

        // 4. RINGKASAN HASIL
        renderSummaryBox(doc, config, hasilUjian, shuffledSoal.length);

        // 5. GET DETAIL SOAL
        const soalReview = await getSoalDetailForReview(shuffledSoal, jawabanSiswa, ujianData.sheetSoal);
        const jawabanBenar = soalReview.filter(item => item.isBenar);
        const jawabanSalah = soalReview.filter(item => !item.isBenar);

        // 6. ANALISIS & REKOMENDASI
        renderAnalysisRecommendation(doc, config, jawabanSalah, soalReview);

        // 7. SECTION: JAWABAN BENAR (GROUPED BY TYPE)
        config.currY += 5;
        renderSectionTitle(doc, config, `ANALISIS JAWABAN BENAR (${jawabanBenar.length} soal)`, config.colors.green);

        if (jawabanBenar.length === 0) {
            renderEmptyState(doc, config, "Tidak ada jawaban yang benar.");
        } else {
            renderGroupedSoal(doc, config, jawabanBenar, false);
        }

        // 8. SECTION: JAWABAN SALAH (GROUPED BY TYPE)
        config.currY += 5;
        checkPageBreak(doc, config, 30);
        renderSectionTitle(doc, config, `ANALISIS JAWABAN SALAH (${jawabanSalah.length} soal)`, config.colors.red);

        if (jawabanSalah.length === 0) {
            renderEmptyState(doc, config, "Luar biasa! Tidak ada jawaban yang salah.");
        } else {
            renderGroupedSoal(doc, config, jawabanSalah, true);
        }

        // 9. FOOTER WITH SIGNATURE
        // 9. FOOTER WITH SIGNATURE
        await renderFooterWithSignature(doc, config, siswaData, ujianData);

        // 10. SAVE FILE
        const safeName = (siswaData['Nama Lengkap'] || 'Siswa').replace(/[^a-zA-Z0-9]/g, '_');
        const safeTopik = (ujianData.topik || 'Ujian').replace(/[^a-zA-Z0-9]/g, '_');
        doc.save(`HASIL_${safeTopik}_${safeName}.pdf`);

    } catch (error) {
        console.error(error);
        alert("Gagal membuat PDF: " + error.message);
    }
}

// ==========================================
// HEADER & INFO COMPONENTS
// ==========================================

function renderHeader(doc, cfg) {
    const cx = cfg.pageWidth / 2;

    // Logo/Title School
    doc.setFont("times", "bold");
    doc.setFontSize(16);
    doc.text("SMP IT DARUL HIDAYAH", cx, cfg.currY, { align: "center" });

    cfg.currY += 6;
    doc.setFontSize(12);
    doc.text("TERAKREDITASI B", cx, cfg.currY, { align: "center" });

    // Address Info
    cfg.currY += 5;
    doc.setFont("times", "normal");
    doc.setFontSize(9);
    doc.text("NSS : 202020234733 / NPSN : 69968049", cx, cfg.currY, { align: "center" });
    cfg.currY += 4;
    doc.text("Jl. Atang Senjaya Bojong Tengah RT.05/06 Desa Bantarsari", cx, cfg.currY, { align: "center" });
    cfg.currY += 4;
    doc.text("Kec. Rancabungur Kab. Bogor", cx, cfg.currY, { align: "center" });

    // Double Line Border
    cfg.currY += 6;
    doc.setLineWidth(0.8);
    doc.line(cfg.margin, cfg.currY, cfg.pageWidth - cfg.margin, cfg.currY);
    doc.setLineWidth(0.3);
    doc.line(cfg.margin, cfg.currY + 1.5, cfg.pageWidth - cfg.margin, cfg.currY + 1.5);
    cfg.currY += 8;
}

function renderStudentInfo(doc, cfg, siswa, meta, hasil) {
    doc.setFont("times", "bold");
    doc.setFontSize(14);
    doc.text("BUKTI HASIL UJIAN", cfg.pageWidth / 2, cfg.currY, { align: "center" });

    cfg.currY += 10;
    doc.setFont("times", "normal");
    doc.setFontSize(10);
    const startY = cfg.currY;

    const labels = [
        ["Nama Lengkap", `: ${siswa['Nama Lengkap']}`],
        ["Nomor Induk (NIS)", `: ${siswa.NIS}`],
        ["Kelas", `: ${siswa.Kelas}`],
        ["Topik Ujian", `: ${meta.topik}`],
        ["Waktu Pengerjaan", `: ${new Date().toLocaleDateString('id-ID', { day: 'numeric', month: 'long', year: 'numeric' })}`]
    ];

    labels.forEach(row => {
        doc.text(row[0], cfg.margin, cfg.currY);
        doc.text(row[1], cfg.margin + 40, cfg.currY);
        cfg.currY += 5.5;
    });

    // BOX NILAI (Enhanced)
    const boxW = 45;
    const boxH = 32;
    const boxX = cfg.pageWidth - cfg.margin - boxW;
    const boxY = startY;

    doc.setDrawColor(...cfg.colors.borderGray);
    doc.setLineWidth(0.5);
    doc.rect(boxX, boxY, boxW, boxH);

    doc.setFontSize(11);
    doc.setFont("times", "bold");
    doc.setTextColor(...cfg.colors.text);
    doc.text("NILAI AKHIR", boxX + (boxW / 2), boxY + 8, { align: "center" });

    doc.setFontSize(28);
    if (hasil.nilai < 75) doc.setTextColor(...cfg.colors.red);
    else doc.setTextColor(...cfg.colors.green);

    doc.text(String(hasil.nilai), boxX + (boxW / 2), boxY + 20, { align: "center" });

    // Status Text
    doc.setFontSize(9);
    doc.setFont("times", "italic");
    const statusText = hasil.nilai >= 75 ? "TUNTAS" : "BELUM TUNTAS";
    doc.text(statusText, boxX + (boxW / 2), boxY + 27, { align: "center" });

    doc.setTextColor(0);
    cfg.currY = Math.max(cfg.currY, boxY + boxH + 8);
}

// ==========================================
// SUMMARY & ANALYSIS COMPONENTS
// ==========================================

function renderSummaryBox(doc, cfg, hasil, totalSoal) {
    checkPageBreak(doc, cfg, 50);

    const boxX = cfg.margin;
    const boxW = cfg.pageWidth - (cfg.margin * 2);
    const boxH = 45;
    const startY = cfg.currY;

    // Border Box
    doc.setDrawColor(...cfg.colors.borderGray);
    doc.setLineWidth(0.5);
    doc.rect(boxX, startY, boxW, boxH);

    // Header
    doc.setFillColor(...cfg.colors.lightGray);
    doc.rect(boxX, startY, boxW, 8, 'F');
    doc.setFont("times", "bold");
    doc.setFontSize(11);
    doc.setTextColor(...cfg.colors.text);
    doc.text("RINGKASAN HASIL UJIAN", boxX + 3, startY + 5.5);

    // Content
    doc.setFont("times", "normal");
    doc.setFontSize(10);
    const contentY = startY + 14;
    const lineSpacing = 6;

    const benar = hasil.benar || 0;
    const salah = hasil.salah || 0;
    const persentase = Math.round((benar / totalSoal) * 100);
    const kkmStatus = hasil.nilai >= 80 ? "LULUS" : "TIDAK LULUS";
    const percobaan = hasil.percobaan || 1;

    doc.text(`Jawaban Benar`, boxX + 5, contentY);
    doc.text(`: ${benar} soal`, boxX + 50, contentY);

    doc.text(`Jawaban Salah`, boxX + 5, contentY + lineSpacing);
    doc.text(`: ${salah} soal`, boxX + 50, contentY + lineSpacing);

    doc.text(`Total Soal`, boxX + 5, contentY + (lineSpacing * 2));
    doc.text(`: ${totalSoal} soal`, boxX + 50, contentY + (lineSpacing * 2));

    doc.text(`Persentase Ketuntasan`, boxX + 5, contentY + (lineSpacing * 3));
    doc.text(`: ${persentase}%`, boxX + 50, contentY + (lineSpacing * 3));

    doc.setFont("times", "bold");
    doc.text(`Status Kelulusan`, boxX + 5, contentY + (lineSpacing * 4));
    if (kkmStatus === "LULUS") {
        doc.setTextColor(...cfg.colors.green);
    } else {
        doc.setTextColor(...cfg.colors.red);
    }
    doc.text(`: ${kkmStatus} (KKM: 80)`, boxX + 50, contentY + (lineSpacing * 4));
    doc.setTextColor(0);

    doc.setFont("times", "normal");
    doc.text(`Percobaan Ke`, boxX + 5, contentY + (lineSpacing * 5));
    doc.text(`: ${percobaan}`, boxX + 50, contentY + (lineSpacing * 5));

    cfg.currY = startY + boxH + 8;
}

function renderAnalysisRecommendation(doc, cfg, jawabanSalah, allSoal) {
    checkPageBreak(doc, cfg, 60);

    const boxX = cfg.margin;
    const boxW = cfg.pageWidth - (cfg.margin * 2);
    const startY = cfg.currY;

    // Header
    doc.setFillColor(...cfg.colors.lightGray);
    doc.rect(boxX, startY, boxW, 8, 'F');
    doc.setFont("times", "bold");
    doc.setFontSize(11);
    doc.setTextColor(...cfg.colors.text);
    doc.text("ANALISIS & REKOMENDASI BELAJAR", boxX + 3, startY + 5.5);

    cfg.currY = startY + 12;
    doc.setFont("times", "normal");
    doc.setFontSize(10);

    // Generate Smart Analysis
    const analysis = generateSmartAnalysis(jawabanSalah, allSoal);

    // Opening Statement
    const contentWidth = boxW - 10;
    const openingLines = doc.splitTextToSize(analysis.opening, contentWidth);
    doc.text(openingLines, boxX + 5, cfg.currY);
    cfg.currY += openingLines.length * 4.5 + 3;

    // Area Yang Perlu Ditingkatkan
    if (analysis.weaknesses.length > 0) {
        doc.setFont("times", "bold");
        doc.text("Area yang Perlu Ditingkatkan:", boxX + 5, cfg.currY);
        cfg.currY += 5;
        doc.setFont("times", "normal");

        analysis.weaknesses.forEach(item => {
            const itemLines = doc.splitTextToSize(`• ${item}`, contentWidth - 5);
            doc.text(itemLines, boxX + 8, cfg.currY);
            cfg.currY += itemLines.length * 4.5;
        });
        cfg.currY += 2;
    }

    // Saran Belajar
    doc.setFont("times", "bold");
    doc.text("Saran Belajar:", boxX + 5, cfg.currY);
    cfg.currY += 5;
    doc.setFont("times", "normal");

    analysis.recommendations.forEach(rec => {
        const recLines = doc.splitTextToSize(`- ${rec}`, contentWidth - 5);
        doc.text(recLines, boxX + 8, cfg.currY);
        cfg.currY += recLines.length * 4.5;
    });

    // Border Box
    const boxH = cfg.currY - startY + 3;
    doc.setDrawColor(...cfg.colors.borderGray);
    doc.setLineWidth(0.5);
    doc.rect(boxX, startY, boxW, boxH);

    cfg.currY += 5;
}

function generateSmartAnalysis(jawabanSalah, allSoal) {
    const totalSalah = jawabanSalah.length;
    const totalSoal = allSoal.length;
    const persentaseBenar = Math.round(((totalSoal - totalSalah) / totalSoal) * 100);

    let opening = "";
    if (persentaseBenar >= 85) {
        opening = "Berdasarkan hasil ujian, kamu menunjukkan pemahaman yang sangat baik pada materi ini dengan pencapaian di atas 85%. Pertahankan konsistensi belajar ini.";
    } else if (persentaseBenar >= 75) {
        opening = "Berdasarkan hasil ujian, kamu menunjukkan pemahaman yang cukup baik pada materi ini. Masih ada beberapa area yang perlu diperkuat untuk mencapai hasil maksimal.";
    } else {
        opening = "Berdasarkan hasil ujian, kamu perlu meningkatkan pemahaman pada beberapa konsep dasar. Disarankan untuk mempelajari ulang materi dengan lebih fokus.";
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
    if (typeCount.PG > 0) {
        weaknesses.push(`${typeCount.PG} soal Pilihan Ganda - Fokus pada pemahaman konsep dan definisi`);
    }
    if (typeCount.PG_KOMPLEKS > 0) {
        weaknesses.push(`${typeCount.PG_KOMPLEKS} soal Pilihan Ganda Kompleks - Latih analisis multi-jawaban`);
    }
    if (typeCount.BENAR_SALAH > 0) {
        weaknesses.push(`${typeCount.BENAR_SALAH} soal Benar/Salah - Tingkatkan ketelitian dalam evaluasi pernyataan`);
    }
    if (typeCount.ISIAN > 0) {
        weaknesses.push(`${typeCount.ISIAN} soal Isian - Perkuat penguasaan materi secara detail`);
    }
    if (typeCount.MENJODOHKAN > 0) {
        weaknesses.push(`${typeCount.MENJODOHKAN} soal Menjodohkan - Tingkatkan ketelitian dalam menghubungkan antar konsep`);
    }

    const recommendations = [];
    if (typeCount.PG > 0 || typeCount.PG_KOMPLEKS > 0) {
        recommendations.push("Pelajari kembali konsep dasar materi yang diujikan");
        recommendations.push("Buat catatan ringkasan untuk definisi-definisi penting");
    }
    if (typeCount.BENAR_SALAH > 0) {
        recommendations.push("Latih kemampuan analisis dengan membaca pernyataan secara teliti");
        recommendations.push("Diskusikan konsep yang masih membingungkan dengan guru");
    }
    if (typeCount.ISIAN > 0) {
        recommendations.push("Perbanyak latihan soal perhitungan dan hafalan");
        recommendations.push("Buat kartu belajar (flashcard) untuk memorisasi");
    }
    if (typeCount.MENJODOHKAN > 0) {
        recommendations.push("Latih pemahaman hubungan antar konsep/istilah");
        recommendations.push("Buat representasi visual untuk mengaitkan materi");
    }

    if (recommendations.length === 0) {
        recommendations.push("Pertahankan metode belajar yang sudah efektif");
        recommendations.push("Tingkatkan latihan soal untuk menjaga konsistensi");
    }

    return { opening, weaknesses, recommendations };
}

// ==========================================
// GROUPED RENDERING (NEW FEATURE)
// ==========================================

function renderGroupedSoal(doc, cfg, soalArray, showKey) {
    // Group by type
    const grouped = {
        PG: [],
        PG_KOMPLEKS: [],
        BENAR_SALAH: [],
        ISIAN: [],
        MENJODOHKAN: []
    };

    soalArray.forEach(item => {
        const tipe = item.tipe || 'PG';
        if (grouped[tipe]) {
            grouped[tipe].push(item);
        }
    });

    // Render in order
    const typeLabels = {
        PG: "PILIHAN GANDA",
        PG_KOMPLEKS: "PILIHAN GANDA KOMPLEKS",
        BENAR_SALAH: "BENAR / SALAH",
        ISIAN: "ISIAN SINGKAT",
        MENJODOHKAN: "MENJODOHKAN"
    };

    const typeOrder = ['PG', 'PG_KOMPLEKS', 'BENAR_SALAH', 'MENJODOHKAN', 'ISIAN'];

    typeOrder.forEach(tipe => {
        if (grouped[tipe].length > 0) {
            renderTypeHeader(doc, cfg, typeLabels[tipe]);

            grouped[tipe].forEach(item => {
                checkPageBreak(doc, cfg, 40);
                renderItemSoal(doc, cfg, item, showKey);
            });

            cfg.currY += 3; // Extra space between types
        }
    });
}

function renderTypeHeader(doc, cfg, label) {
    checkPageBreak(doc, cfg, 15);

    const boxX = cfg.margin + 2;
    const boxW = cfg.pageWidth - (cfg.margin * 2) - 4;
    const boxH = 7;

    // Background
    doc.setFillColor(...cfg.colors.lightGray);
    doc.rect(boxX, cfg.currY, boxW, boxH, 'F');

    // Border
    doc.setDrawColor(...cfg.colors.borderGray);
    doc.setLineWidth(0.3);
    doc.rect(boxX, cfg.currY, boxW, boxH);

    // Text
    doc.setFont("times", "bold");
    doc.setFontSize(10);
    doc.setTextColor(...cfg.colors.text);
    doc.text(label, boxX + 3, cfg.currY + 5);

    cfg.currY += boxH + 5;
}

function renderSectionTitle(doc, cfg, title, colorArr) {
    doc.setFont("times", "bold");
    doc.setFontSize(12);
    doc.setTextColor(...colorArr);
    doc.text(title, cfg.margin, cfg.currY);
    doc.setDrawColor(...colorArr);
    doc.setLineWidth(0.5);
    doc.line(cfg.margin, cfg.currY + 1.5, cfg.pageWidth - cfg.margin, cfg.currY + 1.5);
    doc.setTextColor(0);
    cfg.currY += 8;
}

function renderEmptyState(doc, cfg, msg) {
    doc.setFont("times", "italic");
    doc.setFontSize(10);
    doc.setTextColor(...cfg.colors.darkGray);
    doc.text(msg, cfg.margin, cfg.currY);
    cfg.currY += 8;
    doc.setTextColor(0);
}

// ==========================================
// ITEM RENDERING
// ==========================================

function renderItemSoal(doc, cfg, item, showKey) {
    doc.setFont("times", "bold");
    doc.setFontSize(10);
    const noText = `${item.no}.`;
    const noWidth = doc.getTextWidth(noText);
    doc.text(noText, cfg.margin, cfg.currY);

    const contentWidth = cfg.pageWidth - (cfg.margin * 2) - noWidth - 2;
    const qLines = doc.splitTextToSize(item.pertanyaan, contentWidth);
    doc.text(qLines, cfg.margin + noWidth + 2, cfg.currY);
    cfg.currY += (qLines.length * 4.5) + 3;

    if (item.tipe === 'BENAR_SALAH' || item.tipe === 'MENJODOHKAN') {
        renderBenarSalahTable(doc, cfg, item, showKey);
    } else {
        renderStandardAnswer(doc, cfg, item, showKey);
    }
    cfg.currY += 6;
}

function renderBenarSalahTable(doc, cfg, item, showKey) {
    const startX = cfg.margin + 5;
    const tableWidth = cfg.pageWidth - (cfg.margin * 2) - 10;
    const col1W = 10;
    const col3W = 20;
    const col4W = showKey ? 22 : 0;
    const col2W = tableWidth - col1W - col3W - col4W;

    // Header
    doc.setFillColor(...cfg.colors.lightGray);
    doc.rect(startX, cfg.currY, tableWidth, 7, 'F');
    doc.setFont("times", "bold");
    doc.setFontSize(9);

    const hY = cfg.currY + 5;
    doc.text("No", startX + 2, hY);
    doc.text(item.tipe === 'MENJODOHKAN' ? "Premis" : "Pernyataan", startX + col1W + 2, hY);
    doc.text("Jwb", startX + col1W + col2W + 5, hY);
    if (showKey) doc.text("Kunci", startX + col1W + col2W + col3W + 5, hY);

    doc.setDrawColor(...cfg.colors.borderGray);
    doc.rect(startX, cfg.currY, tableWidth, 7);
    cfg.currY += 7;

    // Rows
    const rows = item.bsData || [];
    doc.setFont("times", "normal");

    rows.forEach((row, idx) => {
        const textLines = doc.splitTextToSize(row.text, col2W - 4);
        const rowHeight = Math.max(7, (textLines.length * 4) + 3);

        if (cfg.currY + rowHeight > cfg.pageHeight - cfg.margin) {
            doc.addPage();
            cfg.currY = cfg.margin;
        }

        // Zebra striping
        if (idx % 2 === 1) {
            doc.setFillColor(250, 250, 250);
            doc.rect(startX, cfg.currY, tableWidth, rowHeight, 'F');
        }

        doc.setDrawColor(...cfg.colors.borderGray);
        doc.rect(startX, cfg.currY, tableWidth, rowHeight);
        doc.line(startX + col1W, cfg.currY, startX + col1W, cfg.currY + rowHeight);
        doc.line(startX + col1W + col2W, cfg.currY, startX + col1W + col2W, cfg.currY + rowHeight);
        if (showKey) doc.line(startX + col1W + col2W + col3W, cfg.currY, startX + col1W + col2W + col3W, cfg.currY + rowHeight);

        doc.setFontSize(9);
        doc.text(String(idx + 1), startX + 2, cfg.currY + 5);
        doc.text(textLines, startX + col1W + 2, cfg.currY + 5);

        const jwb = row.userVal || "-";
        const isMatch = jwb === row.keyVal;
        if (isMatch) doc.setTextColor(...cfg.colors.green);
        else doc.setTextColor(...cfg.colors.red);
        doc.setFont("times", isMatch ? "bold" : "normal");
        doc.text(jwb, startX + col1W + col2W + 5, cfg.currY + 5);
        doc.setTextColor(0);
        doc.setFont("times", "normal");

        if (showKey) {
            doc.setFont("times", "bold");
            doc.text(row.keyVal, startX + col1W + col2W + col3W + 5, cfg.currY + 5);
            doc.setFont("times", "normal");
        }
        cfg.currY += rowHeight;
    });
}

function renderStandardAnswer(doc, cfg, item, showKey) {
    const startX = cfg.margin + 5;
    const contentWidth = cfg.pageWidth - (cfg.margin * 2) - 10;

    const formatAns = (val) => {
        if (!val) return "(Tidak dijawab)";

        const getLabel = (key) => {
            const text = item.pilihanMap && item.pilihanMap[key] ? item.pilihanMap[key] : '';
            return text ? `${key}. ${text}` : key;
        };

        if (Array.isArray(val)) {
            return val.map(v => getLabel(v)).join(" | ");
        }
        return getLabel(val);
    };

    const userAns = formatAns(item.jawabanSiswa);
    const keyAns = formatAns(item.kunci);

    // Render Jawaban Siswa
    doc.setFont("times", "normal");
    doc.setFontSize(10);
    const userLines = doc.splitTextToSize(`Jawaban Kamu: ${userAns}`, contentWidth);
    doc.text(userLines, startX, cfg.currY);
    cfg.currY += (userLines.length * 4.5) + 2;

    // Status Icon
    const isCorrect = item.isBenar;
    doc.setFont("times", "bold");
    doc.setFontSize(10);

    if (isCorrect) {
        doc.setTextColor(...cfg.colors.green);
        doc.text("✓ BENAR", startX, cfg.currY);
    } else {
        doc.setTextColor(...cfg.colors.red);
        doc.text("✗ SALAH", startX, cfg.currY);
    }

    doc.setFont("times", "normal");
    doc.setTextColor(0);
    cfg.currY += 5;

    // Render Kunci (Only if wrong)
    if (showKey && !isCorrect) {
        doc.setFont("times", "bold");
        doc.setFontSize(10);
        const keyLines = doc.splitTextToSize(`Jawaban Benar: ${keyAns}`, contentWidth);
        doc.text(keyLines, startX, cfg.currY);
        doc.setFont("times", "normal");
        cfg.currY += (keyLines.length * 4.5);
    }
}

// ==========================================
// FOOTER WITH SIGNATURE
// ==========================================

async function renderFooterWithSignature(doc, cfg, siswa, meta) {
    checkPageBreak(doc, cfg, 55);
    cfg.currY += 10;

    const dateStr = new Date().toLocaleDateString('id-ID', {
        day: 'numeric',
        month: 'long',
        year: 'numeric'
    });
    const signX = cfg.pageWidth - cfg.margin - 60;

    doc.setFont("times", "normal");
    doc.setFontSize(10);
    doc.text(`Bogor, ${dateStr}`, signX, cfg.currY);
    cfg.currY += 5;
    doc.text("Guru Mata Pelajaran,", signX, cfg.currY);
    cfg.currY += 15;

    // Signature Image (Load dari path)
    try {
        const imgPath = 'img/image.png';

        await new Promise((resolve) => {
            const img = new Image();
            img.src = imgPath;

            img.onload = () => {
                try {
                    // Fix: Use 'PNG' instead of 'SVG'
                    doc.addImage(img, 'PNG', signX, cfg.currY - 10, 15, 15);
                } catch (e) {
                    console.warn("Gagal menambahkan gambar TTD:", e);
                }
                resolve();
            };

            img.onerror = (e) => {
                console.warn("File signature tidak dapat dimuat:", e);
                resolve(); // Resolve anyway to ensure PDF is saved
            };
        });

        cfg.currY += 5;
    } catch (e) {
        console.warn("Error processing signature:", e);
        cfg.currY += 5;
    }

    doc.setFont("times", "bold");
    doc.text("Ibnu Sina Sudrajat", signX, cfg.currY);
    cfg.currY += 1;
    doc.setLineWidth(0.3);
    doc.line(signX, cfg.currY, signX + 45, cfg.currY);
    cfg.currY += 4;

    doc.setFont("times", "normal");
    doc.setFontSize(9);
    doc.text("NIP: -", signX, cfg.currY);

    // Timestamp watermark
    const ts = new Date().toLocaleString('id-ID');
    doc.setFont("times", "italic");
    doc.setFontSize(7);
    doc.setTextColor(...cfg.colors.darkGray);
    doc.text(`Diunduh otomatis oleh sistem GARA pada: ${ts}`, cfg.margin, cfg.pageHeight - 8);
    doc.setTextColor(0);
}

function checkPageBreak(doc, cfg, neededHeight) {
    if (cfg.currY + neededHeight > cfg.pageHeight - cfg.margin) {
        doc.addPage();
        cfg.currY = cfg.margin;
    }
}

// ==========================================
// DATA LOGIC (ROBUST)
// ==========================================

async function getSoalDetailForReview(shuffledSoal, jawabanSiswa, sheetSoal) {
    let serverSoal = [];
    const callApi = async (act, pl) => {
        if (window.callApiInternal) return await window.callApiInternal(act, pl);
        if (window.apiCall) return await window.apiCall(act, pl);
        return { soal: shuffledSoal };
    };

    try {
        const res = await callApi("getSoalWithKey", { sheetSoal });
        serverSoal = res.soal;
    } catch (e) {
        console.warn("Fallback Local Data", e);
        serverSoal = shuffledSoal;
    }

    const serverMap = {};
    serverSoal.forEach(s => { serverMap[s.no] = s; });

    return shuffledSoal.map((soalLocal, idx) => {
        const dbNo = soalLocal.originalIndex + 1;
        const soalDB = serverMap[dbNo] || {};

        const tipe = soalDB.tipe || "PG";
        const kunci = String(soalDB.kunci || "").toUpperCase();
        const userJwb = jawabanSiswa[soalLocal.originalIndex];

        let isBenar = false;
        let bsData = [];

        // Construct Map Pilihan (Key -> Text)
        const pilihanMap = {};
        if (soalLocal.pilihan && Array.isArray(soalLocal.pilihan)) {
            soalLocal.pilihan.forEach(p => {
                if (p.key && p.text) {
                    pilihanMap[p.key] = p.text;
                }
            });
        }

        if (tipe === 'BENAR_SALAH') {
            const kunciArr = kunci.split(',').map(k => k.trim());
            // Karena Benar/Salah tidak diacak (fixed in page-ujian.js), urutan visual = urutan asli
            let userAnswers = Array.isArray(userJwb) ? userJwb : String(userJwb || "").split(',');

            // Pastikan panjang array sama dengan kunci
            while (userAnswers.length < kunciArr.length) userAnswers.push("");

            const statementKeys = ["a", "b", "c", "d", "e"];
            isBenar = true; // Default True, one wrong makes it False

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
            // Karena MENJODOHKAN opsional kunci array length dinamis berdasarkan pairs
            const pairs = soalDB.pairs || soalLocal.pairs || [];
            let userAnswers = Array.isArray(userJwb) ? userJwb : [];
            isBenar = true;

            bsData = pairs.map((pair, i) => {
                const kVal = String(pair.right || "").toUpperCase().trim();
                const uVal = String(userAnswers[i] || "").toUpperCase().trim();

                if (uVal !== kVal) isBenar = false;

                return { text: pair.left, userVal: uVal, keyVal: kVal };
            });

        } else if (tipe === 'PG_KOMPLEKS') {
            const kSet = kunci.split(',').map(s => s.trim()).sort().join(',');
            const uSet = Array.isArray(userJwb) ? userJwb.sort().join(',') : String(userJwb).toUpperCase();
            isBenar = kSet === uSet;
        } else {
            const kClean = kunci.trim();
            const uClean = String(userJwb || "").toUpperCase().trim();
            isBenar = kClean === uClean;
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