#!/usr/bin/env bash
set -euo pipefail

# cowork - Isolated development sessions using devcontainers and full clones
# Single-file bash CLI for managing devcontainer-based development environments

# Cleanup handler
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo -e "\n${RED}Script interrupted or failed${NC}" >&2
    fi
    # Add any cleanup tasks here if needed
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
COWORK_DIR="$HOME/.cowork"
AUTH_DIR="$COWORK_DIR/auth"
SESSIONS_DIR="$COWORK_DIR/sessions"
USER_CONFIG="$COWORK_DIR/.cowork.conf"
PROJECT_CONFIG=""
PROJECT_NAME=""
PROJECT_SAFE=""
PROJECT_HASH=""
ORIGIN_URL=""

# Error handling
error() {
    echo -e "${RED}L ERROR: $1${NC}" >&2
    [[ -n "${2:-}" ]] && echo -e "  =� TIP: $2" >&2
    exit 1
}

info() {
    echo -e "${BLUE}9  $1${NC}"
}

success() {
    echo -e "${GREEN} $1${NC}"
}

warning() {
    echo -e "${YELLOW}�  $1${NC}"
}

# Phase 0: Compatibility Layer - Auth file detection
find_auth_files() {
    # Check multiple possible locations for auth files
    local auth_paths=(
        "$HOME/.credentials.json"
        "$HOME/.claude/credentials.json"
        "$HOME/.anthropic/credentials.json"
        "$HOME/.claude.json"
    )
    
    for path in "${auth_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    # Also check if .claude directory exists with any auth files
    if [[ -d "$HOME/.claude" ]]; then
        if find "$HOME/.claude" -name "*.json" -type f | head -1 | grep -q .; then
            echo "$HOME/.claude"
            return 0
        fi
    fi
    
    return 1
}

# Auth validation helper
validate_auth() {
    local auth_path="$1"
    
    # Check if path exists
    if [[ ! -e "$auth_path" ]]; then
        return 1
    fi
    
    # If it's a directory, check for credential files inside
    if [[ -d "$auth_path" ]]; then
        if ! find "$auth_path" -name "*.json" -type f | head -1 | grep -q .; then
            return 1
        fi
    else
        # It's a file, check size
        local size
        if [[ "$(uname)" == "Darwin" ]]; then
            size=$(stat -f%z "$auth_path" 2>/dev/null || echo 0)
        else
            size=$(stat -c%s "$auth_path" 2>/dev/null || echo 0)
        fi
        
        if [[ "$size" -lt 100 ]]; then
            return 1
        fi
    fi
    
    # Check modification time (warn if older than 30 days)
    if ! find "$auth_path" -mtime -30 -print 2>/dev/null | grep -q .; then
        warning "Authentication may be expired (older than 30 days)"
    fi
    
    return 0
}

# Phase 1: Configuration Management
# Project name sanitization
sanitize_project_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/^-*//' | sed 's/-*$//'
}

# Initialize cowork directories
init_cowork_dirs() {
    mkdir -p "$COWORK_DIR"
    mkdir -p "$AUTH_DIR"
    mkdir -p "$SESSIONS_DIR"
    
    # Create user config if it doesn't exist
    if [[ ! -f "$USER_CONFIG" ]]; then
        touch "$USER_CONFIG"
    fi
}

