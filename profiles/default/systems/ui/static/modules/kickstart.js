/**
 * DOTBOT Control Panel - Kickstart Module
 * Handles new project detection and kickstart flow
 */

// State
let isNewProject = false;
let kickstartInProgress = false;
let analyseInProgress = false;
let kickstartFiles = [];       // { name, size, content (base64) }
let kickstartProcessId = null; // process_id returned from backend
let kickstartPolling = null;   // interval ID for doc appearance detection
let roadmapPolling = null;     // interval ID for task creation detection

// File constraints
const KICKSTART_MAX_FILE_SIZE = 2 * 1024 * 1024; // 2MB
const KICKSTART_MAX_FILES = 10;
const KICKSTART_ALLOWED_EXTENSIONS = [
    // Documents
    '.md', '.txt', '.pdf', '.rtf',
    // Data & config
    '.json', '.yaml', '.yml', '.toml', '.xml', '.csv', '.tsv',
    '.ini', '.env', '.properties', '.cfg', '.conf',
    // Web
    '.html', '.css', '.scss', '.less', '.svg',
    // Code
    '.js', '.ts', '.tsx', '.jsx', '.py', '.cs', '.java',
    '.go', '.rs', '.rb', '.php', '.swift', '.kt', '.c', '.cpp',
    '.h', '.hpp', '.sh', '.ps1', '.sql', '.r', '.lua',
    '.dart', '.vue', '.svelte',
    // Images (Claude vision)
    '.png', '.jpg', '.jpeg', '.gif', '.webp',
    // Notebooks
    '.ipynb',
];

/**
 * Initialize kickstart functionality
 * Checks if this is a new project and sets up event handlers
 */
async function initKickstart() {
    try {
        const response = await fetch(`${API_BASE}/api/product/list`);
        if (response.ok) {
            const data = await response.json();
            const docs = data.docs || [];
            isNewProject = docs.length === 0;
        }
    } catch (error) {
        console.warn('Could not check product docs for kickstart:', error);
    }

    // Now that isNewProject is set, re-trigger executive summary display
    if (isNewProject && typeof updateExecutiveSummary === 'function') {
        updateExecutiveSummary();
    }

    // Bind kickstart modal handlers
    const modal = document.getElementById('kickstart-modal');
    const closeBtn = document.getElementById('kickstart-modal-close');
    const cancelBtn = document.getElementById('kickstart-cancel');
    const submitBtn = document.getElementById('kickstart-submit');
    const textarea = document.getElementById('kickstart-prompt');
    const dropzone = document.getElementById('kickstart-dropzone');
    const fileInput = document.getElementById('kickstart-file-input');

    // Close handlers
    closeBtn?.addEventListener('click', closeKickstartModal);
    cancelBtn?.addEventListener('click', closeKickstartModal);
    modal?.addEventListener('click', (e) => {
        if (e.target === modal) closeKickstartModal();
    });

    // Submit handler
    submitBtn?.addEventListener('click', submitKickstart);

    // Ctrl+Enter to submit
    textarea?.addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
            e.preventDefault();
            submitKickstart();
        }
    });

    // Bind analyse modal handlers
    const analyseModal = document.getElementById('analyse-modal');
    const analyseCloseBtn = document.getElementById('analyse-modal-close');
    const analyseCancelBtn = document.getElementById('analyse-cancel');
    const analyseSubmitBtn = document.getElementById('analyse-submit');
    const analyseTextarea = document.getElementById('analyse-prompt');

    analyseCloseBtn?.addEventListener('click', closeAnalyseModal);
    analyseCancelBtn?.addEventListener('click', closeAnalyseModal);
    analyseModal?.addEventListener('click', (e) => {
        if (e.target === analyseModal) closeAnalyseModal();
    });

    analyseSubmitBtn?.addEventListener('click', submitAnalyse);

    analyseTextarea?.addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
            e.preventDefault();
            submitAnalyse();
        }
    });

    // Dropzone handlers
    if (dropzone) {
        dropzone.addEventListener('click', () => fileInput?.click());

        dropzone.addEventListener('dragover', (e) => {
            e.preventDefault();
            dropzone.classList.add('dragover');
        });

        dropzone.addEventListener('dragleave', (e) => {
            e.preventDefault();
            dropzone.classList.remove('dragover');
        });

        dropzone.addEventListener('drop', (e) => {
            e.preventDefault();
            dropzone.classList.remove('dragover');
            if (e.dataTransfer.files.length > 0) {
                handleFiles(e.dataTransfer.files);
            }
        });
    }

    // File input handler
    fileInput?.addEventListener('change', (e) => {
        if (e.target.files.length > 0) {
            handleFiles(e.target.files);
            e.target.value = ''; // Reset so same file can be selected again
        }
    });
}

