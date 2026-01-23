# 🤖 .bot - Autonomous Development System

## Overview

A self-contained autonomous development system with MCP server, web UI, and Claude CLI integration. Designed for TDD-focused workflow with task-based development.

## Quick Start

```powershell
# Start the web UI
.bot\go.ps1

# Opens browser at http://localhost:8686
```

## Architecture

```
.bot/
├── systems/              # Core infrastructure
│   ├── mcp/              # MCP server (task/session tools)
│   ├── ui/               # Web UI server (port 8686)
│   └── runtime/          # Autonomous execution loop
├── prompts/              # AI prompt definitions
│   ├── agents/           # Specialized AI personas
│   ├── skills/           # Reusable capabilities
│   └── workflows/        # Step-by-step processes
├── state/                # Runtime state (gitignored contents)
│   ├── tasks/            # Task queue (todo/in-progress/done)
│   ├── sessions/         # Session tracking
│   └── product/          # Product documentation
├── hooks/                # Project-specific scripts
│   ├── dev/              # Development helpers
│   ├── scripts/          # Utility scripts
│   └── verify/           # Verification hooks
├── defaults/             # Default configurations
├── init.ps1              # Claude Code integration setup
└── go.ps1                # Launch UI server
```

## MCP Tools

The MCP server (`systems/mcp/dotbot-mcp.ps1`) provides these tools:

### Task Management
- `task_create` - Create a new task
- `task_create_bulk` - Batch create tasks
- `task_get_next` - Get highest priority task
- `task_get_stats` - Overall progress statistics
- `task_list` - List and filter tasks
- `task_mark_in_progress` - Mark task as in-progress
- `task_mark_done` - Mark task as complete
- `task_mark_skipped` - Mark task as skipped
- `task_mark_todo` - Reset task to todo

### Session Management
- `session_initialize` - Start new session
- `session_get_state` - Get current session state
- `session_get_stats` - Get session statistics
- `session_update` - Update session state
- `session_increment_completed` - Increment completed count

### Development
- `dev_start` - Start development environment
- `dev_stop` - Stop development environment

## Web UI

The web UI (`systems/ui/server.ps1`) provides:

- **Real-time task monitoring** - View current, upcoming, and completed tasks
- **Session tracking** - Monitor autonomous session progress
- **Control signals** - Start, pause, stop autonomous loop
- **Activity log** - View real-time activity stream

Access at: `http://localhost:8686`

## Autonomous Loop

The runtime (`systems/runtime/run-loop.ps1`) executes tasks autonomously:

```powershell
# Start autonomous execution
.bot\systems\runtime\run-loop.ps1

# With options
.bot\systems\runtime\run-loop.ps1 -MaxTasks 10 -Model Sonnet
```

### Options
- `-MaxTasks` - Maximum tasks to process (default: unlimited)
- `-AutoContinueDelay` - Seconds between tasks (default: 3)
- `-MaxRetriesPerTask` - Retry attempts per task (default: 2)
- `-Model` - Claude model: Opus, Sonnet, Haiku (default: Opus)
- `-ShowDebug` - Show raw JSON events
- `-ShowVerbose` - Show detailed output

## Task Structure

Tasks are JSON files in `state/tasks/`:

```json
{
  "id": "uuid-here",
  "name": "User Authentication",
  "description": "Implement user auth with JWT",
  "category": "core",
  "priority": 1,
  "effort": "L",
  "status": "todo",
  "acceptance_criteria": [
    "Users can register with email",
    "Passwords are securely hashed"
  ],
  "steps": [
    "Create user database schema",
    "Implement registration endpoint"
  ]
}
```

## Prompts

### Agents (`prompts/agents/`)
Specialized AI personas for different tasks:
- **implementer** - Writes production code
- **planner** - Creates product plans
- **reviewer** - Reviews code changes
- **tester** - Writes tests

### Skills (`prompts/skills/`)
Reusable capabilities:
- **implement-api-endpoint** - REST API implementation
- **create-migration** - Database migrations
- **write-unit-tests** - Test writing

### Workflows (`prompts/workflows/`)
Step-by-step processes:
- **01-plan-product** - Product planning
- **03-plan-roadmap** - Roadmap creation
- **04-new-tasks** - Task creation
- **99-autonomous-task** - Autonomous execution

## Claude Code Integration

Run `init.ps1` to set up Claude Code integration:

```powershell
.bot\init.ps1
```

This copies agents and skills to `.claude/` for Claude Code to discover.

## Hooks

Project-specific scripts in `hooks/`:

- `dev/Start-Dev.ps1` - Start development environment
- `dev/Stop-Dev.ps1` - Stop development environment
- `verify/*.ps1` - Verification scripts (git clean, build, format)
- `scripts/*.ps1` - Utility scripts

## Configuration

### Default Settings (`defaults/`)
- `settings.default.json` - Default application settings
- `theme.default.json` - UI theme configuration

### User Settings
User preferences are stored in `profile/` (gitignored).

## File Watching

The system uses file watchers for real-time updates:
- Task file changes trigger UI updates
- Control signals are detected immediately
- Session state changes are reflected in real-time
