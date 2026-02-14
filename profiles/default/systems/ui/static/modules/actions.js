/**
 * DOTBOT Control Panel - Actions Module
 * Handles action-required items: questions, split approvals, and task creation
 */

// State for action items
let actionItems = [];
let selectedAnswers = {};  // { taskId: [selectedKeys] }

/**
 * Initialize action-required functionality
 */
function initActions() {
    // Widget click handler
    const widget = document.getElementById('action-widget');
    widget?.addEventListener('click', openSlideout);

    // Slideout close handlers
    const overlay = document.getElementById('slideout-overlay');
    const closeBtn = document.getElementById('slideout-close');

    overlay?.addEventListener('click', closeSlideout);
    closeBtn?.addEventListener('click', closeSlideout);

    // Escape key to close
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeSlideout();
            closeTaskCreateModal();
            if (typeof closeKickstartModal === 'function') closeKickstartModal();
        }
    });

    // Initialize task creation modal
    initTaskCreateModal();

    // Initialize git commit button
    initGitCommitButton();
}

/**
 * Initialize task creation modal handlers
 */
function initTaskCreateModal() {
    const modal = document.getElementById('task-create-modal');
    const closeBtn = document.getElementById('task-create-modal-close');
    const cancelBtn = document.getElementById('task-create-cancel');
    const submitBtn = document.getElementById('task-create-submit');
    const textarea = document.getElementById('task-create-prompt');

    // Add task button handlers (both overview and pipeline)
    document.getElementById('add-task-btn-upcoming')?.addEventListener('click', openTaskCreateModal);
    document.getElementById('add-task-btn-pipeline')?.addEventListener('click', openTaskCreateModal);

    // Close handlers
    closeBtn?.addEventListener('click', closeTaskCreateModal);
    cancelBtn?.addEventListener('click', closeTaskCreateModal);
    modal?.addEventListener('click', (e) => {
        if (e.target === modal) {
            closeTaskCreateModal();
        }
    });

    // Submit handler
    submitBtn?.addEventListener('click', submitTaskCreate);

    // Ctrl+Enter to submit
    textarea?.addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
            e.preventDefault();
            submitTaskCreate();
        }
    });
}

/**
 * Open task creation modal
 */
function openTaskCreateModal() {
    const modal = document.getElementById('task-create-modal');
    const textarea = document.getElementById('task-create-prompt');

    if (modal) {
        modal.classList.add('visible');
        // Focus the textarea after a brief delay for the modal animation
        setTimeout(() => textarea?.focus(), 100);
    }
}

/**
 * Close task creation modal
 */
function closeTaskCreateModal() {
    const modal = document.getElementById('task-create-modal');
    const textarea = document.getElementById('task-create-prompt');
    const submitBtn = document.getElementById('task-create-submit');
    const interviewCheckbox = document.getElementById('task-create-interview');

    if (modal) {
        modal.classList.remove('visible');
        // Clear the form
        if (textarea) textarea.value = '';
        if (interviewCheckbox) interviewCheckbox.checked = false;
        // Reset button state
        if (submitBtn) {
            submitBtn.classList.remove('loading');
            submitBtn.disabled = false;
        }
    }
}

/**
 * Submit task creation request
 */
async function submitTaskCreate() {
    const textarea = document.getElementById('task-create-prompt');
    const submitBtn = document.getElementById('task-create-submit');
    const interviewCheckbox = document.getElementById('task-create-interview');

    const prompt = textarea?.value?.trim();
    const needsInterview = interviewCheckbox?.checked || false;

    if (!prompt) {
        showToast('Please describe the task you want to create', 'warning');
        return;
    }

    // Set loading state
    if (submitBtn) {
        submitBtn.classList.add('loading');
        submitBtn.disabled = true;
    }

    try {
        const response = await fetch(`${API_BASE}/api/task/create`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prompt, needs_interview: needsInterview })
        });

        const result = await response.json();

        if (result.success) {
            closeTaskCreateModal();
            // Show success feedback
            showSignalFeedback('Task creation started. Claude is processing your request...', 'success');
            // Trigger state refresh after a delay to pick up the new task
            setTimeout(() => {
                if (typeof pollState === 'function') {
                    pollState();
                }
            }, 2000);
        } else {
            showToast('Failed to create task: ' + (result.error || 'Unknown error'), 'error');
            // Reset button state on error
            if (submitBtn) {
                submitBtn.classList.remove('loading');
                submitBtn.disabled = false;
            }
        }
    } catch (error) {
        console.error('Error creating task:', error);
        showToast('Error creating task: ' + error.message, 'error');
        // Reset button state on error
        if (submitBtn) {
            submitBtn.classList.remove('loading');
            submitBtn.disabled = false;
        }
    }
}

