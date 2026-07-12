/**
 * API MODULE (FAILOVER SYSTEM)
 * Priority: 
 * 1. Google Gemini (Primary)
 * 2. OpenRouter (Failover)
 * 3. Static Message (Final Fallback)
 */

// --- CONFIG: GEMINI ---
const GEMINI_KEY = "AIzaSyCeLJBHRhqxiNdz4akdvUYA54D4knZWKtM";
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=${GEMINI_KEY}`;

// --- CONFIG: OPENROUTER ---
const OPENROUTER_KEY = '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';
const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

// Daftar Model OpenRouter (Sama seperti api_analisis.js)
const OPENROUTER_MODELS = [
  'google/gemini-2.5-flash-lite',          // Primary: Google Flash 2.0
  'nvidia/nemotron-3-nano-30b-a3b:free', // Fallback 1: Llama 3.2
  'deepseek/deepseek-r1-0528:free',       // Fallback 2: Llama 3
  'xiaomi/mimo-v2-flash:free',         // Fallback 3: Zephyr
  'mistralai/mistral-7b-instruct:free'         // Fallback 4: Mistral
];

/**
 * Generates an explanation for a specific question using Multi-tier Failover.
 * @param {string} soal - The question text.
 * @param {string} jawabanSiswa - The student's answer.
 * @param {string} kunci - The correct answer key.
 * @param {function} onRetry - Optional callback for retry status (used mainly in UI).
 * @returns {Promise<string>} - The explanation text.
 */
export async function generateExplanation(soal, jawabanSiswa, kunci, onRetry) {
  const prompt = `Soal: "${soal}"
Jawaban Siswa: "${jawabanSiswa}"
Kunci Jawaban: "${kunci}"

Tugas: Jelaskan kenapa jawaban siswa salah (jika salah dan ini juga prioritas utama) atau benarkan konsepnya (jika benar). Berikan penjelasan jawaban yang benar.
Syarat:
1. Penjelasan harus sangat singkat, padat, dan jelas.
2. Minimal 1-2 kalimat.
3. Langsung ke inti permasalahannya.
4. Gaya bahasa santai gen z tapi edukatif (seperti guru privat).`;

  // 1. TIER 1: GOOGLE GEMINI
  try {
    const result = await tryGemini(prompt, onRetry);
    return result;
  } catch (geminiError) {
    console.warn("[FAILOVER] Gemini Failed, switching to OpenRouter...", geminiError);
  }

  // 2. TIER 2: OPENROUTER (Multi-Model)
  try {
    if (onRetry) onRetry(1, "Failover: OpenRouter"); // Notify UI switching
    const result = await tryOpenRouter(prompt);
    return result;
  } catch (orError) {
    console.warn("[FAILOVER] OpenRouter Failed, switching to Static Fallback...", orError);
  }

  // 3. TIER 3: STATIC FALLBACK (No Error Displayed to User)
  return getStaticFallback(jawabanSiswa, kunci);
}

// --- LOGIC: GEMINI ---
async function tryGemini(prompt, onRetry) {
  const payload = {
    contents: [{
      parts: [{ text: prompt }]
    }]
  };

  // Original logic: maxRetries 0 (Fail fast)
  const maxRetries = 0;

  // Simple fetch without loop since retries are 0, but keeping structure if needed later
  console.log(`[Gemini API] Requesting...`);

  const response = await fetch(GEMINI_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Gemini HTT P${response.status}: ${text}`);
  }

  const data = await response.json();
  if (data.candidates && data.candidates.length > 0 && data.candidates[0].content) {
    return data.candidates[0].content.parts[0].text;
  } else {
    throw new Error("Gemini Empty Response");
  }
}

// --- LOGIC: OPENROUTER ---
async function tryOpenRouter(prompt) {
  let lastError = null;

  for (const modelName of OPENROUTER_MODELS) {
    try {
      console.log(`[OpenRouter] Trying Model: ${modelName}...`);

      const response = await fetch(OPENROUTER_URL, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${OPENROUTER_KEY}`,
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://garudaakademi.id',
          'X-Title': 'Garuda Akademi'
        },
        body: JSON.stringify({
          model: modelName,
          messages: [
            {
              role: "system",
              content: "Kamu adalah AI asisten guru yang gaul dan singkat."
            },
            {
              role: "user",
              content: prompt
            }
          ]
        })
      });

      const result = await response.json();

      if (result.error) {
        console.warn(`[OpenRouter] Model ${modelName} error:`, result.error.message);
        lastError = result.error;
        continue;
      }

      if (result.choices && result.choices.length > 0) {
        let content = result.choices[0].message.content;
        // Cleanup logic if needed
        return content;
      }

    } catch (error) {
      console.warn(`[OpenRouter] Network error with ${modelName}:`, error);
      lastError = error;
    }
  }

  throw lastError || new Error("All OpenRouter models failed");
}

// --- LOGIC: STATIC FALLBACK ---
function getStaticFallback(jawabanSiswa, kunci) {
  // Normalisasi untuk perbandingan sederhana
  const normSiswa = String(jawabanSiswa).trim().toUpperCase();
  const normKunci = String(kunci).trim().toUpperCase();

  // Cek Benar/Salah secara sederhana
  // Note: Logika benar/salah sebenarnya sudah ada di page-hasil.js sebelum panggil API,
  // tapi di sini kita buat pesan aman.

  // Kita asumsikan jika dipanggil berarti butuh penjelasan.
  // Biasanya user minta penjelasan kalau salah, tapi bisa juga kalau benar untuk validasi.

  // Detection logic rudimentary:
  let isCorrect = normSiswa === normKunci;
  if (normKunci.includes(',')) { // Complex check skipped, assume caller knows better, but here we just frame the text
    // Fallback generic
  }

  if (isCorrect) {
    return `Wow Jawaban kamu **${jawabanSiswa}** sudah tepat. Pertahankan!`;
  } else {
    return `Waduh, jawaban kamu untuk soal ini kurang tepat alias salah, jawaban yang benar adalah **${kunci}**, sedangkan kamu menjawab **${jawabanSiswa}**.`;
  }
}