# First-run setup
first_run_setup() {
    info "Welcome to Cowork! Let's set up your preferences."
    echo ""
    
    # Check if multiplexer preference is already set
    if [[ -n "${MULTIPLEXER_PREFERENCE:-}" ]]; then
        return 0
    fi
    
    echo "Cowork can use terminal multiplexers for persistent sessions that survive disconnections."
    echo "This means your work continues even if your connection drops!"
    echo ""
    echo "Which terminal multiplexer would you prefer?"
    echo "  1) tmux (recommended - widely supported)"
    echo "  2) zellij (modern alternative with better UX)"
    echo "  3) none (direct shell connection)"
    echo ""
    echo -n "Enter your choice [1-3] (default: 1): "
    read -r choice
    
    case "${choice:-1}" in
        1)
            MULTIPLEXER_PREFERENCE="tmux"
            success "Set preference to tmux"
            ;;
        2)
            MULTIPLEXER_PREFERENCE="zellij"
            success "Set preference to zellij"
            ;;
        3)
            MULTIPLEXER_PREFERENCE="none"
            success "Set preference to no multiplexer"
            ;;
        *)
            MULTIPLEXER_PREFERENCE="tmux"
            info "Invalid choice, defaulting to tmux"
            ;;
    esac
    
    # Save preference to user config
    {
        if grep -q "^MULTIPLEXER_PREFERENCE=" "$USER_CONFIG" 2>/dev/null; then
            # Update existing preference
            sed -i.bak "s/^MULTIPLEXER_PREFERENCE=.*/MULTIPLEXER_PREFERENCE=\"$MULTIPLEXER_PREFERENCE\"/" "$USER_CONFIG"
            rm -f "${USER_CONFIG}.bak"
        else
            # Add new preference
            echo "MULTIPLEXER_PREFERENCE=\"$MULTIPLEXER_PREFERENCE\"" >> "$USER_CONFIG"
        fi
    }
    
    echo ""
    info "Setup complete! Your preferences have been saved."
    echo ""
}

# Load configuration (user and project level)
load_config() {
    # Initialize SESSIONS array if not already defined
    if [[ -z "${SESSIONS+x}" ]]; then
        SESSIONS=()
    fi
    
    # Always source user config first
    if [[ -f "$USER_CONFIG" ]]; then
        source "$USER_CONFIG"
    fi
    
    # Then override with project config if it exists
    if [[ -n "$PROJECT_CONFIG" ]] && [[ -f "$PROJECT_CONFIG" ]]; then
        source "$PROJECT_CONFIG"
    fi
}

# Save configuration
save_config() {
    local config_file="${1:-$PROJECT_CONFIG}"
    local temp_file="${config_file}.tmp"
    
    [[ -z "$config_file" ]] && error "No config file specified"
    
    # Create directory if needed
    mkdir -p "$(dirname "$config_file")"
    
    # Write configuration
    {
        echo "# Cowork configuration"
        echo "# Generated at $(date)"
        echo ""
        
        # Save SESSIONS array if it exists and has elements
        if [[ ${#SESSIONS[@]} -gt 0 ]]; then
            echo "SESSIONS=("
            for session in "${SESSIONS[@]}"; do
                echo "    \"$session\""
            done
            echo ")"
        fi
        
        # Save session metadata
        for var in $(compgen -v | grep "^SESSION_" | grep -v "^SESSIONS"); do
            if [[ -n "${!var+x}" ]]; then
                echo "$var=\"${!var}\""
            fi
        done
        
        # Save other configuration options
        [[ -n "${DOCKERFILE_OVERRIDE:-}" ]] && echo "DOCKERFILE_OVERRIDE=\"$DOCKERFILE_OVERRIDE\""
        [[ -n "${PROJECT_NAME:-}" ]] && echo "PROJECT_NAME=\"$PROJECT_NAME\""
    } > "$temp_file"
    
    mv "$temp_file" "$config_file"
}


# Check git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Not in a git repository" "Run 'cowork init' from inside a git project"
    fi
    
    PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
    PROJECT_SAFE=$(sanitize_project_name "$PROJECT_NAME")
    PROJECT_HASH=$(git rev-parse --show-toplevel | shasum -a 256 | cut -c1-8)
    PROJECT_CONFIG="$(git rev-parse --show-toplevel)/.cowork/.cowork.conf"
    
    # Get origin URL for cloning
    ORIGIN_URL=$(git config --get remote.origin.url || echo "")
    if [[ -z "$ORIGIN_URL" ]]; then
        error "No git origin found" "Please set a git remote origin"
    fi
}

# Generate default devcontainer.json content
generate_default_devcontainer_json() {
    cat << 'EOF'
{
    "name": "Cowork Development Container",
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/devcontainers/features/git:1": {
            "version": "latest",
            "ppa": false
        },
        "ghcr.io/devcontainers/features/github-cli:1": {},
        "ghcr.io/devcontainers/features/node:1": {
            "version": "lts"
        },
        "ghcr.io/devcontainers/features/python:1": {
            "version": "latest"
        },
        "ghcr.io/devcontainers/features/docker-in-docker:2": {
            "version": "latest",
            "moby": true
        },
        "ghcr.io/devcontainers/features/common-utils:2": {
            "installZsh": true,
            "configureZshAsDefaultShell": true,
            "installOhMyZsh": true,
            "username": "vscode",
            "userUid": "1000",
            "userGid": "1000"
        }
    },
    "customizations": {
        "vscode": {
            "extensions": [
                "ms-azuretools.vscode-docker",
                "ms-vscode.makefile-tools",
                "ms-python.python",
                "dbaeumer.vscode-eslint",
                "esbenp.prettier-vscode"
            ],
            "settings": {
                "terminal.integrated.defaultProfile.linux": "zsh",
                "editor.formatOnSave": true,
                "editor.defaultFormatter": "esbenp.prettier-vscode"
            }
        }
    },
    "postCreateCommand": "npm install -g @anthropic-ai/claude-code pnpm yarn && echo '✅ Container ready!'",
    "mounts": [
        {
            "source": "${localEnv:HOME}/.cowork/auth",
            "target": "/home/vscode/.claude",
            "type": "bind",
            "consistency": "cached"
        },
        {
            "source": "${localEnv:HOME}/.ssh",
            "target": "/home/vscode/.ssh",
            "type": "bind",
            "consistency": "cached"
        },
        {
            "source": "${localEnv:HOME}/.gitconfig",
            "target": "/home/vscode/.gitconfig",
            "type": "bind",
            "consistency": "cached"
        }
    ],
    "remoteEnv": {
        "GIT_AUTHOR_NAME": "${localEnv:GIT_AUTHOR_NAME}",
        "GIT_AUTHOR_EMAIL": "${localEnv:GIT_AUTHOR_EMAIL}",
        "GIT_COMMITTER_NAME": "${localEnv:GIT_COMMITTER_NAME}",
        "GIT_COMMITTER_EMAIL": "${localEnv:GIT_COMMITTER_EMAIL}"
    },
    "forwardPorts": [],
    "portsAttributes": {
        "3000": {
            "label": "Application",
            "onAutoForward": "notify"
        }
    },
    "hostRequirements": {
        "cpus": 2,
        "memory": "4gb",
        "storage": "32gb"
    },
    "remoteUser": "vscode"
}
EOF
}

