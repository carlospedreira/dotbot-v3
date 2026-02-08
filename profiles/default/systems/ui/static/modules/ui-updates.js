/**
 * DOTBOT Control Panel - UI Updates
 * DOM updates from state changes
 */

/**
 * Update all UI elements from state
 * @param {Object} state - State object from server
 */
function updateUI(state) {
    updateTimestamp();
    updateTaskCounts(state.tasks);
    updateProgressPercent(state.tasks);
    updateSessionInfo(state.session);
    updateRunningStatus(state.session, state.control, state.analysis, state.loops);
    updateCurrentTask(state.tasks.current);
    updateUpcomingTasks(state.tasks.upcoming);
    updateCompletedTasks(state.tasks.recent_completed);
    updatePipelineView(state.tasks);
    updateControlSignalStatus(state.control);
    updateControlButtonStates(state.session, state.control, state.loops);

    // Update steering panel with instance info
    if (state.instances) {
        updateSteeringPanel(state.instances);
    }

    // Update task summary in pipeline context panel
    if (state.tasks) {
        updateTaskSummary(state.tasks);
    }

    // Check for notable state changes and show notifications
    if (typeof checkNotifications === 'function') {
        checkNotifications(state);
    }
}

/**
 * Update timestamp display
 */
function updateTimestamp() {
    setElementText('last-update', new Date().toLocaleTimeString());
    // Update footer mission on each poll to ensure it's current
    updateFooterMission();
}

/**
 * Update task count displays
 * @param {Object} tasks - Tasks object from state
 */
function updateTaskCounts(tasks) {
    // Overview stats
    setElementText('todo-count', tasks.todo);
    setElementText('progress-count', tasks.in_progress);
    setElementText('done-count', tasks.done);
    setElementText('analysing-count', tasks.analysing || 0);
    setElementText('needs-input-count', tasks.needs_input || 0);

    // Pipeline counts - Analysis stage
    setElementText('pipeline-todo-count', tasks.todo);
    setElementText('pipeline-analysing-count', tasks.analysing || 0);
    setElementText('pipeline-needs-input-count', tasks.needs_input || 0);
    setElementText('pipeline-analysed-count', tasks.analysed || 0);
    
    // Pipeline counts - Execution stage
    setElementText('pipeline-ready-count', tasks.analysed || 0);  // Ready = Analysed (shared)
    setElementText('pipeline-progress-count', tasks.in_progress);
    setElementText('pipeline-done-count', tasks.done);
    
    // Update action widget
    if (typeof updateActionWidget === 'function') {
        updateActionWidget(tasks.action_required || 0);
    }
}

/**
 * Update progress percentage display
 * @param {Object} tasks - Tasks object from state
 */
function updateProgressPercent(tasks) {
    // Include all statuses in total for accurate progress
    const total = (tasks.todo || 0) + (tasks.analysing || 0) + (tasks.needs_input || 0) + 
                  (tasks.analysed || 0) + (tasks.in_progress || 0) + (tasks.done || 0);
    const percent = total > 0 ? Math.round((tasks.done / total) * 100) : 0;
    setElementText('progress-percent', `${percent}%`);
}

/**
 * Update session info display
 * @param {Object} session - Session object from state
 */
function updateSessionInfo(session) {
    if (!session) {
        setElementText('session-id', '--');
        setElementText('session-status-detail', '--');
        setElementText('session-started', '--');
        setElementText('session-runtime', '--');
        setElementText('session-tasks-completed', '--');
        setElementText('session-tasks-skipped', '--');
        setElementText('session-failures', '--');
        setElementText('handoff-text', 'No handoff notes available');
        sessionStartTime = null;
        // Reset timer state
        sessionTimerElapsed = 0;
        sessionTimerLastResumed = null;
        sessionTimerStatus = null;
        sessionTimerSessionId = null;
        return;
    }

    const sessionId = session.session_id || '--';
    setElementText('session-id', sessionId);

    const status = session.status || 'unknown';
    setElementText('session-status-detail', status.toUpperCase());

    if (session.started_at) {
        const started = new Date(session.started_at);
        setElementText('session-started', started.toLocaleTimeString());
        sessionStartTime = started;
    } else {
        setElementText('session-started', '--');
        sessionStartTime = null;
    }

    // Handle timer state transitions based on session status changes
    updateTimerState(session);

    setElementText('session-tasks-completed', session.tasks_completed || 0);
    setElementText('session-tasks-skipped', session.tasks_skipped || 0);
    setElementText('session-failures', session.consecutive_failures || 0);

    // Handoff preview (mock - would come from API)
    if (session.status === 'running') {
        setElementText('handoff-text', 'Session in progress. Handoff notes will be generated on pause or completion.');
    }
}