/**
 * Render kickstart CTA into a container element
 * Shows "KICKSTART PROJECT" for greenfield or "ANALYSE PROJECT" for existing code
 * @param {HTMLElement} container - Container to render into
 */
function renderKickstartCTA(container) {
    if (kickstartInProgress) {
        const label = hasExistingCode ? 'Analyse In Progress' : 'Kickstart In Progress';
        const desc = hasExistingCode
            ? 'Scanning your codebase and creating product documents. Check the Processes tab for details.'
            : 'Creating product documents, task groups, and roadmap. Check the Processes tab for details.';
        container.innerHTML = `
            <div class="kickstart-cta in-progress">
                <div class="kickstart-glyph">◈</div>
                <div class="kickstart-title">${label}</div>
                <div class="kickstart-description">${desc}</div>
            </div>
        `;
        return;
    }

    if (hasExistingCode) {
        container.innerHTML = `
            <div class="kickstart-cta">
                <div class="kickstart-glyph">◈</div>
                <div class="kickstart-title">Existing Project</div>
                <div class="kickstart-description">
                    Let Claude scan your codebase and generate foundational product documents — mission, tech stack, and entity model.
                </div>
                <button class="kickstart-btn" onclick="openAnalyseModal()">ANALYSE PROJECT</button>
            </div>
        `;
    } else {
        container.innerHTML = `
            <div class="kickstart-cta">
                <div class="kickstart-glyph">◈</div>
                <div class="kickstart-title">New Project</div>
                <div class="kickstart-description">
                    Describe your project and let Claude create your foundational product documents — mission, tech stack, and entity model.
                </div>
                <button class="kickstart-btn" onclick="openKickstartModal()">KICKSTART PROJECT</button>
            </div>
        `;
    }
}

/**
 * Open the kickstart modal
 */
function openKickstartModal() {
    const modal = document.getElementById('kickstart-modal');
    const textarea = document.getElementById('kickstart-prompt');

    if (modal) {
        modal.classList.add('visible');
        setTimeout(() => textarea?.focus(), 100);
    }
}

/**
 * Close the kickstart modal and reset form
 */
function closeKickstartModal() {
    const modal = document.getElementById('kickstart-modal');
    const textarea = document.getElementById('kickstart-prompt');
    const submitBtn = document.getElementById('kickstart-submit');

    if (modal) {
        modal.classList.remove('visible');
        if (textarea) textarea.value = '';
        kickstartFiles = [];
        updateFileList();
        const interviewCheckbox = document.getElementById('kickstart-interview');
        if (interviewCheckbox) interviewCheckbox.checked = true;
        if (submitBtn) {
            submitBtn.classList.remove('loading');
            submitBtn.disabled = false;
        }
    }
}

/**
 * Handle file selection (from drop or browse)
 * @param {FileList} fileList - Files to process
 */
function handleFiles(fileList) {
    const files = Array.from(fileList);

    for (const file of files) {
        // Check total count
        if (kickstartFiles.length >= KICKSTART_MAX_FILES) {
            showToast(`Maximum ${KICKSTART_MAX_FILES} files allowed`, 'warning');
            break;
        }

        // Check extension
        const ext = '.' + file.name.split('.').pop().toLowerCase();
        if (!KICKSTART_ALLOWED_EXTENSIONS.includes(ext)) {
            showToast(`File type ${ext} not supported`, 'warning');
            continue;
        }

        // Check size
        if (file.size > KICKSTART_MAX_FILE_SIZE) {
            showToast(`File "${file.name}" exceeds 2MB limit`, 'warning');
            continue;
        }

        // Check for duplicate
        if (kickstartFiles.some(f => f.name === file.name)) {
            showToast(`File "${file.name}" already added`, 'warning');
            continue;
        }

        // Read as base64
        const reader = new FileReader();
        reader.onload = (e) => {
            // readAsDataURL gives "data:...;base64,XXXXX" — extract just the base64 part
            const base64 = e.target.result.split(',')[1];
            kickstartFiles.push({
                name: file.name,
                size: file.size,
                content: base64
            });
            updateFileList();
        };
        reader.readAsDataURL(file);
    }
}