# Check if devcontainer.json exists and handle accordingly
ensure_devcontainer_config() {
    local session_dir="$1"
    local devcontainer_dir="${session_dir}/.devcontainer"
    local devcontainer_json="${devcontainer_dir}/devcontainer.json"
    
    if [[ -f "$devcontainer_json" ]]; then
        info "Found existing devcontainer.json"
        
        # Check if auth mount already exists
        if grep -q "\.cowork/auth" "$devcontainer_json" 2>/dev/null; then
            success "Auth mount already configured"
            return 0
        fi
        
        warning "Auth mount not found in devcontainer.json"
        echo ""
        echo "To use Claude CLI in your container, you need to add the auth mount."
        echo ""
        echo "Would you like me to:"
        echo "  1) Show instructions for manual update"
        echo "  2) Attempt to update automatically (backup will be created)"
        echo "  3) Continue without Claude CLI support"
        echo ""
        echo -n "Enter your choice [1-3] (default: 1): "
        read -r choice
        
        case "${choice:-1}" in
            1)
                echo ""
                echo "Add this to your 'mounts' array in devcontainer.json:"
                echo '        {
            "source": "${localEnv:HOME}/.cowork/auth",
            "target": "/home/vscode/.claude",
            "type": "bind",
            "consistency": "cached"
        }'
                echo ""
                info "Update the file manually, then restart the container"
                ;;
            2)
                info "Creating backup of devcontainer.json..."
                cp "$devcontainer_json" "${devcontainer_json}.backup"
                
                # Attempt to add mount using jq if available
                if command -v jq &> /dev/null; then
                    local mount_entry='{"source": "${localEnv:HOME}/.cowork/auth", "target": "/home/vscode/.claude", "type": "bind", "consistency": "cached"}'
                    jq --arg mount "$mount_entry" '.mounts = (.mounts // []) + [($mount | fromjson)]' "$devcontainer_json" > "${devcontainer_json}.tmp" && \
                    mv "${devcontainer_json}.tmp" "$devcontainer_json"
                    success "Updated devcontainer.json with auth mount"
                else
                    warning "jq not found - please update manually"
                    echo "Backup saved as: ${devcontainer_json}.backup"
                fi
                ;;
            3)
                warning "Continuing without Claude CLI support"
                ;;
            *)
                info "Invalid choice, showing manual instructions"
                ensure_devcontainer_config "$session_dir"
                return
                ;;
        esac
        
        return 0
    fi
    
    warning "No devcontainer.json found in this project"
    echo -n "Would you like to create a default devcontainer configuration? [y/N] "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        info "Creating default devcontainer.json"
        mkdir -p "$devcontainer_dir"
        generate_default_devcontainer_json > "$devcontainer_json"
        success "Created default devcontainer.json with Claude auth mount"
    else
        error "Cannot proceed without devcontainer.json" "Please create one or let cowork create a default"
    fi
}

