/**
 * DOTBOT Control Panel - Control Buttons
 * Control panel button handlers and settings management
 */

/**
 * Current loop mode ("analysis", "execution", or "both")
 */
let currentLoopMode = 'both';

/**
 * Model options configuration for analysis loop
 */
const ANALYSIS_MODEL_OPTIONS = [
    {
        id: 'Sonnet',
        name: 'Sonnet',
        badge: 'Recommended',
        description: 'Cost-efficient with strong reasoning for task analysis'
    },
    {
        id: 'Opus',
        name: 'Opus',
        badge: null,
        description: 'Most capable model for complex analysis'
    },
    {
        id: 'Haiku',
        name: 'Haiku',
        badge: null,
        description: 'Lightweight and fast for simple analysis'
    }
];

/**
 * Model options configuration for execution loop
 */
const EXECUTION_MODEL_OPTIONS = [
    {
        id: 'Opus',
        name: 'Opus',
        badge: 'Recommended',
        description: 'Most capable model for complex reasoning and code generation'
    },
    {
        id: 'Sonnet',
        name: 'Sonnet',
        badge: null,
        description: 'Balanced performance with faster response times'
    },
    {
        id: 'Haiku',
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
        const savedAnalysisModel = settings.analysisModel || 'Sonnet';
        const savedExecutionModel = settings.executionModel || 'Opus';
        selectAnalysisModel(savedAnalysisModel, false);
        selectExecutionModel(savedExecutionModel, false);
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

    // Initialize model selectors
    initAnalysisModelSelector();
    initExecutionModelSelector();

    // Initialize analysis settings
    initAnalysisSettings();

    // Initialize verification settings
    initVerificationSettings();

    // Load initial settings
    loadSettings();
}

/**
 * Initialize analysis model selector UI
 */
function initAnalysisModelSelector() {
    const modelGrid = document.getElementById('analysis-model-grid');
    if (!modelGrid) return;

    modelGrid.innerHTML = ANALYSIS_MODEL_OPTIONS.map(model => `
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
            selectAnalysisModel(modelId, true);
        });
    });
}

/**
 * Select analysis model and update UI
 * @param {string} modelId - Model ID to select
 * @param {boolean} save - Whether to save the setting
 */
function selectAnalysisModel(modelId, save = true) {
    const modelGrid = document.getElementById('analysis-model-grid');
    if (!modelGrid) return;

    // Update active state
    modelGrid.querySelectorAll('.model-option').forEach(option => {
        option.classList.toggle('active', option.dataset.model === modelId);
    });

    // Save setting
    if (save) {
        saveSetting('analysisModel', modelId);
    }
}

/**
 * Initialize execution model selector UI
 */
function initExecutionModelSelector() {
    const modelGrid = document.getElementById('execution-model-grid');
    if (!modelGrid) return;

    modelGrid.innerHTML = EXECUTION_MODEL_OPTIONS.map(model => `
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
            selectExecutionModel(modelId, true);
        });
    });
}

/**
 * Select execution model and update UI
 * @param {string} modelId - Model ID to select
 * @param {boolean} save - Whether to save the setting
 */
