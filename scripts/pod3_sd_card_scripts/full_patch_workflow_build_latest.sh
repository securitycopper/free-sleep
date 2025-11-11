#!/bin/bash
#
# opensleep Build & Update Script
# Runs directly on the Eight Sleep Pod 3
#
# This script intelligently detects what has been set up and performs:
# - Initial setup (Rust installation, git, dependencies)
# - Updates (git pull and rebuild)
#
# Usage:
#   ./full_patch_workflow_build_latest.sh [options]
#
# Options:
#   -f, --force-setup     Force re-installation of Rust and dependencies
#   -c, --clean           Clean build (removes target directory)
#   -s, --skip-build      Skip the build step (setup only)
#   -d, --debug           Build in debug mode (faster compilation)
#   -n, --no-install      Build but don't install the binary
#   -b, --branch BRANCH   Checkout specific branch (default: main)
#   -r, --repo URL        Use custom repository URL
#   -h, --help            Show this help message
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

REPO_URL="https://github.com/securitycopper/opensleep.git"
REPO_DIR="/opt/opensleep"
INSTALL_DIR="/opt/opensleep"
BACKUP_DIR="/opt/opensleep_backup"
SERVICE_NAME="opensleep"
LOG_FILE="/var/log/opensleep_build.log"
BRANCH="main"

# Build configuration
BUILD_MODE="release"
FORCE_SETUP=false
CLEAN_BUILD=false
SKIP_BUILD=false
NO_INSTALL=false
USE_TARBALL=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $1" >> "$LOG_FILE"
}

usage() {
    cat <<EOF
opensleep Build & Update Script

Usage: $0 [options]

Options:
  -f, --force-setup     Force re-installation of Rust and dependencies
  -c, --clean           Clean build (removes target directory)
  -s, --skip-build      Skip the build step (setup only)
  -d, --debug           Build in debug mode (faster compilation)
  -n, --no-install      Build but don't install the binary
  -b, --branch BRANCH   Checkout specific branch (default: main)
  -r, --repo URL        Use custom repository URL
  -h, --help            Show this help message

Examples:
  # Initial setup and build
  $0

  # Update to latest version
  $0

  # Force clean rebuild
  $0 --clean

  # Build specific branch
  $0 --branch issue_6

  # Setup only (no build)
  $0 --skip-build

  # Debug build (faster)
  $0 --debug

EOF
    exit 0
}

check_disk_space() {
    local required_mb=$1
    local available_mb=$(df /opt | tail -1 | awk '{print int($4/1024)}')
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi
    log_success "Disk space check passed: ${available_mb}MB available"
    return 0
}

is_rust_installed() {
    command -v cargo &> /dev/null && command -v rustc &> /dev/null
}

is_git_installed() {
    command -v git &> /dev/null
}

is_repo_cloned() {
    [ -d "$REPO_DIR/.git" ]
}

get_rust_version() {
    if is_rust_installed; then
        rustc --version 2>/dev/null | awk '{print $2}'
    else
        echo "not installed"
    fi
}

get_current_binary_version() {
    if [ -f "$INSTALL_DIR/opensleep" ]; then
        # Try to get version from binary (if it has --version flag)
        "$INSTALL_DIR/opensleep" --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force-setup)
            FORCE_SETUP=true
            shift
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -s|--skip-build)
            SKIP_BUILD=true
            shift
            ;;
        -d|--debug)
            BUILD_MODE="debug"
            shift
            ;;
        -n|--no-install)
            NO_INSTALL=true
            shift
            ;;
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        -r|--repo)
            REPO_URL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# ============================================================================
# Main Script
# ============================================================================

log "=========================================="
log "opensleep Build & Update Script"
log "=========================================="
log ""
log "Configuration:"
log "  Repository: $REPO_URL"
log "  Branch: $BRANCH"
log "  Build Mode: $BUILD_MODE"
log "  Install Dir: $INSTALL_DIR"
log ""

# Check if running as root (optional, but recommended)
if [ "$EUID" -ne 0 ]; then 
    log_warning "Not running as root. Some operations may fail."
fi

# ============================================================================
# Step 1: Check System Status
# ============================================================================

log "Step 1: Checking system status..."