/**
 * Manage timer state transitions based on session status changes.
 * Tracks accumulated elapsed time so pause/resume works correctly.
 * @param {Object} session - Session object from state
 */
function updateTimerState(session) {
    const newStatus = session.status || 'unknown';
    const newSessionId = session.session_id || null;

    // Detect new session (or first load) - initialize timer
    if (newSessionId && newSessionId !== sessionTimerSessionId) {
        sessionTimerSessionId = newSessionId;
        // On first load, seed elapsed from server's runtime_minutes if available
        // This gives a reasonable starting point for sessions already in progress
        if (session.runtime_minutes > 0) {
            sessionTimerElapsed = session.runtime_minutes * 60000;
        } else {
            sessionTimerElapsed = 0;
        }
        sessionTimerLastResumed = (newStatus === 'running') ? new Date() : null;
        sessionTimerStatus = newStatus;
        return;
    }

    // No status change - nothing to do
    if (newStatus === sessionTimerStatus) return;

    const prevStatus = sessionTimerStatus;
    sessionTimerStatus = newStatus;

    // Transition: anything -> running (start or resume)
    if (newStatus === 'running') {
        sessionTimerLastResumed = new Date();
        return;
    }

    // Transition: running -> paused/stopped/stopping (freeze elapsed time)
    if (prevStatus === 'running' && newStatus !== 'running') {
        if (sessionTimerLastResumed) {
            sessionTimerElapsed += (new Date() - sessionTimerLastResumed);
        }
        sessionTimerLastResumed = null;
        return;
    }
}

/**
 * Update running status indicators
 * @param {Object} session - Session object from state
 * @param {Object} control - Control object from state
 * @param {Object} analysis - Analysis loop state (optional)
 * @param {Object} loops - Combined loop state (optional)
 */
