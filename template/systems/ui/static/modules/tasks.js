/**
 * DOTBOT Control Panel - Task Modal
 * Task modal display and management
 */

/**
 * Initialize task click handlers
 */
function initTaskClicks() {
    // Current task click
    document.getElementById('current-task')?.addEventListener('click', (e) => {
        if (lastState?.tasks?.current) {
            showTaskModal(lastState.tasks.current);
        }
    });

    // Delegate for dynamic task lists
    document.addEventListener('click', (e) => {
        const taskItem = e.target.closest('.task-list-item, .pipeline-task');
        if (taskItem && taskItem.dataset.taskId) {
            const task = findTaskById(taskItem.dataset.taskId);
            if (task) {
                showTaskModal(task);
            }
        }
    });
}

/**
 * Find task by ID in the current state
 * @param {string} id - Task ID
 * @returns {Object|null} Task object or null
 */
function findTaskById(id) {
    if (!lastState?.tasks) return null;

    if (lastState.tasks.current?.id === id) return lastState.tasks.current;

    const upcoming = lastState.tasks.upcoming?.find(t => t.id === id);
    if (upcoming) return upcoming;

    const completed = lastState.tasks.recent_completed?.find(t => t.id === id);
    if (completed) return completed;

    return null;
}

/**
 * Show task details modal
 * @param {Object} task - Task object to display
 */
function showTaskModal(task) {
    const modal = document.getElementById('task-modal');
    const titleEl = document.getElementById('modal-task-name');
    const contentEl = document.getElementById('modal-task-content');

    if (!modal || !task) return;

    titleEl.textContent = task.name || task.id || 'Task Details';

    let html = `
        <div class="task-detail-id">${escapeHtml(task.id || '')}</div>
        <div class="task-detail-name">${escapeHtml(task.name || task.id || 'Unknown')}</div>
    `;

    if (task.description) {
        html += `<div class="task-detail-description">${escapeHtml(task.description)}</div>`;
    }

    html += `
        <div class="task-detail-meta">
            ${task.status ? `<div class="meta-item"><span class="meta-label">Status:</span><span class="meta-value status-${escapeHtml(task.status)}">${escapeHtml(task.status)}</span></div>` : ''}
            ${task.category ? `<div class="meta-item"><span class="meta-label">Category:</span><span class="meta-value">${escapeHtml(task.category)}</span></div>` : ''}
            ${task.priority ? `<div class="meta-item"><span class="meta-label">Priority:</span><span class="meta-value">${escapeHtml(String(task.priority))}</span></div>` : ''}
            ${task.effort ? `<div class="meta-item"><span class="meta-label">Effort:</span><span class="meta-value">${escapeHtml(task.effort)}</span></div>` : ''}
        </div>
    `;

    // Dates section
    const dates = [];
    if (task.created_at) dates.push(`<div class="meta-item"><span class="meta-label">Created:</span><span class="meta-value">${formatCompactDate(task.created_at)}</span></div>`);
    if (task.started_at) dates.push(`<div class="meta-item"><span class="meta-label">Started:</span><span class="meta-value">${formatCompactDate(task.started_at)}</span></div>`);
    if (task.completed_at) dates.push(`<div class="meta-item"><span class="meta-label">Completed:</span><span class="meta-value">${formatCompactDate(task.completed_at)}</span></div>`);
    if (task.updated_at) dates.push(`<div class="meta-item"><span class="meta-label">Updated:</span><span class="meta-value">${formatCompactDate(task.updated_at)}</span></div>`);

    if (dates.length > 0) {
        html += `<div class="task-detail-meta task-detail-dates">${dates.join('')}</div>`;
    }

    // Steps section
    if (task.steps && task.steps.length > 0) {
        html += `
            <div class="task-detail-section">
                <div class="section-title">Steps</div>
                <ol class="task-steps-list">
                    ${task.steps.map(s => `<li>${escapeHtml(s)}</li>`).join('')}
                </ol>
            </div>
        `;
    }

    // Acceptance criteria section
    if (task.acceptance_criteria && task.acceptance_criteria.length > 0) {
        html += `
            <div class="task-detail-section">
                <div class="section-title">Acceptance Criteria</div>
                <ul class="criteria-list">
                    ${task.acceptance_criteria.map(c => `<li>${escapeHtml(c)}</li>`).join('')}
                </ul>
            </div>
        `;
    }

    // Dependencies section
    if (Array.isArray(task.dependencies) && task.dependencies.length > 0) {
        html += `
            <div class="task-detail-section">
                <div class="section-title">Dependencies</div>
                <ul class="dependencies-list">
                    ${task.dependencies.map(d => `<li>${escapeHtml(d)}</li>`).join('')}
                </ul>
            </div>
        `;
    }

    // Applicable agents/standards section
    const references = [];
    if (task.applicable_agents) {
        const agents = Array.isArray(task.applicable_agents) ? task.applicable_agents : [task.applicable_agents];
        agents.forEach(a => references.push(`<span class="ref-tag agent">${escapeHtml(a)}</span>`));
    }
    if (Array.isArray(task.applicable_standards) && task.applicable_standards.length > 0) {
        task.applicable_standards.forEach(s => references.push(`<span class="ref-tag standard">${escapeHtml(s)}</span>`));
    }

    if (references.length > 0) {
        html += `
            <div class="task-detail-section">
                <div class="section-title">References</div>
                <div class="task-references">${references.join('')}</div>
            </div>
        `;
    }

    // Plan Link Section
    if (task.plan_path) {
        html += `<div class="task-detail-section">`;
        html += `<div class="section-title">Implementation Plan</div>`;
        html += `<div class="task-plan-actions">`;
        html += `<button class="ctrl-btn primary" onclick="showPlanModal('${escapeHtml(task.id)}')">`;
        html += `<span class="btn-icon">&#128203;</span> View Plan`;
        html += `</button>`;
        html += `</div>`;
        html += `</div>`;
    }

    // Commits & Changes section (for completed tasks)
    if (task.commit_sha || task.commits) {
        html += `<div class="task-detail-section">`;
        html += `<div class="section-title">Commits & Changes</div>`;

        // Show commits if available
        const commits = task.commits || (task.commit_sha ? [{
            commit_sha: task.commit_sha,
            commit_subject: task.commit_subject,
            files_created: task.files_created,
            files_modified: task.files_modified,
            files_deleted: task.files_deleted
        }] : []);

        commits.forEach((commit, idx) => {
            html += `<div class="commit-entry${idx > 0 ? ' commit-subsequent' : ''}">`;
            html += `<div class="commit-header">`;
            html += `<span class="commit-sha">${escapeHtml(commit.commit_sha?.substring(0, 8) || '')}</span>`;
            html += `<span class="commit-subject">${escapeHtml(commit.commit_subject || '')}</span>`;
            html += `</div>`;

            // File changes
            const hasChanges = (commit.files_created?.length || 0) +
                              (commit.files_modified?.length || 0) +
                              (commit.files_deleted?.length || 0) > 0;

            if (hasChanges) {
                html += `<div class="commit-files">`;
                if (commit.files_created?.length) {
                    commit.files_created.forEach(f => {
                        html += `<div class="file-entry file-created"><span class="file-badge">A</span>${escapeHtml(f)}</div>`;
                    });
                }
                if (commit.files_modified?.length) {
                    commit.files_modified.forEach(f => {
                        html += `<div class="file-entry file-modified"><span class="file-badge">M</span>${escapeHtml(f)}</div>`;
                    });
                }
                if (commit.files_deleted?.length) {
                    commit.files_deleted.forEach(f => {
                        html += `<div class="file-entry file-deleted"><span class="file-badge">D</span>${escapeHtml(f)}</div>`;
                    });
                }
                html += `</div>`;
            }
            html += `</div>`;
        });

        html += `</div>`;
    }

    // Agent Activity section (for completed tasks with activity logs)
    if (task.activity_log && task.activity_log.length > 0) {
        html += `<div class="task-detail-section">`;
        html += `<div class="section-title">Agent Activity</div>`;
        html += `<div class="activity-log">`;

        task.activity_log.forEach(entry => {
            const typeClass = getActivityTypeClass(entry.type);
            const icon = getActivityIcon(entry.type);
            const time = entry.timestamp ? formatCompactTime(entry.timestamp) : '';

            html += `<div class="activity-entry ${typeClass}">`;
            html += `<span class="activity-icon">${icon}</span>`;
            html += `<span class="activity-type">${escapeHtml(entry.type)}</span>`;
            if (entry.message) {
                html += `<span class="activity-message">${escapeHtml(truncateMessage(entry.message, 80))}</span>`;
            }
            if (time) {
                html += `<span class="activity-time">${time}</span>`;
            }
            html += `</div>`;
        });

        html += `</div>`;
        html += `</div>`;
    }

    contentEl.innerHTML = html;
    modal.classList.add('visible');
}

