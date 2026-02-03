# .bot Web UI

A minimal, dependency-free PowerShell web server for monitoring and controlling `.bot` autonomous development.

## Features

- **CP/M-inspired terminal aesthetic** with Axiome Design amber accents
- **Real-time monitoring** via auto-polling (5-second intervals)
- **Task queue visualization** (TODO/In-Progress/Done)
- **Control signals** (Start/Stop/Pause/Resume) via file-based communication
- **Localhost-only** - no authentication needed
- **Zero dependencies** - pure PowerShell + vanilla HTML/CSS/JS

## Quick Start

```powershell
# Start the web server
cd .bot\ui
.\server.ps1

# Open in browser
# http://localhost:8686
```

The server will run on port 8686 by default.

## Architecture

### Hybrid Approach
- **Read-only monitoring**: Web UI reads `.bot` folder state directly from JSON files
- **Control signals**: UI sends commands via `.bot\.control\*.signal` files
- **Auto-polling**: Browser polls `/api/state` every 5 seconds for updates

### File Structure

```
.bot\
├── ui\
│   ├── server.ps1          # PowerShell HTTP server
│   ├── static\
│   │   ├── index.html      # Main UI
│   │   ├── style.css       # Terminal-inspired styling
│   │   └── app.js          # Polling & control logic
│   └── README.md
├── .control\               # Control signal directory (auto-created)
│   ├── start.signal
│   ├── stop.signal
│   ├── pause.signal
│   └── resume.signal
├── tasks\
│   ├── todo\
│   ├── in-progress\
│   └── done\
└── sessions\
```

## API Endpoints

### `GET /api/state`
Returns current .bot state as JSON:
```json
{
  "timestamp": "2026-01-14T18:00:00Z",
  "tasks": {
    "todo": 10,
    "in_progress": 1,
    "done": 42,
    "current": { /* current task details */ },
    "upcoming": [ /* next 10 tasks */ ],
    "recent_completed": [ /* last 10 completed */ ]
  },
  "session": {
    "session_id": "abc123...",
    "status": "running",
    "started_at": "2026-01-14T17:00:00Z",
    "tasks_completed": 5,
    "tasks_skipped": 0,
    "consecutive_failures": 0
  },
  "control": {
    "pause": false,
    "stop": false,
    "resume": false
  }
}
```

### `POST /api/control`
Send control signal:
```json
{
  "action": "pause"  // or "start", "stop", "resume"
}
```

Response:
```json
{
  "success": true,
  "action": "pause",
  "message": "Signal sent: pause"
}
```

## Control Flow

1. **Web UI** → Sends control action to `/api/control`
2. **Server** → Creates `.bot\.control\{action}.signal` file
3. **Autonomous loop** → Checks for signal files periodically (your implementation)
4. **Autonomous loop** → Acts on signal and removes file when processed

### Implementing Signal Handling

Add signal checking to your `run-autonomous-loop.ps1`:

```powershell
# At the start of your main loop
$controlDir = Join-Path $PSScriptRoot "..\.control"

# Check for control signals
$stopSignal = Join-Path $controlDir "stop.signal"
$pauseSignal = Join-Path $controlDir "pause.signal"

if (Test-Path $stopSignal) {
    Write-Host "Stop signal received" -ForegroundColor Yellow
    Remove-Item $stopSignal -Force
    break
}

if (Test-Path $pauseSignal) {
    Write-Host "Pause signal received - waiting..." -ForegroundColor Yellow
    Remove-Item $pauseSignal -Force
    
    # Wait for resume signal
    $resumeSignal = Join-Path $controlDir "resume.signal"
    while (-not (Test-Path $resumeSignal)) {
        Start-Sleep -Seconds 2
    }
    Remove-Item $resumeSignal -Force
    Write-Host "Resume signal received" -ForegroundColor Green
}
```

## Design System

Colors inspired by **Axiome Design** system:

- **Background**: `#1a1a1a` (deep, not pure black)
- **Text**: `#e8e8e8` (primary), `#999999` (secondary)
- **Accent**: `#d4a574` (warm amber - from Axiome)
- **Progress**: `#5fb3b3` (cyan)
- **Success**: `#8fbf7f` (green)
- **Danger**: `#d16969` (red)

Typography: Consolas/Courier New monospace

## Customization

### Change Port

```powershell
.\server.ps1 -Port 3000
```

### Adjust Polling Interval

Edit `static\app.js`:
```javascript
const POLL_INTERVAL = 3000; // 3 seconds instead of 5
```

### Add New Sections

The UI is designed to evolve into a multi-tab view. To add sections:

1. Add HTML section in `index.html`
2. Style in `style.css`
3. Add update function in `app.js` → `updateUI()`

## Future Evolution

Planned enhancements (path to multi-view dashboard):

- **Tab navigation** (Overview | Tasks | Session | History)
- **Session history viewer** (past sessions from `.bot\sessions\`)
- **Real-time logs** (stream from autonomous loop)
- **Task filtering** (by category, priority)
- **Statistics/charts** (completion rates, time per task)

## Troubleshooting

### Server won't start
- Check if port 8686 is already in use
- Try a different port: `.\server.ps1 -Port 8080`

### UI shows "No active session"
- Ensure `run-autonomous-loop.ps1` is running
- Check if `.bot\.dotbot-state.json` exists

### Control buttons don't work
- Verify `.bot\.control\` directory exists (auto-created by server)
- Implement signal handling in your autonomous loop

### Browser shows stale data
- Check browser console for fetch errors
- Verify server is running and accessible at `http://localhost:8686`

## License

Part of the .bot autonomous development system.