function updateRunningStatus(session, control, analysis, loops) {
    const runningLed = document.getElementById('running-led');
    const runningStatus = document.getElementById('running-status');
    const agentLed = document.getElementById('agent-led');
    const agentState = document.getElementById('agent-state');

    // Update loop status LEDs
    const analysisLed = document.getElementById('analysis-loop-led');
    const executionLed = document.getElementById('execution-loop-led');

    // Use loops.analysis_alive if available (PID-validated), fall back to signal file check
    const analysisActive = loops?.analysis_alive ?? analysis?.running;
    const executionActive = loops?.execution_alive ?? control?.running;

    if (analysisLed) {
        if (analysisActive) {
            analysisLed.className = 'led pulse';
        } else {
            analysisLed.className = 'led off';
        }
    }

    if (executionLed) {
        if (executionActive) {
            executionLed.className = 'led pulse';
        } else {
            executionLed.className = 'led off';
        }
    }

    if (!session) {
        if (runningLed) runningLed.className = 'led off';
        if (runningStatus) runningStatus.textContent = 'No Session';
        if (agentLed) agentLed.className = 'led off';
        if (agentState) agentState.innerHTML = '<span class="led off"></span><span>Idle</span>';
        // Update oscilloscope to offline/stopped state
        if (activityScope) activityScope.setState('stopped');
        return;
    }

    const status = session.status || 'unknown';

    // Helper to set LED state
    const setLed = (el, type, pulse) => {
        if (!el) return;
        el.className = pulse ? 'led pulse' : 'led';
        if (type) el.dataset.type = type;
        else delete el.dataset.type;
    };

    switch (status) {
        case 'running':
            setLed(runningLed, null, true);
            if (runningStatus) runningStatus.textContent = 'Running';
            setLed(agentLed, null, true);
            if (agentState) agentState.innerHTML = '<span class="led pulse"></span><span>Processing</span>';
            // Update oscilloscope to running state
            if (activityScope) activityScope.setState('running');
            break;
        case 'paused':
            setLed(runningLed, 'warning', false);
            if (runningStatus) runningStatus.textContent = 'Paused';
            setLed(agentLed, 'warning', false);
            if (agentState) agentState.innerHTML = '<span class="led" data-type="warning"></span><span>Paused</span>';
            // Update oscilloscope to paused state
            if (activityScope) activityScope.setState('paused');
            break;
        case 'stopping':
            setLed(runningLed, 'warning', true);
            if (runningStatus) runningStatus.textContent = 'Stopping';
            setLed(agentLed, 'warning', true);
            if (agentState) agentState.innerHTML = '<span class="led pulse" data-type="warning"></span><span>Stopping</span>';
            // Update oscilloscope to paused (stopping is similar)
            if (activityScope) activityScope.setState('paused');
            break;
        case 'idle':
            setLed(runningLed, null, false);
            if (runningStatus) runningStatus.textContent = 'Idle';
            setLed(agentLed, null, false);
            if (agentState) agentState.innerHTML = '<span class="led"></span><span>Idle</span>';
            // Update oscilloscope to idle state
            if (activityScope) activityScope.setState('idle');
            break;
        default:
            if (runningLed) runningLed.className = 'led off';
            if (runningStatus) runningStatus.textContent = 'Stopped';
            if (agentLed) agentLed.className = 'led off';
            if (agentState) agentState.innerHTML = '<span class="led off"></span><span>Idle</span>';
            // Update oscilloscope to stopped state
            if (activityScope) activityScope.setState('stopped');
    }
}

/**
 * Update current task display
 * @param {Object} task - Current task object
 */
function updateCurrentTask(task) {
    const container = document.getElementById('current-task');
    const statusBadge = document.getElementById('current-task-status');
    const agentTask = document.getElementById('agent-current-task');

    if (!task) {
        if (container) container.innerHTML = '<div class="empty-state">No task in progress</div>';
        if (statusBadge) statusBadge.textContent = '--';
        if (agentTask) agentTask.textContent = 'No active task';
        return;
    }

    if (statusBadge) statusBadge.textContent = 'ACTIVE';
    if (agentTask) agentTask.textContent = task.name || task.id || 'Working...';

    if (container) {
        container.innerHTML = `
            <div class="task-name">${escapeHtml(task.name || task.id || 'Unknown')}</div>
            ${task.description ? `<div class="task-description">${escapeHtml(task.description)}</div>` : ''}
            <div class="task-meta">
                ${task.category ? `<span><span data-type="primary">◈</span> ${escapeHtml(task.category)}</span>` : ''}
                ${task.priority ? `<span><span data-type="secondary">↑</span> P${escapeHtml(task.priority)}</span>` : ''}
            </div>
        `;
    }
}

/**
 * Update upcoming tasks list
 * @param {Array} tasks - Array of upcoming tasks
 */
function updateUpcomingTasks(tasks) {
    const container = document.getElementById('upcoming-tasks');

    // Ensure tasks is an array
    const taskList = Array.isArray(tasks) ? tasks : [];

    if (!container) return;

    if (taskList.length === 0) {
        container.innerHTML = '<div class="empty-state">No upcoming tasks</div>';
        return;
    }

    container.innerHTML = taskList.map(task => `
        <div class="task-list-item" data-task-id="${escapeHtml(task.id || '')}">
            <span class="task-list-item-name">${escapeHtml(task.name || task.id || 'Unknown')}</span>
            <span class="task-list-item-meta">${escapeHtml(task.category || '')}</span>
        </div>
    `).join('');
}

/**
 * Update completed tasks list
 * @param {Array} tasks - Array of completed tasks
 */