# Check internet connectivity if we need to download anything
if ! is_rust_installed || ! is_repo_cloned; then
    log "Checking internet connectivity..."
    if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        log_success "Internet connectivity verified"
    else
        log_error "No internet connection detected!"
        log_error ""
        log_error "This script requires internet access to:"
        log_error "  - Install Rust toolchain (if not installed)"
        log_error "  - Clone/update repository from GitHub"
        log_error ""
        log_error "Please fix network connectivity and try again:"
        log_error "  1. Check WiFi/Ethernet connection"
        log_error "  2. Test with: ping 8.8.8.8"
        log_error "  3. Test DNS: ping google.com"
        log_error ""
        log_error "Alternative: Use cross-compilation on another machine"
        log_error "See: docs/guides/wsl_build_guide.md"
        exit 1
    fi
fi

# Check disk space (need at least 2GB for initial setup, 500MB for updates)
if is_rust_installed && is_repo_cloned; then
    check_disk_space 500 || exit 1
else
    check_disk_space 2048 || exit 1
fi

# Display current status
log "Current status:"
log "  - Rust: $(get_rust_version)"
log "  - Git: $(is_git_installed && echo 'installed' || echo 'not installed')"
log "  - Repository: $(is_repo_cloned && echo 'cloned' || echo 'not cloned')"
log "  - Binary: $(get_current_binary_version)"
log ""

# ============================================================================
# Step 2: Install/Update Rust
# ============================================================================

if ! is_rust_installed || [ "$FORCE_SETUP" = true ]; then
    log "Step 2: Installing Rust toolchain..."
    
    # Download and install rustup
    if [ "$FORCE_SETUP" = true ] && is_rust_installed; then
        log_warning "Forcing Rust reinstallation..."
    fi
    
    log "Attempting to download and install Rust..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable; then
        log_success "Rust installer completed"
    else
        log_error "Failed to download Rust installer"
        log_error ""
        log_error "This usually means no internet connection or DNS issues."
        log_error "Please ensure the Pod has internet connectivity:"
        log_error "  1. Check network connection: ping 8.8.8.8"
        log_error "  2. Check DNS resolution: ping google.com"
        log_error "  3. Verify WiFi/Ethernet configuration"
        log_error ""
        log_error "Alternative: Cross-compile on another machine and copy the binary"
        log_error "See: docs/guides/wsl_build_guide.md"
        exit 1
    fi
    
    # Source cargo environment
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    else
        log_error "Failed to find cargo environment file"
        log_error "Cargo environment should be at: $HOME/.cargo/env"
        exit 1
    fi
    
    # Verify installation
    if is_rust_installed; then
        log_success "Rust $(rustc --version | awk '{print $2}') installed successfully"
    else
        log_error "Rust installation failed"
        exit 1
    fi
else
    log "Step 2: Rust already installed ($(get_rust_version))"
    
    # Make sure cargo is in PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    
    # Optional: Update Rust to latest stable
    log "Checking for Rust updates..."
    if rustup update stable 2>&1 | grep -q "updated"; then
        log_success "Rust updated to latest stable version"
    else
        log "Rust is already up to date"
    fi
fi

log ""

# ============================================================================
# Step 3: Install Git and Dependencies
# ============================================================================

log "Step 3: Checking dependencies..."

# Check for C compiler (required for building Rust projects)
if ! command -v gcc &> /dev/null && ! command -v cc &> /dev/null; then
    log_warning "No C compiler found"
    log "Attempting to install build tools..."
    
    # Try different package managers
    if command -v apt-get &> /dev/null; then
        log "Using apt-get to install compiler..."
        apt-get update || log_warning "apt-get update failed, continuing anyway..."
        
        # Try build-essential first, then fall back to individual packages
        if apt-get install -y build-essential 2>/dev/null; then
            log_success "build-essential installed successfully"
        elif apt-get install -y gcc g++ make 2>/dev/null; then
            log_success "gcc, g++, and make installed successfully"
        elif apt-get install -y gcc 2>/dev/null; then
            log_success "gcc installed successfully"
        else
            log_error "Failed to install C compiler via apt-get"
            log_error ""
            log_error "Available packages:"
            apt-cache search "^gcc" | head -20 | while read line; do log "  $line"; done
            log_error ""
            log_error "Try installing manually with: apt-get install <package-name>"
            exit 1
        fi
    elif command -v yum &> /dev/null; then
        log "Using yum to install development tools..."
        yum groupinstall -y "Development Tools"
    elif command -v dnf &> /dev/null; then
        log "Using dnf to install development tools..."
        dnf groupinstall -y "Development Tools"
    else
        log_error "No supported package manager found (apt-get, yum, dnf)"
        log_error "Please install a C compiler (gcc) manually"
        exit 1
    fi
    
    # Verify installation
    if command -v gcc &> /dev/null; then
        log_success "GCC installed: $(gcc --version | head -n1)"
    else
        log_error "GCC installation failed"
        exit 1
    fi
