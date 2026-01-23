/**
 * DOTBOT Control Panel - Utility Functions
 * Generic utility functions used across modules
 */

/**
 * Escape HTML special characters to prevent XSS
 * @param {string} text - Text to escape
 * @returns {string} Escaped text
 */
function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

/**
 * Set text content of element by ID
 * @param {string} id - Element ID
 * @param {string|number} text - Text to set
 */
function setElementText(id, text) {
    const el = document.getElementById(id);
    if (el) el.textContent = text;
}

/**
 * Format ISO date string to compact display format
 * @param {string} isoString - ISO date string
 * @returns {string} Formatted date like "Jan 15 14:30"
 */
function formatCompactDate(isoString) {
    if (!isoString) return '';
    try {
        const date = new Date(isoString);
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const month = months[date.getMonth()];
        const day = date.getDate();
        const hours = date.getHours().toString().padStart(2, '0');
        const mins = date.getMinutes().toString().padStart(2, '0');
        return `${month} ${day} ${hours}:${mins}`;
    } catch (e) {
        return '';
    }
}

/**
 * Format ISO date string to time only
 * @param {string} isoString - ISO date string
 * @returns {string} Formatted time like "14:30:45"
 */
function formatCompactTime(isoString) {
    if (!isoString) return '';
    try {
        const date = new Date(isoString);
        const hours = date.getHours().toString().padStart(2, '0');
        const mins = date.getMinutes().toString().padStart(2, '0');
        const secs = date.getSeconds().toString().padStart(2, '0');
        return `${hours}:${mins}:${secs}`;
    } catch (e) {
        return '';
    }
}

/**
 * Truncate a message to max length with ellipsis
 * @param {string} message - Message to truncate
 * @param {number} maxLen - Maximum length
 * @returns {string} Truncated message
 */
function truncateMessage(message, maxLen) {
    if (!message) return '';
    if (message.length <= maxLen) return message;
    return message.substring(0, maxLen) + '…';
}

/**
 * Get CSS class for activity type
 * @param {string} type - Activity type
 * @returns {string} CSS class name
 */
function getActivityTypeClass(type) {
    if (!type) return 'activity-other';
    const t = type.toLowerCase();
    if (t === 'read') return 'activity-read';
    if (t === 'write') return 'activity-write';
    if (t === 'edit') return 'activity-edit';
    if (t === 'bash') return 'activity-bash';
    if (t === 'glob' || t === 'grep') return 'activity-search';
    if (t === 'text') return 'activity-text';
    if (t === 'done') return 'activity-done';
    if (t === 'init') return 'activity-init';
    if (t.startsWith('mcp__')) return 'activity-mcp';
    return 'activity-other';
}

/**
 * Get icon for activity type
 * @param {string} type - Activity type
 * @returns {string} Icon character
 */
function getActivityIcon(type) {
    if (!type) return '•';
    const t = type.toLowerCase();
    if (t === 'read') return '◇';
    if (t === 'write') return '◆';
    if (t === 'edit') return '✎';
    if (t === 'bash') return '▶';
    if (t === 'glob' || t === 'grep') return '⌕';
    if (t === 'text') return '¶';
    if (t === 'done') return '✓';
    if (t === 'init') return '⚡';
    if (t.startsWith('mcp__')) return '⚙';
    return '•';
}

/**
 * Format duration between two ISO date strings
 * @param {string} startIso - Start ISO date string
 * @param {string} endIso - End ISO date string
 * @returns {string} Formatted duration like "2h 15m" or "1d 4h"
 */
function formatDuration(startIso, endIso) {
    if (!startIso || !endIso) return '';
    try {
        const start = new Date(startIso);
        const end = new Date(endIso);
        const diffMs = end - start;
        if (diffMs < 0) return '';

        const mins = Math.floor(diffMs / 60000);
        const hours = Math.floor(mins / 60);
        const days = Math.floor(hours / 24);

        if (days > 0) {
            const remainingHours = hours % 24;
            return remainingHours > 0 ? `${days}d ${remainingHours}h` : `${days}d`;
        }
        if (hours > 0) {
            const remainingMins = mins % 60;
            return remainingMins > 0 ? `${hours}h ${remainingMins}m` : `${hours}h`;
        }
        return `${mins}m`;
    } catch (e) {
        return '';
    }
}