# Phase 1: Terminal Multiplexer Support
# Check if tmux is installed in container
check_tmux_installed() {
    local session_dir="$1"
    devcontainer exec --workspace-folder "$session_dir" which tmux &>/dev/null
}

# Check if zellij is installed in container
check_zellij_installed() {
    local session_dir="$1"
    devcontainer exec --workspace-folder "$session_dir" which zellij &>/dev/null
}

# Check for existing tmux sessions
check_tmux_sessions() {
    local session_dir="$1"
    local session_name="$2"
    devcontainer exec --workspace-folder "$session_dir" tmux list-sessions 2>/dev/null | grep -q "^${session_name}:"
}

# Check for existing zellij sessions
check_zellij_sessions() {
    local session_dir="$1"
    local session_name="$2"
    # Zellij doesn't have a direct way to list sessions, so we check if zellij is running
    devcontainer exec --workspace-folder "$session_dir" pgrep -f "zellij" &>/dev/null
}

# Detect preferred multiplexer from config or container
detect_multiplexer() {
    local session_dir="$1"
    
    # Check config preference first
    if [[ -n "${MULTIPLEXER_PREFERENCE:-}" ]]; then
        echo "$MULTIPLEXER_PREFERENCE"
        return
    fi
    
    # Check what's installed in container
    if check_tmux_installed "$session_dir"; then
        echo "tmux"
    elif check_zellij_installed "$session_dir"; then
        echo "zellij"
    else
        echo "none"
    fi
}

# Install tmux in container
install_tmux() {
    local session_dir="$1"
    
    info "Installing tmux in container..."
    
    # Try apt-get first (Ubuntu/Debian)
    if devcontainer exec --workspace-folder "$session_dir" bash -c "which apt-get &>/dev/null"; then
        devcontainer exec --workspace-folder "$session_dir" bash -c "sudo apt-get update && sudo apt-get install -y tmux" && return 0
    fi
    
    # Try yum (RedHat/CentOS)
    if devcontainer exec --workspace-folder "$session_dir" bash -c "which yum &>/dev/null"; then
        devcontainer exec --workspace-folder "$session_dir" bash -c "sudo yum install -y tmux" && return 0
    fi
    
    # Try apk (Alpine)
    if devcontainer exec --workspace-folder "$session_dir" bash -c "which apk &>/dev/null"; then
        devcontainer exec --workspace-folder "$session_dir" bash -c "sudo apk add --no-cache tmux" && return 0
    fi
    
    error "Failed to install tmux" "Package manager not supported"
}

# Install zellij in container
install_zellij() {
    local session_dir="$1"
    
    info "Installing zellij in container..."
    
    # Download and install zellij binary
    devcontainer exec --workspace-folder "$session_dir" bash -c '
        ZELLIJ_VERSION="0.39.2"
        ARCH=$(uname -m)
        case $ARCH in
            x86_64) ARCH="x86_64" ;;
            aarch64|arm64) ARCH="aarch64" ;;
            *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
        esac
        
        DOWNLOAD_URL="https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/zellij-${ARCH}-unknown-linux-musl.tar.gz"
        
        # Create temp directory
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        
        # Download and extract
        curl -L "$DOWNLOAD_URL" -o zellij.tar.gz || exit 1
        tar -xzf zellij.tar.gz || exit 1
        
        # Install to /usr/local/bin
        sudo mv zellij /usr/local/bin/ || exit 1
        sudo chmod +x /usr/local/bin/zellij || exit 1
        
        # Clean up
        cd /
        rm -rf "$TEMP_DIR"
        
        # Verify installation
        which zellij >/dev/null || exit 1
    '
    
    if [[ $? -eq 0 ]]; then
        success "Zellij installed successfully"
        return 0
    else
        error "Failed to install zellij" "Installation script failed"
    fi
}