function updateCompletedTasks(tasks) {
    const container = document.getElementById('completed-tasks');

    // Ensure tasks is an array
    const taskList = Array.isArray(tasks) ? tasks : [];

    if (!container) return;

    if (taskList.length === 0) {
        container.innerHTML = '<div class="empty-state">No completed tasks yet</div>';
        return;
    }

    container.innerHTML = taskList.map(task => `
        <div class="task-list-item done" data-task-id="${escapeHtml(task.id || '')}">
            <span class="task-list-item-name">${escapeHtml(task.name || task.id || 'Unknown')}</span>
            <span class="task-list-item-meta">${escapeHtml(task.category || '')}</span>
        </div>
    `).join('');
}

/**
 * Update pipeline view
 * @param {Object} tasks - Tasks object from state
 */
function updatePipelineView(tasks) {
    const upcoming = Array.isArray(tasks.upcoming) ? tasks.upcoming : [];
    const completed = Array.isArray(tasks.recent_completed) ? tasks.recent_completed : [];
    const analysing = Array.isArray(tasks.analysing_list) ? tasks.analysing_list : [];
    const needsInput = Array.isArray(tasks.needs_input_list) ? tasks.needs_input_list : [];
    const analysed = Array.isArray(tasks.analysed_list) ? tasks.analysed_list : [];
    
    // Analysis pipeline columns
    updatePipelineColumn('pipeline-todo', upcoming, 'todo');
    updatePipelineColumn('pipeline-analysing', analysing, 'analysing');
    updatePipelineColumn('pipeline-needs-input', needsInput, 'needs-input');
    updatePipelineColumn('pipeline-analysed', analysed, 'analysed');
    
    // Execution pipeline columns
    updatePipelineColumn('pipeline-ready', analysed, 'ready');  // Ready = Analysed tasks
    updatePipelineColumn('pipeline-progress', tasks.current ? [tasks.current] : [], 'active');
    updatePipelineColumn('pipeline-done', completed, 'done');
}

/**
 * Update a pipeline column
 * @param {string} containerId - Container element ID
 * @param {Array} tasks - Tasks to display
 * @param {string} type - Column type (todo, active, done)
 */
function updatePipelineColumn(containerId, tasks, type) {
    const container = document.getElementById(containerId);
    if (!container) return;

    // Ensure tasks is an array
    const taskList = Array.isArray(tasks) ? tasks : [];

    // Track total task count for infinite scroll
    pipelineTaskCounts[containerId] = taskList.length;

    if (taskList.length === 0) {
        container.innerHTML = `<div class="empty-state">No tasks</div>`;
        return;
    }

    // Get display limit for this column
    const limit = pipelineDisplayLimits[containerId] || 10;
    const visibleTasks = taskList.slice(0, limit);

    container.innerHTML = visibleTasks.map(task => {
        const priorityClass = task.priority == 1 ? 'priority-high' :
                              task.priority == 2 ? 'priority-med' : '';

        // Format duration or completed date for done items
        let completedBadge = '';
        if (type === 'done' && task.completed_at) {
            const duration = task.started_at
                ? formatDuration(task.started_at, task.completed_at)
                : formatCompactDate(task.completed_at);
            completedBadge = `<span class="task-tag completed-date">${duration}</span>`;
        }

        return `
            <div class="pipeline-task ${type === 'active' ? 'active' : ''} ${priorityClass}" data-task-id="${escapeHtml(task.id || '')}">
                <div class="task-id">${escapeHtml(task.id || '')}</div>
                <div class="task-title">${escapeHtml(task.name || task.id || 'Unknown')}</div>
                <div class="task-tags">
                    ${task.category ? `<span class="task-tag">${escapeHtml(task.category)}</span>` : ''}
                    ${type === 'active' ? '<span class="task-tag">↻ agent</span>' : ''}
                </div>
                ${completedBadge}
            </div>
        `;
    }).join('');
}

/**
 * Initialize pipeline infinite scroll
 */
