# Cowork - Isolated Development Sessions with Devcontainers

A single bash script that manages isolated development sessions using devcontainers and full git clones. Work on multiple features simultaneously in completely isolated environments, each with its own devcontainer instance.

## What It Does

- Creates isolated development sessions with full git clones
- Uses devcontainers for standardized development environments
- Manages Claude authentication centrally (login once, use everywhere)
- Supports persistent terminal sessions with tmux or zellij
- Respects existing `.devcontainer/devcontainer.json` files in your projects
- No complex syncing - code lives directly in cloned directories
- First-run setup wizard for user preferences
- Colored output with clear status indicators

## Requirements

- Git
- Docker
- Bash
- Node.js and npm
- Devcontainer CLI: `npm install -g @devcontainers/cli`

## Installation

```bash
# Download and make executable
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/cowork/main/cowork.sh
chmod +x cowork.sh

# Optionally copy to PATH
sudo cp cowork.sh /usr/local/bin/cowork
```

## Quick Start

```bash
# One-time authentication
cowork auth

# Go to your project
cd /path/to/your/project

# Create sessions (these become git branches)
cowork init feature-backend feature-frontend bugfix-auth

# Work in a session
cowork connect feature-backend
```

## Commands

### `cowork auth`
Authenticate with Claude (one-time setup). Opens a browser for login, then saves credentials for all sessions to use.

### `cowork init <session-names...>`
Create new sessions. Each session gets a full clone of your repository and its own devcontainer.
```bash
cowork init feature-auth feature-payments bugfix-ui
```

### `cowork list`
Show all sessions with their status, current branch, and last modified time.

### `cowork connect <session> [options]`
Connect to a session's devcontainer. Starts the container if stopped.

Options:
- `--tmux` - Force use of tmux for persistent sessions
- `--zellij` - Force use of zellij for persistent sessions  
- `--none` - Connect without a terminal multiplexer

```bash
cowork connect feature-auth              # Uses your configured preference
cowork connect feature-auth --tmux       # Override to use tmux
cowork connect feature-auth --none       # Direct shell connection
```


### `cowork status`
Show comprehensive status including:
- Project information and configuration
- Authentication status and validity
- Docker and DevContainer CLI status
- All sessions with their current state

### `cowork stop`
Stop all running devcontainers.

### `cowork clean`
Remove all containers and session directories (prompts for confirmation).

## How It Works

1. **First Run Setup**: On first use, cowork will:
   - Create necessary directories (`~/.cowork/`)
   - Ask for your terminal multiplexer preference (tmux, zellij, or none)
   - Save your preferences for all future sessions

2. **Authentication**: When you run `cowork auth`, it:
   - Checks for existing Claude credentials in common locations
   - Starts a temporary devcontainer if needed for fresh login
   - Saves credentials to `~/.cowork/auth/` and mounts into all sessions
   - Validates authentication age and warns if expired

3. **Sessions**: Each session you create with `cowork init`:
   - Creates a full clone of your repository
   - Creates a new git branch (or uses existing one)
   - Stores the clone at `~/.cowork/sessions/{project}-{session}/`
   - Gets its own devcontainer instance
   - Supports persistent terminal sessions with multiplexers

4. **Working**: When you `cowork connect`:
   - Starts or attaches to the session's devcontainer
   - Automatically installs your preferred multiplexer if needed
   - Reconnects to existing multiplexer sessions or creates new ones
   - Your code is directly in the cloned directory
   - No syncing needed - changes are immediate

5. **Devcontainer Support**:
   - If your project has `.devcontainer/devcontainer.json`, it's used as-is
   - If not, cowork offers to create a comprehensive default with:
     - Universal development image with multiple languages
     - Git, GitHub CLI, Node.js, Python, Docker-in-Docker
     - Claude CLI pre-installed
     - VS Code extensions and settings
     - Proper auth, SSH, and git config mounts
   - Can automatically add auth mount to existing configurations

## File Locations

- **Auth**: `~/.cowork/auth/`
- **Sessions**: `~/.cowork/sessions/{project}-{session}/`
- **User Config**: `~/.cowork/.cowork.conf`
- **Project Config**: `<project>/.cowork/.cowork.conf`
- **Devcontainer**: `<session>/.devcontainer/devcontainer.json`

## Devcontainer Support

### Using Existing devcontainer.json

If your project already has a `.devcontainer/devcontainer.json`, cowork respects it. You'll need to add the auth mount manually:

```json
"mounts": [
    {
        "source": "${localEnv:HOME}/.cowork/auth",
        "target": "/home/vscode/.claude",
        "type": "bind",
        "consistency": "cached"
    }
]
```

### Default Environment

If no devcontainer.json exists, cowork can create one with:
- Universal development image (mcr.microsoft.com/devcontainers/universal:2-linux)
- Git, GitHub CLI, Docker-in-Docker
- Node.js LTS, Python, common development tools
- Claude CLI pre-installed
- VS Code extensions (Docker, Python, ESLint, Prettier)
- Auth mount configured
- SSH and git config mounts
- Zsh with Oh My Zsh as default shell

## Working with Git

Since each session is a full clone, git operations work normally:

```bash
# Inside the devcontainer
git add .
git commit -m "Your changes"
git push origin <session-name>
```

Or work directly in the session directory:
```bash
cd ~/.cowork/sessions/{project}-{session}/
git status
```

## Common Issues

### Can't authenticate
```bash
# Check existing auth
ls -la ~/.cowork/auth/

# Re-authenticate
cowork auth
```

### Container won't start
```bash
# Check devcontainer logs
cd ~/.cowork/sessions/{project}-{session}/
devcontainer up --workspace-folder .

# Check Docker
docker ps -a
```

### Devcontainer CLI not found
```bash
npm install -g @devcontainers/cli
```

## Features

### Terminal Multiplexer Support
Cowork supports persistent terminal sessions that survive disconnections:
- **tmux** - Widely supported, traditional multiplexer
- **zellij** - Modern alternative with better UX
- **none** - Direct shell connection without persistence

Your preference is saved and used for all sessions. You can override per-connection with `--tmux`, `--zellij`, or `--none`.

### Automatic Authentication Detection
Cowork checks for existing Claude credentials in common locations:
- `~/.credentials.json`
- `~/.claude/credentials.json`
- `~/.anthropic/credentials.json`
- `~/.claude.json`

### Smart DevContainer Integration
- Respects existing `.devcontainer/devcontainer.json` files
- Offers to add auth mount to existing configurations
- Can create feature-rich default configuration
- Supports automatic or manual configuration updates

### Visual Status Indicators
- ✅ Success messages in green
- ⚠️ Warnings in yellow  
- ❌ Errors in red with helpful tips
- ℹ️ Info messages in blue

## Tips

- Each session is a complete, isolated clone of your repository
- Sessions persist - use `cowork connect` to resume work anytime
- Terminal multiplexer sessions survive disconnections
- Your existing devcontainer.json is respected - add the auth mount for Claude
- No syncing needed - work directly in the cloned directories
- Use `cowork list` to see all sessions and their status
- Run `cowork status` for comprehensive system information
