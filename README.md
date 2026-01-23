# dotbot-v3

**Autonomous development system with MCP server, web UI, and Claude CLI integration.**

## Quick Start

### 1. Install dotbot globally (one-time)

```powershell
git clone https://github.com/andresharpe/dotbot-v3 ~/dotbot
cd ~/dotbot
./install.ps1
```

After installation, restart your terminal.

### 2. Add dotbot to your project

```powershell
cd your-project
dotbot init
```

This creates a `.bot/` directory with:
- MCP server for task management
- Web UI for monitoring (port 8686)
- Autonomous loop for Claude CLI
- Agents, skills, and workflows

### 3. Start the UI

```powershell
.bot/go.ps1
```

## Prerequisites

- **PowerShell 7+** - [Download](https://aka.ms/powershell)
- **Claude CLI** - For autonomous mode
- **Git** - For installation

## Commands

```powershell
dotbot help          # Show all commands
dotbot status        # Check installation status
dotbot init          # Add dotbot to current project
dotbot update        # Update global installation
```

## Architecture

```
.bot/
├── systems/          # Core systems
│   ├── mcp/          # MCP server (task/session tools)
│   ├── ui/           # Web UI server
│   └── runtime/      # Autonomous loop
├── prompts/          # AI prompts
│   ├── agents/       # Specialized AI personas
│   ├── skills/       # Reusable capabilities
│   └── workflows/    # Step-by-step processes
├── state/            # Runtime state
│   ├── tasks/        # Task queue (todo/in-progress/done)
│   ├── sessions/     # Session tracking
│   └── product/      # Product documentation
├── hooks/            # Project-specific scripts
├── init.ps1          # Claude Code integration setup
└── go.ps1            # Launch UI server
```

## License

MIT
