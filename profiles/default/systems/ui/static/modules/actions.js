/**
 * DOTBOT Control Panel - Actions Module
 * Handles action-required items: questions and split approvals
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
        }
    });
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
                alert('Please select an option or provide a custom answer');
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
                    alert('Failed to submit answer: ' + (result.error || 'Unknown error'));
                    btn.disabled = false;
                    btn.textContent = 'Submit Answer';
                }
            } catch (error) {
                console.error('Error submitting answer:', error);
                alert('Error submitting answer');
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
            alert('Failed to process split: ' + (result.error || 'Unknown error'));
            btn.disabled = false;
            btn.textContent = approved ? 'Approve Split' : 'Reject';
        }
    } catch (error) {
        console.error('Error processing split:', error);
        alert('Error processing split');
        btn.disabled = false;
        btn.textContent = approved ? 'Approve Split' : 'Reject';
    }
}
