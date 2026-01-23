/**
 * DOTBOT Control Panel - Control Buttons
 * Control panel button handlers and settings management
 */

/**
 * Model options configuration
 */
const MODEL_OPTIONS = [
    {
        id: 'opus',
        name: 'Opus',
        badge: 'Recommended',
        description: 'Most capable model for complex reasoning and code generation'
    },
    {
        id: 'sonnet',
        name: 'Sonnet',
        badge: null,
        description: 'Balanced performance with faster response times'
    },
    {
        id: 'haiku',
        name: 'Haiku',
        badge: null,
        description: 'Lightweight and fast for simple tasks'
    }
];

/**
 * Load settings from server and update UI
 */
async function loadSettings() {
    try {
        const response = await fetch(`${API_BASE}/api/settings`);
        const settings = await response.json();

        // Update toggle states
        const showDebugToggle = document.getElementById('setting-show-debug');
        const showVerboseToggle = document.getElementById('setting-show-verbose');

        if (showDebugToggle) {
            showDebugToggle.checked = settings.showDebug || false;
        }
        if (showVerboseToggle) {
            showVerboseToggle.checked = settings.showVerbose || false;
        }

        // Update model selection
        const savedModel = settings.model || 'opus';
        selectModel(savedModel, false);
    } catch (error) {
        console.error('Failed to load settings:', error);
    }
}

/**
 * Save a setting to the server
 * @param {string} key - Setting key
 * @param {any} value - Setting value
 */
async function saveSetting(key, value) {
    try {
        const body = {};
        body[key] = value;

        const response = await fetch(`${API_BASE}/api/settings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });

        const result = await response.json();
        if (!result.success) {
            console.error('Failed to save setting:', result.error);
        }
    } catch (error) {
        console.error('Failed to save setting:', error);
    }
}

/**
 * Initialize settings toggle handlers
 */
function initSettingsToggles() {
    const showDebugToggle = document.getElementById('setting-show-debug');
    const showVerboseToggle = document.getElementById('setting-show-verbose');

    if (showDebugToggle) {
        showDebugToggle.addEventListener('change', (e) => {
            saveSetting('showDebug', e.target.checked);
        });
    }

    if (showVerboseToggle) {
        showVerboseToggle.addEventListener('change', (e) => {
            saveSetting('showVerbose', e.target.checked);
        });
    }

    // Initialize model selector
    initModelSelector();

    // Load initial settings
    loadSettings();
}

/**
 * Initialize model selector UI
 */
function initModelSelector() {
    const modelGrid = document.getElementById('model-grid');
    if (!modelGrid) return;

    modelGrid.innerHTML = MODEL_OPTIONS.map(model => `
        <div class="model-option" data-model="${model.id}">
            <div class="model-option-header">
                <span class="model-option-name">${model.name}</span>
                ${model.badge ? `<span class="model-option-badge">${model.badge}</span>` : ''}
            </div>
            <div class="model-option-description">${model.description}</div>
        </div>
    `).join('');

    // Add click handlers
    modelGrid.querySelectorAll('.model-option').forEach(option => {
        option.addEventListener('click', () => {
            const modelId = option.dataset.model;
            selectModel(modelId, true);
        });
    });
}

/**
 * Select a model and update UI
 * @param {string} modelId - Model ID to select
 * @param {boolean} save - Whether to save the setting
 */
function selectModel(modelId, save = true) {
    const modelGrid = document.getElementById('model-grid');
    if (!modelGrid) return;

    // Update active state
    modelGrid.querySelectorAll('.model-option').forEach(option => {
        option.classList.toggle('active', option.dataset.model === modelId);
    });

    // Save setting
    if (save) {
        saveSetting('model', modelId);
    }
}

/**
 * Initialize control button click handlers
 */
function initControlButtons() {
    const controls = document.getElementById('controls');
    if (!controls) return;

    controls.addEventListener('click', async (e) => {
        const btn = e.target.closest('.ctrl-btn');
        if (!btn || btn.disabled) return;

        const action = btn.dataset.action;
        if (!action) return;

        await sendControlSignal(action);
    });

    // Panic reset button handler
    const panicBtn = document.getElementById('panic-reset');
    if (panicBtn) {
        panicBtn.addEventListener('click', async () => {
            if (panicBtn.disabled) return;
            await sendControlSignal('reset');
        });
    }
}

/**
 * Send control signal to the server
 * @param {string} action - Action to send (start, stop, pause, resume, reset)
 */
async function sendControlSignal(action) {
    const signalStatus = document.getElementById('signal-status');

    try {
        const buttons = document.querySelectorAll('.ctrl-btn, .panic-btn');
        buttons.forEach(btn => btn.disabled = true);

        const response = await fetch(`${API_BASE}/api/control`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action })
        });

        const result = await response.json();

        if (signalStatus) {
            signalStatus.textContent = `Signal sent: ${action.toUpperCase()}`;
            signalStatus.classList.add('visible');
            setTimeout(() => signalStatus.classList.remove('visible'), 3000);
        }

        await pollState();

    } catch (error) {
        console.error('Control signal error:', error);
        if (signalStatus) {
            signalStatus.textContent = `Error: ${error.message}`;
            signalStatus.classList.add('visible');
        }
    } finally {
        const buttons = document.querySelectorAll('.ctrl-btn, .panic-btn');
        buttons.forEach(btn => btn.disabled = false);
    }
}
