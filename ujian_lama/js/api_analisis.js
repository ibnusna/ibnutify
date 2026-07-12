/**
/**
 * API Module for Comprehensive Exam Analysis
 * Refactored from previous chat-based implementation.
 */

const API_KEY = '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';
const API_URL = 'https://openrouter.ai/api/v1/chat/completions';

// DAFTAR MODEL (Urutan Prioritas - Valid OpenRouter Free Models)
const MODELS = [
    'google/gemini-2.5-flash-lite',          // Primary: Google Flash 2.0 (Cepat & Cerdas)
    'nvidia/nemotron-3-nano-30b-a3b:free', // Fallback 1: Llama 3.2 (Reliable)
    'deepseek/deepseek-r1-0528:free',       // Fallback 2: Llama 3 (Backup)
    'xiaomi/mimo-v2-flash:free',         // Fallback 3: Zephyr (Stable)
    'mistralai/mistral-7b-instruct:free'         // Fallback 4: Mistral
];

/**
 * Menganalisis hasil ujian secara keseluruhan menggunakan AI.
 * @param {Object} data - Data hasil ujian (nilai, jawabanSalah[], topik, dll)
 * @returns {Promise<string>} - HTML string berisi analisis markdown/formatted text
 */
export async function analyzeExamOverall(data) {
    const {
        siswaName,
        mapel,
        nilai,
        benar,
        salah,
        detailSalah // Array of { soal, jawabanSiswa, kunci }
    } = data;

    // Build formatted list of mistakes
    let mistakesContext = "Tidak ada jawaban salah (Nilai Sempurna!). Berikan tips pengayaan.";
    if (detailSalah && detailSalah.length > 0) {
        mistakesContext = detailSalah.map((item, idx) => {
            return `[Soal #${idx + 1}]
   Pertanyaan: "${item.soal}"
   Jawaban Siswa (SALAH): ${item.jawabanSiswa}
   Kunci Benar: ${item.kunci}`;
        }).join('\n\n');
    }

    // Construct Context for AI
    const prompt = `
Peran: Senior Guru IPA/Informatika tingkat profesional.
Siswa: "${siswaName}"
Mapel: "${mapel}"
Skor: ${nilai}/100 (Benar: ${benar}, Salah: ${salah})

DAFTAR KESALAHAN SISWA (Wajib Dianalisis):
---------------------------------------------------
${mistakesContext}
---------------------------------------------------

TUGAS:
Buat laporan evaluasi diri untuk siswa dalam format HTML (div/p/ul/strong) yang rapi. Jangan gunakan Markdown.

INSTRUKSI KHUSUS:
1. JANGAN HALUSINASI. Gunakan data teks jawaban yang sudah disediakan di atas (misal "A (Kucing)"). Jangan mengarang opsi sendiri jika tidak ada di data.
2. JANGAN BASA-BASI. Langsung ke inti analisis per-soal yang salah.
3. FOKUS UTAMA: Jelaskan mengapa opsi jawaban siswa salah dibandingkan kunci yang benar.
4. Gunakan bahasa Indonesia yang asik dan ala gen-z dan ada sedikit kata sundanya, menyemangati, tapi korektif.
5. Bila ada rumus matematika/fisika/kimia, gunakan format LaTeX yang valid:
   - Inline: \\( rumus \\)
   - Block: $$ rumus $$

STRUKTUR HTML OUTPUT (Isi konten di dalamnya):

<div class="ai-analysis-content">
  <h3> Evaluasi</h3>
  <p>...(Komentar ringkas tentang skor)...</p>

  <h3>Bedah Kesalahan</h3>
  <p>...(Ambil 2-3 contoh kesalahan paling fatal dari daftar di atas. Tulis: "Di soal tentang [Topik], kamu menjawab [Jawaban Siswa] yang kurang tepat. Seharusnya [Kunci] karena [Alasan Singkat]" ...)</p>

  <h3>Tips Perbaikan</h3>
  <ul class="list-disc pl-5">
    <li>...(Tips 1)...</li>
    <li>...(Tips 2)...</li>
  </ul>
</div>
`;

    // LOOP TRY MODELS
    let lastError = null;

    for (const modelName of MODELS) {
        try {
            console.log(`Trying AI Model: ${modelName}...`);

            const response = await fetch(API_URL, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${API_KEY}`,
                    'Content-Type': 'application/json',
                    'HTTP-Referer': 'https://garudaakademi.id',
                    'X-Title': 'Garuda Akademi'
                },
                body: JSON.stringify({
                    model: modelName,
                    messages: [
                        {
                            role: "system",
                            content: "Kamu adalah AI Analis Pendidikan yang memberikan feedback terstruktur dan mendalam format HTML."
                        },
                        {
                            role: "user",
                            content: prompt
                        }
                    ]
                })
            });

            const result = await response.json();

            // Cek sukses di level HTTP body (OpenRouter kadang return 200 tapi isinya error)
            if (result.error) {
                console.warn(`Model ${modelName} failed:`, result.error.message);
                lastError = result.error;
                continue; // Coba model berikutnya
            }

            if (result.choices && result.choices.length > 0) {
                let content = result.choices[0].message.content;
                // Clean up possible markdown code blocks
                content = content.replace(/```html/g, '').replace(/```/g, '');
                return content; // SUKSES! Return immediately
            }

        } catch (error) {
            console.warn(`Network error with ${modelName}:`, error);
            lastError = error;
        }
    }

    // Jika sampai sini, semua model gagal
    console.error('All AI Models Failed. Last Error:', lastError);

    let msg = "Terjadi kesalahan pada semua server AI.";
    if (lastError && lastError.message) msg = lastError.message;
    else if (lastError) msg = JSON.stringify(lastError);

    return `<div class="alert alert-danger" style="color: #b91c1c; background: #fef2f2; padding: 1rem; border-radius: 8px; border: 1px solid #fecaca;">
        <strong>Gagal memuat analisis</strong><br>
        <span style="font-family: monospace; font-size: 0.85em;">${msg}</span><br>
        <small>Gara sedang sibuk. Silakan coba lagi nanti.</small>
    </div>`;
}