/**
 * Show signal feedback message
 * @param {string} message - Message to display
 * @param {string} type - Feedback type (success, error, info)
 */
function showSignalFeedback(message, type) {
    const feedback = document.getElementById('signal-status');
    if (feedback) {
        feedback.textContent = message;
        feedback.className = `signal-feedback visible ${type || ''}`;
        // Hide after 5 seconds
        setTimeout(() => {
            feedback.classList.remove('visible');
        }, 5000);
    }
}

/**
 * Update action widget visibility and count
 * @param {number} count - Number of action-required items
 */
function updateActionWidget(count) {
    const widget = document.getElementById('action-widget');
    const countEl = document.getElementById('action-widget-count');
    
    if (!widget) return;
    
    if (count > 0) {
        widget.classList.remove('hidden');
        if (countEl) countEl.textContent = count;
    } else {
        widget.classList.add('hidden');
    }
}

/**
 * Open the slide-out panel and fetch action items
 */
async function openSlideout() {
    const overlay = document.getElementById('slideout-overlay');
    const panel = document.getElementById('slideout-panel');
    
    overlay?.classList.add('visible');
    panel?.classList.add('visible');
    
    // Fetch and render action items
    await fetchAndRenderActionItems();
}

/**
 * Close the slide-out panel
 */
function closeSlideout() {
    const overlay = document.getElementById('slideout-overlay');
    const panel = document.getElementById('slideout-panel');
    
    overlay?.classList.remove('visible');
    panel?.classList.remove('visible');
}

/**
 * Fetch action items from the API and render them
 */
async function fetchAndRenderActionItems() {
    const content = document.getElementById('slideout-content');
    if (!content) return;
    
    content.innerHTML = '<div class="loading-state">Loading...</div>';
    
    try {
        const response = await fetch(`${API_BASE}/api/tasks/action-required`);
        const data = await response.json();
        
        if (data.success && data.items && data.items.length > 0) {
            actionItems = data.items;
            renderActionItems(content, data.items);
        } else {
            content.innerHTML = '<div class="empty-state">No pending actions</div>';
            actionItems = [];
        }
    } catch (error) {
        console.error('Failed to fetch action items:', error);
        content.innerHTML = '<div class="empty-state">Error loading actions</div>';
    }
}

/**
 * Render action items in the slide-out panel
 * @param {HTMLElement} container - Container element
 * @param {Array} items - Action items to render
 */
function renderActionItems(container, items) {
    container.innerHTML = items.map(item => {
        if (item.type === 'question') {
            return renderQuestionItem(item);
        } else if (item.type === 'split') {
            return renderSplitItem(item);
        }
        return '';
    }).join('');
    
    // Attach event handlers
    attachActionHandlers(container);
}

/**
 * Render a question action item
 * @param {Object} item - Question item
 * @returns {string} HTML string
 */
function renderQuestionItem(item) {
    const question = item.question || {};
    const options = question.options || [];
    const isMultiSelect = question.multi_select || false;
    const recommendation = question.recommendation || 'A';
    
    // Initialize selected answers for this task
    if (!selectedAnswers[item.task_id]) {
        selectedAnswers[item.task_id] = [];
    }
    
    return `
        <div class="action-item" data-task-id="${escapeHtml(item.task_id)}" data-type="question">
            <div class="action-item-header">
                <span class="action-item-type question">Question</span>
                <span class="action-item-task">${escapeHtml(item.task_name)}</span>
            </div>
            <div class="action-item-body">
                <div class="action-question-text">${escapeHtml(question.question || 'No question text')}</div>
                ${question.context ? `<div class="action-question-context">${escapeHtml(question.context)}</div>` : ''}
                
                ${isMultiSelect ? '<div class="multi-select-hint">Select one or more options</div>' : ''}
                
                <div class="answer-options" data-multi-select="${isMultiSelect}">
                    ${options.map(opt => `
                        <div class="answer-option${opt.key === recommendation ? ' recommended' : ''}" 
                             data-key="${escapeHtml(opt.key)}">
                            <span class="answer-key">${escapeHtml(opt.key)}</span>
                            <div class="answer-content">
                                <div class="answer-label">${escapeHtml(opt.label)}</div>
                                ${opt.rationale ? `<div class="answer-rationale">${escapeHtml(opt.rationale)}</div>` : ''}
                            </div>
                        </div>
                    `).join('')}
                </div>
                
                <div class="custom-answer-section">
                    <div class="custom-answer-label">Or provide custom response</div>
                    <textarea class="custom-answer-input" placeholder="Type a custom answer..."></textarea>
                </div>
                
                <div class="action-submit">
                    <button class="ctrl-btn primary submit-answer">Submit Answer</button>
                </div>
            </div>
        </div>
    `;
}