function selectExecutionModel(modelId, save = true) {
    const modelGrid = document.getElementById('execution-model-grid');
    if (!modelGrid) return;

    // Update active state
    modelGrid.querySelectorAll('.model-option').forEach(option => {
        option.classList.toggle('active', option.dataset.model === modelId);
    });

    // Save setting
    if (save) {
        saveSetting('executionModel', modelId);
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
    
    // Initialize mode selector
    initModeSelector();
}

/**
 * Initialize loop mode selector
 */
function initModeSelector() {
    const modeSelector = document.getElementById('mode-selector');
    if (!modeSelector) return;
    
    modeSelector.querySelectorAll('.mode-option').forEach(option => {
        option.addEventListener('click', () => {
            const mode = option.dataset.mode;
            selectLoopMode(mode);
        });
    });
}

/**
 * Select loop mode and update UI
 * @param {string} mode - Mode to select ("analysis", "execution", or "both")
 */
function selectLoopMode(mode) {
    currentLoopMode = mode;
    
    const modeSelector = document.getElementById('mode-selector');
    if (!modeSelector) return;
    
    // Update active state
    modeSelector.querySelectorAll('.mode-option').forEach(option => {
        option.classList.toggle('active', option.dataset.mode === mode);
    });
}

/**
 * Get the current loop mode
 * @returns {string} Current mode
 */
function getLoopMode() {
    return currentLoopMode;
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

        // Include mode for start action
        const body = { action };
        if (action === 'start') {
            body.mode = currentLoopMode;
        }

        const response = await fetch(`${API_BASE}/api/control`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
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

// ========== ANALYSIS SETTINGS ==========

const EFFORT_OPTIONS = [
    { id: 'XS', name: 'XS', description: '~1 day' },
    { id: 'S', name: 'S', description: '2-3 days' },
    { id: 'M', name: 'M', description: '~1 week' },
    { id: 'L', name: 'L', description: '~2 weeks' },
    { id: 'XL', name: 'XL', description: '3+ weeks' }
];

const ANALYSIS_MODE_OPTIONS = [
    { id: 'on-demand', name: 'On-Demand', badge: 'Recommended', description: 'Analyse tasks when triggered by the execution loop' },
    { id: 'batch', name: 'Batch', badge: null, description: 'Analyse all pending tasks in a single batch run' }
];

/**
 * Load analysis settings from server
 */
async function loadAnalysisSettings() {
    try {
        const response = await fetch(`${API_BASE}/api/config/analysis`);
        const data = await response.json();

        // Auto-approve toggle
        const toggle = document.getElementById('setting-auto-approve-splits');
        if (toggle) toggle.checked = data.auto_approve_splits || false;

        // Effort threshold
        selectEffortThreshold(data.split_threshold_effort || 'XL', false);

        // Mode
        selectAnalysisMode(data.mode || 'on-demand', false);

        // Timeout
        const timeoutInput = document.getElementById('setting-question-timeout');
        if (timeoutInput) {
            timeoutInput.value = data.question_timeout_hours != null ? data.question_timeout_hours : '';
        }
    } catch (error) {
        console.error('Failed to load analysis settings:', error);
    }
}

/**
 * Save a single analysis setting
 */
async function saveAnalysisSetting(key, value) {
    try {
        const body = {};
        body[key] = value;
        const response = await fetch(`${API_BASE}/api/config/analysis`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        const result = await response.json();
        if (!result.success) {
            console.error('Failed to save analysis setting:', result.error);
        }
    } catch (error) {
        console.error('Failed to save analysis setting:', error);
    }
}

/**
 * Initialize effort threshold selector
 */
function initEffortThresholdSelector() {
    const grid = document.getElementById('effort-threshold-grid');
    if (!grid) return;

    grid.innerHTML = EFFORT_OPTIONS.map(opt => `
        <div class="model-option" data-effort="${opt.id}">
            <div class="model-option-header">
                <span class="model-option-name">${opt.name}</span>
            </div>
            <div class="model-option-description">${opt.description}</div>
        </div>
    `).join('');

    grid.querySelectorAll('.model-option').forEach(option => {
        option.addEventListener('click', () => {
            selectEffortThreshold(option.dataset.effort, true);
        });
    });
}

/**
 * Select effort threshold and update UI
 */
function selectEffortThreshold(id, save = true) {
    const grid = document.getElementById('effort-threshold-grid');
    if (!grid) return;

    grid.querySelectorAll('.model-option').forEach(option => {
        option.classList.toggle('active', option.dataset.effort === id);
    });

    if (save) {
        saveAnalysisSetting('split_threshold_effort', id);
    }
}

/**
 * Initialize analysis mode selector
 */
function initAnalysisModeSelector() {
    const grid = document.getElementById('analysis-mode-grid');
    if (!grid) return;

    grid.innerHTML = ANALYSIS_MODE_OPTIONS.map(opt => `
        <div class="model-option" data-mode="${opt.id}">
            <div class="model-option-header">
                <span class="model-option-name">${opt.name}</span>
                ${opt.badge ? `<span class="model-option-badge">${opt.badge}</span>` : ''}
            </div>
            <div class="model-option-description">${opt.description}</div>
        </div>
    `).join('');

    grid.querySelectorAll('.model-option').forEach(option => {
        option.addEventListener('click', () => {
            selectAnalysisMode(option.dataset.mode, true);
        });
    });
}

/**
 * Select analysis mode and update UI
 */
function selectAnalysisMode(id, save = true) {
    const grid = document.getElementById('analysis-mode-grid');
    if (!grid) return;

    grid.querySelectorAll('.model-option').forEach(option => {
        option.classList.toggle('active', option.dataset.mode === id);
    });

    if (save) {
        saveAnalysisSetting('mode', id);
    }
}

/**
 * Initialize all analysis settings
 */
function initAnalysisSettings() {
    // Auto-approve toggle
    const toggle = document.getElementById('setting-auto-approve-splits');
    if (toggle) {
        toggle.addEventListener('change', (e) => {
            saveAnalysisSetting('auto_approve_splits', e.target.checked);
        });
    }

    // Question timeout input (debounced)
    const timeoutInput = document.getElementById('setting-question-timeout');
    if (timeoutInput) {
        let debounceTimer = null;
        timeoutInput.addEventListener('input', () => {
            // Clamp to non-negative
            if (timeoutInput.value !== '' && parseInt(timeoutInput.value, 10) < 0) {
                timeoutInput.value = 0;
            }
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(() => {
                const val = timeoutInput.value.trim();
                const parsed = parseInt(val, 10);
                saveAnalysisSetting('question_timeout_hours', val === '' ? null : Math.max(0, parsed));
            }, 500);
        });
    }

    // Grid selectors
    initEffortThresholdSelector();
    initAnalysisModeSelector();

    // Load current values
    loadAnalysisSettings();
}

// ========== VERIFICATION SETTINGS ==========

/**
 * Load verification scripts from server
 */
async function loadVerificationScripts() {
    try {
        const response = await fetch(`${API_BASE}/api/config/verification`);
        const data = await response.json();
        renderVerificationScripts(data.scripts || []);
    } catch (error) {
        console.error('Failed to load verification scripts:', error);
    }
}

/**
 * Render verification scripts list
 */
function renderVerificationScripts(scripts) {
    const container = document.getElementById('verification-scripts-list');
    if (!container) return;

    if (!scripts.length) {
        container.innerHTML = '<div class="empty-state">No verification scripts configured</div>';
        return;
    }

    container.innerHTML = scripts.map(script => {
        const isCore = script.core === true;
        return `
            <div class="verify-script-row${isCore ? ' verify-core' : ''}">
                <div class="verify-script-info">
                    <div class="verify-script-header">
                        <span class="verify-script-name">${script.name}</span>
                        ${isCore ? '<span class="verify-core-badge">CORE</span>' : ''}
                    </div>
                    <span class="verify-script-desc">${script.description || ''}</span>
                </div>
                <div class="verify-script-controls">
                    <span class="verify-timeout">${script.timeout_seconds}s</span>
                    <label class="toggle-switch${isCore ? ' toggle-disabled' : ''}">
                        <input type="checkbox" ${script.required ? 'checked' : ''} ${isCore ? 'disabled' : ''}
                            data-script-name="${script.name}">
                        <span class="toggle-slider"></span>
                    </label>
                </div>
            </div>
        `;
    }).join('');

    // Wire change handlers for non-core scripts
    container.querySelectorAll('input[data-script-name]:not([disabled])').forEach(input => {
        input.addEventListener('change', async (e) => {
            await saveVerificationSetting(e.target.dataset.scriptName, e.target.checked);
        });
    });
}

/**
 * Save a verification script setting
 */
async function saveVerificationSetting(name, required) {
    try {
        const response = await fetch(`${API_BASE}/api/config/verification`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, required })
        });
        const result = await response.json();
        if (!result.success) {
            console.error('Failed to save verification setting:', result.error);
            // Reload to revert UI state
            loadVerificationScripts();
        }
    } catch (error) {
        console.error('Failed to save verification setting:', error);
        loadVerificationScripts();
    }
}

/**
 * Initialize verification settings
 */
function initVerificationSettings() {
    loadVerificationScripts();
}

// ========== STEERING ==========
let selectedInstance = null;

/**
 * Initialize steering panel event handlers (now in modal)
 */
function initSteeringPanel() {
    // Instance selector buttons
    document.querySelectorAll('.instance-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            if (btn.disabled) return;
            selectInstance(btn.dataset.instance);
        });
    });

    // Whisper send handlers
    document.getElementById('whisper-send')?.addEventListener('click', sendWhisper);
    document.getElementById('whisper-input')?.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') sendWhisper();
    });

    // Initialize whisper modal toggle
    initWhisperModal();
}