else
    if command -v gcc &> /dev/null; then
        log_success "GCC is already installed: $(gcc --version | head -n1)"
    else
        log_success "C compiler (cc) is already installed"
    fi
fi

# Check for pkg-config (helpful for finding libraries)
if ! command -v pkg-config &> /dev/null; then
    log_warning "pkg-config not found, attempting to install..."
    if command -v apt-get &> /dev/null; then
        apt-get install -y pkg-config && log_success "pkg-config installed" || log_warning "pkg-config installation failed (non-critical)"
    fi
else
    log_success "pkg-config is installed"
fi

# Git is optional - we can use tarball download instead
if ! is_git_installed; then
    log_warning "Git is not installed"
    log "Will use tarball download method instead of git clone"
    USE_TARBALL=true
else
    log_success "Git is installed"
    USE_TARBALL=false
fi

log ""

# ============================================================================
# Step 4: Clone or Update Repository
# ============================================================================

log "Step 4: Managing repository..."

if ! is_repo_cloned; then
    log "Downloading repository from $REPO_URL..."
    
    # If REPO_DIR exists but is not a git repo, remove it
    if [ -d "$REPO_DIR" ] && [ ! -d "$REPO_DIR/.git" ]; then
        log_warning "Directory exists but is not a git repository. Removing..."
        rm -rf "$REPO_DIR"
    fi
    
    if [ "$USE_TARBALL" = true ] || ! is_git_installed; then
        # Download tarball method (works without git)
        log "Using tarball download method (no git available)..."
        
        # Extract owner and repo name from URL
        REPO_OWNER="securitycopper"
        REPO_NAME="opensleep"
        TARBALL_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"
        
        log "Downloading: $TARBALL_URL"
        
        # Download and extract
        TEMP_DIR="/tmp/opensleep_download_$$"
        mkdir -p "$TEMP_DIR"
        
        if curl -L "$TARBALL_URL" -o "$TEMP_DIR/opensleep.tar.gz"; then
            log_success "Download completed"
            
            # Extract tarball
            log "Extracting archive..."
            tar -xzf "$TEMP_DIR/opensleep.tar.gz" -C "$TEMP_DIR"
            
            # Move to final location (tarball extracts to opensleep-BRANCH)
            mv "$TEMP_DIR/opensleep-${BRANCH}" "$REPO_DIR"
            
            # Cleanup
            rm -rf "$TEMP_DIR"
            
            log_success "Repository downloaded and extracted successfully"
        else
            log_error "Failed to download repository tarball"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    else
        # Git clone method
        log "Using git clone method..."
        git clone "$REPO_URL" "$REPO_DIR"
        cd "$REPO_DIR"
        
        # Checkout the specified branch
        if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
            log "Checking out branch: $BRANCH"
            git checkout "$BRANCH"
        fi
        
        log_success "Repository cloned successfully"
    fi