/**
 * Render a split approval action item
 * @param {Object} item - Split item
 * @returns {string} HTML string
 */
function renderSplitItem(item) {
    const proposal = item.split_proposal || {};
    const subTasks = proposal.sub_tasks || [];
    
    return `
        <div class="action-item" data-task-id="${escapeHtml(item.task_id)}" data-type="split">
            <div class="action-item-header">
                <span class="action-item-type split">Split Proposal</span>
                <span class="action-item-task">${escapeHtml(item.task_name)}</span>
            </div>
            <div class="action-item-body">
                ${proposal.reason ? `<div class="split-reason">${escapeHtml(proposal.reason)}</div>` : ''}
                
                <div class="split-tasks">
                    ${subTasks.map((task, idx) => `
                        <div class="split-task-item">
                            <span class="split-task-name">${idx + 1}. ${escapeHtml(task.name)}</span>
                            ${task.effort ? `<span class="split-task-effort">${escapeHtml(task.effort)}</span>` : ''}
                        </div>
                    `).join('')}
                </div>
                
                <div class="action-submit">
                    <button class="ctrl-btn reject-split">Reject</button>
                    <button class="ctrl-btn primary approve-split">Approve Split</button>
                </div>
            </div>
        </div>
    `;
}

/**
 * Attach event handlers to action items
 * @param {HTMLElement} container - Container element
 */
function attachActionHandlers(container) {
    // Answer option selection
    container.querySelectorAll('.answer-option').forEach(option => {
        option.addEventListener('click', (e) => {
            const optionsContainer = option.closest('.answer-options');
            const isMultiSelect = optionsContainer?.dataset.multiSelect === 'true';
            const taskId = option.closest('.action-item')?.dataset.taskId;
            const key = option.dataset.key;
            
            if (!taskId) return;
            
            if (isMultiSelect) {
                // Toggle selection
                option.classList.toggle('selected');
                if (option.classList.contains('selected')) {
                    if (!selectedAnswers[taskId]) selectedAnswers[taskId] = [];
                    if (!selectedAnswers[taskId].includes(key)) {
                        selectedAnswers[taskId].push(key);
                    }
                } else {
                    selectedAnswers[taskId] = selectedAnswers[taskId].filter(k => k !== key);
                }
            } else {
                // Single select - clear others
                optionsContainer?.querySelectorAll('.answer-option').forEach(opt => {
                    opt.classList.remove('selected');
                });
                option.classList.add('selected');
                selectedAnswers[taskId] = [key];
            }
        });
    });
    
    // Submit answer buttons
    container.querySelectorAll('.submit-answer').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            const actionItem = btn.closest('.action-item');
            const taskId = actionItem?.dataset.taskId;
            if (!taskId) return;
            
            const selected = selectedAnswers[taskId] || [];
            const customText = actionItem.querySelector('.custom-answer-input')?.value?.trim() || '';
            
            if (selected.length === 0 && !customText) {
                showToast('Please select an option or provide a custom answer', 'warning');
                return;
            }
            
            btn.disabled = true;
            btn.textContent = 'Submitting...';
            
            try {
                const response = await fetch(`${API_BASE}/api/task/answer`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        task_id: taskId,
                        answer: selected.length === 1 ? selected[0] : selected,
                        custom_text: customText || null
                    })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    // Remove the answered item from UI
                    actionItem.remove();
                    delete selectedAnswers[taskId];
                    
                    // Update widget count
                    const remaining = document.querySelectorAll('.action-item').length;
                    updateActionWidget(remaining);
                    
                    if (remaining === 0) {
                        document.getElementById('slideout-content').innerHTML = 
                            '<div class="empty-state">No pending actions</div>';
                    }
                    
                    // Trigger state refresh
                    if (typeof pollState === 'function') {
                        pollState();
                    }
                } else {
                    showToast('Failed to submit answer: ' + (result.error || 'Unknown error'), 'error');
                    btn.disabled = false;
                    btn.textContent = 'Submit Answer';
                }
            } catch (error) {
                console.error('Error submitting answer:', error);
                showToast('Error submitting answer', 'error');
                btn.disabled = false;
                btn.textContent = 'Submit Answer';
            }
        });
    });
    
    // Approve split buttons
    container.querySelectorAll('.approve-split').forEach(btn => {
        btn.addEventListener('click', () => handleSplitAction(btn, true));
    });
    
    // Reject split buttons
    container.querySelectorAll('.reject-split').forEach(btn => {
        btn.addEventListener('click', () => handleSplitAction(btn, false));
    });
}