# Install multiplexer if needed
ensure_multiplexer() {
    local session_dir="$1"
    local preferred_multiplexer="${2:-tmux}"
    
    # If multiplexer is already installed, we're done
    if [[ "$preferred_multiplexer" == "tmux" ]] && check_tmux_installed "$session_dir"; then
        return 0
    elif [[ "$preferred_multiplexer" == "zellij" ]] && check_zellij_installed "$session_dir"; then
        return 0
    elif [[ "$preferred_multiplexer" == "none" ]]; then
        return 0
    fi
    
    # Install the preferred multiplexer
    case "$preferred_multiplexer" in
        tmux)
            install_tmux "$session_dir"
            ;;
        zellij)
            install_zellij "$session_dir"
            ;;
        *)
            warning "Unknown multiplexer: $preferred_multiplexer"
            ;;
    esac
}

# Show help
show_help() {
    cat << EOF
cowork - Isolated development sessions using devcontainers and full clones

Usage: cowork <command> [options]

Commands:
  auth              Authenticate with Anthropic Claude
  init <names...>   Initialize development sessions for this project
  list              List all configured sessions and their status
  connect <name>    Connect to a specific session
                    Options: --tmux, --zellij, --none (override multiplexer)
  status            Show detailed status of all sessions
  stop              Stop all running devcontainers
  clean             Remove all devcontainer data and session directories
  help              Show this help message

Examples:
  cowork init feature-backend feature-frontend bugfix-auth
  cowork connect feature-backend
  cowork auth

Configuration:
  Sessions directory: ~/.cowork/sessions/
  Auth directory:     ~/.cowork/auth/
  Project config:     <project>/.cowork/.cowork.conf
EOF
}

# Main command handler
main() {
    local command="${1:-help}"
    shift || true
    
    # Initialize cowork directories
    init_cowork_dirs
    
    # Check for first run (no config exists with preferences)
    local is_first_run=false
    if [[ ! -f "$USER_CONFIG" ]] || ! grep -q "MULTIPLEXER_PREFERENCE" "$USER_CONFIG" 2>/dev/null; then
        is_first_run=true
    fi
    
    # Load user config to check preferences
    load_config
    
    # Run first-time setup if needed (except for help command)
    if [[ "$is_first_run" == true ]] && [[ "$command" != "help" ]] && [[ "$command" != "--help" ]] && [[ "$command" != "-h" ]]; then
        first_run_setup
        # Reload config after setup
        load_config
    fi
    
    # Commands that don't require git repo or devcontainer CLI
    case "$command" in
        help|--help|-h)
            show_help
            return 0
            ;;
        auth)
            cmd_auth "$@"
            return 0
            ;;
    esac
    
    # All other commands require git repo
    check_git_repo
    load_config
    
    # Handle remaining commands
    case "$command" in
        init)
            cmd_init "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        connect)
            cmd_connect "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        clean)
            cmd_clean "$@"
            ;;
        *)
            error "Unknown command: $command" "Run 'cowork help' for usage"
            ;;
    esac
}

