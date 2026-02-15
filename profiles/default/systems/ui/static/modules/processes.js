/**
 * DOTBOT Control Panel - Processes Module
 * Manages the Processes tab: listing, launching, stopping, and whispering to processes
 */

// Process state
let processesData = [];
let processPollingTimer = null;
let expandedProcessId = null;
let processOutputPositions = {};  // Track output position per process

/**
 * Initialize the Processes tab
 */
function initProcesses() {
    // Launch bar event listeners
    const launchBtn = document.getElementById('process-launch-btn');
    if (launchBtn) {
        launchBtn.addEventListener('click', handleProcessLaunch);
    }

    // Type selector changes available options
    const typeSelect = document.getElementById('process-type-select');
    if (typeSelect) {
        typeSelect.addEventListener('change', updateLaunchBarOptions);
    }

    // Quick launch buttons in sidebar
    const quickAnalysis = document.getElementById('quick-launch-analysis');
    if (quickAnalysis) {
        quickAnalysis.addEventListener('click', () => quickLaunch('analysis'));
    }
    const quickExecution = document.getElementById('quick-launch-execution');
    if (quickExecution) {
        quickExecution.addEventListener('click', () => quickLaunch('execution'));
    }
}

/**
 * Start polling for processes (called when Processes tab becomes active)
 */
function startProcessPolling() {
    pollProcesses();
    if (!processPollingTimer) {
        processPollingTimer = setInterval(pollProcesses, 3000);
    }
}

/**
 * Stop process polling (called when leaving Processes tab)
 */
function stopProcessPolling() {
    if (processPollingTimer) {
        clearInterval(processPollingTimer);
        processPollingTimer = null;
    }
}

/**
 * Poll for process list
 */
async function pollProcesses() {
    try {
        const response = await fetch(`${API_BASE}/api/processes`);
        if (!response.ok) return;
        const data = await response.json();
        processesData = data.processes || [];
        renderProcessList(processesData);
        updateProcessSidebar(processesData);

        // If a process is expanded and running, poll its output
        if (expandedProcessId) {
            const proc = processesData.find(p => p.id === expandedProcessId);
            if (proc) {
                pollProcessOutput(expandedProcessId);
            }
        }
    } catch (error) {
        console.error('Process poll error:', error);
    }
}

/**
 * Render the grouped process list
 */