/**
 * Re-render the file list from kickstartFiles[]
 */
function updateFileList() {
    const container = document.getElementById('kickstart-file-list');
    if (!container) return;

    if (kickstartFiles.length === 0) {
        container.innerHTML = '';
        return;
    }

    container.innerHTML = kickstartFiles.map((file, index) => {
        const sizeStr = file.size < 1024
            ? `${file.size} B`
            : `${Math.round(file.size / 1024)} KB`;

        return `
            <div class="kickstart-file-item">
                <span class="kickstart-file-icon">◇</span>
                <span class="kickstart-file-name">${escapeHtml(file.name)}</span>
                <span class="kickstart-file-size">${sizeStr}</span>
                <button class="kickstart-file-remove" onclick="removeKickstartFile(${index})" title="Remove file">&times;</button>
            </div>
        `;
    }).join('');
}

/**
 * Remove a file from the kickstart file list
 * @param {number} index - Index in kickstartFiles array
 */
function removeKickstartFile(index) {
    kickstartFiles.splice(index, 1);
    updateFileList();
}

/**
 * Submit the kickstart request to the backend
 */
async function submitKickstart() {
    const textarea = document.getElementById('kickstart-prompt');
    const submitBtn = document.getElementById('kickstart-submit');

    const prompt = textarea?.value?.trim();
    const needsInterview = document.getElementById('kickstart-interview')?.checked ?? true;

    if (!prompt) {
        showToast('Please describe your project', 'warning');
        return;
    }

    // Set loading state
    if (submitBtn) {
        submitBtn.classList.add('loading');
        submitBtn.disabled = true;
    }

    try {
        const response = await fetch(`${API_BASE}/api/product/kickstart`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                prompt: prompt,
                needs_interview: needsInterview,
                files: kickstartFiles.map(f => ({
                    name: f.name,
                    content: f.content
                }))
            })
        });

        const result = await response.json();

        if (result.success) {
            closeKickstartModal();
            kickstartInProgress = true;
            kickstartProcessId = result.process_id || null;

            // Re-render CTAs to show in-progress state
            if (typeof updateExecutiveSummary === 'function') updateExecutiveSummary();
            const navContainer = document.getElementById('product-file-nav');
            if (navContainer) {
                delete navContainer.dataset.loaded;
                if (typeof updateProductFileNav === 'function') updateProductFileNav();
            }

            showToast('Kickstart initiated! Claude is creating your product documents...', 'success', 8000);
            startKickstartPolling();
        } else {
            showToast('Failed to kickstart: ' + (result.error || 'Unknown error'), 'error');
            if (submitBtn) {
                submitBtn.classList.remove('loading');
                submitBtn.disabled = false;
            }
        }
    } catch (error) {
        console.error('Error starting kickstart:', error);
        showToast('Error starting kickstart: ' + error.message, 'error');
        if (submitBtn) {
            submitBtn.classList.remove('loading');
            submitBtn.disabled = false;
        }
    }
}

/**
 * Start polling for product doc appearance after kickstart
 * Polls /api/product/list every 5s; when docs appear, transitions UI
 */
function startKickstartPolling() {
    if (kickstartPolling) clearInterval(kickstartPolling);

    let attempts = 0;
    const maxAttempts = 60; // 5 minutes at 5s intervals

    kickstartPolling = setInterval(async () => {
        attempts++;
        if (attempts > maxAttempts) {
            clearInterval(kickstartPolling);
            kickstartPolling = null;
            kickstartInProgress = false;
            return;
        }

        try {
            const response = await fetch(`${API_BASE}/api/product/list`);
            if (!response.ok) return;

            const data = await response.json();
            const docs = data.docs || [];

            if (docs.length > 0) {
                // Docs appeared! Transition UI
                clearInterval(kickstartPolling);
                kickstartPolling = null;
                isNewProject = false;
                kickstartInProgress = false;

                // Clear sidebar loaded flag so it re-fetches
                const navContainer = document.getElementById('product-file-nav');
                if (navContainer) delete navContainer.dataset.loaded;

                // Refresh product nav
                if (typeof updateProductFileNav === 'function') {
                    updateProductFileNav();
                }

                // Re-fetch executive summary
                if (typeof initProjectName === 'function') {
                    initProjectName();
                }

                // Analyse only creates product docs (no roadmap/tasks)
                if (analyseInProgress) {
                    analyseInProgress = false;
                    showToast('Product documents created from your codebase!', 'success');
                } else {
                    showToast('Product documents created! Now planning roadmap...', 'success');

                    // Roadmap planning is chained server-side in the same background job.
                    // Start polling for tasks to appear.
                    startRoadmapPolling();
                }
            }
        } catch (error) {
            // Silently continue polling
        }
    }, 5000);
}