/**
 * Handle split approval/rejection
 * @param {HTMLElement} btn - Button element
 * @param {boolean} approved - Whether approved or rejected
 */
/**
 * Initialize git commit button handler
 */
function initGitCommitButton() {
    const btn = document.getElementById('git-commit-btn');
    btn?.addEventListener('click', submitGitCommit);
}

/**
 * Update git commit button visibility based on git status
 * Called from notifications.js updateGitPanel when git status changes.
 * Also resets loading state when repo becomes clean (operation completed).
 * @param {boolean} isClean - Whether the repo is clean
 */
function updateGitCommitButton(isClean) {
    const actionDiv = document.getElementById('git-commit-action');
    const btn = document.getElementById('git-commit-btn');
    if (!actionDiv) return;

    if (isClean) {
        actionDiv.style.display = 'none';
        // Reset button state when repo is clean (commit completed successfully)
        if (btn) {
            btn.disabled = false;
            btn.classList.remove('loading');
        }
    } else {
        actionDiv.style.display = 'block';
    }
}

/**
 * Submit git commit-and-push request via Claude
 * Button remains disabled until git status polling detects repo is clean again.
 */
async function submitGitCommit() {
    const btn = document.getElementById('git-commit-btn');
    if (!btn || btn.disabled) return;

    // Set loading state - button stays disabled until git status shows clean
    btn.disabled = true;
    btn.classList.add('loading');

    try {
        const response = await fetch(`${API_BASE}/api/git/commit-and-push`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });

        const result = await response.json();

        if (result.success) {
            showSignalFeedback('Commit started. Claude is organizing and pushing changes...', 'success');
            // Poll git status more frequently for a while to pick up changes
            // Button will be re-enabled by updateGitCommitButton when repo becomes clean
            setTimeout(() => {
                if (typeof pollGitStatus === 'function') pollGitStatus();
            }, 5000);
            setTimeout(() => {
                if (typeof pollGitStatus === 'function') pollGitStatus();
            }, 15000);
            setTimeout(() => {
                if (typeof pollGitStatus === 'function') pollGitStatus();
            }, 30000);
        } else {
            showToast('Failed to start commit: ' + (result.error || 'Unknown error'), 'error');
            // Re-enable button on API error - operation didn't start
            btn.disabled = false;
            btn.classList.remove('loading');
        }
    } catch (error) {
        console.error('Error starting commit:', error);
        showToast('Error starting commit: ' + error.message, 'error');
        // Re-enable button on network/fetch error - operation didn't start
        btn.disabled = false;
        btn.classList.remove('loading');
    }
    // Note: No finally block that auto-re-enables. Button stays disabled until:
    // 1. Git status polling detects repo is clean (updateGitCommitButton resets state)
    // 2. An error occurred (handled in catch blocks above)
}

async function handleSplitAction(btn, approved) {
    const actionItem = btn.closest('.action-item');
    const taskId = actionItem?.dataset.taskId;
    if (!taskId) return;
    
    btn.disabled = true;
    btn.textContent = approved ? 'Approving...' : 'Rejecting...';
    
    try {
        const response = await fetch(`${API_BASE}/api/task/approve-split`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                task_id: taskId,
                approved: approved
            })
        });
        
        const result = await response.json();
        
        if (result.success) {
            // Remove the item from UI
            actionItem.remove();
            
            // Update widget count
            const remaining = document.querySelectorAll('.action-item').length;
            updateActionWidget(remaining);
            
            if (remaining === 0) {
                document.getElementById('slideout-content').innerHTML = 
                    '<div class="empty-state">No pending actions</div>';
            }
            
            // Trigger state refresh
            if (typeof pollState === 'function') {
                pollState();
            }
        } else {
            showToast('Failed to process split: ' + (result.error || 'Unknown error'), 'error');
            btn.disabled = false;
            btn.textContent = approved ? 'Approve Split' : 'Reject';
        }
    } catch (error) {
        console.error('Error processing split:', error);
        showToast('Error processing split', 'error');
        btn.disabled = false;
        btn.textContent = approved ? 'Approve Split' : 'Reject';
    }
}