/**
 * Initialize whisper modal toggle handlers
 */
function initWhisperModal() {
    const whisperBtn = document.getElementById('whisper-btn');
    const whisperModal = document.getElementById('whisper-modal');
    const whisperModalClose = document.getElementById('whisper-modal-close');

    if (!whisperBtn || !whisperModal) return;

    // Open modal on button click
    whisperBtn.addEventListener('click', () => {
        whisperModal.classList.add('visible');
        // Focus the input if an instance is selected
        const input = document.getElementById('whisper-input');
        if (input && !input.disabled) {
            setTimeout(() => input.focus(), 100);
        }
    });

    // Close modal on X button click
    whisperModalClose?.addEventListener('click', () => {
        whisperModal.classList.remove('visible');
    });

    // Close modal on backdrop click
    whisperModal.addEventListener('click', (e) => {
        if (e.target === whisperModal) {
            whisperModal.classList.remove('visible');
        }
    });

    // Close modal on Escape key
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && whisperModal.classList.contains('visible')) {
            whisperModal.classList.remove('visible');
        }
    });
}

/**
 * Select an instance for steering
 * @param {string} type - Instance type ("analysis" or "execution")
 */
function selectInstance(type) {
    selectedInstance = type;
    document.querySelectorAll('.instance-btn').forEach(b => b.classList.remove('active'));
    document.getElementById(`btn-${type}`)?.classList.add('active');

    // Update status text immediately from last known state
    if (lastState?.instances) {
        updateSteeringStatus(lastState.instances);
    }
}