function initPipelineInfiniteScroll() {
    const columnIds = [
        'pipeline-todo', 'pipeline-analysing', 'pipeline-needs-input', 'pipeline-analysed',
        'pipeline-ready', 'pipeline-progress', 'pipeline-done'
    ];

    columnIds.forEach(containerId => {
        const container = document.getElementById(containerId);
        if (!container) return;

        container.addEventListener('scroll', () => {
            // Check if scrolled near bottom (within 50px)
            const scrollBottom = container.scrollHeight - container.scrollTop - container.clientHeight;
            if (scrollBottom < 50) {
                const currentLimit = pipelineDisplayLimits[containerId] || 10;
                const totalTasks = pipelineTaskCounts[containerId] || 0;

                // Load more if there are more tasks available
                if (currentLimit < totalTasks) {
                    pipelineDisplayLimits[containerId] = currentLimit + 5;

                    // Re-render with updated limit
                    if (lastState?.tasks) {
                        updatePipelineView(lastState.tasks);
                    }
                }
            }
        });
    });
}

/**
 * Update control signal status display
 * @param {Object} control - Control object from state
 */
function updateControlSignalStatus(control) {
    const controlLed = document.getElementById('control-led');
    const controlStatus = document.getElementById('control-signal-status');

    if (!control) {
        if (controlLed) controlLed.className = 'led off';
        if (controlStatus) controlStatus.textContent = 'No Signal';
        return;
    }

    const setControlLed = (type) => {
        if (!controlLed) return;
        controlLed.className = 'led';
        if (type) controlLed.dataset.type = type;
        else delete controlLed.dataset.type;
    };

    if (control.stop) {
        setControlLed('error');
        if (controlStatus) controlStatus.textContent = 'Stop Pending';
    } else if (control.pause) {
        setControlLed('warning');
        if (controlStatus) controlStatus.textContent = 'Pause Pending';
    } else if (control.resume) {
        setControlLed('info');
        if (controlStatus) controlStatus.textContent = 'Resume Pending';
    } else {
        if (controlLed) controlLed.className = 'led off';
        if (controlStatus) controlStatus.textContent = 'No Signal';
    }
}

/**
 * Update control button enabled/disabled states
 * @param {Object} session - Session object from state
 * @param {Object} control - Control object from state
 * @param {Object} loops - Combined loop state (optional)
 */
function updateControlButtonStates(session, control, loops) {
    const startBtn = document.querySelector('.ctrl-btn[data-action="start"]');
    const pauseBtn = document.querySelector('.ctrl-btn[data-action="pause"]');
    const resumeBtn = document.querySelector('.ctrl-btn[data-action="resume"]');
    const stopBtn = document.querySelector('.ctrl-btn[data-action="stop"]');

    // Determine current session state
    const sessionStatus = session?.status || 'stopped';
    const isPaused = sessionStatus === 'paused';
    const isRunning = sessionStatus === 'running';
    const isStopping = sessionStatus === 'stopping';

    // Use PID-validated loop state if available, otherwise fall back to session status
    const anyLoopAlive = loops?.any_alive ?? (isRunning || isPaused);
    const anyLoopRunning = loops?.any_running ?? isRunning;

    // Check for pending control signals
    const hasPendingStop = control?.stop || false;
    const hasPendingPause = control?.pause || false;
    const hasPendingResume = control?.resume || false;
    const hasPendingSignal = hasPendingStop || hasPendingPause || hasPendingResume;

    // Enable/disable logic:
    // START: enabled only if no loops running and no pending signals
    if (startBtn) {
        startBtn.disabled = !(!anyLoopRunning && !isPaused && !hasPendingSignal);
    }

    // PAUSE: enabled only if running (either session status or any loop alive) and no pending signals
    if (pauseBtn) {
        pauseBtn.disabled = !(anyLoopAlive && !hasPendingSignal);
    }

    // RESUME: enabled only if paused or has pending pause/stop signal
    if (resumeBtn) {
        resumeBtn.disabled = !(isPaused || hasPendingPause || hasPendingStop);
    }

    // STOP: enabled if any loop is alive or has pending signal (but not already pending stop)
    if (stopBtn) {
        stopBtn.disabled = !(anyLoopAlive && !hasPendingStop);
    }
}

/**
 * Set connection status display
 * @param {string} status - Connection status (connected, error, connecting)
 */