else
    log "Repository already exists at $REPO_DIR"
    cd "$REPO_DIR"
    
    if [ -d "$REPO_DIR/.git" ] && is_git_installed; then
        # Git repository - update it
        log "Updating repository using git..."
        
        # Stash any local changes
        if ! git diff --quiet || ! git diff --cached --quiet; then
            log_warning "Local changes detected. Stashing..."
            git stash save "Auto-stash by build script at $(date)"
        fi
        
        # Fetch latest changes
        log "Fetching latest changes..."
        git fetch origin
        
        # Checkout the specified branch
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
            log "Switching from $CURRENT_BRANCH to $BRANCH..."
            git checkout "$BRANCH"
        fi
        
        # Pull latest changes
        log "Pulling latest changes..."
        if git pull origin "$BRANCH"; then
            log_success "Repository updated successfully"
        else
            log_error "Failed to pull latest changes"
            exit 1
        fi
        
        # Show what changed
        log "Latest commit: $(git log -1 --oneline)"
    else
        # Not a git repo or git not available - re-download
        log_warning "Cannot update (not a git repository or git not available)"
        log "Will download fresh copy..."
        
        # Backup old version
        if [ -d "$REPO_DIR" ]; then
            BACKUP_REPO_DIR="${REPO_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
            log "Backing up existing directory to $BACKUP_REPO_DIR"
            mv "$REPO_DIR" "$BACKUP_REPO_DIR"
        fi
        
        # Download fresh copy using tarball
        REPO_OWNER="securitycopper"
        REPO_NAME="opensleep"
        TARBALL_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${BRANCH}.tar.gz"
        
        log "Downloading: $TARBALL_URL"
        
        TEMP_DIR="/tmp/opensleep_download_$$"
        mkdir -p "$TEMP_DIR"
        
        if curl -L "$TARBALL_URL" -o "$TEMP_DIR/opensleep.tar.gz"; then
            log_success "Download completed"
            log "Extracting archive..."
            tar -xzf "$TEMP_DIR/opensleep.tar.gz" -C "$TEMP_DIR"
            mv "$TEMP_DIR/opensleep-${BRANCH}" "$REPO_DIR"
            rm -rf "$TEMP_DIR"
            log_success "Repository downloaded successfully"
        else
            log_error "Failed to download repository"
            # Restore backup if download failed
            if [ -d "$BACKUP_REPO_DIR" ]; then
                mv "$BACKUP_REPO_DIR" "$REPO_DIR"
                log_warning "Restored from backup"
            fi
            exit 1
        fi
    fi
fi

# Ensure we're in the repo directory
cd "$REPO_DIR"

log ""

# Exit if skip-build is set
if [ "$SKIP_BUILD" = true ]; then
    log "Skipping build as requested (--skip-build)"
    log_success "Setup completed successfully"
    exit 0
fi

# ============================================================================
# Step 5: Build the Project
# ============================================================================

log "Step 5: Building opensleep..."

cd "$REPO_DIR"

# Configure Cargo to use the native compiler (not cross-compiler)
log "Configuring build environment..."

# Detect the native compiler
NATIVE_CC=""
if command -v gcc &> /dev/null; then
    NATIVE_CC="gcc"
elif command -v cc &> /dev/null; then
    NATIVE_CC="cc"
else
    log_error "No C compiler found (gcc or cc)"
    log_error "Please install a C compiler to build Rust projects"
    exit 1
fi

log "Detected native compiler: $NATIVE_CC"

# Get the host triple
HOST_TRIPLE=$(rustc -vV | grep host | cut -d' ' -f2)
log "Host triple: $HOST_TRIPLE"

# Always recreate the cargo config to ensure clean state
log "Setting up native compilation configuration..."
mkdir -p "$HOME/.cargo"

# Backup existing config if it exists
if [ -f "$HOME/.cargo/config.toml" ]; then
    cp "$HOME/.cargo/config.toml" "$HOME/.cargo/config.toml.backup.$(date +%s)"
    log "Backed up existing cargo config"
fi

# Create config for native compilation
cat > "$HOME/.cargo/config.toml" <<EOF
# Native compilation configuration for $HOST_TRIPLE
[target.$HOST_TRIPLE]
linker = "$NATIVE_CC"

[build]
target = "$HOST_TRIPLE"
EOF

log_success "Cargo configuration created:"
cat "$HOME/.cargo/config.toml" | while read line; do log "  $line"; done

# Clean build if requested
if [ "$CLEAN_BUILD" = true ]; then
    log "Performing clean build..."
    cargo clean
fi

# Determine build command
if [ "$BUILD_MODE" = "debug" ]; then
    log "Building in debug mode (faster compilation, slower runtime)..."
    BUILD_CMD="cargo build"
    BINARY_PATH="target/debug/opensleep"
else
    log "Building in release mode (optimized)..."
    BUILD_CMD="cargo build --release"
    BINARY_PATH="target/release/opensleep"
fi

# Build the project
log "Running: $BUILD_CMD"
log "This may take 30-60 minutes on first build..."
log ""

START_TIME=$(date +%s)