function renderProcessList(processes) {
    const container = document.getElementById('process-list');
    if (!container) return;

    if (!processes || processes.length === 0) {
        container.innerHTML = '<div class="empty-state">No processes</div>';
        return;
    }

    // Group by type
    const groups = {};
    const typeOrder = ['analysis', 'execution', 'kickstart', 'analyse', 'planning', 'commit', 'task-creation'];
    const typeLabels = {
        'analysis': 'Analysis',
        'execution': 'Execution',
        'kickstart': 'Kickstart',
        'analyse': 'Analyse',
        'planning': 'Planning',
        'commit': 'Commit',
        'task-creation': 'Task Creation'
    };

    for (const proc of processes) {
        const type = proc.type || 'unknown';
        if (!groups[type]) groups[type] = [];
        groups[type].push(proc);
    }

    // Sort within groups: running first, then completed, then failed/stopped
    const statusOrder = { 'starting': 0, 'running': 1, 'completed': 2, 'stopped': 3, 'failed': 4 };
    for (const type in groups) {
        groups[type].sort((a, b) => (statusOrder[a.status] || 5) - (statusOrder[b.status] || 5));
    }

    let html = '';
    for (const type of typeOrder) {
        if (!groups[type] || groups[type].length === 0) continue;

        html += `<div class="process-group">`;
        html += `<div class="process-group-header">${typeLabels[type] || type}</div>`;

        for (const proc of groups[type]) {
            const statusClass = getProcessStatusClass(proc.status, proc);
            const statusIcon = getProcessStatusIcon(proc.status, proc);
            const timeAgo = getTimeAgo(proc.started_at);
            const displayName = proc.task_name || proc.description || proc.id;
            const isExpanded = expandedProcessId === proc.id;
            const isRunning = proc.status === 'running' || proc.status === 'starting';

            // TTL countdown for failed/stopped
            let ttlHtml = '';
            if ((proc.status === 'failed' || proc.status === 'stopped') && proc.failed_at) {
                const failedAt = new Date(proc.failed_at);
                const ttlMs = 5 * 60 * 1000 - (Date.now() - failedAt.getTime());
                if (ttlMs > 0) {
                    const ttlMin = Math.ceil(ttlMs / 60000);
                    ttlHtml = `<span class="process-ttl">(clears in ${ttlMin}m)</span>`;
                }
            }

            html += `<div class="process-row ${statusClass} ${isExpanded ? 'expanded' : ''}" data-process-id="${proc.id}">`;
            html += `  <div class="process-row-main" onclick="toggleProcessExpand('${proc.id}')">`;
            html += `    <span class="process-status-icon">${statusIcon}</span>`;
            html += `    <span class="process-id">${proc.id}</span>`;
            html += `    <span class="process-name">${escapeHtml(displayName)}</span>`;
            html += `    <span class="process-time">${timeAgo}</span>`;
            const displayStatus = isProcessCrashed(proc) ? 'crashed' : proc.status;
            html += `    <span class="process-status-label">${displayStatus}${ttlHtml}</span>`;

            if (isRunning) {
                html += `    <div class="process-actions">`;
                html += `      <button class="process-action-btn" onclick="event.stopPropagation(); showProcessWhisper('${proc.id}')" title="Whisper">W</button>`;
                html += `      <button class="process-action-btn" onclick="event.stopPropagation(); stopProcess('${proc.id}')" title="Graceful Stop">S</button>`;
                html += `      <button class="process-action-btn danger" onclick="event.stopPropagation(); killProcess('${proc.id}')" title="Kill (immediate)">K</button>`;
                html += `    </div>`;
            }

            html += `  </div>`;

            // Expanded detail panel
            if (isExpanded) {
                html += `<div class="process-detail">`;

                // Metadata
                html += `<div class="process-meta">`;
                html += `  <span class="process-meta-item"><b>Model:</b> ${proc.model || '--'}</span>`;
                html += `  <span class="process-meta-item"><b>Tasks:</b> ${proc.tasks_completed || 0}</span>`;
                if (proc.heartbeat_status) {
                    html += `  <span class="process-meta-item"><b>Status:</b> ${escapeHtml(proc.heartbeat_status)}</span>`;
                }
                if (proc.heartbeat_next_action) {
                    html += `  <span class="process-meta-item"><b>Next:</b> ${escapeHtml(proc.heartbeat_next_action)}</span>`;
                }
                html += `</div>`;

                // Output viewer
                html += `<div class="process-output" id="process-output-${proc.id}">`;
                html += `  <div class="loading-state">Loading output...</div>`;
                html += `</div>`;

                // Inline whisper for running processes
                if (isRunning) {
                    html += `<div class="process-whisper-inline">`;
                    html += `  <input type="text" class="process-whisper-input" id="whisper-input-${proc.id}" placeholder="Send guidance..." maxlength="500">`;
                    html += `  <select class="process-whisper-priority" id="whisper-priority-${proc.id}">`;
                    html += `    <option value="normal">Normal</option>`;
                    html += `    <option value="urgent">Urgent</option>`;
                    html += `  </select>`;
                    html += `  <button class="ctrl-btn-sm primary" onclick="sendProcessWhisper('${proc.id}')">Send</button>`;
                    html += `</div>`;
                }

                html += `</div>`;
            }

            html += `</div>`;
        }

        html += `</div>`;
    }

    container.innerHTML = html;
}

/**
 * Toggle process row expansion
 */
function toggleProcessExpand(processId) {
    if (expandedProcessId === processId) {
        expandedProcessId = null;
    } else {
        expandedProcessId = processId;
        // Reset output position for fresh load
        processOutputPositions[processId] = 0;
    }
    renderProcessList(processesData);

    // If expanded, load output immediately
    if (expandedProcessId) {
        pollProcessOutput(expandedProcessId);
    }
}

/**
 * Poll process output/activity stream
 */