function setConnectionStatus(status) {
    const led = document.getElementById('connection-led');
    const text = document.getElementById('connection-status');

    if (!led || !text) return;

    switch (status) {
        case 'connected':
            led.className = 'led';
            delete led.dataset.type;
            text.textContent = 'CONNECTED';
            isConnected = true;
            break;
        case 'error':
            led.className = 'led';
            led.dataset.type = 'error';
            text.textContent = 'ERROR';
            isConnected = false;
            break;
        default:
            led.className = 'led pulse';
            led.dataset.type = 'warning';
            text.textContent = 'CONNECTING';
            isConnected = false;
    }
}

/**
 * Start runtime timer
 */
function startRuntimeTimer() {
    runtimeTimer = setInterval(updateRuntime, 1000);
}

/**
 * Update runtime display.
 * Uses accumulated elapsed time model to correctly handle pause/resume.
 */
function updateRuntime() {
    if (!sessionStartTime) return;

    // Calculate total elapsed: accumulated + current running segment
    let totalElapsed = sessionTimerElapsed;
    if (sessionTimerLastResumed) {
        totalElapsed += (new Date() - sessionTimerLastResumed);
    }

    const hours = Math.floor(totalElapsed / 3600000);
    const mins = Math.floor((totalElapsed % 3600000) / 60000);
    const secs = Math.floor((totalElapsed % 60000) / 1000);

    const runtime = hours > 0
        ? `${hours}h ${mins}m ${secs}s`
        : mins > 0
            ? `${mins}m ${secs}s`
            : `${secs}s`;

    setElementText('session-runtime', runtime);
}

/**
 * Initialize project name from API
 */
async function initProjectName() {
    try {
        const response = await fetch(`${API_BASE}/api/info`);
        if (response.ok) {
            const info = await response.json();
            projectName = info.project_name || 'unknown';
            projectRoot = info.full_path || 'unknown';
            executiveSummary = info.executive_summary || null;
        }
    } catch (error) {
        console.warn('Could not fetch project info:', error);
        projectName = 'unknown';
        projectRoot = 'unknown';
        executiveSummary = null;
    }
    updateProjectBadge();
    updateFooterMission();
    updateExecutiveSummary();
}

/**
 * Update project badge in header
 */
function updateProjectBadge() {
    const badge = document.getElementById('project-name');
    if (badge) {
        badge.textContent = projectName;
    }
}

/**
 * Update footer mission text
 */
function updateFooterMission() {
    const footerMission = document.getElementById('footer-mission');
    if (footerMission) {
        footerMission.textContent = projectRoot;
        footerMission.title = projectRoot; // Add tooltip for full path
    }
}

/**
 * Update executive summary display
 */
function updateExecutiveSummary() {
    const container = document.getElementById('executive-summary');
    if (!container) return;

    if (executiveSummary) {
        container.innerHTML = `<div class="summary-title">◈ Executive Summary</div><p>${escapeHtml(executiveSummary)}</p>`;
        container.style.display = 'block';
    } else {
        container.style.display = 'none';
    }
}

/**
 * Update steering panel with instance information
 * @param {Object} instances - Instances object from state
 */
function updateSteeringPanel(instances) {
    ['analysis', 'execution'].forEach(type => {
        const btn = document.getElementById(`btn-${type}`);
        const led = document.getElementById(`led-${type}`);
        const pid = document.getElementById(`pid-${type}`);
        const inst = instances?.[type];

        const isAlive = inst?.alive === true;

        if (btn) btn.disabled = !isAlive;
        if (led) led.className = 'instance-led ' + (isAlive ? 'alive' : 'dead');
        if (pid) pid.textContent = inst?.pid ? `#${inst.pid}` : '';
    });

    // Update status text for selected instance
    if (typeof updateSteeringStatus === 'function') {
        updateSteeringStatus(instances);
    }

    // Enable/disable whisper input based on selection and instance status
    const canSend = typeof getSelectedInstance === 'function' &&
                    getSelectedInstance() &&
                    instances?.[getSelectedInstance()]?.alive;
    const input = document.getElementById('whisper-input');
    const priority = document.getElementById('whisper-priority');
    const sendBtn = document.getElementById('whisper-send');
    if (input) input.disabled = !canSend;
    if (priority) priority.disabled = !canSend;
    if (sendBtn) sendBtn.disabled = !canSend;
}