if $BUILD_CMD 2>&1 | tee -a "$LOG_FILE"; then
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    log_success "Build completed successfully in ${BUILD_TIME} seconds"
else
    log_error "Build failed. Check $LOG_FILE for details."
    exit 1
fi

# Verify binary exists
if [ ! -f "$BINARY_PATH" ]; then
    log_error "Binary not found at $BINARY_PATH"
    exit 1
fi

log "Binary size: $(du -h "$BINARY_PATH" | cut -f1)"
log ""

# Exit if no-install is set
if [ "$NO_INSTALL" = true ]; then
    log "Skipping installation as requested (--no-install)"
    log_success "Build completed successfully"
    log "Binary location: $BINARY_PATH"
    exit 0
fi

# ============================================================================
# Step 6: Install the Binary
# ============================================================================

log "Step 6: Installing opensleep binary..."

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup existing binary
if [ -f "$INSTALL_DIR/opensleep" ]; then
    BACKUP_FILE="$BACKUP_DIR/opensleep.$(date +%Y%m%d_%H%M%S)"
    log "Creating backup: $BACKUP_FILE"
    cp "$INSTALL_DIR/opensleep" "$BACKUP_FILE"
    log_success "Backup created"
fi

# Check if service is running
SERVICE_WAS_RUNNING=false
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    SERVICE_WAS_RUNNING=true
    log "Stopping $SERVICE_NAME service..."
    systemctl stop "$SERVICE_NAME"
    log_success "Service stopped"
fi

# Install the new binary
log "Installing new binary to $INSTALL_DIR/opensleep..."
cp "$BINARY_PATH" "$INSTALL_DIR/opensleep"
chmod +x "$INSTALL_DIR/opensleep"
log_success "Binary installed"

# Start service if it was running
if [ "$SERVICE_WAS_RUNNING" = true ]; then
    log "Starting $SERVICE_NAME service..."
    systemctl start "$SERVICE_NAME"
    
    # Wait a moment for service to start
    sleep 2
    
    # Check service status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service started successfully"
    else
        log_error "Service failed to start!"
        log_error "Attempting to restore from backup..."
        
        # Restore from backup
        LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/opensleep.* 2>/dev/null | head -n1)
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$INSTALL_DIR/opensleep"
            chmod +x "$INSTALL_DIR/opensleep"
            systemctl start "$SERVICE_NAME"
            
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                log_warning "Backup restored and service started"
                log_error "New binary failed to start. Check logs: journalctl -u $SERVICE_NAME -n 50"
            else
                log_error "Failed to start service even with backup. Manual intervention required."
            fi
        else
            log_error "No backup found. Service is stopped."
        fi
        exit 1
    fi
else
    log_warning "Service was not running. Not starting it automatically."
    log "To start the service manually, run: systemctl start $SERVICE_NAME"
fi

log ""

# ============================================================================
# Step 7: Cleanup and Summary
# ============================================================================

log "Step 7: Cleanup..."

# Keep only last 5 backups
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/opensleep.* 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt 5 ]; then
    log "Cleaning old backups (keeping last 5)..."
    ls -t "$BACKUP_DIR"/opensleep.* | tail -n +6 | xargs rm -f
    log_success "Old backups removed"
fi

log ""
log "=========================================="
log "Build & Update Complete!"
log "=========================================="
log ""
log "Summary:"
log "  - Rust version: $(rustc --version | awk '{print $2}')"
log "  - Repository: $REPO_DIR"
log "  - Branch: $(cd "$REPO_DIR" && git rev-parse --abbrev-ref HEAD)"
log "  - Commit: $(cd "$REPO_DIR" && git log -1 --oneline)"
log "  - Binary: $INSTALL_DIR/opensleep"
log "  - Build mode: $BUILD_MODE"
log "  - Service status: $(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo 'not running')"
log "  - Backups: $BACKUP_DIR ($(ls -1 "$BACKUP_DIR"/opensleep.* 2>/dev/null | wc -l) available)"
log ""
log "Useful commands:"
log "  - View logs: journalctl -u $SERVICE_NAME -f"
log "  - Service status: systemctl status $SERVICE_NAME"
log "  - Restart service: systemctl restart $SERVICE_NAME"
log "  - View build log: cat $LOG_FILE"
log ""
log_success "All operations completed successfully!"
log ""

exit 0