# Phase 2: Authentication Implementation
cmd_auth() {
    info "Setting up Claude authentication"
    
    # Check if credentials already exist and are valid
    local existing_auth=""
    if existing_auth=$(find_auth_files); then
        if validate_auth "$existing_auth"; then
            success "Valid authentication already exists at: $existing_auth"
            
            # Copy to central auth directory if not already there
            if [[ "$existing_auth" != "$AUTH_DIR"* ]]; then
                info "Copying credentials to central auth directory..."
                if [[ -d "$existing_auth" ]]; then
                    cp -r "$existing_auth"/* "$AUTH_DIR/" 2>/dev/null || true
                else
                    cp "$existing_auth" "$AUTH_DIR/" 2>/dev/null || true
                fi
                chmod -R 600 "$AUTH_DIR"/* 2>/dev/null || true
            fi
            return 0
        else
            warning "Existing authentication is invalid or expired"
        fi
    fi
    
    # Create a temporary directory for auth setup
    local temp_dir=$(mktemp -d)
    local temp_devcontainer="${temp_dir}/.devcontainer"
    mkdir -p "$temp_devcontainer"
    
    # Create minimal devcontainer.json for auth
    cat > "${temp_devcontainer}/devcontainer.json" << 'EOF'
{
    "name": "Claude Auth Setup",
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/devcontainers/features/node:1": {
            "version": "lts"
        }
    },
    "postCreateCommand": "npm install -g @anthropic-ai/claude-code pnpm",
    "remoteUser": "vscode"
}
EOF
    
    info "Starting authentication container..."
    cd "$temp_dir"
    
    # Check if devcontainer CLI is installed
    if ! command -v devcontainer &> /dev/null; then
        error "devcontainer CLI not found" "Please install it: npm install -g @devcontainers/cli"
    fi
    
    # Start the container and run claude login
    devcontainer up --workspace-folder .
    
    info "Please complete the authentication in your browser..."
    devcontainer exec --workspace-folder . claude login
    
    # Copy credentials from container to host
    info "Saving authentication credentials..."
    devcontainer exec --workspace-folder . tar -cf - /home/vscode/.claude 2>/dev/null | \
        tar -xf - -C "${AUTH_DIR}" --strip-components=2
    
    # Clean up
    info "Cleaning up authentication container..."
    local container_id=$(docker ps -q --filter "label=devcontainer.local_folder=${temp_dir}")
    if [[ -n "$container_id" ]]; then
        docker stop "$container_id" 2>/dev/null || true
        docker rm "$container_id" 2>/dev/null || true
    fi
    rm -rf "$temp_dir"
    
    # Set proper permissions
    chmod -R 700 "$AUTH_DIR" 2>/dev/null || true
    
    success "Authentication completed successfully"
}

cmd_init() {
    [[ $# -eq 0 ]] && error "No session names provided" "Usage: cowork init <session1> <session2> ..."
    
    info "Initializing sessions for project: $PROJECT_NAME"
    
    # Check for existing sessions and warn about resource usage
    local existing_count=${#SESSIONS[@]}
    local new_count=$#
    local total_count=$((existing_count + new_count))
    
    if [[ $total_count -gt 10 ]]; then
        warning "Creating $total_count total sessions. This may consume significant disk space."
    fi
    
    # Check if devcontainer CLI is installed
    if ! command -v devcontainer &> /dev/null; then
        error "devcontainer CLI not found" "Please install it: npm install -g @devcontainers/cli"
    fi
    
    for session_name in "$@"; do
        local session_dir="${SESSIONS_DIR}/${PROJECT_SAFE}-${session_name}"
        
        if [[ -d "$session_dir" ]]; then
            warning "Session '$session_name' already exists, skipping"
            continue
        fi
        
        info "Creating session: $session_name"
        
        # Clone repository
        info "Cloning repository..."
        git clone --depth=1 "$ORIGIN_URL" "$session_dir"
        
        # Create and checkout branch
        cd "$session_dir"
        git checkout -b "$session_name" 2>/dev/null || git checkout "$session_name"
        
        # Ensure devcontainer.json exists
        ensure_devcontainer_config "$session_dir"
        
        # Add session to configuration
        SESSIONS+=("$session_name")
        
        success "Session '$session_name' created"
    done
    
    # Remove duplicates from SESSIONS array
    local unique_sessions=()
    if [[ ${#SESSIONS[@]} -gt 0 ]]; then
        for session in "${SESSIONS[@]}"; do
            local found=false
            if [[ ${#unique_sessions[@]} -gt 0 ]]; then
                for unique in "${unique_sessions[@]}"; do
                    if [[ "$session" == "$unique" ]]; then
                        found=true
                        break
                    fi
                done
            fi
            if [[ "$found" == "false" ]]; then
                unique_sessions+=("$session")
            fi
        done
        SESSIONS=("${unique_sessions[@]}")
    fi
    
    # Save updated configuration
    save_config
    
    success "All sessions initialized"
}

cmd_list() {
    # Load sessions
    SESSIONS=()
    load_config
    
    if [[ ${#SESSIONS[@]} -eq 0 ]]; then
        info "No sessions configured. Run 'cowork init <session_name>' to create one."
        return
    fi
    
    echo "Sessions for $PROJECT_NAME:"
    echo ""
    printf "%-20s %-12s %-20s %s\n" "SESSION" "STATUS" "BRANCH" "LAST MODIFIED"
    echo "────────────────────────────────────────────────────────────────────"
    
    for session in "${SESSIONS[@]}"; do
        local session_dir="${SESSIONS_DIR}/${PROJECT_SAFE}-${session}"
        local status="not found"
        local branch="-"
        local last_modified="-"
        
        if [[ -d "$session_dir" ]]; then
            # Check if container is running
            if docker ps --format '{{.Label "devcontainer.local_folder"}}' | grep -q "$session_dir"; then
                status="${GREEN}running${NC}"
            else
                status="${YELLOW}stopped${NC}"
            fi
            
            # Get current branch
            if [[ -d "${session_dir}/.git" ]]; then
                branch=$(cd "$session_dir" && git branch --show-current 2>/dev/null || echo "-")
            fi
            
            # Get last modification time
            if [[ "$(uname)" == "Darwin" ]]; then
                last_modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$session_dir" 2>/dev/null || echo "-")
            else
                last_modified=$(stat -c "%y" "$session_dir" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 || echo "-")
            fi
        else
            status="${RED}missing${NC}"
        fi
        
        printf "%-20s %-20b %-20s %s\n" "$session" "$status" "$branch" "$last_modified"
    done
    
    echo ""
    echo "Multiplexer preference: ${MULTIPLEXER_PREFERENCE:-not set}"
}

cmd_connect() {
    # Parse arguments
    local session_name=""
    local multiplexer_override=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tmux)
                multiplexer_override="tmux"
                shift
                ;;
            --zellij)
                multiplexer_override="zellij"
                shift
                ;;
            --none)
                multiplexer_override="none"
                shift
                ;;
            -*)
                error "Unknown option: $1" "Use --tmux, --zellij, or --none"
                ;;
            *)
                if [[ -z "$session_name" ]]; then
                    session_name="$1"
                else
                    error "Too many arguments" "Usage: cowork connect <session_name> [--tmux|--zellij|--none]"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$session_name" ]]; then
        error "No session name provided" "Usage: cowork connect <session_name> [--tmux|--zellij|--none]"
    fi
    
    local session_dir="${SESSIONS_DIR}/${PROJECT_SAFE}-${session_name}"
    
    if [[ ! -d "$session_dir" ]]; then
        error "Session '$session_name' not found" "Run 'cowork init $session_name' first"
    fi
    
    info "Connecting to session: $session_name"
    
    # Check if auth exists
    if [[ ! -d "${AUTH_DIR}/.claude" ]] && ! find "$AUTH_DIR" -name "*.json" -type f 2>/dev/null | head -1 | grep -q .; then
        warning "No authentication found. Running 'cowork auth' first..."
        cmd_auth
    fi
    
    # Start or check container
    cd "$session_dir"
    
    # Check if container is already running
    local container_running=false
    if docker ps --format '{{.Label "devcontainer.local_folder"}}' | grep -q "$session_dir"; then
        container_running=true
    else
        info "Starting container..."
        devcontainer up --workspace-folder .
    fi
    
    # Determine multiplexer to use
    local multiplexer="${multiplexer_override:-$(detect_multiplexer "$session_dir")}"
    
    # Ensure multiplexer is installed if needed
    if [[ "$multiplexer" != "none" ]]; then
        ensure_multiplexer "$session_dir" "$multiplexer"
    fi
    
    # Connect based on multiplexer preference
    case "$multiplexer" in
        tmux)
            info "Connecting via tmux..."
            if check_tmux_sessions "$session_dir" "$session_name"; then
                info "Attaching to existing tmux session..."
                devcontainer exec --workspace-folder . tmux attach-session -t "$session_name"
            else
                info "Creating new tmux session..."
                devcontainer exec --workspace-folder . tmux new-session -s "$session_name"
            fi
            ;;
        zellij)
            info "Connecting via zellij..."
            # Zellij auto-creates sessions, so we just attach
            devcontainer exec --workspace-folder . zellij attach "$session_name" -c
            ;;
        none|*)
            if [[ "$container_running" == true ]]; then
                info "Attaching to existing container..."
            else
                info "Container started successfully"
            fi
            devcontainer exec --workspace-folder . /bin/bash
            ;;
    esac
}


cmd_status() {
    echo "═══════════════════════════════════════════════════════════════"
    echo "Cowork Status Report"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Project Information:"
    echo "  Name:        $PROJECT_NAME"
    echo "  Safe name:   $PROJECT_SAFE"
    echo "  Hash:        $PROJECT_HASH"
    echo "  Origin:      $ORIGIN_URL"
    echo ""
    echo "System Configuration:"
    echo "  Cowork dir:  $COWORK_DIR"
    echo "  Sessions:    ${SESSIONS_DIR}"
    echo "  Config:      $PROJECT_CONFIG"
    echo ""
    echo "Authentication Status:"
    local auth_status="Not configured"
    local auth_age="N/A"
    if [[ -d "${AUTH_DIR}/.claude" ]] || find "$AUTH_DIR" -name "*.json" -type f 2>/dev/null | head -1 | grep -q .; then
        auth_status="${GREEN}Configured${NC}"
        # Check auth age
        local auth_file=$(find "$AUTH_DIR" -name "*.json" -type f 2>/dev/null | head -1)
        if [[ -n "$auth_file" ]]; then
            local days_old=$(find "$auth_file" -mtime +0 -print 2>/dev/null | wc -l)
            if [[ $days_old -gt 30 ]]; then
                auth_age="${YELLOW}May be expired (>30 days)${NC}"
            else
                auth_age="${GREEN}Valid${NC}"
            fi
        fi
    else
        auth_status="${RED}Not configured${NC}"
    fi
    printf "  Status:      %b\n" "$auth_status"
    printf "  Age:         %b\n" "$auth_age"
    echo ""
    
    # Check Docker status
    echo "Docker Status:"
    if docker info &>/dev/null; then
        echo -e "  Docker:      ${GREEN}Running${NC}"
        local container_count=$(docker ps --filter "label=devcontainer.local_folder" | grep -c "${PROJECT_SAFE}" || echo "0")
        echo "  Containers:  $container_count running"
    else
        echo -e "  Docker:      ${RED}Not running${NC}"
    fi
    echo ""
    
    # Check devcontainer CLI
    echo "DevContainer CLI:"
    if command -v devcontainer &> /dev/null; then
        local version=$(devcontainer --version 2>/dev/null || echo "unknown")
        echo -e "  Status:      ${GREEN}Installed${NC}"
        echo "  Version:     $version"
    else
        echo -e "  Status:      ${RED}Not installed${NC}"
        echo "  Install:     npm install -g @devcontainers/cli"
    fi
    echo ""
    
    # Show sessions
    cmd_list
}

cmd_stop() {
    info "Stopping all running containers for project: $PROJECT_NAME"
    
    # Load sessions
    SESSIONS=()
    load_config
    
    for session in "${SESSIONS[@]}"; do
        local session_dir="${SESSIONS_DIR}/${PROJECT_SAFE}-${session}"
        
        if [[ -d "$session_dir" ]]; then
            local container_id=$(docker ps -q --filter "label=devcontainer.local_folder=${session_dir}")
            if [[ -n "$container_id" ]]; then
                info "Stopping container for session: $session"
                docker stop "$container_id"
            fi
        fi
    done
    
    success "All containers stopped"
}

cmd_clean() {
    warning "This will remove ALL containers and session data for project: $PROJECT_NAME"
    echo ""
    echo "This action will:"
    echo "  • Stop all running containers"
    echo "  • Remove all session directories"
    echo "  • Clear session configuration"
    echo ""
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    read -p "Are you absolutely sure? Type 'yes' to confirm: " -r
    
    if [[ "$REPLY" != "yes" ]]; then
        info "Clean cancelled - no changes made"
        return
    fi
    
    # Stop all containers first
    cmd_stop
    
    info "Removing all session data for project: $PROJECT_NAME"
    
    # Load sessions
    SESSIONS=()
    load_config
    
    for session in "${SESSIONS[@]}"; do
        local session_dir="${SESSIONS_DIR}/${PROJECT_SAFE}-${session}"
        
        if [[ -d "$session_dir" ]]; then
            info "Removing session: $session"
            rm -rf "$session_dir"
        fi
    done
    
    # Clear configuration
    SESSIONS=()
    save_config
    
    success "All sessions cleaned"
}

# Run main function
main "$@"