async function pollProcessOutput(processId) {
    try {
        const position = processOutputPositions[processId] || 0;
        const response = await fetch(`${API_BASE}/api/process/${processId}/output?position=${position}&tail=50`);
        if (!response.ok) return;

        const data = await response.json();
        if (data.position !== undefined) {
            processOutputPositions[processId] = data.position;
        }

        const outputEl = document.getElementById(`process-output-${processId}`);
        if (!outputEl) return;

        if (data.events && data.events.length > 0) {
            let html = '';
            for (const evt of data.events) {
                const ts = evt.timestamp ? new Date(evt.timestamp).toLocaleTimeString() : '';
                const typeClass = evt.type === 'rate_limit' ? 'warning' : (evt.type === 'text' ? 'text' : 'tool');
                html += `<div class="process-output-line ${typeClass}">`;
                html += `  <span class="output-time">${ts}</span>`;
                html += `  <span class="output-type">${escapeHtml(evt.type || '')}</span>`;
                html += `  <span class="output-msg">${escapeHtml(evt.message || '')}</span>`;
                html += `</div>`;
            }
            outputEl.innerHTML = html;
            // Auto-scroll to bottom
            outputEl.scrollTop = outputEl.scrollHeight;
        } else if (position === 0) {
            outputEl.innerHTML = '<div class="empty-state">No output yet</div>';
        }
    } catch (error) {
        console.error('Process output poll error:', error);
    }
}

/**
 * Launch a new process from the launch bar
 */
async function handleProcessLaunch() {
    const typeSelect = document.getElementById('process-type-select');
    const continueCheck = document.getElementById('process-continue-check');
    const modelSelect = document.getElementById('process-model-select');

    const type = typeSelect?.value;
    if (!type) return;

    const body = { type };
    if (continueCheck?.checked) body.continue = true;
    if (modelSelect?.value) body.model = modelSelect.value;

    // For prompt-based types, check for prompt input
    const promptInput = document.getElementById('process-prompt-input');
    if (promptInput && promptInput.value.trim()) {
        body.prompt = promptInput.value.trim();
    }

    try {
        const launchBtn = document.getElementById('process-launch-btn');
        if (launchBtn) {
            launchBtn.disabled = true;
            launchBtn.textContent = 'Launching...';
        }

        const response = await fetch(`${API_BASE}/api/process/launch`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });

        const data = await response.json();
        if (data.success) {
            showToast(`Process ${data.process_id} launched`, 'success');
            // Clear prompt input
            if (promptInput) promptInput.value = '';
            // Refresh list immediately
            pollProcesses();
        } else {
            showToast(`Launch failed: ${data.error || 'Unknown error'}`, 'error');
        }
    } catch (error) {
        showToast(`Launch error: ${error.message}`, 'error');
    } finally {
        const launchBtn = document.getElementById('process-launch-btn');
        if (launchBtn) {
            launchBtn.disabled = false;
            launchBtn.textContent = 'LAUNCH';
        }
    }
}

/**
 * Stop a process
 */
async function stopProcess(processId) {
    try {
        const response = await fetch(`${API_BASE}/api/process/${processId}/stop`, {
            method: 'POST'
        });
        const data = await response.json();
        if (data.success) {
            showToast(`Stop signal sent to ${processId}`, 'success');
            pollProcesses();
        } else {
            showToast(`Stop failed: ${data.error || 'Unknown error'}`, 'error');
        }
    } catch (error) {
        showToast(`Stop error: ${error.message}`, 'error');
    }
}

/**
 * Kill a process immediately via PID
 */
async function killProcess(processId) {
    if (!confirm(`Kill process ${processId} immediately? This will terminate it without finishing the current task.`)) {
        return;
    }

    try {
        const response = await fetch(`${API_BASE}/api/process/${processId}/kill`, {
            method: 'POST'
        });
        const data = await response.json();
        if (data.success) {
            showToast(`Process ${processId} killed`, 'warning');
            pollProcesses();
        } else {
            showToast(`Kill failed: ${data.error || 'Unknown error'}`, 'error');
        }
    } catch (error) {
        showToast(`Kill error: ${error.message}`, 'error');
    }
}

/**
 * Show whisper input for a process (uses inline whisper in expanded view)
 */
function showProcessWhisper(processId) {
    // Expand the process row first
    if (expandedProcessId !== processId) {
        toggleProcessExpand(processId);
    }
    // Focus the whisper input after render
    setTimeout(() => {
        const input = document.getElementById(`whisper-input-${processId}`);
        if (input) input.focus();
    }, 100);
}