/**
 * Open the analyse modal
 */
function openAnalyseModal() {
    const modal = document.getElementById('analyse-modal');
    const textarea = document.getElementById('analyse-prompt');

    if (modal) {
        modal.classList.add('visible');
        setTimeout(() => textarea?.focus(), 100);
    }
}

/**
 * Close the analyse modal and reset form
 */
function closeAnalyseModal() {
    const modal = document.getElementById('analyse-modal');
    const textarea = document.getElementById('analyse-prompt');
    const submitBtn = document.getElementById('analyse-submit');

    if (modal) {
        modal.classList.remove('visible');
        if (textarea) textarea.value = '';
        if (submitBtn) {
            submitBtn.classList.remove('loading');
            submitBtn.disabled = false;
        }
    }
}

/**
 * Submit the analyse request to the backend
 */
async function submitAnalyse() {
    const textarea = document.getElementById('analyse-prompt');
    const modelSelect = document.getElementById('analyse-model');
    const submitBtn = document.getElementById('analyse-submit');

    const prompt = textarea?.value?.trim() || '';
    const model = modelSelect?.value || 'Sonnet';

    // Set loading state
    if (submitBtn) {
        submitBtn.classList.add('loading');
        submitBtn.disabled = true;
    }

    try {
        const response = await fetch(`${API_BASE}/api/product/analyse`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt, model })
        });

        const result = await response.json();

        if (result.success) {
            closeAnalyseModal();
            kickstartInProgress = true;
            analyseInProgress = true;

            // Re-render CTAs to show in-progress state
            if (typeof updateExecutiveSummary === 'function') updateExecutiveSummary();
            const navContainer = document.getElementById('product-file-nav');
            if (navContainer) {
                delete navContainer.dataset.loaded;
                if (typeof updateProductFileNav === 'function') updateProductFileNav();
            }

            showToast('Analyse initiated! Claude is scanning your codebase...', 'success', 8000);
            startKickstartPolling();
        } else {
            showToast('Failed to analyse: ' + (result.error || 'Unknown error'), 'error');
            if (submitBtn) {
                submitBtn.classList.remove('loading');
                submitBtn.disabled = false;
            }
        }
    } catch (error) {
        console.error('Error starting analyse:', error);
        showToast('Error starting analyse: ' + error.message, 'error');
        if (submitBtn) {
            submitBtn.classList.remove('loading');
            submitBtn.disabled = false;
        }
    }
}

/**
 * Poll for task creation after roadmap planning
 * Watches /api/state for tasks to appear (todo > 0)
 */
function startRoadmapPolling() {
    if (roadmapPolling) clearInterval(roadmapPolling);

    let attempts = 0;
    const maxAttempts = 120; // 10 minutes at 5s intervals

    roadmapPolling = setInterval(async () => {
        attempts++;
        if (attempts > maxAttempts) {
            clearInterval(roadmapPolling);
            roadmapPolling = null;
            showToast('Roadmap planning is taking longer than expected. Check the Pipeline tab for progress.', 'warning', 10000);
            return;
        }

        try {
            const response = await fetch(`${API_BASE}/api/state`);
            if (!response.ok) return;

            const state = await response.json();

            if (state.tasks && state.tasks.todo > 0) {
                clearInterval(roadmapPolling);
                roadmapPolling = null;

                const taskCount = state.tasks.todo;
                showToast(`Roadmap created! ${taskCount} task${taskCount !== 1 ? 's' : ''} ready in the pipeline.`, 'success', 10000);

                // Refresh product nav to show roadmap-overview.md
                const navContainer = document.getElementById('product-file-nav');
                if (navContainer) delete navContainer.dataset.loaded;
                if (typeof updateProductFileNav === 'function') {
                    updateProductFileNav();
                }
            }
        } catch (error) {
            // Silently continue polling
        }
    }, 5000);
}