/**
 * Get the currently selected instance
 * @returns {string|null} Selected instance type
 */
function getSelectedInstance() {
    return selectedInstance;
}

/**
 * Send a whisper to the selected instance
 */
async function sendWhisper() {
    if (!selectedInstance) return;
    const input = document.getElementById('whisper-input');
    const message = input?.value?.trim();
    if (!message) return;

    const btn = document.getElementById('whisper-send');
    const originalText = btn.textContent;
    btn.disabled = true;
    btn.textContent = '...';

    try {
        const response = await fetch(`${API_BASE}/api/whisper`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                instance_type: selectedInstance,
                message: message,
                priority: document.getElementById('whisper-priority')?.value || 'normal'
            })
        });
        const result = await response.json();
        if (result.success) {
            input.value = '';
            showSignalFeedback(`Whisper → ${selectedInstance}`);
        } else {
            throw new Error(result.error);
        }
    } catch (e) {
        showSignalFeedback(`Error: ${e.message}`);
    } finally {
        btn.disabled = false;
        btn.textContent = originalText;
    }
}

/**
 * Show feedback in the signal feedback area
 * @param {string} message - Message to display
 */
function showSignalFeedback(message) {
    const signalStatus = document.getElementById('signal-status');
    if (signalStatus) {
        signalStatus.textContent = message;
        signalStatus.classList.add('visible');
        setTimeout(() => signalStatus.classList.remove('visible'), 3000);
    }
}

/**
 * Update steering status text for selected instance
 * @param {Object} instances - Instances object from state
 */
function updateSteeringStatus(instances) {
    const textEl = document.getElementById('steering-text');
    if (!textEl) return;

    if (!selectedInstance) {
        textEl.textContent = 'No instance selected';
        textEl.className = 'steering-text muted';
        return;
    }

    const inst = instances?.[selectedInstance];
    if (!inst?.alive) {
        textEl.textContent = `${selectedInstance} not running`;
        textEl.className = 'steering-text muted';
    } else if (inst.status) {
        textEl.textContent = inst.status + (inst.next_action ? `\n→ ${inst.next_action}` : '');
        textEl.className = 'steering-text';
    } else {
        textEl.textContent = 'Awaiting heartbeat...';
        textEl.className = 'steering-text muted';
    }
}