/**
 * Send a whisper to a process
 */
async function sendProcessWhisper(processId) {
    const input = document.getElementById(`whisper-input-${processId}`);
    const prioritySelect = document.getElementById(`whisper-priority-${processId}`);

    const message = input?.value?.trim();
    if (!message) return;

    const priority = prioritySelect?.value || 'normal';

    try {
        const response = await fetch(`${API_BASE}/api/process/${processId}/whisper`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message, priority })
        });
        const data = await response.json();
        if (data.success) {
            showToast(`Whisper sent to ${processId}`, 'success');
            if (input) input.value = '';
        } else {
            showToast(`Whisper failed: ${data.error || 'Unknown error'}`, 'error');
        }
    } catch (error) {
        showToast(`Whisper error: ${error.message}`, 'error');
    }
}

/**
 * Update launch bar options based on selected type
 */
function updateLaunchBarOptions() {
    const typeSelect = document.getElementById('process-type-select');
    const continueGroup = document.getElementById('process-continue-group');
    const promptGroup = document.getElementById('process-prompt-group');

    const type = typeSelect?.value;
    const isTaskBased = type === 'analysis' || type === 'execution';

    if (continueGroup) {
        continueGroup.style.display = isTaskBased ? '' : 'none';
    }
    if (promptGroup) {
        promptGroup.style.display = isTaskBased ? 'none' : '';
    }
}

// --- Helpers ---

function isProcessCrashed(proc) {
    // A process is "crashed" if it went to stopped without a user-initiated stop,
    // detected by having error set or failed_at without completed_at
    return proc.status === 'stopped' && proc.error && !proc.completed_at;
}

function getProcessStatusClass(status, proc) {
    if (proc && isProcessCrashed(proc)) return 'status-failed';
    switch (status) {
        case 'running':
        case 'starting': return 'status-running';
        case 'completed': return 'status-completed';
        case 'failed': return 'status-failed';
        case 'stopped': return 'status-stopped';
        default: return '';
    }
}

function getProcessStatusIcon(status, proc) {
    if (proc && isProcessCrashed(proc)) return '<span class="led error"></span>';
    switch (status) {
        case 'running':
        case 'starting': return '<span class="led active"></span>';
        case 'completed': return '<span class="led success"></span>';
        case 'failed': return '<span class="led error"></span>';
        case 'stopped': return '<span class="led off"></span>';
        default: return '<span class="led off"></span>';
    }
}

function getTimeAgo(isoString) {
    if (!isoString) return '--';
    const diff = Date.now() - new Date(isoString).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    return `${Math.floor(hours / 24)}d ago`;
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

/**
 * Quick launch a process from sidebar buttons
 */
async function quickLaunch(type) {
    try {
        const response = await fetch(`${API_BASE}/api/process/launch`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ type, continue: true })
        });
        const data = await response.json();
        if (data.success) {
            showToast(`${type} process launched: ${data.process_id}`, 'success');
            pollProcesses();
        } else {
            showToast(`Launch failed: ${data.error || 'Unknown error'}`, 'error');
        }
    } catch (error) {
        showToast(`Launch error: ${error.message}`, 'error');
    }
}

/**
 * Update the process summary counts in the sidebar
 * Called from pollProcesses after data is fetched
 */
function updateProcessSidebar(processes) {
    const running = processes.filter(p => p.status === 'running' || p.status === 'starting').length;
    const completed = processes.filter(p => p.status === 'completed').length;
    const failed = processes.filter(p => p.status === 'failed' || p.status === 'stopped').length;
    const totalTasks = processes.reduce((sum, p) => sum + (p.tasks_completed || 0), 0);

    const runEl = document.getElementById('proc-running-count');
    const compEl = document.getElementById('proc-completed-count');
    const failEl = document.getElementById('proc-failed-count');
    const taskEl = document.getElementById('proc-total-tasks');

    if (runEl) runEl.textContent = running;
    if (compEl) compEl.textContent = completed;
    if (failEl) failEl.textContent = failed;
    if (taskEl) taskEl.textContent = totalTasks;
}
