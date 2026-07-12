/**
 * CAMERA MODULE - Browser Based (Client-Side)
 * -------------------------------------------
 * Features:
 * - Desktop Only Detection
 * - Draggable & Resizable Overlay
 * - Auto-Hide on Timeout (60s) if no camera
 * - Minimalist UI
 */

const CameraModule = (() => {
    // Configuration
    const CONFIG = {
        TIMEOUT_MS: 60000, // 60 Seconds
        MIN_WIDTH: 160,
        MIN_HEIGHT: 120,
        DEFAULT_POS: { bottom: '20px', right: '20px' }
    };

    // State
    const state = {
        isActive: false,
        stream: null,
        isDragging: false,
        isResizing: false,
        dragOffset: { x: 0, y: 0 },
        timeoutId: null
    };

    // DOM Elements
    let els = {};

    /**
     * Initialize Module
     */
    function init() {
        // 1. Check Device (Desktop Only)
        if (!isDesktop()) {
            console.log('CameraModule: Mobile device detected. Module disabled.');
            return;
        }

        // 2. Bind DOM Elements
        bindElements();

        // 3. Setup Event Listeners (Drag, Resize, Toggle)
        setupInteractions();

        // 4. Start Camera Sequence
        startCameraSequence();
    }

    /**
     * Check if user is on Desktop
     * Simple User Agent check + Screen Width
     */
    function isDesktop() {
        const ua = navigator.userAgent;
        const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(ua);
        const isWide = window.innerWidth > 768; // CSS Breakpoint match
        return !isMobile && isWide;
    }

    /**
     * Bind DOM Elements
     */
    function bindElements() {
        els.module = document.getElementById('cameraModule');
        els.header = document.getElementById('cameraHeader');
        els.video = document.getElementById('userCamera');
        els.status = document.getElementById('cameraStatus');
        els.statusText = els.status ? els.status.querySelector('p') : null;
        els.btnPermission = document.getElementById('btnRequestPermission');
        els.resizer = document.querySelector('.camera-resizer');
        els.btnMinimize = document.querySelector('.btn-cam-minimize'); // Select by class inside header
        els.btnFloat = document.getElementById('btnShowCameraFloat');

        // Ensure elements exist
        if (!els.module || !els.video) {
            console.error('CameraModule: DOM elements not found.');
        }
    }

    /**
     * Start Camera with Timeout Logic
     */
    async function startCameraSequence() {
        // Show Module immediately so user knows it's trying
        els.module.classList.remove('hidden');

        // Start Timeout Timer
        state.timeoutId = setTimeout(() => {
            if (!state.stream) {
                console.warn('CameraModule: Timeout reached. Camera not found/allowed.');
                // Don't fully shutdown if just permission pending, but usually 60s is enough
                shutdownModule();
            }
        }, CONFIG.TIMEOUT_MS);

        requestCamera();
    }

    async function requestCamera() {
        if (els.statusText) els.statusText.innerText = "Memuat Kamera...";
        if (els.btnPermission) els.btnPermission.classList.add('hidden');

        try {
            // Request Camera
            const stream = await navigator.mediaDevices.getUserMedia({
                video: {
                    width: { ideal: 640 },
                    height: { ideal: 480 },
                    facingMode: "user"
                },
                audio: false
            });

            handleStreamSuccess(stream);

        } catch (err) {
            handleStreamError(err);
        }
    }

    function handleStreamSuccess(stream) {
        // Clear Timeout
        clearTimeout(state.timeoutId);

        state.stream = stream;
        state.isActive = true;

        // Show Module (in case it was hidden)
        els.module.classList.remove('hidden');

        // Attach Stream
        els.video.srcObject = stream;
        els.status.style.display = 'none'; // Hide "Memuat..." text and button

        console.log('CameraModule: Active.');
    }

    function handleStreamError(err) {
        console.error('CameraModule: Access denied or error.', err);

        // Show Button to manually retry (triggers user gesture)
        if (els.statusText) els.statusText.innerText = "Kamera tidak aktif.";
        if (els.btnPermission) {
            els.btnPermission.classList.remove('hidden');
            els.btnPermission.onclick = () => {
                requestCamera();
            };
        }

        // Don't remove timeout id, so it still auto-hides after 60s if user ignores it
    }

    function shutdownModule() {
        if (els.module) els.module.classList.add('hidden');
        if (els.btnFloat) els.btnFloat.classList.add('hidden');
        state.isActive = false;
    }

    /**
     * Setup Drag, Resize, and Toggle Interactions
     */
    function setupInteractions() {
        if (!els.module) return;

        // --- DRAG FUNCTIONALITY ---
        els.header.addEventListener('mousedown', startDrag);

        // --- RESIZE FUNCTIONALITY ---
        els.resizer.addEventListener('mousedown', startResize);

        // --- GLOBAL MOUSE EVENTS (Move/Up) ---
        document.addEventListener('mousemove', (e) => {
            if (state.isDragging) drag(e);
            if (state.isResizing) resize(e);
        });

        document.addEventListener('mouseup', () => {
            state.isDragging = false;
            state.isResizing = false;
            document.body.style.cursor = 'default';
        });

        // --- TOGGLE (MINIMIZE / RESTORE) ---
        if (els.btnMinimize) {
            els.btnMinimize.addEventListener('click', (e) => {
                e.stopPropagation(); // Prevent drag start
                minimize();
            });
        }

        if (els.btnFloat) {
            els.btnFloat.addEventListener('click', restore);
        }
    }

    // --- DRAG LOGIC ---
    function startDrag(e) {
        // Prevent if clicking buttons
        if (e.target.closest('button')) return;

        state.isDragging = true;
        // Calculate offset from the top-left of the module
        const rect = els.module.getBoundingClientRect();
        state.dragOffset.x = e.clientX - rect.left;
        state.dragOffset.y = e.clientY - rect.top;
    }

    function drag(e) {
        e.preventDefault();

        // Calculate new position
        let newX = e.clientX - state.dragOffset.x;
        let newY = e.clientY - state.dragOffset.y;

        // Boundaries (Keep within window)
        const winWidth = window.innerWidth;
        const winHeight = window.innerHeight;
        const rect = els.module.getBoundingClientRect();

        // 0 <= x <= winWidth - width
        // 0 <= y <= winHeight - height
        // But we are using FIXED position.
        // Let's stick to Right/Bottom or Left/Top. 
        // Plan uses Bottom/Right fixed.

        // To make it fully draggable, better to switch to Top/Left style positioning
        // OR calculate Right/Bottom values.

        // Let's set Top/Left for dragging as it's more direct to mouse coordinates
        els.module.style.bottom = 'auto';
        els.module.style.right = 'auto';
        els.module.style.left = `${newX}px`;
        els.module.style.top = `${newY}px`;
    }

    // --- RESIZE LOGIC ---
    function startResize(e) {
        state.isResizing = true;
        e.preventDefault();
        e.stopPropagation();
    }

    function resize(e) {
        const rect = els.module.getBoundingClientRect();

        // Calculate new dimensions
        // Mouse X minus Left Edge = Width
        // Mouse Y minus Top Edge = Height
        let newWidth = e.clientX - rect.left;
        let newHeight = e.clientY - rect.top;

        // Min Limits
        if (newWidth > CONFIG.MIN_WIDTH) els.module.style.width = `${newWidth}px`;
        if (newHeight > CONFIG.MIN_HEIGHT) els.module.style.height = `${newHeight}px`;
    }

    // --- TOGGLE LOGIC ---
    function minimize() {
        els.module.classList.add('hidden');
        els.btnFloat.classList.remove('hidden');
    }

    function restore() {
        els.module.classList.remove('hidden');
        els.btnFloat.classList.add('hidden');
    }

    // Public API
    return {
        init: init
    };

})();

// Auto-Init when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    CameraModule.init();
});