/**
 * Initialize modal close handlers
 */
function initModalClose() {
    const modal = document.getElementById('task-modal');
    const closeBtn = document.getElementById('modal-close');

    closeBtn?.addEventListener('click', () => {
        modal?.classList.remove('visible');
    });

    modal?.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.classList.remove('visible');
        }
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            modal?.classList.remove('visible');
            document.getElementById('plan-modal')?.classList.remove('visible');
        }
    });

    // Initialize plan modal close handlers
    initPlanModalClose();
}

/**
 * Show plan in modal with markdown rendering
 * @param {string} taskId - The task ID to show the plan for
 */
async function showPlanModal(taskId) {
    const planModal = document.getElementById('plan-modal');
    const contentEl = document.getElementById('plan-modal-content');
    const titleEl = document.getElementById('plan-modal-title');

    if (!planModal || !contentEl || !titleEl) return;

    // Show loading state
    contentEl.innerHTML = '<div class="loading-state">Loading plan...</div>';
    planModal.classList.add('visible');

    // Fetch plan content via API endpoint
    try {
        const response = await fetch(`/api/plan/${taskId}`);
        const data = await response.json();

        if (data.has_plan) {
            titleEl.textContent = `Plan: ${data.task_name}`;
            // Use existing markdown renderer if available, otherwise show raw
            if (typeof markdownToHtml === 'function') {
                contentEl.innerHTML = markdownToHtml(data.content);
                // Render any Mermaid diagrams
                if (typeof renderMermaidDiagrams === 'function') {
                    renderMermaidDiagrams(contentEl);
                }
            } else {
                contentEl.innerHTML = `<pre>${escapeHtml(data.content)}</pre>`;
            }
        } else {
            contentEl.innerHTML = '<p class="no-plan">No plan found for this task.</p>';
        }
    } catch (err) {
        contentEl.innerHTML = `<p class="error">Error loading plan: ${escapeHtml(err.message)}</p>`;
    }
}

/**
 * Initialize plan modal close handlers
 */
function initPlanModalClose() {
    const modal = document.getElementById('plan-modal');
    const closeBtn = document.getElementById('plan-modal-close');
    const backBtn = document.getElementById('plan-modal-back');

    closeBtn?.addEventListener('click', () => modal?.classList.remove('visible'));
    backBtn?.addEventListener('click', () => modal?.classList.remove('visible'));

    modal?.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.classList.remove('visible');
        }
    });
}
