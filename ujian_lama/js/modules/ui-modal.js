/**
 * UI MODAL MODULE
 * Mengontrol tampilan modal ANBK yang sudah ada di HTML statis.
 * Tidak membuat elemen baru, hanya memanipulasi DOM yang sudah ada.
 */

// Cache DOM Elements (Lazy getter agar aman saat dipanggil)
const getModalElements = () => ({
    modal: document.getElementById('anbkModal'),
    title: document.getElementById('anbkModalTitle'),
    message: document.getElementById('anbkModalMessage'),
    icon: document.getElementById('anbkModalIcon'),
    buttons: document.getElementById('anbkModalButtons')
});

/**
 * Menampilkan Modal ANBK
 * @param {Object} options 
 * @param {string} options.title - Judul modal
 * @param {string} options.text - Isi pesan (bisa HTML)
 * @param {string} options.icon - Tipe icon: 'info' | 'warning' | 'error' | 'success' | 'question' | 'loading'
 * @param {boolean} options.showCancelButton - Tampilkan tombol batal?
 * @param {string} options.confirmButtonText - Teks tombol konfirmasi
 * @param {string} options.cancelButtonText - Teks tombol batal
 * @param {Function} options.onConfirm - Callback saat tombol konfirmasi diklik
 */
export const showModal = ({ 
    title = "Informasi", 
    text = "", 
    icon = "info", 
    showCancelButton = false, 
    confirmButtonText = "OK", 
    cancelButtonText = "Batal", 
    onConfirm = null 
}) => {
    const el = getModalElements();
    
    if (!el.modal) {
        console.error("Modal element #anbkModal not found in HTML!");
        return;
    }

    // 1. Set Content
    el.title.innerText = title;
    el.message.innerHTML = text;

    // 2. Set Icon
    let iconHtml = '';
    switch (icon) {
        case 'warning':
            iconHtml = '<i class="fas fa-exclamation-triangle text-[#f39c12]" style="color: #f39c12;"></i>';
            break;
        case 'error':
            iconHtml = '<i class="fas fa-times-circle text-red-600" style="color: #dc2626;"></i>';
            break;
        case 'success':
            iconHtml = '<i class="fas fa-check-circle text-green-500" style="color: #10b981;"></i>';
            break;
        case 'question':
            iconHtml = '<i class="fas fa-question-circle text-[#0b57d0]" style="color: #0b57d0;"></i>';
            break;
        case 'loading':
            iconHtml = '<i class="fas fa-spinner fa-spin text-[#0b57d0]" style="color: #0b57d0;"></i>';
            break;
        default: // info
            iconHtml = '<i class="fas fa-info-circle text-blue-500" style="color: #0b57d0;"></i>';
    }
    el.icon.innerHTML = iconHtml;

    // 3. Set Buttons
    let buttonsHtml = '';

    if (icon === 'loading') {
        // Loading state: No buttons
        buttonsHtml = '';
    } else {
        if (showCancelButton) {
            buttonsHtml += `
                <button id="anbkCancelBtn" style="padding: 8px 16px; border-radius: 4px; border: 1px solid #d1d5db; background: white; color: #374151; font-weight: 500; cursor: pointer;">
                    ${cancelButtonText}
                </button>
            `;
        }
        buttonsHtml += `
            <button id="anbkConfirmBtn" style="padding: 8px 24px; border-radius: 4px; background-color: #0b57d0; color: white; font-weight: bold; border: none; cursor: pointer;">
                ${confirmButtonText}
            </button>
        `;
    }
    
    el.buttons.innerHTML = buttonsHtml;

    // 4. Attach Event Listeners
    // Kita harus attach manual karena innerHTML me-reset elemen button
    if (icon !== 'loading') {
        const confirmBtn = document.getElementById('anbkConfirmBtn');
        if (confirmBtn) {
            confirmBtn.onclick = () => {
                closeModal();
                if (onConfirm) onConfirm();
            };
        }

        const cancelBtn = document.getElementById('anbkCancelBtn');
        if (cancelBtn) {
            cancelBtn.onclick = () => {
                closeModal();
            };
        }
    }

    // 5. Show Modal
    el.modal.classList.remove('hidden');
    el.modal.style.display = 'flex';
};

/**
 * Menutup Modal ANBK
 */
export const closeModal = () => {
    const el = getModalElements();
    if (el.modal) {
        el.modal.classList.add('hidden');
        el.modal.style.display = 'none';
    }
};

// Inisialisasi awal (jika perlu menutup modal saat user klik area luar/backdrop)
// Opsional, tapi bagus untuk UX
document.addEventListener('DOMContentLoaded', () => {
    const modal = document.getElementById('anbkModal');
    if (modal) {
        // Jangan close saat loading
        /* modal.addEventListener('click', (e) => {
            if (e.target === modal) {
               // Cek apakah sedang loading? Kalau ya jangan close.
               // Untuk keamanan ujian, biasanya modal konfirmasi tidak boleh di-close lewat backdrop.
               // Jadi kita biarkan kosong atau hanya close jika tombol X diklik.
            }
        }); 
        */
    }
});