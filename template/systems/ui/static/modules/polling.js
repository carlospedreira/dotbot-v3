/**
 * DOTBOT Control Panel - Polling
 * State polling and activity streaming
 */

/**
 * Start polling for state and activity
 */
function startPolling() {
    // Start interval-based polling for state (non-blocking)
    pollState();
    setInterval(pollState, POLL_INTERVAL);

    // Start activity polling
    console.log('Starting activity polling...');
    pollActivity();
    activityTimer = setInterval(pollActivity, 2000);
}

/**
 * Poll server for current state
 */
async function pollState() {
    try {
        const response = await fetch(`${API_BASE}/api/state`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);

        const state = await response.json();
        lastPollTime = new Date();
        lastState = state;

        setConnectionStatus('connected');
        updateUI(state);

    } catch (error) {
        console.error('Poll error:', error);
        setConnectionStatus('error');
    }
}

/**
 * Poll server for activity events
 */
async function pollActivity() {
    try {
        // On initial load, request only last 12 lines from server
        let url = `${API_BASE}/api/activity/tail?position=${activityPosition}`;
        if (!activityInitialized) {
            url += '&tail=12';
        }
        const response = await fetch(url);
        if (!response.ok) return;

        const data = await response.json();

        // Always update position
        if (data.position !== undefined) {
            activityPosition = data.position;
        }

        // Process events if any
        if (data.events && data.events.length > 0) {
            if (!activityInitialized) {
                console.log('Activity: loaded last', data.events.length, 'events');
            } else {
                console.log('Activity:', data.events.length, 'new events');
            }
            activityInitialized = true;

            // Find latest text, rate_limit, and command for display
            let latestText = null;
            let latestRateLimit = null;
            let latestCmd = null;

            for (const event of data.events) {
                const eventType = (event.type || '').toLowerCase();
                if (eventType === 'text') {
                    latestText = event;
                    latestRateLimit = null;  // Clear rate limit when new text comes
                } else if (eventType === 'rate_limit') {
                    latestRateLimit = event;
                } else {
                    latestCmd = event;
                }

                // Send to oscilloscope
                if (activityScope) {
                    const scopeEvent = mapEventToScope(event);
                    activityScope.addEvent(scopeEvent);
                }
            }

            // Update displays with latest of each type
            // Rate limit takes precedence over text if it came after
            if (latestRateLimit) {
                updateTextDisplay(latestRateLimit, true);
            } else if (latestText) {
                updateTextDisplay(latestText, false);
            }
            if (latestCmd) {
                updateCommandDisplay(latestCmd);
            }
        }
    } catch (error) {
        console.error('Activity poll error:', error);
    }
}
